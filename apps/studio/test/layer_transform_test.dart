import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/layer_transform.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

/// Drawings made by these tests use the default 1024² canvas.
const legacyExtent = 1024.0;

Future<Uint8List> blueImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff0000ff), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 2);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<List<int>> pixel(
  StudioController c,
  int x,
  int y, {
  bool preview = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(32 / legacyExtent);
  paintDocument(
    canvas,
    c.document,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
    transform: preview ? c.transformDraft : null,
    transformLayerId: c.transformLayerId,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List().sublist(
    (y * 32 + x) * 4,
    (y * 32 + x) * 4 + 4,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'uniform affine mapping has a stable inverse and clamps invalid input',
    () {
      final transform =
          const LayerTransform(bounds: ui.Rect.fromLTWH(100, 150, 500, 250))
              .copyWith(
                translation: const ui.Offset(78, -49),
                scale: .65,
                rotation: math.pi / 3,
              );
      const source = ui.Offset(180, 240);
      expect(
        (transform.inverse(transform.map(source)) - source).distance,
        lessThan(.000001),
      );
      expect(transform.copyWith(scale: 100).scale, 8);
      expect(
        () => transform.copyWith(scale: double.nan),
        throwsFormatException,
      );
    },
  );

  test('preview/cancel are nondestructive and applying move, scale and rotation survives undo and disk reopen', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-transform-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStudioStorage(dir);
    final c = StudioController(storage: storage);
    await c.initialize();
    await c.addImageLayer(await blueImage(), 'Blue study');
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(opacity: .5));
    await c.save();
    final original = c.document;
    final sourcePixel = await pixel(c, 16, 16);
    expect(c.beginTransform(), isTrue);
    c.previewTransform(
      c.transformDraft!.copyWith(
        translation: const ui.Offset(256, 0),
        scale: .5,
        rotation: math.pi / 2,
      ),
    );
    final targetPixel = await pixel(c, 24, 16, preview: true);
    expect(targetPixel, sourcePixel);
    expect(await pixel(c, 16, 16, preview: true), [255, 253, 248, 255]);
    expect(c.document, same(original));
    await c.save();
    expect(
      (await storage.loadDocument())!.activeLayer.raster!.tiles,
      isNotEmpty,
    );
    c.cancelTransform();
    expect(c.document, same(original));
    expect(c.tool, StudioTool.brush);
    expect(c.beginTransform(), isTrue);
    c.previewTransform(
      c.transformDraft!.copyWith(
        translation: const ui.Offset(256, 0),
        scale: .5,
        rotation: math.pi / 2,
      ),
    );
    final applying = c.applyTransform();
    expect(c.documentTransition, isTrue);
    c.undo();
    c.addLayer('Must not interrupt the pending transform');
    c.selectLayer(c.document.layers.first.id);
    c.cancelTransform();
    expect(c.document, same(original));
    expect(c.transformDraft, isNotNull);
    await applying;
    expect(c.transformDraft, isNull);
    expect(c.document.activeLayer.raster!.tiles, isNotEmpty);
    expect(c.document.activeLayer.opacity, .5);
    expect(await pixel(c, 24, 16), targetPixel);
    expect(await pixel(c, 16, 16), [255, 253, 248, 255]);
    expect(c.beginTransform(), isTrue);
    // Transparent margins in a baked PNG must not become the next transform's pivot.
    expect(c.transformDraft!.bounds.center.dx, closeTo(768, 2));
    expect(c.transformDraft!.bounds.center.dy, closeTo(512, 2));
    c.cancelTransform();
    c.undo();
    expect(c.document, same(original));
    expect(await pixel(c, 16, 16), sourcePixel);
    c.redo();
    await c.save();
    c.dispose();
    final reopened = StudioController(storage: LocalStudioStorage(dir));
    await reopened.initialize();
    expect(reopened.initialized, isTrue);
    expect(await pixel(reopened, 24, 16), targetPixel);
    reopened.dispose();
  });

  test('ink transforms only its layer, keeps local erasures and accepts fresh ink after apply', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    void line(double y) {
      c.beginStroke(InkPoint(256, y, .5), simulatePressure: false);
      c.appendPoint(InkPoint(768, y, .5));
      c.finishStroke();
    }

    c.setSize(128);
    c.selectColor(0xffff0000);
    line(512);
    final bottom = c.document.activeLayer;
    c.addLayer('Top');
    c.selectColor(0xff0000ff);
    line(512);
    c.selectTool(StudioTool.eraser);
    c.beginStroke(const InkPoint(512, 512, .5), simulatePressure: false);
    c.finishStroke();
    expect(c.beginTransform(), isTrue);
    c.previewTransform(
      c.transformDraft!.copyWith(translation: const ui.Offset(0, -256)),
    );
    await c.applyTransform();
    expect(c.document.layers.first, same(bottom));
    expect(await pixel(c, 10, 8), [0, 0, 255, 255]);
    expect(await pixel(c, 16, 8), [255, 253, 248, 255]);
    expect(await pixel(c, 16, 16), [255, 0, 0, 255]);
    expect(c.tool, StudioTool.eraser);
    c.selectTool(StudioTool.brush);
    line(768);
    expect(c.document.activeLayer.strokes, hasLength(1));
    expect(await pixel(c, 16, 24), [0, 0, 255, 255]);
    c.undo();
    c.undo();
    expect(c.document.activeLayer.raster, isNull);
    expect(c.document.activeLayer.strokes, hasLength(2));
    c.dispose();
  });

  test('identity, hidden, locked and empty layers cannot create destructive transform steps', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    expect(c.beginTransform(), isFalse);
    c.beginStroke(const InkPoint(512, 512, .5), simulatePressure: false);
    c.finishStroke();
    final original = c.document;
    expect(c.beginTransform(), isTrue);
    expect(
      c.beginStroke(const InkPoint(20, 20, .5), simulatePressure: false),
      isFalse,
    );
    await c.applyTransform();
    expect(c.document, same(original));
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(locked: true));
    expect(c.beginTransform(), isFalse);
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(locked: false, visible: false),
    );
    expect(c.beginTransform(), isFalse);
    c.dispose();
  });
}
