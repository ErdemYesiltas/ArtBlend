import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/layer_compositor.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const dimensions = CanvasSize(600, 400);

/// A layer of soft diagonal bands in one colour, on every tile.
ArtLayer bands(String id, int r, int g, int b, {int seed = 0}) {
  final grid = TileGrid(dimensions);
  const size = TiledRaster.size;
  return ArtLayer(
    id: id,
    name: id,
    raster: TiledRaster(grid, {
      for (var i = 0; i < grid.count; i++)
        i: () {
          final (ox, oy) = grid.origin(i);
          final rgba = Uint8List(size * size * 4);
          for (var y = 0; y < size; y++) {
            for (var x = 0; x < size; x++) {
              final p = (y * size + x) * 4;
              rgba
                ..[p] = r
                ..[p + 1] = g
                ..[p + 2] = b
                ..[p + 3] = ((ox + x + oy + y + seed * 40) * 3) % 256;
            }
          }
          return RasterAsset(
            id: newId(),
            png: encodeRgbaPng(rgba, size, size),
            width: size,
            height: size,
          );
        }(),
    }),
  );
}

Future<Uint8List> render(void Function(ui.Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    dimensions.width,
    dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a composited frame has the same pixels as drawing every layer, '
      'and painting the active layer never rebuilds it', () async {
    final layers = [
      bands('a', 200, 40, 40),
      bands('b', 40, 160, 60, seed: 1).copyWith(opacity: .6),
      bands('c', 30, 60, 220, seed: 2).copyWith(blend: LayerBlend.multiply),
      bands('d', 250, 200, 0, seed: 3).copyWith(
        mask: SelectionRegion.rectangle(
          const ui.Rect.fromLTWH(80, 40, 300, 260),
        ),
      ),
      bands('e', 90, 90, 90, seed: 4).copyWith(visible: false),
      bands('f', 10, 200, 200, seed: 5).copyWith(opacity: .4),
    ];
    final cache = RasterCache();
    addTearDown(cache.dispose);
    var ready = Completer<void>();
    final compositor = LayerCompositor(
      onReady: () {
        if (!ready.isCompleted) ready.complete();
      },
    );
    addTearDown(compositor.dispose);
    for (final activeId in ['b', 'c', 'd']) {
      final doc = ArtDocument(
        id: 'doc',
        name: 'Layers',
        layers: layers,
        activeLayerId: activeId,
        dimensions: dimensions,
      );
      await cache.prepare(documentRasters(doc));
      ready = Completer();
      expect(compositor.frame(doc, cache.images), isNull);
      await ready.future;
      final frame = compositor.frame(doc, cache.images)!;
      // Above 'c' sits only normal layers: flattened. Above 'b' is the
      // multiply layer: drawn one by one.
      expect(frame.flat, activeId != 'b');
      final expected = await render(
        (canvas) => paintDocument(
          canvas,
          doc,
          FreehandBrushEngine(),
          rasterImages: cache.images,
        ),
      );
      final composited = await render(
        (canvas) => paintComposited(
          canvas,
          doc,
          FreehandBrushEngine(),
          frame,
          rasterImages: cache.images,
        ),
      );
      var largest = 0;
      for (var i = 0; i < expected.length; i++) {
        final d = (expected[i] - composited[i]).abs();
        if (d > largest) largest = d;
      }
      // Flattening rounds once more through 8-bit premultiplied pixels.
      expect(largest, lessThanOrEqualTo(2), reason: 'active $activeId');

      // A new version of the active layer keeps the composites.
      final painted = doc.copyWith(
        layers: [
          for (final layer in doc.layers)
            layer.id == activeId ? layer.copyWith(opacity: .9) : layer,
        ],
      );
      expect(compositor.frame(painted, cache.images), isNotNull);
    }
  });
}
