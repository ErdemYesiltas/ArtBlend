import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:atelier_studio/data/document_package.dart';

import 'support/memory_storage.dart';

/// Drawings made by these tests use the default 1024² canvas.
const legacyExtent = 1024.0;

Future<Uint8List> blueImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff0000ff), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 2);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<List<int>> pixel(
  StudioController c,
  int x,
  int y, {
  bool preview = false,
}) async {
  final recorder = ui.PictureRecorder();
  paintDocument(
    ui.Canvas(recorder)..scale(32 / legacyExtent),
    c.document,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
    transform: preview ? c.transformDraft : null,
    transformLayerId: c.transformLayerId,
    transformSelection: c.transformSelection,
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

void line(
  StudioController c, {
  double y = 512,
  double x1 = 100,
  double x2 = 924,
}) {
  c.beginStroke(InkPoint(x1, y, .5), simulatePressure: false);
  c.appendPoint(InkPoint(x2, y, .5));
  c.finishStroke();
}

const paper = [255, 253, 248, 255];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rectangle clips ink, persists through disk reopen, and inverse clips erasing outside it', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-selection-');
    addTearDown(() => dir.delete(recursive: true));
    final c = StudioController(storage: LocalStudioStorage(dir));
    await c.initialize();
    c.setSize(128);
    c.selectColor(0xffff0000);
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(256, 256, 512, 512)),
    );
    line(c);
    expect(await pixel(c, 16, 16), [255, 0, 0, 255]);
    expect(await pixel(c, 4, 16), paper);
    await c.save();
    final imported = await compute(
      decodeDocumentFile,
      Uint8List.fromList(utf8.encode(jsonEncode(c.document.toJson()))),
    );
    expect(imported.activeLayer.strokes.single.clip, isNotNull);
    expect(c.document.toJson()['version'], 4);
    c.dispose();
    final reopened = StudioController(storage: LocalStudioStorage(dir));
    await reopened.initialize();
    expect(await pixel(reopened, 16, 16), [255, 0, 0, 255]);
    expect(await pixel(reopened, 4, 16), paper);
    reopened.setSize(128);
    reopened.selectColor(0xff0000ff);
    reopened.setSelection(null);
    line(reopened, y: 640);
    final selected = SelectionRegion.rectangle(
      const ui.Rect.fromLTWH(256, 256, 512, 512),
    );
    reopened.setSelection(selected.invert());
    reopened.selectTool(StudioTool.eraser);
    line(reopened, y: 640);
    expect(await pixel(reopened, 4, 20), paper);
    expect(await pixel(reopened, 16, 20), [0, 0, 255, 255]);
    reopened.dispose();
  });

  test('freehand even-odd selection shares one definition across many strokes and rejects broken references', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    final region = SelectionRegion.lasso(const [
      ui.Offset(128, 128),
      ui.Offset(896, 128),
      ui.Offset(512, 896),
    ]);
    c.setSelection(region);
    c.setSize(128);
    c.selectColor(0xff0000ff);
    for (var i = 0; i < 12; i++) {
      line(c);
    }
    expect(await pixel(c, 16, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 4, 16), paper);
    final json = c.document.toJson();
    expect((json['regions'] as Map).length, 1);
    final reopened = ArtDocument.fromJson(jsonDecode(jsonEncode(json)));
    final clips = reopened.activeLayer.strokes.map((s) => s.clip).toList();
    expect(clips.every((clip) => identical(clip, clips.first)), isTrue);
    json['regions'] = <String, dynamic>{};
    expect(() => ArtDocument.fromJson(json), throwsFormatException);
    final old = c.document.toJson()..['version'] = 3;
    expect(() => ArtDocument.fromJson(old), throwsFormatException);
    expect(
      () => SelectionRegion.lasso(const [
        ui.Offset(0, 0),
        ui.Offset(double.nan, 3),
        ui.Offset(5, 7),
      ]),
      throwsFormatException,
    );
    c.dispose();
  });

  test('layer mask hides pixels nondestructively, can be removed and undone, and persists', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await c.addImageLayer(await blueImage(), 'Image');
    final original = c.document.activeLayer.raster;
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 512, 1024)),
    );
    expect(c.maskLayerFromSelection(), isTrue);
    expect(c.selection, isNull);
    expect(await pixel(c, 8, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 24, 16), paper);
    expect(c.document.activeLayer.raster, same(original));
    final decoded = ArtDocument.fromJson(
      jsonDecode(jsonEncode(c.document.toJson())),
    );
    expect(decoded.activeLayer.mask, isNotNull);
    expect(decoded.activeLayer.raster!.tiles.keys, original!.tiles.keys);
    c.updateLayer(
      c.document.activeLayerId,
      (layer) => layer.copyWith(clearMask: true),
    );
    expect(await pixel(c, 24, 16), [0, 0, 255, 255]);
    c.undo();
    expect(await pixel(c, 24, 16), paper);
    c.redo();
    expect(c.document.activeLayer.mask, isNull);
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 512, 1024)),
    );
    c.maskLayerFromSelection();
    final mask = c.document.activeLayer.mask;
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(128, 256, 128, 512)),
    );
    await c.deleteSelectedPixels();
    expect(c.document.activeLayer.mask, same(mask));
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(clearMask: true));
    expect(await pixel(c, 24, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 6, 16), paper);
    c.dispose();
  });

  test('moving selected pixels preserves everything else and moving eraser holes reveal stationary source', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setSize(128);
    c.selectColor(0xff00ff00);
    line(c);
    await c.addImageLayer(await blueImage(), 'Top');
    c.selectColor(0xffff0000);
    line(c, x1: 300, x2: 450);
    c.setSize(128);
    c.selectTool(StudioTool.eraser);
    c.beginStroke(const InkPoint(384, 512, .5), simulatePressure: false);
    c.finishStroke();
    final before = c.document;
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(256, 256, 256, 512)),
    );
    expect(c.beginTransform(), isTrue);
    c.previewTransform(
      c.transformDraft!.copyWith(translation: const ui.Offset(256, 0)),
    );
    expect(await pixel(c, 4, 16, preview: true), [0, 0, 255, 255]);
    expect(await pixel(c, 10, 16, preview: true), [0, 255, 0, 255]);
    expect(await pixel(c, 20, 16, preview: true), [0, 0, 255, 255]);
    expect(await pixel(c, 17, 16, preview: true), [255, 0, 0, 255]);
    await c.applyTransform();
    expect(c.selection, isNull);
    expect(await pixel(c, 4, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 10, 16), [0, 255, 0, 255]);
    expect(await pixel(c, 20, 16), [0, 0, 255, 255]);
    expect(await pixel(c, 17, 16), [255, 0, 0, 255]);
    c.undo();
    expect(c.document, same(before));
    expect(c.document.activeLayer.strokes, hasLength(2));
    c.dispose();
  });

  test('erase selection is one undo step and exported mask uses white selected, black protected', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await c.addImageLayer(await blueImage(), 'Blue');
    final before = c.document;
    final region = SelectionRegion.rectangle(
      const ui.Rect.fromLTWH(256, 256, 512, 512),
    );
    c.setSelection(region);
    final png = await renderSelectionMaskPng(region, CanvasSize.legacy);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    expect(raw.sublist((512 * 1024 + 512) * 4, (512 * 1024 + 512) * 4 + 4), [
      255,
      255,
      255,
      255,
    ]);
    expect(raw.sublist((512 * 1024 + 100) * 4, (512 * 1024 + 100) * 4 + 4), [
      0,
      0,
      0,
      255,
    ]);
    image.dispose();
    codec.dispose();
    await c.deleteSelectedPixels();
    expect(await pixel(c, 16, 16), paper);
    expect(await pixel(c, 4, 16), [0, 0, 255, 255]);
    c.undo();
    expect(c.document, same(before));
    expect(await pixel(c, 16, 16), [0, 0, 255, 255]);
    c.dispose();
  });
  test('transforming a masked layer matches its preview and undo restores editable source and mask', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await c.addImageLayer(await blueImage(), 'Masked source');
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 512, 1024)),
    );
    c.maskLayerFromSelection();
    final before = c.document;
    expect(c.beginTransform(), isTrue);
    c.previewTransform(
      c.transformDraft!.copyWith(translation: const ui.Offset(512, 0)),
    );
    expect(await pixel(c, 8, 16, preview: true), paper);
    expect(await pixel(c, 24, 16, preview: true), [0, 0, 255, 255]);
    await c.applyTransform();
    expect(c.document.activeLayer.mask, isNull);
    expect(await pixel(c, 8, 16), paper);
    expect(await pixel(c, 24, 16), [0, 0, 255, 255]);
    c.undo();
    expect(c.document, same(before));
    expect(c.document.activeLayer.raster!.tiles, isNotEmpty);
    expect(c.document.activeLayer.mask, isNotNull);
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(clearMask: true));
    expect(await pixel(c, 24, 16), [0, 0, 255, 255]);
    c.dispose();
  });
}
