import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/drawing/raster_tiles.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

final charcoal = initialBrushes.firstWhere((b) => b.id == 'mypaint-charcoal');

Future<void> stroke(StudioController c, double x1, double x2, double y) async {
  var t = const Duration(seconds: 1);
  c.beginStroke(InkPoint(x1, y, .8), simulatePressure: false, time: t);
  for (var x = x1 + 4; x <= x2; x += 4) {
    t += const Duration(milliseconds: 8);
    c.appendPoint(InkPoint(x, y, .8), time: t);
  }
  c.finishStroke();
  await c.settleStroke();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stroke re-encodes only the tiles it touches; history shares the '
      'rest', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectBrush(charcoal);
    c.setSize(20);
    await stroke(c, 40, 200, 60);
    final first = c.document.activeLayer.raster!;
    expect(first.tiles.keys, [0]);
    await stroke(c, 800, 980, 900);
    final second = c.document.activeLayer.raster!;
    expect(second.tiles.keys.toSet(), {0, 15});
    expect(second.tiles[0], same(first.tiles[0]));
    c.undo();
    await c.settleStroke();
    expect(c.document.activeLayer.raster, same(first));
  });

  test('a canvas-sized legacy raster converts to tiles byte for byte and '
      'saves as version 5', () async {
    const extent = 1024;
    final rgba = Uint8List(extent * extent * 4);
    for (var y = 100; y < 700; y++) {
      for (var x = 300; x < 620; x++) {
        final i = (y * extent + x) * 4;
        rgba
          ..[i] = x & 255
          ..[i + 1] = y & 255
          ..[i + 2] = 200
          // Low alpha would drift through a premultiplied GPU round trip.
          ..[i + 3] = 1 + (x + y) % 9;
      }
    }
    final legacy = RasterAsset(
      id: newId(),
      png: encodeRgbaPng(rgba, extent, extent),
      width: extent,
      height: extent,
    );
    final layer = ArtLayer(id: newId(), name: 'Old', legacyRaster: legacy);
    final storage = MemoryStorage()
      ..document = ArtDocument(
        id: newId(),
        name: 'Before tiles',
        layers: [layer],
        activeLayerId: layer.id,
      );
    expect(storage.document!.toJson()['version'], 2);
    final c = StudioController(storage: storage);
    addTearDown(c.dispose);
    await c.initialize();
    final converted = c.document.activeLayer;
    expect(converted.legacyRaster, isNull);
    // Rows 100–699, columns 300–619 touch tile rows 0–2 and columns 1–2.
    expect(converted.raster!.tiles.keys.toSet(), {1, 2, 5, 6, 9, 10});
    final pngs = {
      for (final MapEntry(:key, :value) in converted.raster!.tiles.entries)
        key: value.png,
    };
    expect(assembleTiles(pngs, c.document.grid), rgba);
    expect(c.rasters.images.keys.toSet(), documentRasters(c.document).toSet());
    c.renameDocument('After tiles');
    await c.save();
    expect(storage.document!.toJson()['version'], 5);
  });

  test(
    'neighbouring and edge tiles meet without seams at a fractional zoom',
    () async {
      const size = TiledRaster.size;
      final red = Uint8List(size * size * 4);
      for (var i = 0; i < red.length; i += 4) {
        red
          ..[i] = 255
          ..[i + 3] = 255;
      }
      final png = encodeRgbaPng(red, size, size);
      // Not square and not a multiple of the tile size: edge tiles are cut.
      const dimensions = CanvasSize(1000, 700);
      final grid = TileGrid(dimensions);
      final raster = TiledRaster(grid, {
        for (var i = 0; i < grid.count; i++)
          i: RasterAsset(id: newId(), png: png, width: size, height: size),
      });
      final layer = ArtLayer(id: newId(), name: 'Fill', raster: raster);
      final doc = ArtDocument(
        id: newId(),
        name: 'Seams',
        layers: [layer],
        activeLayerId: layer.id,
        dimensions: dimensions,
        background: 0xff00ff00,
      );
      final cache = RasterCache();
      addTearDown(cache.dispose);
      await cache.prepare(documentRasters(doc));
      const scale = .613;
      final width = (dimensions.width * scale).floor();
      final height = (dimensions.height * scale).floor();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(scale);
      paintDocument(
        canvas,
        doc,
        FreehandBrushEngine(),
        rasterImages: cache.images,
      );
      final image = await recorder.endRecording().toImage(width, height);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      var seams = 0;
      for (var y = 0; y < height - 1; y++) {
        for (var x = 0; x < width - 1; x++) {
          // The green paper must not show through anywhere inside the canvas.
          if (data.getUint8((y * width + x) * 4 + 1) > 8) seams++;
        }
      }
      expect(seams, 0);
    },
  );
}
