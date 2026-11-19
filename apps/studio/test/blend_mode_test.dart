import 'dart:convert';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

/// Drawings made by these tests use the default 1024² canvas.
const legacyExtent = 1024.0;

Future<List<int>> centerPixel(
  StudioController c, {
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
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List().sublist(
    (16 * 32 + 16) * 4,
    (16 * 32 + 16) * 4 + 4,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('normal, multiply and screen composite actual pixels and survive versioned round-trip', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    void ink(int color) {
      c.selectColor(color);
      c.setSize(128);
      c.beginStroke(const InkPoint(100, 512, .5), simulatePressure: false);
      c.appendPoint(const InkPoint(924, 512, .5));
      c.finishStroke();
    }

    ink(0xff804020);
    c.addLayer('Color glaze');
    ink(0xff4080c0);
    final id = c.document.activeLayerId;
    expect(await centerPixel(c), [64, 128, 192, 255]);
    c.updateLayer(id, (l) => l.copyWith(blend: LayerBlend.multiply));
    expect(await centerPixel(c), [32, 32, 24, 255]);
    expect(c.document.toJson()['version'], 3);
    final decoded = ArtDocument.fromJson(
      jsonDecode(jsonEncode(c.document.toJson())),
    );
    expect(decoded.activeLayer.blend, LayerBlend.multiply);
    c.undo();
    expect(c.document.activeLayer.blend, LayerBlend.normal);
    expect(c.document.toJson()['version'], 1);
    c.redo();
    c.updateLayer(id, (l) => l.copyWith(opacity: .5));
    final half = await centerPixel(c);
    for (var i = 0; i < 3; i++) {
      expect(half[i], closeTo([80, 48, 28][i], 1));
    }
    c.updateLayer(id, (l) => l.copyWith(blend: LayerBlend.screen, opacity: 1));
    expect(await centerPixel(c), [160, 160, 200, 255]);
    final invalid = c.document.toJson()..['version'] = 2;
    expect(() => ArtDocument.fromJson(invalid), throwsFormatException);
    final invalidLayer = c.document.activeLayer.toJson()
      ..['blend'] = 'unrecognized';
    expect(
      () => ArtLayer.fromJson(invalidLayer, TileGrid(CanvasSize.legacy)),
      throwsFormatException,
    );
    c.dispose();
  });

  test('applying a transform never bakes opacity or the backdrop blend into source pixels', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setSize(128);
    c.selectColor(0xff4080c0);
    c.beginStroke(const InkPoint(200, 512, .5), simulatePressure: false);
    c.appendPoint(const InkPoint(824, 512, .5));
    c.finishStroke();
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(opacity: .5, blend: LayerBlend.multiply),
    );
    expect(c.beginTransform(), isTrue);
    c.previewTransform(c.transformDraft!.copyWith(scale: .7));
    final preview = await centerPixel(c, preview: true);
    await c.applyTransform();
    expect(await centerPixel(c), preview);
    expect(c.document.activeLayer.blend, LayerBlend.multiply);
    expect(c.document.activeLayer.opacity, .5);
    c.dispose();
  });
}
