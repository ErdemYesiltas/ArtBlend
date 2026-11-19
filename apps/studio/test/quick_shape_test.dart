import 'dart:math' as math;

import 'package:atelier_studio/drawing/quick_shape.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-drawn look: [points] with a small steady wobble.
List<Offset> wobbly(List<Offset> points, {double amount = 2}) => [
  for (var i = 0; i < points.length; i++)
    points[i] + Offset(math.sin(i * 1.7) * amount, math.cos(i * 2.3) * amount),
];

List<Offset> along(List<Offset> corners, {double step = 4}) => [
  for (var i = 1; i < corners.length; i++)
    for (var t = 0.0; t < 1; t += step / (corners[i] - corners[i - 1]).distance)
      Offset.lerp(corners[i - 1], corners[i], t)!,
  corners.last,
];

List<Offset> ellipse(
  Offset c,
  double a,
  double b, {
  double end = 2 * math.pi,
}) => [
  for (var t = 0.0; t <= end; t += .05)
    c + Offset(math.cos(t) * a, math.sin(t) * b),
];

void main() {
  test('recognises what was drawn', () {
    QuickShapeKind? kind(List<Offset> s) => QuickShape.recognise(s)?.kind;
    expect(
      kind(wobbly(along(const [Offset(10, 10), Offset(400, 120)]))),
      QuickShapeKind.line,
    );
    expect(
      kind(
        wobbly(ellipse(const Offset(300, 300), 200, 200, end: 1.2 * math.pi)),
      ),
      QuickShapeKind.arc,
    );
    expect(
      kind(
        wobbly(
          along(const [
            Offset(0, 0),
            Offset(200, 0),
            Offset(200, 200),
            Offset(400, 200),
          ]),
        ),
      ),
      QuickShapeKind.polyline,
    );
    final oval = QuickShape.recognise(
      wobbly(ellipse(const Offset(300, 300), 200, 120, end: 2 * math.pi + .1)),
    )!;
    expect(oval.kind, QuickShapeKind.ellipse);
    final [c, a, b] = oval.points;
    expect((c - const Offset(300, 300)).distance, lessThan(8));
    final radii = [(a - c).distance, (b - c).distance]..sort();
    expect(radii[0], closeTo(120, 12));
    expect(radii[1], closeTo(200, 15));
    final square = QuickShape.recognise(
      wobbly(
        along(const [
          Offset(100, 100),
          Offset(400, 100),
          Offset(400, 400),
          Offset(100, 400),
          Offset(100, 104),
        ]),
      ),
    )!;
    expect(square.kind, QuickShapeKind.polygon);
    expect(square.points, hasLength(4));
    final triangle = QuickShape.recognise(
      wobbly(
        along(const [
          Offset(200, 50),
          Offset(400, 380),
          Offset(0, 380),
          Offset(197, 55),
        ]),
      ),
    )!;
    expect(
      (triangle.kind, triangle.points.length),
      (QuickShapeKind.polygon, 3),
    );
    expect(QuickShape.recognise(const [Offset(1, 1), Offset(3, 2)]), isNull);
  });

  test('perfect shapes: 15° lines, circles, regular polygons', () {
    final line = QuickShape(QuickShapeKind.line, const [
      Offset.zero,
      Offset(100, 8),
    ]).perfected();
    expect(line.points.last.dy, closeTo(0, 1e-9));
    expect(line.points.last.dx, closeTo(100.32, .01));
    final circle = QuickShape(QuickShapeKind.ellipse, const [
      Offset(50, 50),
      Offset(150, 50),
      Offset(50, 110),
    ]).perfected();
    expect((circle.points[1] - circle.points[0]).distance, closeTo(80, 1e-9));
    expect((circle.points[2] - circle.points[0]).distance, closeTo(80, 1e-9));
    final square = QuickShape(QuickShapeKind.polygon, const [
      Offset(0, 0),
      Offset(110, 5),
      Offset(100, 95),
      Offset(-5, 100),
    ]).perfected();
    final sides = [
      for (var i = 0; i < 4; i++)
        (square.points[(i + 1) % 4] - square.points[i]).distance,
    ];
    for (final s in sides) {
      expect(s, closeTo(sides.first, 1e-6));
    }
  });

  test('a held shape follows the pen; edit nodes move corners and axes', () {
    final line = QuickShape(QuickShapeKind.line, const [
      Offset.zero,
      Offset(100, 0),
    ]);
    final moved = line.movedBy(const Offset(100, 0), const Offset(0, 200));
    expect((moved.points.last - const Offset(0, 200)).distance, lessThan(1e-9));
    expect(moved.points.first.distance, lessThan(1e-9));
    final oval = QuickShape(QuickShapeKind.ellipse, const [
      Offset(100, 100),
      Offset(200, 100),
      Offset(100, 150),
    ]);
    final turned = oval.withNode(0, const Offset(100, 250));
    expect(turned.points[1], const Offset(100, 250));
    expect((turned.points[2] - turned.points[0]).distance, closeTo(50, 1e-9));
    final taller = oval.withNode(3, const Offset(100, 20));
    expect((taller.points[2] - taller.points[0]).distance, closeTo(80, 1e-9));
    expect((taller.points[1] - taller.points[0]).distance, closeTo(100, 1e-9));
    expect(
      oval.withNode(4, const Offset(0, 0)).points[1],
      const Offset(100, 0),
    );
    final arc = QuickShape(QuickShapeKind.arc, const [
      Offset(0, 0),
      Offset(50, -50),
      Offset(100, 0),
    ]).outline();
    expect(arc.first.distance, lessThan(1e-9));
    expect((arc.last - const Offset(100, 0)).distance, lessThan(1e-9));
    expect(arc.map((p) => p.dy).reduce(math.min), closeTo(-50, .5));
    final ring = oval.outline();
    expect((ring.first - ring.last).distance, lessThan(1e-9));
  });
}
