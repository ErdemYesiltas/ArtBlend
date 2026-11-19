import 'dart:math' as math;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import '../domain/document.dart';
import 'layer_compositor.dart';
import 'layer_transform.dart';
import 'text_layer.dart';
import '../domain/selection.dart';

abstract interface class BrushEngine {
  Path outline(InkStroke stroke, {bool complete = true});
}

/// Milestone-one backend. Native textured engines can implement the same contract.
class FreehandBrushEngine implements BrushEngine {
  @override
  Path outline(InkStroke stroke, {bool complete = true}) {
    final outline = getStroke(
      stroke.points.map((p) => PointVector(p.x, p.y, p.pressure)).toList(),
      options: StrokeOptions(
        size: stroke.size,
        thinning: stroke.thinning,
        smoothing: stroke.smoothing,
        streamline: .3,
        simulatePressure: stroke.simulatePressure,
        isComplete: complete,
      ),
    );
    final path = Path();
    if (outline.isEmpty) return path;
    path.addPolygon(outline, true);
    return path;
  }
}

/// Live native blocks of one stroke: each tile replaces its square of the
/// layer content (inside [clip] when the stroke was limited by a selection).
class NativeOverlay {
  const NativeOverlay(this.tiles, [this.clip]);
  final List<(Offset, Image)> tiles;
  final SelectionRegion? clip;
}

/// Strokes still drawing or committing on a layer, oldest first, painted over
/// its committed content; later strokes' blocks already contain earlier ones.
class LayerContentOverride {
  const LayerContentOverride(this.overlays, {this.replace});
  final List<NativeOverlay> overlays;

  /// Paints instead of the layer's own content (an adjustment's preview).
  final void Function(Canvas canvas, Rect bounds)? replace;
}

/// An image fitted and centred on the canvas.
Rect rasterBounds(RasterAsset raster, CanvasSize dimensions) {
  final scale = math.min(
    dimensions.width / raster.width,
    dimensions.height / raster.height,
  );
  final width = raster.width * scale, height = raster.height * scale;
  return Rect.fromLTWH(
    (dimensions.width - width) / 2,
    (dimensions.height - height) / 2,
    width,
    height,
  );
}

Rect? layerContentBounds(
  ArtLayer layer,
  BrushEngine engine,
  CanvasSize dimensions, {
  Map<RasterAsset, Rect?>? pixelBounds,
}) {
  Rect? bounds;
  void include(Rect rect) =>
      bounds = bounds == null ? rect : bounds!.expandToInclude(rect);
  if (layer.text case final text?) {
    // Italics and outlines reach a little past the box.
    include(textBounds(text).inflate(text.size * .25));
  }
  for (final MapEntry(:key, :value) in (layer.raster?.tiles ?? {}).entries) {
    const full = Rect.fromLTWH(
      0,
      0,
      TiledRaster.size + .0,
      TiledRaster.size + .0,
    );
    final pixels = pixelBounds?.containsKey(value) == true
        ? pixelBounds![value]
        : full;
    if (pixels == null) continue;
    final (x, y) = layer.raster!.grid.origin(key);
    include(pixels.shift(Offset(x.toDouble(), y.toDouble())));
  }
  final raster = layer.legacyRaster;
  if (raster != null) {
    final pixels = pixelBounds?.containsKey(raster) == true
        ? pixelBounds![raster]
        : Rect.fromLTWH(
            0,
            0,
            raster.width.toDouble(),
            raster.height.toDouble(),
          );
    if (pixels != null) {
      final placement = rasterBounds(raster, dimensions);
      final scale = placement.width / raster.width;
      include(
        Rect.fromLTRB(
          placement.left + pixels.left * scale,
          placement.top + pixels.top * scale,
          placement.left + pixels.right * scale,
          placement.top + pixels.bottom * scale,
        ),
      );
    }
  }
  for (final stroke in layer.strokes) {
    if (stroke.eraser || stroke.opacity == 0 || Color(stroke.color).a == 0) {
      continue;
    }
    include(engine.outline(stroke).getBounds());
  }
  var content = bounds;
  if (content == null) return null;
  if (layer.mask != null) content = content.intersect(layer.mask!.bounds);
  final visible = content.intersect(dimensions.rect);
  return visible.isEmpty ? null : visible;
}

/// The Flutter blend mode for [blend]; for the modes the blend shader
/// paints (see [customBlend]) the nearest one, used where that cannot run.
BlendMode layerBlendMode(LayerBlend blend) => switch (blend) {
  LayerBlend.normal => BlendMode.srcOver,
  LayerBlend.darken => BlendMode.darken,
  LayerBlend.multiply => BlendMode.multiply,
  LayerBlend.colorBurn || LayerBlend.linearBurn => BlendMode.colorBurn,
  LayerBlend.darkerColor => BlendMode.darken,
  LayerBlend.lighten || LayerBlend.lighterColor => BlendMode.lighten,
  LayerBlend.screen => BlendMode.screen,
  LayerBlend.colorDodge => BlendMode.colorDodge,
  LayerBlend.add => BlendMode.plus,
  LayerBlend.overlay => BlendMode.overlay,
  LayerBlend.softLight => BlendMode.softLight,
  LayerBlend.hardLight ||
  LayerBlend.vividLight ||
  LayerBlend.linearLight ||
  LayerBlend.pinLight ||
  LayerBlend.hardMix => BlendMode.hardLight,
  LayerBlend.difference || LayerBlend.subtract => BlendMode.difference,
  LayerBlend.exclusion || LayerBlend.divide => BlendMode.exclusion,
  LayerBlend.hue => BlendMode.hue,
  LayerBlend.saturation => BlendMode.saturation,
  LayerBlend.color => BlendMode.color,
  LayerBlend.luminosity => BlendMode.luminosity,
};

/// The blend shader's mode for [blend], or null when Flutter paints it.
int? customBlend(LayerBlend blend) => switch (blend) {
  LayerBlend.linearBurn => 0,
  LayerBlend.darkerColor => 1,
  LayerBlend.lighterColor => 2,
  LayerBlend.vividLight => 3,
  LayerBlend.linearLight => 4,
  LayerBlend.pinLight => 5,
  LayerBlend.hardMix => 6,
  LayerBlend.subtract => 7,
  LayerBlend.divide => 8,
  _ => null,
};

/// The blend shader, loaded once (the editor loads it on start). Until
/// then its modes fall back to [layerBlendMode].
class BlendShader {
  static FragmentProgram? program;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= () async {
    try {
      program = await FragmentProgram.fromAsset('shaders/blend.frag');
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
}

/// Paints one layer (or a clipping group) onto a canvas of its own.
typedef LayerPainter = void Function(
  Canvas canvas,
  ArtLayer layer, {
  required bool asBase,
});

/// Whether [blend] at this point needs the blend shader.
bool _shaded(LayerBlend blend) =>
    customBlend(blend) != null && BlendShader.program != null;

/// Replaces [bounds] on [canvas] with what [content] paints blended by
/// [blend] at [opacity] over what [backdrop] paints: Flutter cannot read
/// the canvas, so both are drawn to images first.
void paintCustomBlend(
  Canvas canvas,
  Rect bounds,
  LayerBlend blend,
  double opacity,
  void Function(Canvas canvas) backdrop,
  void Function(Canvas canvas) content,
) {
  final width = bounds.width.ceil(), height = bounds.height.ceil();
  Image record(void Function(Canvas canvas) paint) {
    final recorder = PictureRecorder();
    final c = Canvas(recorder)
      ..translate(-bounds.left, -bounds.top)
      ..clipRect(bounds);
    paint(c);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  final back = record(backdrop), layer = record(content);
  final shader = BlendShader.program!.fragmentShader()
    ..setFloat(0, width.toDouble())
    ..setFloat(1, height.toDouble())
    ..setFloat(2, customBlend(blend)!.toDouble())
    ..setFloat(3, opacity)
    ..setImageSampler(0, back)
    ..setImageSampler(1, layer);
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final result = picture.toImageSync(width, height);
  picture.dispose();
  shader.dispose();
  back.dispose();
  layer.dispose();
  canvas.drawImage(
    result,
    bounds.topLeft,
    Paint()
      ..blendMode = BlendMode.src
      ..filterQuality = FilterQuality.none,
  );
  result.dispose();
}

/// Paints [layers] bottom to top, honouring clipping masks: a layer and the
/// clipping layers right above it form a group composited with the base's
/// blend mode and opacity; the clipped layers keep their own blend modes
/// against the base and are then cut to the base's pixels. A hidden base
/// hides its clipped layers; a clipping layer with no base draws plainly.
/// [paint] draws one layer; `asBase` asks for it without its own opacity
/// and blend (the group carries them).
void paintLayerStack(
  Canvas canvas,
  List<ArtLayer> layers,
  Rect bounds,
  LayerPainter paint, {
  void Function(Canvas canvas)? under,
}) {
  for (var i = 0; i < layers.length; i++) {
    final base = layers[i];
    var end = i + 1;
    while (end < layers.length && layers[end].clipping) {
      end++;
    }
    final clipped = [
      for (final l in layers.sublist(i + 1, end))
        if (l.visible && l.opacity > 0) l,
    ];
    if (!base.visible || base.opacity == 0) {
      i = end - 1;
      continue;
    }
    void group(Canvas c) {
      paint(c, base, asBase: true);
      for (final layer in clipped) {
        paint(c, layer, asBase: false);
      }
      // Clipped paint only where the base has pixels.
      c.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
      paint(c, base, asBase: true);
      c.restore();
    }

    if (_shaded(base.blend)) {
      final below = layers.sublist(0, i);
      paintCustomBlend(canvas, bounds, base.blend, base.opacity, (c) {
        under?.call(c);
        paintLayerStack(c, below, bounds, paint, under: under);
      }, clipped.isEmpty ? (c) => paint(c, base, asBase: true) : group);
      i = end - 1;
      continue;
    }
    if (clipped.isEmpty) {
      paint(canvas, base, asBase: false);
      i = end - 1;
      continue;
    }
    canvas.saveLayer(
      bounds,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, base.opacity)
        ..blendMode = layerBlendMode(base.blend),
    );
    group(canvas);
    canvas.restore();
    i = end - 1;
  }
}

/// [paintLayerStack] with layer groups: a hidden group hides its layers;
/// one with opacity or a blend mode is composited as one layer; a
/// pass-through group draws as if its layers were not grouped. Clipping
/// stays inside a group.
void paintGroupedLayers(
  Canvas canvas,
  List<ArtLayer> layers,
  List<LayerGroup> groups,
  Rect bounds,
  LayerPainter paint, {
  void Function(Canvas canvas)? under,
}) {
  if (groups.isEmpty) {
    paintLayerStack(canvas, layers, bounds, paint, under: under);
    return;
  }
  final byId = {for (final g in groups) g.id: g};
  var i = 0;
  while (i < layers.length) {
    final start = i;
    final id = layers[i].group;
    var end = i + 1;
    while (end < layers.length && layers[end].group == id) {
      end++;
    }
    final run = layers.sublist(i, end);
    final group = id == null ? null : byId[id];
    i = end;
    // What lies under this run: for blend modes that need it.
    void backdrop(Canvas c) {
      under?.call(c);
      paintGroupedLayers(
        c,
        layers.sublist(0, start),
        groups,
        bounds,
        paint,
        under: under,
      );
    }

    if (group == null || group.passThrough) {
      if (group != null && !group.visible) continue;
      paintLayerStack(canvas, run, bounds, paint, under: backdrop);
      continue;
    }
    if (!group.visible || group.opacity == 0) continue;
    if (_shaded(group.blend)) {
      paintCustomBlend(
        canvas,
        bounds,
        group.blend,
        group.opacity,
        backdrop,
        (c) => paintLayerStack(c, run, bounds, paint),
      );
      continue;
    }
    canvas.saveLayer(
      bounds,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, group.opacity)
        ..blendMode = layerBlendMode(group.blend),
    );
    paintLayerStack(canvas, run, bounds, paint);
    canvas.restore();
  }
}

/// True when [index] belongs to a clipping group: it clips, or it is the
/// base of a clipping layer above it.
bool inClippingGroup(List<ArtLayer> layers, int index) =>
    layers[index].clipping ||
    (index + 1 < layers.length && layers[index + 1].clipping);

/// Paint just one layer into its own transparent compositing group. Its
/// opacity is applied when restoring, after erasers have cleared this group.
void paintLayer(
  Canvas canvas,
  ArtLayer layer,
  BrushEngine engine,
  CanvasSize dimensions, {
  List<InkStroke> pending = const [],
  Map<InkStroke, Path>? cache,
  Map<RasterAsset, Image> rasterImages = const {},
  LayerTransform? transform,
  SelectionRegion? transformSelection,
  bool applyOpacity = true,
  bool applyMask = true,
  LayerContentOverride? override,
  Rect? visible,
}) {
  final bounds = dimensions.rect;
  final compositing = Paint()
    ..color = Color.fromRGBO(255, 255, 255, applyOpacity ? layer.opacity : 1)
    ..blendMode = !applyOpacity
        ? BlendMode.srcOver
        : layerBlendMode(layer.blend);
  canvas.saveLayer(bounds, compositing);
  if (transform != null && transform.mesh != null) {
    // Distort / Warp: what stays, then the content across the mesh.
    if (transformSelection != null) {
      canvas.save();
      canvas.clipPath(transformSelection.complement);
      _paintLayerContent(
        canvas,
        layer,
        engine,
        dimensions,
        cache: cache,
        rasterImages: rasterImages,
      );
      canvas.restore();
    }
    canvas.save();
    canvas.clipRect(bounds);
    transform.paintMesh(canvas);
    canvas.restore();
  } else if (transform != null &&
      transformSelection != null &&
      !transform.isIdentity) {
    canvas.save();
    canvas.clipPath(transformSelection.complement);
    _paintLayerContent(
      canvas,
      layer,
      engine,
      dimensions,
      cache: cache,
      rasterImages: rasterImages,
    );
    canvas.restore();
    canvas.save();
    transform.applyTo(canvas);
    canvas.clipPath(transformSelection.path);
    // Isolate moving pixels: their eraser holes reveal stationary content.
    canvas.saveLayer(bounds, Paint());
    _paintLayerContent(
      canvas,
      layer,
      engine,
      dimensions,
      cache: cache,
      rasterImages: rasterImages,
      filterQuality: transform.filter,
    );
    canvas.restore();
    canvas.restore();
  } else {
    canvas.save();
    transform?.applyTo(canvas);
    _paintLayerContent(
      canvas,
      layer,
      engine,
      dimensions,
      pending: pending,
      cache: cache,
      rasterImages: rasterImages,
      applyMask: applyMask,
      override: override,
      // Moved pixels come from tiles anywhere on the canvas.
      visible: transform == null ? visible : null,
      filterQuality: transform?.filter ?? FilterQuality.medium,
    );
    canvas.restore();
  }
  canvas.restore();
}

void _paintLayerContent(
  Canvas canvas,
  ArtLayer layer,
  BrushEngine engine,
  CanvasSize dimensions, {
  List<InkStroke> pending = const [],
  Map<InkStroke, Path>? cache,
  Map<RasterAsset, Image> rasterImages = const {},
  bool applyMask = true,
  LayerContentOverride? override,
  Rect? visible,
  FilterQuality filterQuality = FilterQuality.medium,
}) {
  final bounds = dimensions.rect;
  canvas.save();
  canvas.clipRect(bounds);
  final mask = applyMask ? layer.mask : null;
  // A soft-edged mask multiplies the content by its blurred coverage.
  final soft = mask != null && mask.feather > 0;
  if (soft) {
    canvas.saveLayer(visible ?? bounds, Paint());
  } else if (mask != null) {
    canvas.clipPath(mask.path);
  }
  if (override?.replace case final replace?) {
    replace(canvas, visible ?? bounds);
    if (soft) {
      keepInside(canvas, mask, visible ?? bounds);
      canvas.restore();
    }
    canvas.restore();
    return;
  }
  // No edge anti-aliasing: neighbouring tiles must meet without a seam.
  final tilePaint = Paint()
    ..filterQuality = filterQuality
    ..isAntiAlias = false;
  for (final MapEntry(:key, :value) in (layer.raster?.tiles ?? {}).entries) {
    final image = rasterImages[value];
    if (image == null) throw StateError('Raster tile has not been prepared');
    final (x, y) = layer.raster!.grid.origin(key);
    // Tiles outside the visible part of the canvas are not drawn at all.
    if (visible != null &&
        !visible.overlaps(
          Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            TiledRaster.size + .0,
            TiledRaster.size + .0,
          ),
        )) {
      continue;
    }
    canvas.drawImage(image, Offset(x.toDouble(), y.toDouble()), tilePaint);
  }
  final raster = layer.legacyRaster;
  if (raster != null) {
    final image = rasterImages[raster];
    if (image == null) throw StateError('Raster image has not been prepared');
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
      rasterBounds(raster, dimensions),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
  for (final stroke in layer.strokes) {
    final path =
        cache?.putIfAbsent(stroke, () => engine.outline(stroke)) ??
        engine.outline(stroke);
    _paintStroke(canvas, stroke, path);
  }
  for (final stroke in pending) {
    _paintStroke(canvas, stroke, engine.outline(stroke, complete: false));
  }
  if (layer.text case final text?) paintLayerText(canvas, text);
  final replace = Paint()..blendMode = BlendMode.src;
  for (final overlay in override?.overlays ?? const <NativeOverlay>[]) {
    if (overlay.tiles.isEmpty) continue;
    final clip = overlay.clip;
    if (clip != null && clip.feather > 0) {
      // Live blocks fade into the layer across the selection's soft edge.
      canvas.saveLayer(visible ?? bounds, Paint());
      for (final (offset, image) in overlay.tiles) {
        canvas.drawImage(image, offset, replace);
      }
      keepInside(canvas, clip, visible ?? bounds);
      canvas.restore();
      continue;
    }
    canvas.save();
    if (clip != null) canvas.clipPath(clip.path);
    for (final (offset, image) in overlay.tiles) {
      canvas.drawImage(image, offset, replace);
    }
    canvas.restore();
  }
  if (soft) {
    keepInside(canvas, mask, visible ?? bounds);
    canvas.restore();
  }
  canvas.restore();
}

/// Keeps what the open layer holds only inside [region], fading across its
/// soft edge. The coverage gets a layer of its own, composited with dstIn:
/// a blurred path drawn straight in dstIn is not reliable.
void keepInside(Canvas canvas, SelectionRegion region, Rect bounds) {
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
  canvas.drawPath(region.path, region.coveragePaint);
  canvas.restore();
}

void paintDocument(
  Canvas canvas,
  ArtDocument doc,
  BrushEngine engine, {
  List<InkStroke> pending = const [],
  Map<InkStroke, Path>? cache,
  Map<RasterAsset, Image> rasterImages = const {},
  LayerTransform? transform,
  String? transformLayerId,
  SelectionRegion? transformSelection,
  Map<String, LayerContentOverride> overrides = const {},
  Rect? visible,
}) {
  final bounds = doc.dimensions.rect;
  canvas.save();
  canvas.clipRect(bounds);
  void paper(Canvas c) {
    if (!doc.backgroundHidden) {
      c.drawRect(bounds, Paint()..color = Color(doc.background));
    }
  }

  paper(canvas);
  // Blend modes drawn from images only need what is on screen.
  final area = visible == null ? bounds : _whole(visible.intersect(bounds));
  if (area.isEmpty) {
    canvas.restore();
    return;
  }
  paintGroupedLayers(canvas, doc.layers, doc.groups, area, under: paper, (
    canvas,
    layer, {
    required asBase,
  }) {
    paintLayer(
      canvas,
      layer,
      engine,
      doc.dimensions,
      cache: cache,
      rasterImages: rasterImages,
      pending: layer.id == doc.activeLayerId ? pending : const [],
      transform: layer.id == transformLayerId ? transform : null,
      transformSelection: layer.id == transformLayerId
          ? transformSelection
          : null,
      override: overrides[layer.id],
      visible: visible,
      applyOpacity: !asBase,
    );
  });
  canvas.restore();
}

Rect _whole(Rect r) => Rect.fromLTRB(
  r.left.floorToDouble(),
  r.top.floorToDouble(),
  r.right.ceilToDouble(),
  r.bottom.ceilToDouble(),
);

/// A frame from [composite]: the flattened paper and layers below, the
/// active layer drawn live (strokes, previews, transform), then the layers
/// above, flattened or one by one. Same pixels as [paintDocument].
void paintComposited(
  Canvas canvas,
  ArtDocument doc,
  BrushEngine engine,
  CompositeFrame composite, {
  List<InkStroke> pending = const [],
  Map<InkStroke, Path>? cache,
  Map<RasterAsset, Image> rasterImages = const {},
  LayerTransform? transform,
  SelectionRegion? transformSelection,
  Map<String, LayerContentOverride> overrides = const {},
  Rect? visible,
}) {
  // Pieces meet edge to edge: no edge anti-aliasing, like tiles.
  final flattened = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = false;
  void drawChunks(Canvas canvas, CompositeChunks chunks) {
    for (final (offset, image) in chunks) {
      final area = offset & Size(image.width + .0, image.height + .0);
      if (visible != null && !visible.overlaps(area)) continue;
      canvas.drawImage(image, offset, flattened);
    }
  }

  final active = doc.layers[composite.activeIndex];
  void below(Canvas canvas) {
    drawChunks(canvas, composite.below);
    if (!active.visible || active.opacity == 0) return;
    paintLayer(
      canvas,
      active,
      engine,
      doc.dimensions,
      cache: cache,
      rasterImages: rasterImages,
      pending: pending,
      transform: transform,
      transformSelection: transformSelection,
      override: overrides[active.id],
      visible: visible,
    );
  }

  canvas.save();
  canvas.clipRect(doc.dimensions.rect);
  below(canvas);
  if (composite.flat) {
    drawChunks(canvas, composite.above);
  } else {
    final bounds = doc.dimensions.rect;
    paintGroupedLayers(
      canvas,
      doc.layers.sublist(composite.activeIndex + 1),
      doc.groups,
      visible == null ? bounds : _whole(visible.intersect(bounds)),
      under: below,
      (canvas, layer, {required asBase}) => paintLayer(
        canvas,
        layer,
        engine,
        doc.dimensions,
        cache: cache,
        rasterImages: rasterImages,
        override: overrides[layer.id],
        visible: visible,
        applyOpacity: !asBase,
      ),
    );
  }
  canvas.restore();
}

void _paintStroke(Canvas canvas, InkStroke stroke, Path path) {
  final paint = Paint()
    ..color = Color(stroke.color)
        .withValues(alpha: stroke.opacity * Color(stroke.color).a)
    ..blendMode = stroke.eraser
        ? BlendMode.clear
        : stroke.atop
        ? BlendMode.srcATop
        : BlendMode.srcOver
    ..isAntiAlias = true;
  canvas.save();
  if (stroke.clip != null) canvas.clipPath(stroke.clip!.path);
  canvas.drawPath(path, paint);
  canvas.restore();
}
