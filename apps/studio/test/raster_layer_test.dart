import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

/// Drawings made by these tests use the default 1024² canvas.
const legacyExtent = 1024.0;

Future<Uint8List> bluePng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff0000ff), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 2);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<List<int>> pixel(StudioController c, int x, int y) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(32 / legacyExtent);
  paintDocument(
    canvas,
    c.document,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  picture.dispose();
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return raw!.buffer.asUint8List().sublist(
    (y * 32 + x) * 4,
    (y * 32 + x) * 4 + 4,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('image layers render with aspect ratio, erase independently, undo, save and reopen', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-raster-');
    addTearDown(() => dir.delete(recursive: true));
    final c = StudioController(storage: LocalStudioStorage(dir));
    await c.initialize();
    c.selectColor(0xffff0000);
    c.setSize(128);
    c.beginStroke(const InkPoint(100, 512, .5), simulatePressure: false);
    c.appendPoint(const InkPoint(924, 512, .5));
    c.finishStroke();
    await c.addImageLayer(await bluePng(), 'Generated image');
    expect(c.document.toJson()['version'], 5);
    expect(await pixel(c, 16, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 16, 2), [255, 253, 248, 255]);
    c.selectTool(StudioTool.eraser);
    c.beginStroke(const InkPoint(100, 512, .5), simulatePressure: false);
    c.appendPoint(const InkPoint(924, 512, .5));
    c.finishStroke();
    expect(await pixel(c, 16, 16), [255, 0, 0, 255]);
    c.undo();
    expect(await pixel(c, 16, 16), [0, 0, 255, 255]);
    c.undo();
    expect(c.document.toJson()['version'], 1);
    expect(await pixel(c, 16, 16), [255, 0, 0, 255]);
    c.redo();
    await c.save();
    c.dispose();
    final reopened = StudioController(storage: LocalStudioStorage(dir));
    await reopened.initialize();
    expect(reopened.initialized, isTrue);
    expect(reopened.document.activeLayer.name, 'Generated image');
    expect(await pixel(reopened, 16, 16), [0, 0, 255, 255]);
    final json = jsonDecode(
      jsonEncode(reopened.document.toJson()),
    ) as Map<String, dynamic>;
    json['version'] = 1;
    expect(() => ArtDocument.fromJson(json), throwsFormatException);
    await reopened.replaceDocument(ArtDocument.empty());
    expect(reopened.rasters.images, isEmpty);
    reopened.dispose();
  });

  test(
    'invalid images or stale target documents never change artwork',
    () async {
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      final before = c.document;
      await expectLater(
        c.addImageLayer(Uint8List.fromList([1, 2, 3]), 'Bad'),
        throwsA(anything),
      );
      expect(c.document, same(before));
      await expectLater(
        c.addImageLayer(await bluePng(), 'Stale', expectedDocumentId: 'other'),
        throwsStateError,
      );
      expect(c.document, same(before));
      expect(c.rasters.images, isEmpty);
      final png = await bluePng();
      expect(
        () => RasterAsset(id: 'mismatch', png: png, width: 4096, height: 4096),
        throwsFormatException,
      );
      c.dispose();
    },
  );

  test(
    'raster decoder failure preserves the saved document and disables editing',
    () async {
      final png = await bluePng();
      // Valid size header followed by truncated compressed data.
      final broken = Uint8List.fromList(png.sublist(0, 33));
      final layer = ArtLayer(
        id: newId(),
        name: 'Damaged',
        legacyRaster: RasterAsset(
          id: newId(),
          png: broken,
          width: 4,
          height: 2,
        ),
      );
      final original = ArtDocument(
        id: newId(),
        name: 'Preserve me',
        layers: [layer],
        activeLayerId: layer.id,
      );
      final storage = MemoryStorage()..document = original;
      final c = StudioController(storage: storage);
      await c.initialize();
      expect(c.initialized, isFalse);
      await c.save();
      expect(storage.document, same(original));
      expect(c.rasters.images, isEmpty);
      c.dispose();
    },
  );
}
