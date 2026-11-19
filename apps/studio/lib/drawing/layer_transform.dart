import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Procreate's transform modes.
enum TransformMode { freeform, uniform, distort, warp }

/// A transient transform of the active layer. Applying it rasterizes the
/// layer at document resolution; the original stays in undo history.
///
/// Freeform and Uniform are affine (stretch, rotate, move, flip). Distort
/// and Warp move a [mesh] instead: four corners (a perspective quad) or
/// sixteen Bézier control points, drawing [source] — the content inside
/// [bounds], rendered once — across it.
class LayerTransform {
  const LayerTransform({
    required this.bounds,
    this.translation = Offset.zero,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.mesh,
    this.source,
    this.filter = FilterQuality.medium,
  });
  final Rect bounds;
  final Offset translation;

  /// Negative for a flip.
  final double scaleX, scaleY;
  final double rotation;

  /// Document points: 4 corners (top left, clockwise) or 4×4 control points
  /// row by row. Null while affine.
  final List<Offset>? mesh;

  /// The content inside [bounds], for a mesh to draw.
  final Image? source;

  /// Interpolation: none (nearest), low (bilinear) or high (bicubic).
  final FilterQuality filter;

  Offset get pivot => bounds.center;

  /// The uniform size, whatever the stretch.
  double get scale => scaleX.abs();

  bool get isIdentity =>
      mesh == null &&
      translation.distance < .000001 &&
      (scaleX - 1).abs() < .000001 &&
      (scaleY - 1).abs() < .000001 &&
      rotation.abs() < .000001;

  static double _size(double value) =>
      (value < 0 ? -1 : 1) * value.abs().clamp(.05, 8);

  LayerTransform copyWith({
    Offset? translation,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    List<Offset>? mesh,
    bool clearMesh = false,
    Image? source,
    FilterQuality? filter,
  }) {
    var x = scaleX ?? this.scaleX, y = scaleY ?? this.scaleY;
    if (scale != null) {
      // Uniform: both sides by the same factor, flips and stretch kept.
      final ratio = y.abs() / x.abs();
      x = x.sign * scale;
      y = y.sign * scale * ratio;
    }
    final offset = translation ?? this.translation;
    final angle = rotation ?? this.rotation;
    final points = clearMesh ? null : mesh ?? this.mesh;
    if (![offset.dx, offset.dy, x, y, angle].every((v) => v.isFinite) ||
        (points != null &&
            !points.every((p) => p.dx.isFinite && p.dy.isFinite))) {
      throw const FormatException('Non-finite layer transform');
    }
    return LayerTransform(
      bounds: bounds,
      translation: Offset(
        offset.dx.clamp(-8192, 8192),
        offset.dy.clamp(-8192, 8192),
      ),
      scaleX: _size(x),
      scaleY: _size(y),
      rotation: (angle + math.pi) % (2 * math.pi) - math.pi,
      mesh: points == null
          ? null
          : List.unmodifiable([
              for (final p in points)
                Offset(p.dx.clamp(-16384, 16384), p.dy.clamp(-16384, 16384)),
            ]),
      source: source ?? this.source,
      filter: filter ?? this.filter,
    );
  }

  /// [point] (inside [bounds]) where the transform puts it.
  Offset map(Offset point) {
    if (mesh != null) {
      return surface(
        (point.dx - bounds.left) / bounds.width,
        (point.dy - bounds.top) / bounds.height,
      );
    }
    final p = point - pivot;
    final local = Offset(p.dx * scaleX, p.dy * scaleY);
    final c = math.cos(rotation), s = math.sin(rotation);
    return pivot +
        translation +
        Offset(local.dx * c - local.dy * s, local.dx * s + local.dy * c);
  }

  /// The affine transform's source point for [point].
  Offset inverse(Offset point) {
    final p = point - pivot - translation;
    final c = math.cos(rotation), s = math.sin(rotation);
    final local = Offset(p.dx * c + p.dy * s, -p.dx * s + p.dy * c);
    return pivot + Offset(local.dx / scaleX, local.dy / scaleY);
  }

  void applyTo(Canvas canvas) {
    canvas.translate(pivot.dx + translation.dx, pivot.dy + translation.dy);
    canvas.rotate(rotation);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  List<Offset> get sourceCorners => [
    bounds.topLeft,
    bounds.topRight,
    bounds.bottomRight,
    bounds.bottomLeft,
  ];

  List<Offset> get corners => switch (mesh) {
    final m? when m.length == 4 => m,
    final m? => [m[0], m[3], m[15], m[12]],
    null => sourceCorners.map(map).toList(),
  };

  /// Midpoints of the sides, top first, clockwise.
  List<Offset> get sides {
    if (mesh != null && mesh!.length == 16) {
      return [surface(.5, 0), surface(1, .5), surface(.5, 1), surface(0, .5)];
    }
    final c = corners;
    return [for (var i = 0; i < 4; i++) (c[i] + c[(i + 1) % 4]) / 2];
  }

  /// Where the mesh puts source position ([u], [v]), each 0–1.
  Offset surface(double u, double v) {
    final m = mesh!;
    if (m.length == 4) return _quad(m, u, v);
    final bu = _bernstein(u), bv = _bernstein(v);
    var x = 0.0, y = 0.0;
    for (var j = 0; j < 4; j++) {
      for (var i = 0; i < 4; i++) {
        final w = bu[i] * bv[j];
        x += m[j * 4 + i].dx * w;
        y += m[j * 4 + i].dy * w;
      }
    }
    return Offset(x, y);
  }

  static List<double> _bernstein(double t) {
    final s = 1 - t;
    return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t];
  }

  /// The unit square onto quad [q] in perspective.
  static Offset _quad(List<Offset> q, double u, double v) {
    final dx1 = q[1].dx - q[2].dx, dx2 = q[3].dx - q[2].dx;
    final dy1 = q[1].dy - q[2].dy, dy2 = q[3].dy - q[2].dy;
    final sx = q[0].dx - q[1].dx + q[2].dx - q[3].dx;
    final sy = q[0].dy - q[1].dy + q[2].dy - q[3].dy;
    final den = dx1 * dy2 - dx2 * dy1;
    var g = 0.0, h = 0.0;
    if (den.abs() > 1e-9) {
      g = (sx * dy2 - dx2 * sy) / den;
      h = (dx1 * sy - sx * dy1) / den;
    }
    final a = q[1].dx - q[0].dx + g * q[1].dx;
    final b = q[3].dx - q[0].dx + h * q[3].dx;
    final d = q[1].dy - q[0].dy + g * q[1].dy;
    final e = q[3].dy - q[0].dy + h * q[3].dy;
    final w = g * u + h * v + 1;
    // A corner dragged across makes w reach 0: stay finite.
    final safe = w.abs() < 1e-6 ? 1e-6 : w;
    return Offset(
      (a * u + b * v + q[0].dx) / safe,
      (d * u + e * v + q[0].dy) / safe,
    );
  }

  /// The source position (u, v) the mesh draws nearest [point], or null
  /// when it is outside.
  (double, double)? meshAt(Offset point, {double reach = 0}) {
    const steps = 48;
    (double, double)? best;
    var distance = double.infinity;
    for (var j = 0; j <= steps; j++) {
      for (var i = 0; i <= steps; i++) {
        final d = (surface(i / steps, j / steps) - point).distance;
        if (d < distance) {
          distance = d;
          best = (i / steps, j / steps);
        }
      }
    }
    final inside = _contains(point);
    return inside || distance <= reach ? best : null;
  }

  bool _contains(Offset point) {
    final outline = Path();
    const n = 24;
    for (var i = 0; i <= 4 * n; i++) {
      final t = (i % n) / n;
      final p = switch (i ~/ n) {
        0 => surface(t, 0),
        1 => surface(1, t),
        2 => surface(1 - t, 1),
        _ => surface(0, 1 - t),
      };
      i == 0 ? outline.moveTo(p.dx, p.dy) : outline.lineTo(p.dx, p.dy);
    }
    return outline.contains(point);
  }

  // Changes, each returning a new transform.

  /// Moved by [delta].
  LayerTransform translated(Offset delta) => mesh != null
      ? copyWith(mesh: [for (final p in mesh!) p + delta])
      : copyWith(translation: translation + delta);

  /// Two fingers: what was under [from] follows [to], scaled by [factor]
  /// and turned by [turn] around it.
  LayerTransform pinched(Offset from, Offset to, double factor, double turn) {
    if (mesh != null) {
      final c = math.cos(turn), s = math.sin(turn);
      return copyWith(
        mesh: [
          for (final p in mesh!)
            to +
                Offset(
                      (p - from).dx * c - (p - from).dy * s,
                      (p - from).dx * s + (p - from).dy * c,
                    ) *
                    factor,
        ],
      );
    }
    final anchor = inverse(from);
    final linear = copyWith(
      translation: Offset.zero,
      scale: scale * factor,
      rotation: rotation + turn,
    );
    return linear.copyWith(translation: to - linear.map(anchor));
  }

  /// A corner handle dragged to [point]: the opposite corner stays.
  /// [uniform] keeps the proportions.
  LayerTransform resizedByCorner(
    int corner,
    Offset point, {
    required bool uniform,
  }) {
    final fixedSource = sourceCorners[(corner + 2) % 4];
    final fixed = map(fixedSource);
    final local = _local(point - fixed);
    final d = sourceCorners[corner] - fixedSource;
    double x, y;
    if (uniform) {
      final ratio = scaleY.abs() / scaleX.abs();
      final w = Offset(d.dx * scaleX.sign, d.dy * scaleY.sign * ratio);
      final s =
          (local.dx * w.dx + local.dy * w.dy) / (w.dx * w.dx + w.dy * w.dy);
      x = scaleX.sign * s.abs();
      y = scaleY.sign * s.abs() * ratio;
    } else {
      x = local.dx / d.dx;
      y = local.dy / d.dy;
    }
    final next = copyWith(scaleX: x, scaleY: y);
    return next.copyWith(
      translation: next.translation + fixed - next.map(fixedSource),
    );
  }

  /// A side handle (top first, clockwise) dragged to [point]: the opposite
  /// side stays; only that axis stretches.
  LayerTransform resizedBySide(int side, Offset point) {
    final mids = [
      bounds.topCenter,
      bounds.centerRight,
      bounds.bottomCenter,
      bounds.centerLeft,
    ];
    final fixedSource = mids[(side + 2) % 4];
    final fixed = map(fixedSource);
    final local = _local(point - fixed);
    final d = mids[side] - fixedSource;
    final next = side.isOdd
        ? copyWith(scaleX: local.dx / d.dx)
        : copyWith(scaleY: local.dy / d.dy);
    return next.copyWith(
      translation: next.translation + fixed - next.map(fixedSource),
    );
  }

  /// [vector] in the layer's own (unrotated) axes.
  Offset _local(Offset vector) {
    final c = math.cos(rotation), s = math.sin(rotation);
    return Offset(
      vector.dx * c + vector.dy * s,
      -vector.dx * s + vector.dy * c,
    );
  }

  /// As a perspective quad: Distort's start.
  LayerTransform toDistort(Image source) =>
      copyWith(mesh: corners, source: source)._withoutAffine();

  /// As a Bézier mesh: Warp's start, matching what is shown now.
  LayerTransform toWarp(Image source) {
    final points = [
      for (var j = 0; j < 4; j++)
        for (var i = 0; i < 4; i++)
          mesh != null
              ? surface(i / 3, j / 3)
              : map(
                  Offset(
                    bounds.left + bounds.width * i / 3,
                    bounds.top + bounds.height * j / 3,
                  ),
                ),
    ];
    // A Bézier patch through a perspective quad's thirds bends slightly;
    // through an affine grid it is exact.
    return copyWith(mesh: points, source: source)._withoutAffine();
  }

  LayerTransform _withoutAffine() => LayerTransform(
    bounds: bounds,
    mesh: mesh,
    source: source,
    filter: filter,
  );

  /// Distort: corner [index] to [point].
  LayerTransform withCorner(int index, Offset point) =>
      copyWith(mesh: [...mesh!]..[index] = point);

  /// Distort: side [index] (top first, clockwise) moved by [delta], both
  /// its corners with it.
  LayerTransform withSideMoved(int index, Offset delta) {
    final points = [...mesh!];
    points[index] += delta;
    points[(index + 1) % 4] += delta;
    return copyWith(mesh: points);
  }

  /// Warp: the place at ([u], [v]) follows [delta], the mesh bending
  /// smoothly around it (the smallest change of control points).
  LayerTransform warped(double u, double v, Offset delta) {
    final bu = _bernstein(u), bv = _bernstein(v);
    final weights = Float64List(16);
    var total = 0.0;
    for (var j = 0; j < 4; j++) {
      for (var i = 0; i < 4; i++) {
        final w = bu[i] * bv[j];
        weights[j * 4 + i] = w;
        total += w * w;
      }
    }
    return copyWith(
      mesh: [
        for (var k = 0; k < 16; k++) mesh![k] + delta * (weights[k] / total),
      ],
    );
  }

  /// The size shown, as a factor of the original: a mesh's top edge
  /// against the original's width.
  double get shownScale =>
      mesh == null ? scale : (corners[1] - corners[0]).distance / bounds.width;

  /// The angle shown: a mesh's top edge.
  double get shownRotation {
    if (mesh == null) return rotation;
    final d = corners[1] - corners[0];
    return math.atan2(d.dy, d.dx);
  }

  /// Resized to [value] (as [shownScale] measures it), around the middle.
  LayerTransform withShownScale(double value) {
    if (mesh == null) return copyWith(scale: value);
    final current = shownScale;
    if (current <= 0) return this;
    final centre = _shownBounds.center;
    return pinched(centre, centre, value.clamp(.05, 8) / current, 0);
  }

  /// Turned to [value] (as [shownRotation] measures it).
  LayerTransform withShownRotation(double value) => mesh == null
      ? copyWith(rotation: value)
      : rotatedBy(value - shownRotation);

  /// Turned by [turn] around the middle of what is shown.
  LayerTransform rotatedBy(double turn) {
    if (mesh == null) return copyWith(rotation: rotation + turn);
    final centre = _shownBounds.center;
    return pinched(centre, centre, 1, turn);
  }

  /// Mirrored across the shown middle, sideways or upside down.
  LayerTransform flipped({required bool horizontal}) {
    if (mesh == null) {
      return horizontal ? copyWith(scaleX: -scaleX) : copyWith(scaleY: -scaleY);
    }
    final c = _shownBounds.center;
    return copyWith(
      mesh: [
        for (final p in mesh!)
          horizontal
              ? Offset(2 * c.dx - p.dx, p.dy)
              : Offset(p.dx, 2 * c.dy - p.dy),
      ],
    );
  }

  /// As large as fits [canvas], centred on it.
  LayerTransform fittedTo(Rect canvas) {
    final shown = _shownBounds;
    if (shown.isEmpty) return this;
    final factor = math.min(
      canvas.width / shown.width,
      canvas.height / shown.height,
    );
    if (mesh != null) {
      return copyWith(
        mesh: [
          for (final p in mesh!) canvas.center + (p - shown.center) * factor,
        ],
      );
    }
    final next = copyWith(scale: scale * factor);
    final moved = next._shownBounds.center;
    return next.copyWith(translation: next.translation + canvas.center - moved);
  }

  /// Where what is shown lies on the canvas.
  Rect get shownBounds => _shownBounds;

  Rect get _shownBounds {
    final points = mesh?.length == 16
        ? [
            for (var j = 0; j <= 8; j++)
              for (var i = 0; i <= 8; i++) surface(i / 8, j / 8),
          ]
        : corners;
    var r = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  /// Draws [source] across the mesh.
  void paintMesh(Canvas canvas) {
    final image = source;
    if (image == null) return;
    const n = 32;
    final positions = Float32List((n + 1) * (n + 1) * 2);
    final texture = Float32List((n + 1) * (n + 1) * 2);
    var k = 0;
    for (var j = 0; j <= n; j++) {
      for (var i = 0; i <= n; i++) {
        final p = surface(i / n, j / n);
        positions[k] = p.dx;
        positions[k + 1] = p.dy;
        texture[k] = image.width * i / n;
        texture[k + 1] = image.height * j / n;
        k += 2;
      }
    }
    final indices = Uint16List(n * n * 6);
    k = 0;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final a = j * (n + 1) + i, b = a + 1, c = a + n + 1, d = c + 1;
        indices.setAll(k, [a, b, c, b, d, c]);
        k += 6;
      }
    }
    final vertices = Vertices.raw(
      VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: indices,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..shader = ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
          filterQuality: filter,
        ),
    );
    vertices.dispose();
  }
}

/// Snapping: how far to move a box at [bounds] so its nearest edge or
/// middle meets one of [xs] (vertical lines) and [ys] (horizontal lines)
/// within [reach]; and the lines met, to show as guides.
(Offset, List<(Offset, Offset)>) snapBounds(
  Rect bounds,
  List<double> xs,
  List<double> ys,
  double reach,
  Rect canvas,
) {
  (double, double)? nearest(List<double> own, List<double> targets) {
    (double, double)? best;
    for (final o in own) {
      for (final t in targets) {
        final d = t - o;
        if (d.abs() <= reach && (best == null || d.abs() < best.$1.abs())) {
          best = (d, t);
        }
      }
    }
    return best;
  }

  final x = nearest([bounds.left, bounds.center.dx, bounds.right], xs);
  final y = nearest([bounds.top, bounds.center.dy, bounds.bottom], ys);
  return (
    Offset(x?.$1 ?? 0, y?.$1 ?? 0),
    [
      if (x != null) (Offset(x.$2, canvas.top), Offset(x.$2, canvas.bottom)),
      if (y != null) (Offset(canvas.left, y.$2), Offset(canvas.right, y.$2)),
    ],
  );
}

/// Magnetics: [delta] along the nearest of the horizontal, vertical and
/// diagonal axes.
Offset lockToAxis(Offset delta) {
  if (delta.distance < 1e-9) return delta;
  const step = math.pi / 4;
  final angle = (math.atan2(delta.dy, delta.dx) / step).round() * step;
  final axis = Offset(math.cos(angle), math.sin(angle));
  final along = delta.dx * axis.dx + delta.dy * axis.dy;
  return axis * along;
}

/// Magnetics: [angle] (radians) to the nearest 15°.
double snapAngle(double angle) {
  const step = math.pi / 12;
  return (angle / step).round() * step;
}
