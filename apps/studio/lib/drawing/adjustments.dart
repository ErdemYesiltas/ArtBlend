import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;

import '../domain/document.dart';
import '../domain/selection.dart';
import 'brush_engine.dart';
import 'flood_fill.dart';

/// One of Procreate's adjustments (the magic wand menu).
enum AdjustmentKind {
  hueSaturationBrightness([
    AdjustmentParam('hue'),
    AdjustmentParam('saturation'),
    AdjustmentParam('brightness'),
  ]),
  colorBalance([
    AdjustmentParam('shadowsRed'),
    AdjustmentParam('shadowsGreen'),
    AdjustmentParam('shadowsBlue'),
    AdjustmentParam('midtonesRed'),
    AdjustmentParam('midtonesGreen'),
    AdjustmentParam('midtonesBlue'),
    AdjustmentParam('highlightsRed'),
    AdjustmentParam('highlightsGreen'),
    AdjustmentParam('highlightsBlue'),
  ]),
  curves([]),
  gradientMap([AdjustmentParam('amount', neutral: 0, initial: 1)]),
  gaussianBlur([AdjustmentParam('amount', neutral: 0)], swipe: 'amount'),
  motionBlur([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('angle', neutral: 0, drives: false),
  ], swipe: 'amount'),
  perspectiveBlur([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('x', drives: false),
    AdjustmentParam('y', drives: false),
    AdjustmentParam('directional', neutral: 0, drives: false),
    AdjustmentParam('angle', neutral: 0, drives: false),
  ], swipe: 'amount'),
  sharpen([AdjustmentParam('amount', neutral: 0)], swipe: 'amount'),
  noise([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('type', neutral: 0, drives: false),
    AdjustmentParam('scale', initial: .4, drives: false),
    AdjustmentParam('octaves', initial: .5, drives: false),
    AdjustmentParam('turbulence', neutral: 0, initial: .2, drives: false),
  ], swipe: 'amount'),
  bloom([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('size', initial: .3, drives: false),
    AdjustmentParam('burn', neutral: 0, initial: .2, drives: false),
  ], swipe: 'amount'),
  glitch([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('type', neutral: 0, drives: false),
    AdjustmentParam('block', initial: .3, drives: false),
    AdjustmentParam('zoom', initial: .3, drives: false),
  ], swipe: 'amount'),
  halftone([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('type', neutral: 0, drives: false),
  ], swipe: 'amount'),
  chromaticAberration([
    AdjustmentParam('amount', neutral: 0),
    AdjustmentParam('type', neutral: 0, drives: false),
    AdjustmentParam('falloff', drives: false),
    AdjustmentParam('x', drives: false),
    AdjustmentParam('y', drives: false),
    AdjustmentParam('angle', neutral: 0, drives: false),
  ], swipe: 'amount'),

  /// Replaces the colour under the crosshair (and those near it) with the
  /// current one: the connected area, or everywhere ([global]).
  recolor([
    AdjustmentParam('threshold', neutral: 0, initial: .25),
    AdjustmentParam('x', drives: false),
    AdjustmentParam('y', drives: false),
    AdjustmentParam('global', neutral: 0, drives: false),
  ], swipe: 'threshold');

  const AdjustmentKind(this.params, {this.swipe});

  /// Each value runs 0–1, shown as a percentage.
  final List<AdjustmentParam> params;

  /// The value a sideways drag on the canvas changes, if any.
  final String? swipe;
}

/// Color Balance's tonal ranges.
enum ToneRange { shadows, midtones, highlights }

/// Curves' channels: gamma moves all three.
enum CurveChannel { gamma, red, green, blue }

class AdjustmentParam {
  const AdjustmentParam(
    this.id, {
    this.neutral = .5,
    double? initial,
    this.drives = true,
  }) : initial = initial ?? neutral;
  final String id;

  /// False for a setting that changes nothing by itself (a direction, a
  /// centre): the adjustment is neutral whatever it is.
  final bool drives;

  /// The value that leaves the layer as it is.
  final double neutral;

  /// The value an adjustment opens (and resets) with.
  final double initial;
}

/// A gradient: (position 0–1, ARGB) stops in order.
typedef GradientStops = List<(double, int)>;

/// Gradient Map's ready-made gradients, dark to light.
enum GradientPreset {
  noir([(0, 0xff000000), (1, 0xffffffff)]),
  sepia([(0, 0xff1e1208), (.5, 0xff8a6136), (1, 0xfff5e6c8)]),
  sunset([
    (0, 0xff1b0b3a),
    (.4, 0xffb0305c),
    (.75, 0xfff28a30),
    (1, 0xfffff1b8),
  ]),
  ocean([
    (0, 0xff02101f),
    (.45, 0xff0b5a8a),
    (.8, 0xff3cc3d4),
    (1, 0xffe8fbff),
  ]),
  neon([(0, 0xff0a0014), (.35, 0xff6a00ff), (.7, 0xffff2fa8), (1, 0xfff5ff6b)]),
  gold([(0, 0xff120a00), (.5, 0xff9c6b12), (.85, 0xffe8c35a), (1, 0xfffff8df)]);

  const GradientPreset(this.stops);
  final GradientStops stops;
}

/// An adjustment and its settings.
class Adjustment {
  const Adjustment(
    this.kind,
    this.values, {
    this.curves = const {},
    this.gradient = const [],
    this.color = 0xff000000,
  });

  /// How [kind] opens: changing nothing, except Gradient Map, which shows
  /// its first gradient at once.
  Adjustment.initial(this.kind)
    : values = {for (final p in kind.params) p.id: p.initial},
      curves = const {},
      gradient = kind == AdjustmentKind.gradientMap
          ? GradientPreset.noir.stops
          : const [],
      color = 0xff000000;

  final AdjustmentKind kind;
  final Map<String, double> values;

  /// Curve points (x, y in 0–1, in x order) per channel; missing is straight.
  final Map<CurveChannel, List<Offset>> curves;
  final GradientStops gradient;

  /// Recolor's new colour (ARGB).
  final int color;

  static const straight = [Offset.zero, Offset(1, 1)];

  double operator [](String id) => values[id]!;

  List<Offset> curve(CurveChannel channel) => curves[channel] ?? straight;

  Adjustment withValue(String id, double value) => Adjustment(
    kind,
    {...values, id: value.clamp(0.0, 1.0)},
    curves: curves,
    gradient: gradient,
    color: color,
  );

  Adjustment withCurve(CurveChannel channel, List<Offset> points) => Adjustment(
    kind,
    values,
    curves: {...curves, channel: List.unmodifiable(points)},
    gradient: gradient,
    color: color,
  );

  Adjustment withGradient(GradientStops stops) => Adjustment(
    kind,
    values,
    curves: curves,
    gradient: List.unmodifiable(stops),
    color: color,
  );

  Adjustment withColor(int argb) =>
      Adjustment(kind, values, curves: curves, gradient: gradient, color: argb);

  /// Shows a centre disc to drag on the canvas.
  bool get centred =>
      kind == AdjustmentKind.perspectiveBlur ||
      kind == AdjustmentKind.recolor ||
      (kind == AdjustmentKind.chromaticAberration && this['type'] < .5);

  bool get isNeutral =>
      kind.params.every((p) => !p.drives || values[p.id] == p.neutral) &&
      CurveChannel.values.every((c) => listEquals(curve(c), straight));

  @override
  bool operator ==(Object other) =>
      other is Adjustment &&
      other.kind == kind &&
      kind.params.every((p) => other.values[p.id] == values[p.id]) &&
      CurveChannel.values.every((c) => listEquals(other.curve(c), curve(c))) &&
      listEquals(other.gradient, gradient) &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAll(kind.params.map((p) => values[p.id])),
    Object.hashAll(gradient),
    color,
  );
}

/// The curve through [points] (sorted by x) at 256 inputs, 0–255: a
/// monotone cubic, so it never swings past its points.
Uint8List curveTable(List<Offset> points) {
  final table = Uint8List(256);
  final n = points.length;
  final slopes = List<double>.filled(n, 0);
  final secants = [
    for (var i = 0; i < n - 1; i++)
      (points[i + 1].dy - points[i].dy) /
          math.max(points[i + 1].dx - points[i].dx, 1e-6),
  ];
  if (n == 2) {
    slopes[0] = slopes[1] = secants[0];
  } else {
    slopes[0] = secants[0];
    slopes[n - 1] = secants[n - 2];
    for (var i = 1; i < n - 1; i++) {
      final a = secants[i - 1], b = secants[i];
      slopes[i] = a * b <= 0 ? 0 : 2 / (1 / a + 1 / b);
    }
  }
  for (var v = 0; v < 256; v++) {
    final x = v / 255;
    double y;
    if (x <= points.first.dx) {
      y = points.first.dy;
    } else if (x >= points.last.dx) {
      y = points.last.dy;
    } else {
      var i = 0;
      while (x > points[i + 1].dx) {
        i++;
      }
      final p0 = points[i], p1 = points[i + 1];
      final h = p1.dx - p0.dx, t = (x - p0.dx) / h;
      final t2 = t * t, t3 = t2 * t;
      y =
          (2 * t3 - 3 * t2 + 1) * p0.dy +
          (t3 - 2 * t2 + t) * h * slopes[i] +
          (-2 * t3 + 3 * t2) * p1.dy +
          (t3 - t2) * h * slopes[i + 1];
    }
    table[v] = (y.clamp(0.0, 1.0) * 255).round();
  }
  return table;
}

/// Curves as one RGB lookup: each channel's curve after gamma's.
Uint8List curvesLut(Adjustment adjustment) {
  final gamma = curveTable(adjustment.curve(CurveChannel.gamma));
  final channels = [
    for (final c in [CurveChannel.red, CurveChannel.green, CurveChannel.blue])
      curveTable(adjustment.curve(c)),
  ];
  final lut = Uint8List(256 * 4);
  for (var v = 0; v < 256; v++) {
    for (var c = 0; c < 3; c++) {
      lut[v * 4 + c] = channels[c][gamma[v]];
    }
    lut[v * 4 + 3] = 255;
  }
  return lut;
}

/// [stops]' colour at 256 positions, as RGBA.
Uint8List gradientLut(GradientStops stops) {
  final lut = Uint8List(256 * 4);
  for (var v = 0; v < 256; v++) {
    final color = gradientColor(stops, v / 255);
    lut
      ..[v * 4] = (color >> 16) & 0xff
      ..[v * 4 + 1] = (color >> 8) & 0xff
      ..[v * 4 + 2] = color & 0xff
      ..[v * 4 + 3] = 255;
  }
  return lut;
}

/// [stops]' colour at [t] (0–1), opaque.
int gradientColor(GradientStops stops, double t) {
  if (t <= stops.first.$1) return stops.first.$2 | 0xff000000;
  if (t >= stops.last.$1) return stops.last.$2 | 0xff000000;
  var i = 0;
  while (t > stops[i + 1].$1) {
    i++;
  }
  final (a, from) = stops[i];
  final (b, to) = stops[i + 1];
  final f = b > a ? (t - a) / (b - a) : 1.0;
  int mix(int shift) {
    final x = (from >> shift) & 0xff, y = (to >> shift) & 0xff;
    return (x + (y - x) * f).round() << shift;
  }

  return 0xff000000 | mix(16) | mix(8) | mix(0);
}

/// A 256×1 image of [lut] (RGBA), for a shader to look up.
Image lutImage(Uint8List lut) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..isAntiAlias = false;
  for (var v = 0; v < 256; v++) {
    paint.color = Color.fromARGB(
      255,
      lut[v * 4],
      lut[v * 4 + 1],
      lut[v * 4 + 2],
    );
    canvas.drawRect(Rect.fromLTWH(v.toDouble(), 0, 1, 1), paint);
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(256, 1);
  picture.dispose();
  return image;
}

/// How many visible pixels of straight RGBA [rgba] have each luminance.
List<int> lumaHistogram(Uint8List rgba) {
  final bins = List<int>.filled(256, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] == 0) continue;
    bins[(rgba[i] * 54 + rgba[i + 1] * 183 + rgba[i + 2] * 19) >> 8]++;
  }
  return bins;
}

/// [lumaHistogram] on a background isolate.
Future<List<int>> lumaHistogramOffThread(Uint8List rgba) =>
    Isolate.run(() => lumaHistogram(rgba));

/// The adjustments' shader programs, loaded once.
class AdjustmentShaders {
  AdjustmentShaders._(this.programs);

  final Map<String, FragmentProgram> programs;

  FragmentShader shader(String name) => programs[name]!.fragmentShader();

  static const names = [
    'hue_saturation_brightness',
    'color_balance',
    'curves',
    'gradient_map',
    'motion_blur',
    'perspective_blur',
    'sharpen',
    'noise',
    'bloom',
    'glitch',
    'halftone',
    'chromatic',
    'recolor',
    'lens_blur',
  ];

  static Future<AdjustmentShaders>? _loading;

  static Future<AdjustmentShaders> load() => _loading ??= () async {
    try {
      return AdjustmentShaders._({
        for (final name in names)
          name: await FragmentProgram.fromAsset('shaders/$name.frag'),
      });
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
}

/// Draws [source] (a whole layer, at the origin) adjusted by [adjustment].
/// Recolor in flood mode reads where it may change from [mask] (alpha);
/// without one nothing changes yet.
void paintAdjusted(
  Canvas canvas,
  Image source,
  Adjustment adjustment,
  AdjustmentShaders shaders, {
  Image? mask,
}) {
  final size = Size(source.width.toDouble(), source.height.toDouble());
  void shade(String name, List<double> floats, [Image? lut]) {
    final shader = shaders.shader(name)
      ..setFloat(0, size.width)
      ..setFloat(1, size.height);
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(2 + i, floats[i]);
    }
    shader.setImageSampler(0, source);
    if (lut != null) shader.setImageSampler(1, lut);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
    lut?.dispose();
  }

  switch (adjustment.kind) {
    case AdjustmentKind.hueSaturationBrightness:
      final saturation = adjustment['saturation'];
      shade('hue_saturation_brightness', [
        adjustment['hue'] - .5,
        // Down to grey at 0, three times as vivid at 1.
        saturation < .5 ? saturation * 2 : 1 + (saturation - .5) * 4,
        (adjustment['brightness'] - .5) * 2,
      ]);
    case AdjustmentKind.colorBalance:
      shade('color_balance', [
        for (final range in ToneRange.values)
          for (final channel in ['Red', 'Green', 'Blue'])
            (adjustment['${range.name}$channel'] - .5) * 2,
      ]);
    case AdjustmentKind.curves:
      shade('curves', const [], lutImage(curvesLut(adjustment)));
    case AdjustmentKind.gradientMap:
      shade('gradient_map', [
        adjustment['amount'],
      ], lutImage(gradientLut(adjustment.gradient)));
    case AdjustmentKind.motionBlur:
      final length = blurLength(adjustment['amount'], size);
      final angle = adjustment['angle'] * math.pi;
      shade('motion_blur', [
        math.cos(angle) * length,
        math.sin(angle) * length,
      ]);
    case AdjustmentKind.perspectiveBlur:
      final angle = adjustment['angle'] * 2 * math.pi;
      shade('perspective_blur', [
        adjustment['x'] * size.width,
        adjustment['y'] * size.height,
        math.cos(angle),
        math.sin(angle),
        adjustment['amount'] * .35,
        adjustment['directional'],
      ]);
    case AdjustmentKind.sharpen:
      shade(
        'sharpen',
        [adjustment['amount'] * 3],
        _record(source, size, (c) {
          c.drawImage(
            source,
            Offset.zero,
            Paint()
              ..imageFilter = ImageFilter.blur(
                sigmaX: 2,
                sigmaY: 2,
                tileMode: TileMode.clamp,
              ),
          );
        }),
      );
    case AdjustmentKind.noise:
      final scale = adjustment['scale'];
      shade('noise', [
        adjustment['amount'] * .6,
        4 + scale * scale * 400,
        1 + (adjustment['octaves'] * 7).roundToDouble(),
        adjustment['turbulence'],
        adjustment['type'],
        adjustment.values['offsetX'] ?? 0,
        adjustment.values['offsetY'] ?? 0,
      ]);
    case AdjustmentKind.bloom:
      final bright = _record(source, size, (c) {
        final shader = shaders.shader('bloom')
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, 1 - adjustment['amount'] * .9)
          ..setFloat(3, adjustment['burn'])
          ..setImageSampler(0, source);
        c.drawRect(Offset.zero & size, Paint()..shader = shader);
        shader.dispose();
      });
      final sigma =
          2 + adjustment['size'] * .03 * math.max(size.width, size.height);
      canvas.drawImage(source, Offset.zero, Paint());
      canvas.drawImage(
        bright,
        Offset.zero,
        Paint()
          ..blendMode = BlendMode.plus
          ..imageFilter = ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
      );
      bright.dispose();
    case AdjustmentKind.glitch:
      shade('glitch', [
        adjustment['amount'],
        adjustment['block'],
        adjustment['zoom'],
        adjustment['type'],
      ]);
    case AdjustmentKind.halftone:
      shade('halftone', [
        3 + adjustment['amount'] * .04 * math.max(size.width, size.height),
        adjustment['type'],
      ]);
    case AdjustmentKind.chromaticAberration:
      final angle = adjustment['angle'] * 2 * math.pi;
      shade('chromatic', [
        adjustment['amount'],
        adjustment['x'] * size.width,
        adjustment['y'] * size.height,
        math.cos(angle),
        math.sin(angle),
        adjustment['falloff'],
        adjustment['type'],
      ]);
    case AdjustmentKind.recolor:
      final global = adjustment['global'] > .5;
      if (!global && mask == null) {
        canvas.drawImage(source, Offset.zero, Paint());
        return;
      }
      final color = adjustment.color;
      final shader = shaders.shader('recolor')
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, adjustment['x'] * size.width)
        ..setFloat(3, adjustment['y'] * size.height)
        ..setFloat(4, adjustment['threshold'])
        ..setFloat(5, global ? 1 : 0)
        ..setFloat(6, (color >> 16 & 0xff) / 255)
        ..setFloat(7, (color >> 8 & 0xff) / 255)
        ..setFloat(8, (color & 0xff) / 255)
        ..setImageSampler(0, source)
        ..setImageSampler(1, mask ?? source);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      shader.dispose();
    case AdjustmentKind.gaussianBlur:
      final sigma = gaussianSigma(adjustment['amount'], size);
      canvas.drawImage(
        source,
        Offset.zero,
        Paint()
          ..imageFilter = sigma > 0
              ? ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.decal,
                )
              : null,
      );
  }
}

/// What [paint] draws, as an image the size of [source].
Image _record(Image source, Size size, void Function(Canvas canvas) paint) {
  final recorder = PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(source.width, source.height);
  picture.dispose();
  return image;
}

/// Motion blur's streak at [amount]: up to 12% of the longer side.
double blurLength(double amount, Size size) =>
    amount * .12 * math.max(size.width, size.height);

/// Gaussian blur's spread at [amount]: up to 2.5% of the longer side.
double gaussianSigma(double amount, Size size) =>
    amount * .025 * math.max(size.width, size.height);

/// An adjustment being tried on one layer: the layer's own pixels, the
/// result, and in pencil mode the strokes that say where it applies.
class AdjustmentSession {
  AdjustmentSession({
    required this.layerId,
    required this.source,
    required this.shaders,
    required this._adjustment,
    this.clip,
    this.onRendered,
  }) {
    _render();
    _flood();
  }

  final String layerId;

  /// The layer's content, without its opacity, blend or mask.
  final Image source;
  final AdjustmentShaders shaders;

  /// The selection when the session began: the adjustment stays inside it.
  final SelectionRegion? clip;

  Adjustment get adjustment => _adjustment;
  Adjustment _adjustment;

  /// Paint the adjustment on with strokes instead of over the whole layer.
  bool pencil = false;

  /// Pencil strokes, and the one being drawn.
  final List<InkStroke> strokes = [];
  InkStroke? drawing;

  /// Hold Preview: the layer as it was.
  bool showOriginal = false;

  /// The layer's luminance spread, for Curves; null until counted.
  List<int>? histogram;

  /// Earlier states, for Undo inside the session.
  final List<(Adjustment, int, bool)> _history = [];
  bool get canUndo => _history.isNotEmpty;

  Image? _adjusted;
  bool _disposed = false;

  /// Recolor's connected area (flood mode), and the layer's pixels it is
  /// found in.
  Image? _floodMask;
  Future<Uint8List?>? _pixels;
  int _floodRun = 0, _floodDone = 0;
  (double, double, double)? _floodFor;

  /// Recolor's flood area is found for the current crosshair and threshold
  /// (always true for other adjustments and Global).
  bool get floodReady =>
      _adjustment.kind != AdjustmentKind.recolor ||
      _adjustment['global'] > .5 ||
      (_floodMask != null && _floodDone == _floodRun);

  /// Called when a result computed in the background is ready.
  final void Function()? onRendered;

  /// Remembers the current state as an Undo step.
  void checkpoint() => _history.add((_adjustment, strokes.length, pencil));

  set adjustment(Adjustment next) {
    if (next == _adjustment) return;
    _adjustment = next;
    _render();
    _flood();
  }

  /// Recolor's flood area for the crosshair and threshold, found off the
  /// UI thread; a newer request makes an older one moot.
  void _flood() {
    final a = _adjustment;
    if (a.kind != AdjustmentKind.recolor || a['global'] > .5) return;
    final key = (a['x'], a['y'], a['threshold']);
    if (key == _floodFor) return;
    _floodFor = key;
    final run = ++_floodRun;
    final width = source.width, height = source.height;
    _pixels ??= source
        .toByteData(format: ImageByteFormat.rawStraightRgba)
        .then((d) => d?.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
    unawaited(() async {
      final rgba = await _pixels;
      if (rgba == null || run != _floodRun || _disposed) return;
      final coverage = await _floodOffThread(
        rgba,
        width,
        height,
        (key.$1 * width).floor().clamp(0, width - 1),
        (key.$2 * height).floor().clamp(0, height - 1),
        key.$3,
      );
      if (run != _floodRun || _disposed) return;
      final mask = await _coverageImage(coverage, width, height);
      if (run != _floodRun || _disposed) {
        mask.dispose();
        return;
      }
      _floodMask?.dispose();
      _floodMask = mask;
      _floodDone = run;
      _render();
      onRendered?.call();
    }());
  }

  void undo() {
    if (_history.isEmpty) return;
    final (adjustment, count, wasPencil) = _history.removeLast();
    strokes.removeRange(count, strokes.length);
    pencil = wasPencil;
    this.adjustment = adjustment;
  }

  void reset() {
    checkpoint();
    strokes.clear();
    adjustment = Adjustment.initial(_adjustment.kind);
  }

  void _render() {
    final recorder = PictureRecorder();
    paintAdjusted(
      Canvas(recorder),
      source,
      _adjustment,
      shaders,
      mask: _floodMask,
    );
    final picture = recorder.endRecording();
    final next = picture.toImageSync(source.width, source.height);
    picture.dispose();
    _adjusted?.dispose();
    _adjusted = next;
  }

  /// Paints the layer as it would be: adjusted where the selection and, in
  /// pencil mode, the strokes allow, and as it was elsewhere.
  void paint(Canvas canvas, Rect bounds) {
    final adjusted = _adjusted;
    if (showOriginal || adjusted == null || _disposed) {
      canvas.drawImage(source, Offset.zero, Paint());
      return;
    }
    if (!pencil && clip == null) {
      canvas.drawImage(adjusted, Offset.zero, Paint());
      return;
    }
    // original × (1 − mask) + adjusted × mask
    canvas.saveLayer(bounds, Paint());
    canvas.drawImage(source, Offset.zero, Paint());
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstOut);
    _paintMask(canvas, bounds);
    canvas.restore();
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.plus);
    canvas.drawImage(adjusted, Offset.zero, Paint());
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    _paintMask(canvas, bounds);
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  void _paintMask(Canvas canvas, Rect bounds) {
    final region = clip;
    if (!pencil) {
      canvas.drawPath(region!.path, region.coveragePaint);
      return;
    }
    canvas.saveLayer(bounds, Paint());
    final engine = FreehandBrushEngine();
    for (final stroke in [...strokes, ?drawing]) {
      canvas.drawPath(
        engine.outline(stroke, complete: !identical(stroke, drawing)),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, stroke.opacity)
          ..blendMode = stroke.eraser ? BlendMode.clear : BlendMode.srcOver,
      );
    }
    if (region != null) keepInside(canvas, region, bounds);
    canvas.restore();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _adjusted?.dispose();
    _adjusted = null;
    _floodMask?.dispose();
    _floodMask = null;
    source.dispose();
  }
}

/// [floodFill] on a background isolate (a top-level function: the closure
/// sent there must not reach the session).
Future<Uint8List> _floodOffThread(
  Uint8List rgba,
  int width,
  int height,
  int x,
  int y,
  double threshold,
) => Isolate.run(
  () => floodFill(rgba, width, height, x, y, threshold: threshold),
);

/// [coverage] (a byte a pixel) as an image whose alpha it is.
Future<Image> _coverageImage(Uint8List coverage, int width, int height) {
  final rgba = Uint8List(coverage.length * 4);
  for (var i = 0; i < coverage.length; i++) {
    final v = coverage[i];
    rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = rgba[i * 4 + 3] = v;
  }
  final done = Completer<Image>();
  decodeImageFromPixels(
    rgba,
    width,
    height,
    PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}
