import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'canvas_geometry.dart';

/// Selections are checked against the largest canvas; everything they clip
/// is clipped to its own drawing's canvas anyway.
const selectionCanvasBounds = CanvasSize.maxBounds;

/// How a later shape changes a selection, in order (Procreate's Add and
/// Remove, and Invert once there is more than one shape).
enum SelectionOp { add, subtract, invert }

/// One step after a selection's first shape; [points] is empty for invert.
final class SelectionEdit {
  SelectionEdit(this.op, List<Offset> points)
    : points = List.unmodifiable(points) {
    if ((op == SelectionOp.invert) != points.isEmpty) {
      throw const FormatException('Invalid selection edit');
    }
    if (op != SelectionOp.invert) _checkPolygon(points);
  }
  final SelectionOp op;
  final List<Offset> points;
  Map<String, dynamic> toJson() => {
    'op': op.name,
    if (points.isNotEmpty) 'points': points.map((p) => [p.dx, p.dy]).toList(),
  };
  factory SelectionEdit.fromJson(Map<String, dynamic> json) => SelectionEdit(
    SelectionOp.values.asNameMap()[json['op']] ??
        (throw const FormatException('Invalid selection edit')),
    _readPoints(json['points'] ?? const []),
  );
}

void _checkPolygon(List<Offset> points) {
  if (points.length < 3 ||
      points.length > 4096 ||
      points.any(
        (p) =>
            !p.dx.isFinite ||
            !p.dy.isFinite ||
            p.dx < 0 ||
            p.dy < 0 ||
            p.dx > CanvasSize.maxSide ||
            p.dy > CanvasSize.maxSide,
      )) {
    throw const FormatException('Invalid selection geometry');
  }
  // Keep parsing sendable to Flutter's background file-import isolate.
  final bounds = Rect.fromLTRB(
    points.map((p) => p.dx).reduce(math.min),
    points.map((p) => p.dy).reduce(math.min),
    points.map((p) => p.dx).reduce(math.max),
    points.map((p) => p.dy).reduce(math.max),
  );
  if (bounds.width < 1 || bounds.height < 1) {
    throw const FormatException('Selection is too small');
  }
}

List<Offset> _readPoints(Object? raw) {
  if (raw is! List || raw.length > 4096) {
    throw const FormatException('Invalid selection points');
  }
  return raw.map((p) {
    if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) {
      throw const FormatException('Invalid selection point');
    }
    return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
  }).toList();
}

Path _polygon(List<Offset> points) => Path()
  ..fillType = PathFillType.evenOdd
  ..addPolygon(points, true);

/// Document-space selection: a first shape ([points], [inverted] by itself
/// as files before edits stored it), then [edits] in order, then a soft
/// edge of [feather] pixels. Flutter's even-odd paths and boolean path
/// operations keep it exact across drawing, export and transforms.
class SelectionRegion {
  SelectionRegion({
    required this.id,
    required List<Offset> points,
    this.inverted = false,
    List<SelectionEdit> edits = const [],
    this.feather = 0,
  }) : points = List.unmodifiable(points),
       edits = List.unmodifiable(edits) {
    if (id.isEmpty ||
        id.length > 128 ||
        this.edits.length > maxEdits ||
        !feather.isFinite ||
        feather < 0 ||
        feather > maxFeather) {
      throw const FormatException('Invalid selection geometry');
    }
    _checkPolygon(points);
  }
  static const maxEdits = 32;
  static const maxFeather = 256.0;
  final String id;
  final List<Offset> points;
  final bool inverted;
  final List<SelectionEdit> edits;

  /// Width of the soft edge in canvas pixels; the hard [path] is its middle.
  final double feather;

  /// Every point stored, for document limits.
  int get pointCount =>
      points.length + edits.fold(0, (n, e) => n + e.points.length);

  Path get polygon => _polygon(points);
  late final Path path = () {
    var path = !inverted
        ? polygon
        : Path.combine(
            PathOperation.difference,
            Path()..addRect(selectionCanvasBounds),
            polygon,
          );
    for (final edit in edits) {
      path = switch (edit.op) {
        SelectionOp.add => Path.combine(
          PathOperation.union,
          path,
          _polygon(edit.points),
        ),
        SelectionOp.subtract => Path.combine(
          PathOperation.difference,
          path,
          _polygon(edit.points),
        ),
        SelectionOp.invert => Path.combine(
          PathOperation.difference,
          Path()..addRect(selectionCanvasBounds),
          path,
        ),
      };
    }
    return path;
  }();
  late final Path complement = Path.combine(
    PathOperation.difference,
    Path()..addRect(selectionCanvasBounds),
    path,
  );

  /// Where the selection reaches, its soft edge included.
  Rect get bounds => path.getBounds().inflate(feather);

  /// Paints coverage: white inside, fading over [feather] pixels on each
  /// side of the line (three standard deviations of the blur).
  Paint get coveragePaint => Paint()
    ..color = const Color(0xffffffff)
    ..maskFilter = feather > 0
        ? MaskFilter.blur(BlurStyle.normal, feather / 3)
        : null;

  SelectionRegion _with({
    bool? inverted,
    List<SelectionEdit>? edits,
    double? feather,
  }) => SelectionRegion(
    id: const Uuid().v4(),
    points: points,
    inverted: inverted ?? this.inverted,
    edits: edits ?? this.edits,
    feather: feather ?? this.feather,
  );

  SelectionRegion invert() => edits.isEmpty
      ? _with(inverted: !inverted)
      : edits.last.op == SelectionOp.invert
      ? _with(edits: edits.sublist(0, edits.length - 1))
      : _with(edits: [...edits, SelectionEdit(SelectionOp.invert, const [])]);

  /// [shape] added to or taken from this selection.
  SelectionRegion combine(SelectionOp op, List<Offset> shape) {
    if (edits.length >= maxEdits) {
      throw const FormatException('Too many selection edits');
    }
    return _with(edits: [...edits, SelectionEdit(op, shape)]);
  }

  SelectionRegion withFeather(double value) => _with(feather: value);

  /// Every point moved by [map] (a canvas cropped, resized, turned or
  /// flipped), cut to the largest canvas; the edge's softness scaled by
  /// [featherScale]. Null when nothing of the first shape is left.
  SelectionRegion? mapped(
    Offset Function(Offset point) map, {
    double featherScale = 1,
  }) {
    List<Offset>? shape(List<Offset> points) {
      final clipped = _clipToBounds([for (final p in points) map(p)]);
      if (clipped.length < 3) return null;
      try {
        _checkPolygon(clipped);
        return clipped;
      } on FormatException {
        return null;
      }
    }

    final first = shape(points);
    if (first == null) return null;
    final moved = <SelectionEdit>[];
    for (final edit in edits) {
      if (edit.op == SelectionOp.invert) {
        moved.add(edit);
        continue;
      }
      final next = shape(edit.points);
      if (next != null) moved.add(SelectionEdit(edit.op, next));
    }
    return SelectionRegion(
      id: const Uuid().v4(),
      points: first,
      inverted: inverted,
      edits: moved,
      feather: (feather * featherScale).clamp(0, maxFeather),
    );
  }

  /// Sutherland–Hodgman: [polygon] cut to [selectionCanvasBounds], which
  /// leaves what lies inside exactly as it was.
  static List<Offset> _clipToBounds(List<Offset> polygon) {
    const r = selectionCanvasBounds;
    var out = polygon;
    for (final (inside, cross)
        in <(bool Function(Offset), Offset Function(Offset, Offset))>[
          ((p) => p.dx >= r.left, (a, b) => _atX(a, b, r.left)),
          ((p) => p.dx <= r.right, (a, b) => _atX(a, b, r.right)),
          ((p) => p.dy >= r.top, (a, b) => _atY(a, b, r.top)),
          ((p) => p.dy <= r.bottom, (a, b) => _atY(a, b, r.bottom)),
        ]) {
      if (out.isEmpty) break;
      final input = out;
      out = [];
      for (var i = 0; i < input.length; i++) {
        final a = input[(i + input.length - 1) % input.length], b = input[i];
        if (inside(b)) {
          if (!inside(a)) out.add(cross(a, b));
          out.add(b);
        } else if (inside(a)) {
          out.add(cross(a, b));
        }
      }
    }
    return out;
  }

  static Offset _atX(Offset a, Offset b, double x) =>
      Offset(x, a.dy + (b.dy - a.dy) * (x - a.dx) / (b.dx - a.dx));

  static Offset _atY(Offset a, Offset b, double y) =>
      Offset(a.dx + (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy), y);

  factory SelectionRegion.rectangle(Rect rect) =>
      SelectionRegion(id: const Uuid().v4(), points: rectanglePoints(rect));
  factory SelectionRegion.ellipse(Rect rect) =>
      SelectionRegion(id: const Uuid().v4(), points: ellipsePoints(rect));
  factory SelectionRegion.lasso(List<Offset> points) =>
      SelectionRegion(id: const Uuid().v4(), points: points);

  static List<Offset> rectanglePoints(Rect rect) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  /// An ellipse as a polygon fine enough to look round at any size.
  static List<Offset> ellipsePoints(Rect rect) {
    final n = (math.max(rect.width, rect.height) / 4).clamp(32, 256).round();
    return [
      for (var i = 0; i < n; i++)
        Offset(
          rect.center.dx + rect.width / 2 * math.cos(2 * math.pi * i / n),
          rect.center.dy + rect.height / 2 * math.sin(2 * math.pi * i / n),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'inverted': inverted,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    if (edits.isNotEmpty) 'edits': edits.map((e) => e.toJson()).toList(),
    if (feather > 0) 'feather': feather,
  };
  factory SelectionRegion.fromJson(Map<String, dynamic> json) {
    final edits = json['edits'];
    if (edits != null && (edits is! List || edits.length > maxEdits)) {
      throw const FormatException('Invalid selection edits');
    }
    final feather = json['feather'];
    if (feather != null && feather is! num) {
      throw const FormatException('Invalid selection feather');
    }
    return SelectionRegion(
      id: json['id'] as String,
      inverted: json['inverted'] as bool? ?? false,
      points: _readPoints(json['points']),
      edits: [
        for (final edit in (edits as List?) ?? const [])
          SelectionEdit.fromJson(Map<String, dynamic>.from(edit as Map)),
      ],
      feather: (feather as num? ?? 0).toDouble(),
    );
  }
}

/// Share one immutable selection across many strokes in the document file.
String registerSelection(
  SelectionRegion region,
  Map<String, SelectionRegion> registry,
) {
  final existing = registry[region.id];
  if (existing != null &&
      !identical(existing, region) &&
      jsonEncode(existing.toJson()) != jsonEncode(region.toJson())) {
    throw const FormatException('Conflicting selection identities');
  }
  registry.putIfAbsent(region.id, () => region);
  return region.id;
}

SelectionRegion? readSelection(
  Map<String, dynamic> json,
  String key,
  Map<String, SelectionRegion> regions,
) {
  final reference = json['${key}Id'];
  final inline = json[key];
  if (reference != null) {
    if (reference is! String ||
        inline != null ||
        !regions.containsKey(reference)) {
      throw const FormatException('Invalid selection reference');
    }
    return regions[reference];
  }
  return inline == null
      ? null
      : SelectionRegion.fromJson(Map<String, dynamic>.from(inline as Map));
}
