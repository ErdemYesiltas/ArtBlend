import 'dart:math' as math;
import 'dart:ui';

/// Procreate's drawing guides (symmetry is set beside them).
enum GuideKind { none, grid, isometric, perspective }

/// The drawing guide and how it looks. Points are kept as fractions of the
/// canvas (0–1), so the guide fits any canvas size.
class DrawingGuide {
  const DrawingGuide({
    this.kind = GuideKind.none,
    this.gridSize = 64,
    this.color = 0xff3a7bd5,
    this.opacity = .3,
    this.thickness = 1,
    this.vanishing = const [Offset(.5, .4)],
    this.symmetryCentre = const Offset(.5, .5),
    this.rotational = false,
  });

  final GuideKind kind;

  /// Grid and isometric spacing, in canvas pixels.
  final double gridSize;
  final int color;
  final double opacity;

  /// Line width in screen pixels.
  final double thickness;

  /// Perspective's vanishing points (one to three).
  final List<Offset> vanishing;

  /// Where symmetry mirrors or turns around.
  final Offset symmetryCentre;

  /// Symmetry turns copies (180°, or a quarter each) instead of mirroring.
  final bool rotational;

  static const maxVanishing = 3;

  DrawingGuide copyWith({
    GuideKind? kind,
    double? gridSize,
    int? color,
    double? opacity,
    double? thickness,
    List<Offset>? vanishing,
    Offset? symmetryCentre,
    bool? rotational,
  }) => DrawingGuide(
    kind: kind ?? this.kind,
    gridSize: (gridSize ?? this.gridSize).clamp(8, 512),
    color: color ?? this.color,
    opacity: (opacity ?? this.opacity).clamp(.05, 1),
    thickness: (thickness ?? this.thickness).clamp(.5, 6),
    vanishing: vanishing ?? this.vanishing,
    symmetryCentre: symmetryCentre ?? this.symmetryCentre,
    rotational: rotational ?? this.rotational,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'gridSize': gridSize,
    'color': color,
    'opacity': opacity,
    'thickness': thickness,
    'vanishing': [
      for (final p in vanishing) [p.dx, p.dy],
    ],
    'symmetryCentre': [symmetryCentre.dx, symmetryCentre.dy],
    'rotational': rotational,
  };

  /// Settings saved by an earlier version; anything odd falls back.
  factory DrawingGuide.fromJson(Object? json) {
    if (json is! Map) return const DrawingGuide();
    Offset? point(Object? p) =>
        p is List && p.length == 2 && p[0] is num && p[1] is num
        ? Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
        : null;
    final vanishing = [
      for (final p in (json['vanishing'] as List? ?? const [])) ?point(p),
    ];
    const fallback = DrawingGuide();
    return fallback.copyWith(
      kind: GuideKind.values.asNameMap()[json['kind']],
      gridSize: (json['gridSize'] as num?)?.toDouble(),
      color: json['color'] as int?,
      opacity: (json['opacity'] as num?)?.toDouble(),
      thickness: (json['thickness'] as num?)?.toDouble(),
      vanishing: vanishing.isEmpty
          ? null
          : vanishing.take(maxVanishing).toList(),
      symmetryCentre: point(json['symmetryCentre']),
      rotational: json['rotational'] as bool?,
    );
  }

  /// Vanishing points in canvas pixels.
  List<Offset> vanishingOn(Size canvas) => [
    for (final p in vanishing)
      Offset(p.dx * canvas.width, p.dy * canvas.height),
  ];

  Offset symmetryCentreOn(Size canvas) => Offset(
    symmetryCentre.dx * canvas.width,
    symmetryCentre.dy * canvas.height,
  );
}

/// The guide's lines on a [canvas]-sized drawing, each from one end to the
/// other (painting clips them to the canvas).
List<(Offset, Offset)> guideLines(DrawingGuide guide, Size canvas) {
  final reach = canvas.longestSide * 2;
  List<(Offset, Offset)> family(double angle, double spacing) {
    final d = Offset(math.cos(angle), math.sin(angle));
    final n = Offset(-d.dy, d.dx);
    final centre = canvas.center(Offset.zero);
    final count = (canvas.longestSide * 1.5 / spacing).ceil();
    return [
      for (var k = -count; k <= count; k++)
        (
          centre + n * (k * spacing) - d * reach,
          centre + n * (k * spacing) + d * reach,
        ),
    ];
  }

  switch (guide.kind) {
    case GuideKind.none:
      return const [];
    case GuideKind.grid:
      final s = guide.gridSize;
      return [
        for (var x = s; x < canvas.width; x += s)
          (Offset(x, 0), Offset(x, canvas.height)),
        for (var y = s; y < canvas.height; y += s)
          (Offset(0, y), Offset(canvas.width, y)),
      ];
    case GuideKind.isometric:
      // Verticals and the two 30° slopes, meeting at shared points.
      final s = guide.gridSize;
      return [
        ...family(math.pi / 2, s),
        ...family(math.pi / 6, s * math.cos(math.pi / 6)),
        ...family(-math.pi / 6, s * math.cos(math.pi / 6)),
      ];
    case GuideKind.perspective:
      final points = guide.vanishingOn(canvas);
      return [
        // The horizon: through one point level, or through the first two.
        if (points.length == 1)
          (Offset(-reach, points[0].dy), Offset(reach, points[0].dy))
        else
          (
            points[0] + (points[0] - points[1]) * 10,
            points[1] + (points[1] - points[0]) * 10,
          ),
        for (final vp in points)
          for (var i = 0; i < 48; i++)
            (
              vp,
              vp +
                  Offset(
                        math.cos(i * math.pi / 24),
                        math.sin(i * math.pi / 24),
                      ) *
                      reach,
            ),
        // One and two points: true verticals.
        if (points.length < 3)
          for (
            var x = guide.gridSize;
            x < canvas.width;
            x += guide.gridSize * 2
          )
            (Offset(x, 0), Offset(x, canvas.height)),
      ];
  }
}

/// Drawing assist: the directions a stroke from [start] may follow on
/// [guide] (unit vectors).
List<Offset> assistDirections(DrawingGuide guide, Size canvas, Offset start) {
  Offset at(double angle) => Offset(math.cos(angle), math.sin(angle));
  switch (guide.kind) {
    case GuideKind.none:
      return const [];
    case GuideKind.grid:
      return [at(0), at(math.pi / 2)];
    case GuideKind.isometric:
      return [at(math.pi / 2), at(math.pi / 6), at(-math.pi / 6)];
    case GuideKind.perspective:
      final points = guide.vanishingOn(canvas);
      return [
        for (final vp in points)
          if ((vp - start).distance > 1e-6)
            (vp - start) / (vp - start).distance,
        if (points.length < 3) at(math.pi / 2),
        if (points.length == 1) at(0),
      ];
  }
}

/// Of [directions], the one nearest [heading] (either way along it).
Offset? nearestDirection(List<Offset> directions, Offset heading) {
  if (heading.distance < 1e-9) return null;
  Offset? best;
  var bestDot = -1.0;
  for (final d in directions) {
    final dot =
        (d.dx * heading.dx + d.dy * heading.dy).abs() / heading.distance;
    if (dot > bestDot) {
      bestDot = dot;
      best = d;
    }
  }
  return best;
}

/// [point] put on the line through [origin] along [direction].
Offset projectOnto(Offset point, Offset origin, Offset direction) {
  final d = point - origin;
  final along = d.dx * direction.dx + d.dy * direction.dy;
  return origin + direction * along;
}
