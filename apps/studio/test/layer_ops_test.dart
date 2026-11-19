import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

/// A 64² solid square PNG.
Uint8List square(int r, int g, int b) {
  final rgba = Uint8List(64 * 64 * 4);
  for (var i = 0; i < 64 * 64; i++) {
    rgba
      ..[i * 4] = r
      ..[i * 4 + 1] = g
      ..[i * 4 + 2] = b
      ..[i * 4 + 3] = 255;
  }
  return encodeRgbaPng(rgba, 64, 64);
}

Future<Uint8List> pixels(StudioController c) async {
  final recorder = ui.PictureRecorder();
  paintDocument(
    ui.Canvas(recorder),
    c.document,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final image = await recorder.endRecording().toImage(1024, 1024);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'layers duplicate, reorder, clear and add above the active one',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      final base = c.document.activeLayerId;
      c.addLayer('Top');
      final top = c.document.activeLayerId;
      c.selectLayer(base);
      c.addLayer('Middle');
      expect(c.document.layers.map((l) => l.name), [
        c.document.layers.first.name,
        'Middle',
        'Top',
      ]);
      await c.addImageLayer(square(200, 40, 40), 'Red');
      final red = c.document.activeLayer;
      c.duplicateLayer(red.id, 'Red copy');
      final copy = c.document.activeLayer;
      expect(copy.id, isNot(red.id));
      expect(copy.raster, same(red.raster), reason: 'tiles are shared');
      expect(
        c.document.layers.indexOf(copy),
        c.document.layers.indexOf(red) + 1,
      );
      c.reorderLayer(copy.id, 0);
      expect(c.document.layers.first.id, copy.id);
      c.clearLayer(copy.id);
      expect(c.document.layers.first.raster, isNull);
      c.undo();
      expect(c.document.layers.first.raster, same(red.raster));
      expect(c.document.layers.any((l) => l.id == top), isTrue);
    },
  );

  test(
    'merge down bakes the upper layer as it looks into the lower one',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      await c.addImageLayer(square(200, 200, 200), 'Grey');
      await c.addImageLayer(square(40, 80, 220), 'Blue');
      c.updateLayer(
        c.document.activeLayerId,
        (l) => l.copyWith(blend: LayerBlend.multiply, opacity: .5),
      );
      final before = await pixels(c);
      final count = c.document.layers.length;
      final grey = c.document.layers[count - 2];
      await c.mergeDown(c.document.activeLayerId);
      expect(c.document.layers, hasLength(count - 1));
      expect(c.document.activeLayer.id, grey.id);
      expect(c.document.activeLayer.name, 'Grey');
      final after = await pixels(c);
      var largest = 0;
      for (var i = 0; i < before.length; i++) {
        final d = (before[i] - after[i]).abs();
        if (d > largest) largest = d;
      }
      expect(largest, lessThanOrEqualTo(2));
      c.undo();
      expect(c.document.layers, hasLength(count));
    },
  );

  test('every blend mode survives saving', () {
    for (final blend in LayerBlend.values) {
      final layer = ArtLayer(id: 'l', name: 'L', blend: blend);
      final back = ArtLayer.fromJson(
        layer.toJson(),
        TileGrid(CanvasSize.legacy),
      );
      expect(back.blend, blend);
    }
  });
}
