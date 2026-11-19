import 'dart:math' as math;
import 'dart:ui';

/// What QuickShape turned a stroke into.
enum QuickShapeKind { line, arc, polyline, ellipse, polygon }

/// A shape made from a held stroke, in document pixels.
///
/// [points]: line — its two ends; arc — start, a point it passes through,
/// end; polyline and polygon — the corners; ellipse — centre, the end of
/// one axis, the end of the other.
class QuickShape {
  QuickShape(this.kind, List<Offset> points)
    : points = List.unmodifiable(points);

  final QuickShapeKind kind;
  final List<Offset> points;

  bool get closed =>
      kind == QuickShapeKind.ellipse || kind == QuickShapeKind.polygon;

  /// Where a resize turns around: the start of an open shape, the middle
  /// of a closed one.
  Offset get anchor => switch (kind) {
    QuickShapeKind.ellipse => points.first,
    QuickShapeKind.polygon => _centroid(points),
    _ => points.first,
  };

  /// The handles Edit Shape shows: an ellipse's four axis ends and its
  /// centre, otherwise the points themselves.
  List<Offset> get nodes {
    if (kind != QuickShapeKind.ellipse) return points;
    final [c, a, b] = points;
    return [a, b, c * 2 - a, c * 2 - b, c];
  }

  /// Node [index] moved to [to].
  QuickShape withNode(int index, Offset to) {
    if (kind != QuickShapeKind.ellipse) {
      return QuickShape(kind, [...points]..[index] = to);
    }
    final [c, a, b] = points;
    if (index == 4) return QuickShape(kind, [to, a - c + to, b - c + to]);
    Offset turned(Offset x) => Offset(-x.dy, x.dx) / x.distance;
    final u = a - c, v = b - c;
    final side = (u.dx * v.dy - u.dy * v.dx) >= 0 ? 1.0 : -1.0;
    // An axis end: that axis turns and stretches; the other stays square
    // to it at its own length.
    if (index.isEven) {
      final along = index == 0 ? to - c : c - to;
      if (along.distance < 1e-6) return this;
      return QuickShape(kind, [
        c,
        c + along,
        c + turned(along) * v.distance * side,
      ]);
    }
    final along = index == 1 ? to - c : c - to;
    if (along.distance < 1e-6) return this;
    return QuickShape(kind, [
      c,
      c - turned(along) * u.distance * side,
      c + along,
    ]);
  }

  /// Turned and scaled about [anchor] so that [from] lands on [to].
  QuickShape movedBy(Offset from, Offset to) {
    final o = anchor;
    final a = from - o, b = to - o;
    if (a.distance < 1e-6) return this;
    final scale = b.distance / a.distance;
    final turn = math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx);
    final c = math.cos(turn) * scale, s = math.sin(turn) * scale;
    Offset map(Offset p) {
      final d = p - o;
      return o + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    }

    return QuickShape(kind, [for (final p in points) map(p)]);
  }

  /// The perfect version (a second finger in Procreate): lines and edges
  /// in 15° steps, a circle, a symmetric arc, a regular polygon.
  QuickShape perfected() {
    switch (kind) {
      case QuickShapeKind.line:
      case QuickShapeKind.polyline:
        final out = [points.first];
        for (var i = 1; i < points.length; i++) {
          final d = points[i] - points[i - 1];
          out.add(out.last + _snapped(d));
        }
        return QuickShape(kind, out);
      case QuickShapeKind.arc:
        final [start, _, end] = points;
        final through = points[1];
        final mid = (start + end) / 2;
        final chord = end - start;
        if (chord.distance < 1e-6) return this;
        final normal = Offset(-chord.dy, chord.dx) / chord.distance;
        final bulge =
            (through - mid).dx * normal.dx + (through - mid).dy * normal.dy;
        return QuickShape(kind, [start, mid + normal * bulge, end]);
      case QuickShapeKind.ellipse:
        final [c, a, b] = points;
        final r = ((a - c).distance + (b - c).distance) / 2;
        final u = (a - c) / (a - c).distance;
        return QuickShape(kind, [c, c + u * r, c + Offset(-u.dy, u.dx) * r]);
      case QuickShapeKind.polygon:
        final centre = _centroid(points);
        final r =
            points.map((p) => (p - centre).distance).reduce((x, y) => x + y) /
            points.length;
        final first = points.first - centre;
        final start = math.atan2(first.dy, first.dx);
        final n = points.length;
        // Keep the drawing's winding.
        final turn = _area(points) >= 0 ? 1 : -1;
        return QuickShape(kind, [
          for (var i = 0; i < n; i++)
            centre +
                Offset(
                      math.cos(start + turn * 2 * math.pi * i / n),
                      math.sin(start + turn * 2 * math.pi * i / n),
                    ) *
                    r,
        ]);
    }
  }

  static Offset _snapped(Offset d) {
    const step = math.pi / 12;
    final angle = (math.atan2(d.dy, d.dx) / step).round() * step;
    return Offset(math.cos(angle), math.sin(angle)) * d.distance;
  }

  /// Points along the shape about [spacing] apart, ready to draw as a
  /// stroke; a closed shape ends where it began.
  List<Offset> outline({double spacing = 2}) {
    switch (kind) {
      case QuickShapeKind.line:
      case QuickShapeKind.polyline:
      case QuickShapeKind.polygon:
        final corners = closed ? [...points, points.first] : points;
        final out = <Offset>[corners.first];
        for (var i = 1; i < corners.length; i++) {
          final a = corners[i - 1], b = corners[i];
          final n = math.max(1, ((b - a).distance / spacing).ceil());
          for (var k = 1; k <= n; k++) {
            out.add(Offset.lerp(a, b, k / n)!);
          }
        }
        return out;
      case QuickShapeKind.ellipse:
        final [c, a, b] = points;
        final u = a - c, v = b - c;
        final perimeter =
            math.pi *
            (3 * (u.distance + v.distance) -
                math.sqrt(
                  (3 * u.distance + v.distance) * (u.distance + 3 * v.distance),
                ));
        final n = math.max(12, (perimeter / spacing).ceil());
        return [
          for (var k = 0; k <= n; k++)
            c +
                u * math.cos(2 * math.pi * k / n) +
                v * math.sin(2 * math.pi * k / n),
        ];
      case QuickShapeKind.arc:
        final [start, through, end] = points;
        final circle = _circleThrough(start, through, end);
        if (circle == null) {
          return QuickShape(QuickShapeKind.line, [
            start,
            end,
          ]).outline(spacing: spacing);
        }
        final (centre, radius) = circle;
        double angle(Offset p) =>
            math.atan2(p.dy - centre.dy, p.dx - centre.dx);
        final a0 = angle(start), a1 = angle(through), a2 = angle(end);
        // Go from start to end the way that passes through the middle.
        var sweep = _wrap(a2 - a0);
        final toMiddle = _wrap(a1 - a0);
        if (sweep > 0
            ? !(toMiddle > 0 && toMiddle < sweep)
            : !(toMiddle < 0 && toMiddle > sweep)) {
          sweep -= sweep.sign * 2 * math.pi;
        }
        final n = math.max(4, (sweep.abs() * radius / spacing).ceil());
        return [
          for (var k = 0; k <= n; k++)
            centre +
                Offset(
                      math.cos(a0 + sweep * k / n),
                      math.sin(a0 + sweep * k / n),
                    ) *
                    radius,
        ];
    }
  }

  static double _wrap(double a) {
    var x = a % (2 * math.pi);
    if (x > math.pi) x -= 2 * math.pi;
    return x;
  }

  /// Recognises a held stroke, or null when it is too small to be a shape.
  static QuickShape? recognise(List<Offset> stroke) {
    final points = _dedupe(stroke);
    if (points.length < 2) return null;
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    final box = _bounds(points);
    final size = math.max(box.width, box.height);
    if (length < 8 || size < 6) return null;
    final gap = (points.last - points.first).distance;
    final closed = points.length > 8 && gap < math.max(.2 * size, 12);

    if (!closed) {
      final start = points.first, end = points.last;
      final deviation = points
          .map((p) => _distanceToLine(p, start, end))
          .reduce(math.max);
      if (deviation < math.max(.05 * gap, 3) && gap > .8 * length) {
        return QuickShape(QuickShapeKind.line, [start, end]);
      }
      final through = _pointAt(points, length / 2);
      if (_circleThrough(start, through, end) case (final centre, final r)) {
        final strays = points
            .map((p) => ((p - centre).distance - r).abs())
            .reduce(math.max);
        if (strays < math.max(.06 * size, 4)) {
          return QuickShape(QuickShapeKind.arc, [start, through, end]);
        }
      }
      final corners = _simplify(points, .06 * size);
      if (corners.length > 2) {
        return QuickShape(QuickShapeKind.polyline, corners);
      }
      return QuickShape(QuickShapeKind.arc, [start, through, end]);
    }

    final loop = [...points.sublist(0, points.length - 1), points.first];
    var corners = _simplify(loop, .08 * size);
    if (corners.length > 1 && corners.first == corners.last) {
      corners = corners.sublist(0, corners.length - 1);
    }
    corners = _mergeCorners(corners, .12 * size);
    final ellipse = _fitEllipse(loop);
    final sharp =
        corners.length >= 3 && corners.length <= 6 && _cornersSharp(corners);
    if (sharp && (ellipse == null || ellipse.$2 > .045)) {
      return QuickShape(QuickShapeKind.polygon, corners);
    }
    if (ellipse != null && ellipse.$2 < .12) return ellipse.$1;
    if (corners.length >= 3) {
      return QuickShape(QuickShapeKind.polygon, corners);
    }
    return ellipse?.$1;
  }

  static List<Offset> _dedupe(List<Offset> points) {
    final out = <Offset>[];
    for (final p in points) {
      if (out.isEmpty || (p - out.last).distance > .5) out.add(p);
    }
    return out;
  }

  static Rect _bounds(List<Offset> points) {
    var r = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  static double _distanceToLine(Offset p, Offset a, Offset b) {
    final d = b - a;
    if (d.distance < 1e-9) return (p - a).distance;
    return ((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / d.distance;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final d = b - a;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 < 1e-9) return (p - a).distance;
    final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + d * t)).distance;
  }

  /// Ramer–Douglas–Peucker.
  static List<Offset> _simplify(List<Offset> points, double tolerance) {
    if (points.length < 3) return points;
    var worst = 0.0;
    var index = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final d = _distanceToSegment(points[i], points.first, points.last);
      if (d > worst) {
        worst = d;
        index = i;
      }
    }
    if (worst <= tolerance) return [points.first, points.last];
    final left = _simplify(points.sublist(0, index + 1), tolerance);
    final right = _simplify(points.sublist(index), tolerance);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  /// Corners closer than [distance] become one.
  static List<Offset> _mergeCorners(List<Offset> corners, double distance) {
    final out = <Offset>[];
    for (final c in corners) {
      if (out.isNotEmpty && (c - out.last).distance < distance) {
        out[out.length - 1] = (out.last + c) / 2;
      } else {
        out.add(c);
      }
    }
    if (out.length > 2 && (out.first - out.last).distance < distance) {
      out[0] = (out.first + out.last) / 2;
      out.removeLast();
    }
    return out;
  }

  static double _turn(Offset a, Offset b, Offset c) {
    final u = b - a, v = c - b;
    return (math.atan2(v.dy, v.dx) - math.atan2(u.dy, u.dx)).abs() %
        (2 * math.pi);
  }

  /// Every corner turns by at least 35°: a polygon, not a wobbly circle.
  static bool _cornersSharp(List<Offset> corners) {
    final n = corners.length;
    for (var i = 0; i < n; i++) {
      var t = _turn(corners[(i - 1 + n) % n], corners[i], corners[(i + 1) % n]);
      if (t > math.pi) t = 2 * math.pi - t;
      if (t < 35 * math.pi / 180) return false;
    }
    return true;
  }

  static Offset _pointAt(List<Offset> points, double distance) {
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final step = (points[i] - points[i - 1]).distance;
      if (walked + step >= distance) {
        return Offset.lerp(
          points[i - 1],
          points[i],
          step == 0 ? 0 : (distance - walked) / step,
        )!;
      }
      walked += step;
    }
    return points.last;
  }

  /// The ellipse with the stroke's spread (axes from its second moments,
  /// sized to its mean radius), and how far the stroke strays from it
  /// (the spread of normalised radii).
  static (QuickShape, double)? _fitEllipse(List<Offset> loop) {
    var total = 0.0;
    var cx = 0.0, cy = 0.0;
    final weights = <double>[];
    for (var i = 0; i < loop.length - 1; i++) {
      final w = (loop[i + 1] - loop[i]).distance;
      weights.add(w);
      final m = (loop[i] + loop[i + 1]) / 2;
      cx += m.dx * w;
      cy += m.dy * w;
      total += w;
    }
    if (total <= 0) return null;
    final c = Offset(cx / total, cy / total);
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (var i = 0; i < loop.length - 1; i++) {
      final m = (loop[i] + loop[i + 1]) / 2 - c;
      sxx += m.dx * m.dx * weights[i];
      syy += m.dy * m.dy * weights[i];
      sxy += m.dx * m.dy * weights[i];
    }
    sxx /= total;
    syy /= total;
    sxy /= total;
    final angle = .5 * math.atan2(2 * sxy, sxx - syy);
    final trace = (sxx + syy) / 2;
    final spread = math.sqrt(
      math.max(0, (sxx - syy) * (sxx - syy) / 4 + sxy * sxy),
    );
    var a = math.sqrt(2 * (trace + spread));
    var b = math.sqrt(math.max(1e-6, 2 * (trace - spread)));
    if (a < 1e-6) return null;
    final u = Offset(math.cos(angle), math.sin(angle));
    final v = Offset(-u.dy, u.dx);
    final radii = [
      for (final p in loop)
        math.sqrt(
          math.pow(((p - c).dx * u.dx + (p - c).dy * u.dy) / a, 2) +
              math.pow(((p - c).dx * v.dx + (p - c).dy * v.dy) / b, 2),
        ),
    ];
    final mean = radii.reduce((x, y) => x + y) / radii.length;
    final variance =
        radii
            .map((r) => (r / mean - 1) * (r / mean - 1))
            .reduce((x, y) => x + y) /
        radii.length;
    a *= mean;
    b *= mean;
    return (
      QuickShape(QuickShapeKind.ellipse, [c, c + u * a, c + v * b]),
      math.sqrt(variance),
    );
  }

  static (Offset, double)? _circleThrough(Offset a, Offset b, Offset c) {
    final d =
        2 *
        (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
    if (d.abs() < 1e-6) return null;
    final a2 = a.dx * a.dx + a.dy * a.dy;
    final b2 = b.dx * b.dx + b.dy * b.dy;
    final c2 = c.dx * c.dx + c.dy * c.dy;
    final centre = Offset(
      (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d,
      (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d,
    );
    final radius = (a - centre).distance;
    // A nearly straight arc has a huge circle: draw it as a line.
    if (radius > 1e5) return null;
    return (centre, radius);
  }

  static Offset _centroid(List<Offset> points) =>
      points.reduce((a, b) => a + b) / points.length.toDouble();

  static double _area(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s / 2;
  }
}
