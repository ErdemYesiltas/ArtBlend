import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/movie.dart';
import '../drawing/adjustments.dart';
import '../l10n/app_localizations.dart';

String filterName(AppLocalizations l, FilterKind kind) => switch (kind) {
  FilterKind.opacity => l.filterOpacity,
  FilterKind.gaussianBlur => l.filterGaussianBlur,
  FilterKind.sharpen => l.filterSharpen,
  FilterKind.hsb => l.filterHsb,
  FilterKind.noise => l.filterNoise,
  FilterKind.lensBlur => l.filterLensBlur,
};

String filterParamName(AppLocalizations l, String id) => switch (id) {
  'amount' => l.filterAmount,
  'hue' => l.filterHue,
  'saturation' => l.filterSaturation,
  'brightness' => l.filterBrightness,
  'type' => l.filterNoiseType,
  'scale' => l.filterScale,
  'octaves' => l.filterOctaves,
  'turbulence' => l.filterTurbulence,
  'offsetX' => l.filterOffsetX,
  'offsetY' => l.filterOffsetY,
  'travelX' => l.filterTravelX,
  'travelY' => l.filterTravelY,
  'radius' => l.filterRadius,
  'contrast' => l.filterContrast,
  _ => id,
};

/// A keyframe lane's name for [content]: a filter's setting, a Distort
/// corner, a Warp node.
String keyLabel(AppLocalizations l, MovieContent? content, String id) {
  if (id == 'volume') return l.volume;
  final dot = id.indexOf('.');
  if (dot < 0) return id;
  final owner = id.substring(0, dot), param = id.substring(dot + 1);
  if (owner == 'distort') return '${l.distort} ${param.toUpperCase()}';
  if (owner == 'warp') return '${l.warp} $param';
  final filter = content?.filters.where((f) => f.id == owner).firstOrNull;
  return filter == null
      ? param
      : '${filterName(l, filter.kind)} · ${filterParamName(l, param)}';
}

/// How see-through [content] is at [frame]: its Opacity filters together.
double filterOpacity(MovieContent content, int frame) {
  var opacity = 1.0;
  for (final f in content.filters) {
    if (f.kind == FilterKind.opacity) {
      opacity *= content
          .filterValue(f, f.kind.params.single, frame)
          .clamp(0.0, 1.0);
    }
  }
  return opacity;
}

/// [source] through [content]'s live filters at [frame], in order, with
/// the same shaders as painting's filters (Opacity is left to the caller);
/// null when no filter changes pixels. The caller disposes the result.
ui.Image? filterImage(
  ui.Image source,
  MovieContent content,
  int frame,
  int fps,
  AdjustmentShaders shaders,
) {
  ui.Image? owned;
  var current = source;
  for (final f in content.filters) {
    if (f.kind == FilterKind.opacity) continue;
    double v(String id) => content.filterValue(
      f,
      f.kind.params.firstWhere((p) => p.id == id),
      frame,
    );
    final w = current.width.toDouble(), h = current.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final input = current;
    void adjust(AdjustmentKind kind, Map<String, double> values) =>
        paintAdjusted(canvas, input, Adjustment(kind, values), shaders);
    switch (f.kind) {
      case FilterKind.opacity:
        break;
      case FilterKind.gaussianBlur:
        adjust(AdjustmentKind.gaussianBlur, {'amount': v('amount')});
      case FilterKind.sharpen:
        adjust(AdjustmentKind.sharpen, {'amount': v('amount')});
      case FilterKind.hsb:
        adjust(AdjustmentKind.hueSaturationBrightness, {
          'hue': v('hue'),
          'saturation': v('saturation'),
          'brightness': v('brightness'),
        });
      case FilterKind.noise:
        final seconds = (frame - content.start) / fps;
        adjust(AdjustmentKind.noise, {
          'amount': v('amount'),
          'type': v('type'),
          'scale': v('scale'),
          'octaves': v('octaves'),
          'turbulence': v('turbulence'),
          'offsetX':
              (v('offsetX') - .5 + (v('travelX') - .5) * seconds) * 2 * w,
          'offsetY':
              (v('offsetY') - .5 + (v('travelY') - .5) * seconds) * 2 * h,
        });
      case FilterKind.lensBlur:
        final shader = shaders.shader('lens_blur')
          ..setFloat(0, w)
          ..setFloat(1, h)
          ..setFloat(2, v('radius') * .05 * math.max(w, h))
          ..setFloat(3, v('brightness'))
          ..setFloat(4, .5 + v('contrast'))
          ..setImageSampler(0, input);
        canvas.drawRect(
          ui.Offset.zero & ui.Size(w, h),
          ui.Paint()..shader = shader,
        );
        shader.dispose();
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(current.width, current.height);
    picture.dispose();
    owned?.dispose();
    owned = next;
    current = next;
  }
  return owned;
}

/// [image] drawn into [size] (a content's own pixels) through its Distort
/// corners and Warp nodes at [local], as a fine mesh of triangles.
void drawMesh(
  ui.Canvas canvas,
  ui.Image image,
  MovieContent content,
  int local,
  ui.Size size,
  ui.Paint paint,
) {
  const steps = 16;
  final positions = <double>[], uvs = <double>[];
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  for (var r = 0; r <= steps; r++) {
    for (var c = 0; c <= steps; c++) {
      final u = c / steps, v = r / steps;
      final p = meshPoint(
        content.keys,
        local,
        size,
        u,
        v,
        cols: content.warpCols,
        rows: content.warpRows,
      );
      positions.addAll([p.dx, p.dy]);
      uvs.addAll([u * iw, v * ih]);
    }
  }
  final indices = <int>[];
  for (var r = 0; r < steps; r++) {
    for (var c = 0; c < steps; c++) {
      final a = r * (steps + 1) + c, b = a + 1;
      final d = a + steps + 1, e = d + 1;
      indices.addAll([a, b, d, b, e, d]);
    }
  }
  final vertices = ui.Vertices.raw(
    ui.VertexMode.triangles,
    Float32List.fromList(positions),
    textureCoordinates: Float32List.fromList(uvs),
    indices: Uint16List.fromList(indices),
  );
  canvas.drawVertices(
    vertices,
    ui.BlendMode.srcOver,
    paint
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.medium,
      ),
  );
  vertices.dispose();
}
