import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/document.dart';
import 'brush_engine.dart';
import 'layer_transform.dart';
import 'png_bands.dart';
import 'raster_tiles.dart';
import '../domain/selection.dart';

/// Owns native image handles independently of immutable document history.
class RasterCache {
  final Map<RasterAsset, ui.Image> images = {};
  final Map<RasterAsset, ui.Rect?> pixelBounds = {};
  bool _disposed = false;

  Future<void> prepare(Iterable<RasterAsset> assets) async {
    final added = <RasterAsset, ui.Image>{};
    final addedBounds = <RasterAsset, ui.Rect?>{};
    try {
      for (final asset in assets.toSet()) {
        if (images.containsKey(asset)) continue;
        final codec = await ui.instantiateImageCodec(asset.png);
        try {
          final frame = await codec.getNextFrame();
          added[asset] = frame.image;
          if (frame.image.width != asset.width ||
              frame.image.height != asset.height) {
            throw const FormatException(
              'Decoded raster dimensions do not match',
            );
          }
          addedBounds[asset] = pixelBounds.containsKey(asset)
              ? pixelBounds[asset]
              : await _opaqueBounds(frame.image);
        } finally {
          codec.dispose();
        }
      }
      if (_disposed) throw StateError('Raster cache closed');
      for (final entry in added.entries) {
        if (images.containsKey(entry.key)) {
          entry.value.dispose();
        } else {
          images[entry.key] = entry.value;
          pixelBounds[entry.key] = addedBounds[entry.key];
        }
      }
    } catch (_) {
      for (final image in added.values) {
        image.dispose();
      }
      rethrow;
    }
  }

  Future<ui.Rect?> _opaqueBounds(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Cannot read image alpha');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    var left = image.width, top = image.height, right = -1, bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (bytes[(y * image.width + x) * 4 + 3] == 0) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return right < 0
        ? null
        : ui.Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            (right + 1).toDouble(),
            (bottom + 1).toDouble(),
          );
  }

  /// Takes ownership of an image already decoded from [asset]'s pixels.
  void adopt(RasterAsset asset, ui.Image image, ui.Rect? bounds) {
    if (_disposed) {
      image.dispose();
      throw StateError('Raster cache closed');
    }
    images.remove(asset)?.dispose();
    images[asset] = image;
    pixelBounds[asset] = bounds;
  }

  /// Keeps decoded images only for [decoded]. Alpha bounds, cheap to keep
  /// and costly to recompute, survive for [known] assets as well.
  void retain(Set<RasterAsset> decoded, [Set<RasterAsset> known = const {}]) {
    for (final key in images.keys.toList()) {
      if (!decoded.contains(key)) images.remove(key)!.dispose();
    }
    pixelBounds.removeWhere(
      (key, _) => !decoded.contains(key) && !known.contains(key),
    );
  }

  void dispose() {
    _disposed = true;
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
    pixelBounds.clear();
  }
}

Iterable<RasterAsset> layerRasters(ArtLayer layer) sync* {
  final tiles = layer.raster?.tiles.values;
  if (tiles != null) yield* tiles;
  final legacy = layer.legacyRaster;
  if (legacy != null) yield legacy;
}

Iterable<RasterAsset> documentRasters(ArtDocument doc) =>
    doc.layers.expand(layerRasters);

/// Decode through Flutter's native codec, bound source dimensions before
/// allocating pixels, and normalize imports to a single-frame PNG.
Future<RasterAsset> importRaster(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
    throw const FormatException('Image exceeds import size limit');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width > 8192 ||
        descriptor.height > 8192 ||
        descriptor.width * descriptor.height > 32 * 1024 * 1024) {
      throw const FormatException('Image dimensions exceed import limits');
    }
    final ratio = math.min(
      1.0,
      4096 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * ratio).round()),
      targetHeight: math.max(1, (descriptor.height * ratio).round()),
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Cannot encode image');
    return RasterAsset(
      id: newId(),
      png: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> renderDocumentPng(
  ArtDocument document,
  Map<RasterAsset, ui.Image> images,
) async {
  final recorder = ui.PictureRecorder();
  paintDocument(
    ui.Canvas(recorder),
    document,
    FreehandBrushEngine(),
    rasterImages: images,
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      document.dimensions.width,
      document.dimensions.height,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('PNG encoding failed');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// The layer as displayed (mask applied, no opacity or blend), baked into
/// tiles; strokes become pixels.
Future<RenderedTiles> rasterizeLayer(
  ArtLayer layer,
  TileGrid grid,
  Map<RasterAsset, ui.Image> images, {
  LayerTransform? transform,
  SelectionRegion? transformSelection,
  SelectionRegion? keepSelection,
}) => renderTiles(grid, (canvas) {
  final soft = keepSelection != null && keepSelection.feather > 0;
  if (soft) {
    canvas.saveLayer(grid.dimensions.rect, ui.Paint());
  } else if (keepSelection != null) {
    canvas.clipPath(keepSelection.path);
  }
  paintLayer(
    canvas,
    layer,
    FreehandBrushEngine(),
    grid.dimensions,
    rasterImages: images,
    transform: transform,
    transformSelection: transformSelection,
    applyOpacity: false,
  );
  if (soft) {
    keepInside(canvas, keepSelection, grid.dimensions.rect);
    canvas.restore();
  }
});

/// An imported image fitted and centred on the canvas, as tiles.
/// Draws [image] fitted to the canvas, or stretched over [target].
Future<RenderedTiles> placeRaster(
  RasterAsset asset,
  ui.Image image,
  TileGrid grid, {
  ui.Rect? target,
}) => renderTiles(
  grid,
  (canvas) => canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, asset.width.toDouble(), asset.height.toDouble()),
    target ?? rasterBounds(asset, grid.dimensions),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  ),
);

/// The selection as a black-and-white PNG (white selected), for exporting.
Future<Uint8List> renderSelectionMaskPng(
  SelectionRegion selection,
  CanvasSize dimensions,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  canvas.drawPath(selection.path, selection.coveragePaint);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(dimensions.width, dimensions.height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Mask encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Pixels generative fill aims for: what image models are trained on.
const generativeFillPixels = 1024 * 1024;

/// The part of the drawing generative fill sends for [selection]: its
/// bounds plus surroundings for context, scaled to about
/// [generativeFillPixels] (small selections up to 4×) in multiples of 16.
/// Never the whole large canvas.
({ui.Rect area, int width, int height}) generativeFillArea(
  ui.Rect selection,
  CanvasSize dimensions,
) {
  final pad = math.max(32.0, math.max(selection.width, selection.height) * .15);
  final area = ui.Rect.fromLTRB(
    math.max(0.0, (selection.left - pad).floorToDouble()),
    math.max(0.0, (selection.top - pad).floorToDouble()),
    math.min(
      dimensions.width.toDouble(),
      (selection.right + pad).ceilToDouble(),
    ),
    math.min(
      dimensions.height.toDouble(),
      (selection.bottom + pad).ceilToDouble(),
    ),
  );
  final scale = math.min(
    math.min(4.0, 2048 / math.max(area.width, area.height)),
    math.sqrt(generativeFillPixels / (area.width * area.height)),
  );
  int side(double v) => math.max(64, (v * scale / 16).round() * 16);
  return (area: area, width: side(area.width), height: side(area.height));
}

/// What generative fill sends for [selection]: the visible drawing in
/// [area] at [width] × [height] as one PNG whose alpha marks the repaint
/// area (transparent inside the selection), the OpenAI edit convention the
/// hub accepts for every workflow. Colors stay under the transparent
/// pixels, so a model can still see what it repaints.
Future<Uint8List> renderGenerativeFill(
  ArtDocument document,
  Map<RasterAsset, ui.Image> images,
  SelectionRegion selection,
  ui.Rect area,
  int width,
  int height,
) async {
  Future<Uint8List> pixels(void Function(ui.Canvas) paint) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(width / area.width, height / area.height)
      ..translate(-area.left, -area.top)
      ..clipRect(area);
    paint(canvas);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) throw StateError('Cannot read the drawing');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  final drawing = await pixels(
    (canvas) => paintDocument(
      canvas,
      document,
      FreehandBrushEngine(),
      rasterImages: images,
      visible: area,
    ),
  );
  final coverage = await pixels(
    (canvas) => canvas.drawPath(selection.path, selection.coveragePaint),
  );
  return _encodeFillOffThread(drawing, coverage, width, height);
}

/// What a vision model sees when writing a fill prompt: the drawing around
/// [selection] (the generative fill area) at most [maxSide] pixels, with
/// the selection outlined in magenta. Opaque PNG.
Future<Uint8List> renderSelectionPreview(
  ArtDocument document,
  Map<RasterAsset, ui.Image> images,
  SelectionRegion selection, {
  int maxSide = 512,
}) async {
  final bounds = selection.bounds.intersect(document.dimensions.rect);
  final (:area, width: _, height: _) = generativeFillArea(
    bounds,
    document.dimensions,
  );
  final scale = math.min(1.0, maxSide / math.max(area.width, area.height));
  final width = math.max(1, (area.width * scale).round());
  final height = math.max(1, (area.height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..scale(width / area.width, height / area.height)
    ..translate(-area.left, -area.top)
    ..clipRect(area);
  paintDocument(
    canvas,
    document,
    FreehandBrushEngine(),
    rasterImages: images,
    visible: area,
  );
  canvas.drawPath(
    selection.path,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3 * area.width / width
      ..color = const ui.Color(0xffff00cc),
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Cannot read the drawing');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Its own function: a closure made inside [renderGenerativeFill] would
/// share that context (images included) and could not be sent.
Future<Uint8List> _encodeFillOffThread(
  Uint8List drawing,
  Uint8List coverage,
  int width,
  int height,
) => Isolate.run(() => _encodeFill(drawing, coverage, width, height));

Uint8List _encodeFill(
  Uint8List drawing,
  Uint8List coverage,
  int width,
  int height,
) {
  for (var i = 3; i < drawing.length; i += 4) {
    drawing[i] = 255 - coverage[i];
  }
  return encodeRgbaPng(drawing, width, height, level: 1);
}
