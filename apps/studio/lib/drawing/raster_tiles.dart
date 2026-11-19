import 'dart:math' as math;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:artblend_brush_engine/brush_worker.dart' show premultiplyRgba;

import '../domain/document.dart';
import 'png_bands.dart';

/// Opaque pixel bounds inside one tile (left, top, right, bottom), or null.
typedef TileBounds = (int, int, int, int);

/// One tile re-encoded off the UI isolate: [png] null means it became fully
/// transparent and is dropped.
class TileUpdate {
  const TileUpdate(this.index, this.png, this.premultiplied, this.bounds);
  final int index;
  final Uint8List? png;

  /// Same pixels, premultiplied for a direct GPU upload.
  final Uint8List? premultiplied;
  final TileBounds? bounds;
}

/// The [TiledRaster.size]² tile whose top-left is ([x], [y]) in a
/// [width] × [height] straight RGBA buffer; parts past the buffer edge (an
/// edge tile of a canvas that is not a multiple of the tile size) are
/// transparent.
Uint8List cropTile(Uint8List rgba, int width, int height, int x, int y) {
  const size = TiledRaster.size;
  final out = Uint8List(size * size * 4);
  final columns = (width - x).clamp(0, size);
  final rows = (height - y).clamp(0, size);
  for (var row = 0; row < rows; row++) {
    final from = ((y + row) * width + x) * 4;
    out.setRange(row * size * 4, row * size * 4 + columns * 4, rgba, from);
  }
  return out;
}

TileBounds? tileAlphaBounds(Uint8List tile) {
  const size = TiledRaster.size;
  var left = size, top = size, right = -1, bottom = -1;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (tile[(y * size + x) * 4 + 3] == 0) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return right < 0 ? null : (left, top, right + 1, bottom + 1);
}

/// zlib level for tiles. A commit re-encodes every tile a stroke touched
/// while the user keeps drawing: on grainy brush paint level 1 measured ~7×
/// faster than 6 for tiles ~12% larger (smooth paint: ~4× for ~36% of a few
/// KiB). Saves are incremental, so the size rarely matters.
const tileDeflateLevel = 1;

/// Isolates tile encoding is spread over, leaving cores for the UI and
/// raster threads and the brush worker.
final tileEncoders = math.max(1, math.min(4, Platform.numberOfProcessors - 2));

/// Encodes one cut [TiledRaster.size]² straight-alpha tile losslessly as
/// tile [index].
TileUpdate encodeCutTile(int index, Uint8List tile) {
  const size = TiledRaster.size;
  final bounds = tileAlphaBounds(tile);
  if (bounds == null) return TileUpdate(index, null, null, null);
  return TileUpdate(
    index,
    encodeRgbaPng(tile, size, size, level: tileDeflateLevel),
    premultiplyRgba(Uint8List.fromList(tile)),
    bounds,
  );
}

/// Encodes cut tiles on [tileEncoders] background isolates at once. Call it
/// where the tiles already are (e.g. inside the isolate that cut them), so
/// the UI isolate never copies them.
Future<List<TileUpdate>> encodeTiles(List<(int, Uint8List)> tiles) async {
  if (tiles.isEmpty) return const [];
  final groups = math.min(tileEncoders, tiles.length);
  final parts = [
    for (var g = 0; g < groups; g++)
      [for (var k = g; k < tiles.length; k += groups) tiles[k]],
  ];
  final encoded = await Future.wait([
    for (final part in parts)
      Isolate.run(() => [for (final (i, t) in part) encodeCutTile(i, t)]),
  ]);
  return [for (final group in encoded) ...group];
}

/// The tiles of a whole-layer buffer that hold any pixel, cut out.
List<(int, Uint8List)> cutAllTiles(Uint8List rgba, TileGrid grid) {
  final CanvasSize(:width, :height) = grid.dimensions;
  return [
    for (var i = 0; i < grid.count; i++)
      if (cropTile(rgba, width, height, grid.origin(i).$1, grid.origin(i).$2)
          case final tile when tileAlphaBounds(tile) != null)
        (i, tile),
  ];
}

/// Straight RGBA of a whole layer from its tiles, decoded with the exact PNG
/// decoder, or null when a tile is not in the 8-bit RGBA form we write.
Uint8List? assembleTiles(Map<int, Uint8List> pngs, TileGrid grid) {
  const size = TiledRaster.size;
  final CanvasSize(:width, :height) = grid.dimensions;
  final out = Uint8List(width * height * 4);
  for (final MapEntry(:key, :value) in pngs.entries) {
    final tile = decodeRgbaPng(value, size, size);
    if (tile == null) return null;
    final (x, y) = grid.origin(key);
    final columns = (width - x).clamp(0, size);
    for (var row = 0; row < size && y + row < height; row++) {
      out.setRange(
        ((y + row) * width + x) * 4,
        ((y + row) * width + x + columns) * 4,
        tile,
        row * size * 4,
      );
    }
  }
  return out;
}

/// Raster tiles plus what the cache needs to show them without decoding.
class RenderedTiles {
  const RenderedTiles(this.raster, this.updates);
  final TiledRaster? raster;
  final List<TileUpdate> updates;
  Iterable<(RasterAsset, TileUpdate)> get assets sync* {
    final tiles = raster?.tiles;
    if (tiles == null) return;
    for (final update in updates) {
      final asset = tiles[update.index];
      if (asset != null) yield (asset, update);
    }
  }
}

/// Tiles of a straight-alpha layer buffer, encoded on a background isolate.
Future<RenderedTiles> tilesFromRgba(Uint8List rgba, TileGrid grid) async {
  final updates = await Isolate.run(() => encodeTiles(cutAllTiles(rgba, grid)));
  if (updates.isEmpty) return const RenderedTiles(null, []);
  return RenderedTiles(
    TiledRaster(grid, {
      for (final update in updates)
        update.index: RasterAsset(
          id: newId(),
          png: update.png!,
          width: TiledRaster.size,
          height: TiledRaster.size,
        ),
    }),
    updates,
  );
}

/// Draws [paint] at document resolution and cuts the result into tiles.
Future<RenderedTiles> renderTiles(
  TileGrid grid,
  void Function(ui.Canvas) paint,
) async {
  final dimensions = grid.dimensions;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.clipRect(dimensions.rect);
  paint(canvas);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(dimensions.width, dimensions.height);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) throw StateError('Cannot read layer pixels');
    return await tilesFromRgba(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      grid,
    );
  } finally {
    image?.dispose();
    picture.dispose();
  }
}
