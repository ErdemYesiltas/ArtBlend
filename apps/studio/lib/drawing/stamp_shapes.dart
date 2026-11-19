import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:artblend_brush_engine/stamp_settings.dart';

import '../domain/document.dart';

/// Edge of built-in tips and of imported tips once fitted.
const stampTipSide = 128;

/// Edge of built-in grains (they tile); imported grains fit 512.
const stampGrainSide = 256, maxImportedGrainSide = 512;

/// Tips and grains drawn in code, so the app ships no texture files.
/// Deterministic: the same name always gives the same pixels.
StampImage builtinStampImage(String name) => switch (name) {
  'round-soft' => _tip((x, y, r) => _smooth(1 - r)),
  'round-hard' => _tip((x, y, r) => r <= .96 ? 1 : 0),
  'graphite' => _graphite(),
  'chalk' => _chalk(),
  'bristle' => _bristle(),
  'splatter' => _splatter(),
  'paper' => _grain([(64, .5), (32, .3), (16, .2)], contrast: 2.2),
  'rough' => _grain([(32, .5), (64, .35), (8, .15)], contrast: 2.6),
  'canvas' => _canvas(),
  _ => throw FormatException('Unknown built-in stamp image $name'),
};

/// The pixels of a `builtin:` or `png:` stamp image. PNG tips fit
/// [stampTipSide] and grains [maxImportedGrainSide]; a PNG with transparency
/// paints where opaque, an opaque one where light (white paints, as in
/// Procreate's shape and grain sources).
Future<StampImage> decodeStampShape(String spec, {required bool grain}) async {
  if (spec.startsWith('builtin:')) {
    return builtinStampImage(spec.substring('builtin:'.length));
  }
  if (!spec.startsWith('png:')) {
    throw const FormatException('Invalid stamp brush shape');
  }
  final png = base64Decode(spec.substring('png:'.length));
  final limit = grain ? maxImportedGrainSide : stampTipSide;
  final probe = await ui.instantiateImageCodec(png);
  final first = (await probe.getNextFrame()).image;
  probe.dispose();
  final scale = math.min(1.0, limit / math.max(first.width, first.height));
  final width = math.max(1, (first.width * scale).round());
  final height = math.max(1, (first.height * scale).round());
  first.dispose();
  final codec = await ui.instantiateImageCodec(
    png,
    targetWidth: width,
    targetHeight: height,
  );
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  if (data == null) throw const FormatException('Unreadable stamp image');
  final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  var transparent = false;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] < 250) {
      transparent = true;
      break;
    }
  }
  final pixels = Uint8List(width * height);
  for (var i = 0; i < pixels.length; i++) {
    final p = i * 4;
    pixels[i] = transparent
        ? rgba[p + 3]
        : ((rgba[p] * 54 + rgba[p + 1] * 183 + rgba[p + 2] * 19) >> 8);
  }
  return StampImage(pixels, width, height);
}

/// A stamp brush whose tip is the image [png] (white or opaque paints),
/// with paper grain; checked by decoding it once.
Future<BrushPreset> pngTipBrush(Uint8List png, String filename) async {
  if (png.length > BrushPreset.maxShapeChars * 3 ~/ 4) {
    throw const FormatException('The tip image is too large');
  }
  final tip = 'png:${base64Encode(png)}';
  await decodeStampShape(tip, grain: false);
  var name = filename.replaceFirst(RegExp(r'\.png$', caseSensitive: false), '');
  name = name.trim().isEmpty ? 'PNG' : name.trim();
  return BrushPreset(
    id: newId(),
    name: name.length > 64 ? name.substring(0, 64) : name,
    size: 30,
    engine: BrushEngineKind.stamp,
    tip: tip,
    grain: 'builtin:paper',
    stamp: const StampSettings(rotationJitter: .2, grainDepth: .3),
  );
}

/// A stamp preset's tip and grain, decoded once per spec.
final Map<String, Future<StampImage>> _shapes = {};

/// A dual brush's secondary tip with its settings, or null.
Future<(StampImage, DualStamp)?> resolveDualShape(BrushPreset preset) async {
  final dual = preset.dual, spec = preset.dualTip;
  if (dual == null || spec == null) return null;
  final tip = await _shapes.putIfAbsent('false:$spec', () {
    return decodeStampShape(spec, grain: false).catchError((Object e) {
      _shapes.remove('false:$spec');
      throw e;
    });
  });
  return (tip, dual);
}

Future<(StampImage, StampImage?)> resolveStampShapes(BrushPreset preset) async {
  Future<StampImage> load(String spec, bool grain) =>
      _shapes.putIfAbsent('$grain:$spec', () {
        return decodeStampShape(spec, grain: grain).catchError((Object e) {
          _shapes.remove('$grain:$spec');
          throw e;
        });
      });
  final grain = preset.grain;
  return (
    await load(preset.tip!, false),
    grain == null ? null : await load(grain, true),
  );
}

// ---- generators ----

double _smooth(double t) {
  final v = t.clamp(0.0, 1.0);
  return v * v * (3 - 2 * v);
}

/// A tip from coverage at (x, y) in −1…1 and radius r.
StampImage _tip(double Function(double x, double y, double r) coverage) {
  const n = stampTipSide;
  final pixels = Uint8List(n * n);
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final x = (i + .5) / n * 2 - 1, y = (j + .5) / n * 2 - 1;
      final c = coverage(x, y, math.sqrt(x * x + y * y));
      pixels[j * n + i] = (c.clamp(0.0, 1.0) * 255).round();
    }
  }
  return StampImage(pixels, n, n);
}

/// Value noise that tiles every [period] cells over [side] pixels.
double Function(double, double) _noise(int period, int seed) {
  final random = math.Random(seed);
  final lattice = List.generate(period * period, (_) => random.nextDouble());
  double at(int x, int y) =>
      lattice[(y % period + period) % period * period +
          (x % period + period) % period];
  return (double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = _smooth(x - x0), fy = _smooth(y - y0);
    final top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx;
    final bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx;
    return top * (1 - fy) + bottom * fy;
  };
}

/// Fractal noise tiling over [stampGrainSide]: (cells per side, weight).
StampImage _grain(List<(int, double)> octaves, {required double contrast}) {
  const n = stampGrainSide;
  final layers = [
    for (final (i, (cells, weight)) in octaves.indexed)
      (_noise(cells, 17 + i), cells / n, weight),
  ];
  final pixels = Uint8List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      var v = 0.0;
      for (final (noise, scale, weight) in layers) {
        v += noise(x * scale, y * scale) * weight;
      }
      v = ((v - .5) * contrast + .5).clamp(0.0, 1.0);
      pixels[y * n + x] = (v * 255).round();
    }
  }
  return StampImage(pixels, n, n);
}

StampImage _canvas() {
  const n = stampGrainSide, threads = 32;
  final noise = _noise(32, 5);
  final pixels = Uint8List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final u = x * threads / n, v = y * threads / n;
      // Over-under weave: alternate which thread is on top per cell.
      final over = (u.floor() + v.floor()).isEven;
      final thread = over
          ? math.sin(math.pi * (v - v.floor()))
          : math.sin(math.pi * (u - u.floor()));
      final c = .35 + .5 * thread + .3 * (noise(u, v) - .5);
      pixels[y * n + x] = (c.clamp(0.0, 1.0) * 255).round();
    }
  }
  return StampImage(pixels, n, n);
}

StampImage _graphite() {
  final noise = _noise(16, 3);
  return _tip((x, y, r) {
    final edge = .82 + .12 * noise((x + 1) * 8, (y + 1) * 8);
    final body = .55 + .45 * noise((x + 1) * 8 + 40, (y + 1) * 8);
    return _smooth((edge - r) * 6) * body;
  });
}

StampImage _chalk() {
  final noise = _noise(16, 9), fine = _noise(64, 11);
  return _tip((x, y, r) {
    final angle = math.atan2(y, x);
    final edge =
        .78 + .18 * noise(8 + 6 * math.cos(angle), 8 + 6 * math.sin(angle));
    final holes = fine((x + 1) * 32, (y + 1) * 32) > .3 ? 1.0 : .2;
    return _smooth((edge - r) * 8) * holes;
  });
}

StampImage _bristle() {
  final random = math.Random(21);
  final hairs = [
    for (var i = 0; i < 26; i++)
      (
        (random.nextDouble() * 2 - 1) * .2,
        (random.nextDouble() * 2 - 1) * .85,
        .05 + random.nextDouble() * .07,
        .5 + random.nextDouble() * .5,
      ),
  ];
  // A flat brush: hairs across y, the stroke runs along x.
  return _tip((x, y, r) {
    var c = 0.0;
    for (final (hx, hy, radius, strength) in hairs) {
      final d = math.sqrt(math.pow(x - hx, 2) + math.pow(y - hy, 2));
      c = math.max(c, _smooth((radius - d) / radius * 2) * strength);
    }
    return c;
  });
}

StampImage _splatter() {
  final random = math.Random(33);
  final drops = [
    for (var i = 0; i < 34; i++)
      () {
        final angle = random.nextDouble() * 2 * math.pi;
        final distance = math.pow(random.nextDouble(), .7) * .85;
        return (
          math.cos(angle) * distance,
          math.sin(angle) * distance,
          .02 + math.pow(random.nextDouble(), 3) * .16,
        );
      }(),
  ];
  return _tip((x, y, r) {
    for (final (dx, dy, radius) in drops) {
      final d = math.sqrt(math.pow(x - dx, 2) + math.pow(y - dy, 2));
      if (d < radius) return 1;
    }
    return 0;
  });
}
