import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:artblend_brush_engine/brush_worker.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native brush pixels survive ArtBlend save and reopen as editable layer pixels', () async {
    final worker = await BrushWorker.create(width: 128, height: 128);
    addTearDown(worker.close);
    await worker.configure(diameter: 16, hue: 0, saturation: 1, value: 1);
    await worker.beginStroke();
    await worker.points([
      (16, 64, 0, 0, 0, 0.05),
      for (int x = 16; x < 112; x++) (x.toDouble(), 64, 1, 0, 0, 0.01),
    ]);
    final pixels = await worker.readRgba();
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      128,
      128,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    final image = await decoded.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final asset = RasterAsset(
      id: newId(),
      png: png!.buffer.asUint8List(),
      width: 128,
      height: 128,
    );
    final document = ArtDocument.empty();
    final painted = document.copyWith(
      layers: [document.activeLayer.copyWith(legacyRaster: asset)],
    );
    final storage = MemoryStorage();
    final controller = StudioController(storage: storage);
    await controller.initialize();
    await controller.replaceDocument(painted);
    await controller.save();
    controller.dispose();
    final reopened = StudioController(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    final restored = ArtDocument.fromJson(
      jsonDecode(jsonEncode(reopened.document.toJson()))
          as Map<String, dynamic>,
    );
    // The pre-tile raster was converted on opening and saved as tiles.
    expect(restored.activeLayer.legacyRaster, isNull);
    // The 128² image fills the canvas: its centre lands in tile 10 at (0, 0).
    final tile = restored.activeLayer.raster!.tiles[10]!;
    final cached = reopened
        .rasters
        .images[reopened.document.activeLayer.raster!.tiles[10]]!;
    expect(cached.width, TiledRaster.size);
    final codec = await ui.instantiateImageCodec(tile.png);
    final frame = (await codec.getNextFrame()).image;
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.dispose();
    expect(rgba!.getUint8(0), greaterThan(240));
    expect(rgba.getUint8(3), greaterThan(200));
    // Existing document raster pipeline remains valid for native output.
    expect(
      await renderDocumentPng(reopened.document, reopened.rasters.images),
      isNotEmpty,
    );
  });
  test('imported brush sizes remain within the tool slider range after restore and selection', () async {
    const large = BrushPreset(
      id: 'large',
      name: 'Large',
      size: 200,
      thinning: 0,
      smoothing: 0.5,
    );
    final storage = MemoryStorage()
      ..library = {
        'brushes': [large.toJson()],
        'palettes': [],
      };
    final controller = StudioController(storage: storage);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.initialized, isTrue);
    expect(controller.size, 128);
    controller.selectBrush(initialBrushes.first);
    controller.selectBrush(large);
    expect(controller.size, 128);
    expect(controller.brush.size, 200);
  });
}
