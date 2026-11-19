import 'dart:math' as math;
import 'dart:ui';

import '../domain/document.dart';

/// Drawing assistance: every stroke also drawn mirrored or turned around
/// the canvas centre, as Procreate's symmetry guide does.
enum SymmetryKind { off, vertical, horizontal, quadrant, radial }

/// Copies a stroke point takes, each a row-major 2×2 matrix applied around
/// the centre; the first is the stroke itself. [rotational] turns copies
/// (half a turn, or a quarter each) instead of mirroring them.
List<(double, double, double, double)> symmetryMatrices(
  SymmetryKind kind, {
  int segments = 8,
  bool rotational = false,
}) => switch (kind) {
  SymmetryKind.off => const [(1, 0, 0, 1)],
  SymmetryKind.vertical || SymmetryKind.horizontal when rotational => const [
    (1, 0, 0, 1),
    (-1, 0, 0, -1),
  ],
  SymmetryKind.quadrant when rotational => const [
    (1, 0, 0, 1),
    (0, -1, 1, 0),
    (-1, 0, 0, -1),
    (0, 1, -1, 0),
  ],
  SymmetryKind.vertical => const [(1, 0, 0, 1), (-1, 0, 0, 1)],
  SymmetryKind.horizontal => const [(1, 0, 0, 1), (1, 0, 0, -1)],
  SymmetryKind.quadrant => const [
    (1, 0, 0, 1),
    (-1, 0, 0, 1),
    (1, 0, 0, -1),
    (-1, 0, 0, -1),
  ],
  SymmetryKind.radial => [
    for (var i = 0; i < segments; i++)
      () {
        final a = 2 * math.pi * i / segments;
        // Exact zeros keep axis-aligned copies on whole pixels.
        double clean(double v) => v.abs() < 1e-12 ? 0 : v;
        return (
          clean(math.cos(a)),
          clean(-math.sin(a)),
          clean(math.sin(a)),
          clean(math.cos(a)),
        );
      }(),
  ],
};

Offset _map(
  (double, double, double, double) m,
  Offset center,
  double x,
  double y,
) {
  final (a, b, c, d) = m;
  final dx = x - center.dx, dy = y - center.dy;
  return Offset(center.dx + a * dx + b * dy, center.dy + c * dx + d * dy);
}

/// [stroke] and its symmetric copies (vector strokes; native brushes draw
/// copies in the engine).
List<InkStroke> symmetricStrokes(
  InkStroke stroke,
  SymmetryKind kind,
  Offset center, {
  bool rotational = false,
}) {
  final matrices = symmetryMatrices(kind, rotational: rotational);
  return [
    stroke,
    for (final m in matrices.skip(1))
      InkStroke(
        id: newId(),
        points: [
          for (final p in stroke.points)
            () {
              final at = _map(m, center, p.x, p.y);
              return InkPoint(at.dx, at.dy, p.pressure);
            }(),
        ],
        color: stroke.color,
        size: stroke.size,
        opacity: stroke.opacity,
        eraser: stroke.eraser,
        simulatePressure: stroke.simulatePressure,
        smoothing: stroke.smoothing,
        thinning: stroke.thinning,
        clip: stroke.clip,
        atop: stroke.atop,
      ),
  ];
}

/// Lines to show for [kind] on a canvas of [size]: through the centre.
List<(Offset, Offset)> symmetryAxes(
  SymmetryKind kind,
  Size size, {
  Offset? centre,
}) {
  final c = centre ?? size.center(Offset.zero);
  final reach = size.longestSide;
  return switch (kind) {
    SymmetryKind.off => const [],
    SymmetryKind.vertical => [(Offset(c.dx, 0), Offset(c.dx, size.height))],
    SymmetryKind.horizontal => [(Offset(0, c.dy), Offset(size.width, c.dy))],
    // (Quadrant and radial lines run through the centre.)
    SymmetryKind.quadrant => [
      (Offset(c.dx, 0), Offset(c.dx, size.height)),
      (Offset(0, c.dy), Offset(size.width, c.dy)),
    ],
    SymmetryKind.radial => [
      for (var i = 0; i < 4; i++)
        () {
          final a = math.pi * i / 4;
          final d = Offset(math.cos(a), math.sin(a)) * reach;
          return (c - d, c + d);
        }(),
    ],
  };
}
