import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../drawing/adjustments.dart';

/// Curves' graph: the layer's histogram behind one channel's curve.
/// Dragging moves the nearest point or adds one (up to [maxPoints]); a
/// double tap removes a point between the ends.
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    super.key,
    required this.points,
    required this.color,
    required this.onChangeStart,
    required this.onChanged,
    this.histogram,
  });

  final List<Offset> points;
  final Color color;
  final List<int>? histogram;
  final VoidCallback onChangeStart;
  final ValueChanged<List<Offset>> onChanged;

  static const maxPoints = 11;

  /// How near (logical pixels) a touch must be to take a point.
  static const reach = 22.0;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  int? _dragging;
  Offset? _lastTap;

  /// The latest points: drag events can come before the rebuild.
  late List<Offset> _points = widget.points;

  @override
  void didUpdateWidget(CurveEditor old) {
    super.didUpdateWidget(old);
    _points = widget.points;
  }

  void _emit(List<Offset> points) {
    _points = points;
    widget.onChanged(points);
  }

  Offset _toValue(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (1 - local.dy / size.height).clamp(0.0, 1.0),
  );

  int? _nearest(Offset local, Size size) {
    int? best;
    var distance = CurveEditor.reach;
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      final d = (Offset(p.dx * size.width, (1 - p.dy) * size.height) - local)
          .distance;
      if (d <= distance) {
        best = i;
        distance = d;
      }
    }
    return best;
  }

  void _start(Offset local, Size size) {
    widget.onChangeStart();
    final near = _nearest(local, size);
    if (near != null) {
      _dragging = near;
      return;
    }
    if (_points.length >= CurveEditor.maxPoints) {
      _dragging = null;
      return;
    }
    final value = _toValue(local, size);
    final points = [..._points];
    var index = points.indexWhere((p) => p.dx > value.dx);
    if (index <= 0) index = points.length - 1;
    points.insert(index, value);
    _dragging = index;
    _emit(points);
  }

  void _move(Offset local, Size size) {
    final index = _dragging;
    if (index == null) return;
    final points = [..._points];
    var value = _toValue(local, size);
    // The ends stay at the edges; the others keep their order.
    if (index == 0) {
      value = Offset(0, value.dy);
    } else if (index == points.length - 1) {
      value = Offset(1, value.dy);
    } else {
      value = Offset(
        value.dx.clamp(points[index - 1].dx + .01, points[index + 1].dx - .01),
        value.dy,
      );
    }
    points[index] = value;
    _emit(points);
  }

  void _doubleTap(Size size) {
    final tap = _lastTap;
    if (tap == null) return;
    final index = _nearest(tap, size);
    if (index == null || index == 0 || index == _points.length - 1) {
      return;
    }
    widget.onChangeStart();
    _emit([..._points]..removeAt(index));
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          key: const ValueKey('curve-editor'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _start(d.localPosition, size),
          onPanUpdate: (d) => _move(d.localPosition, size),
          onPanEnd: (_) => _dragging = null,
          onDoubleTapDown: (d) => _lastTap = d.localPosition,
          onDoubleTap: () => _doubleTap(size),
          child: CustomPaint(
            size: size,
            painter: _CurvePainter(
              points: _points,
              color: widget.color,
              histogram: widget.histogram,
              grid: Theme.of(context).colorScheme.outlineVariant,
              fill: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      },
    ),
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.color,
    required this.histogram,
    required this.grid,
    required this.fill,
  });

  final List<Offset> points;
  final Color color, grid, fill;
  final List<int>? histogram;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final bins = histogram;
    if (bins != null) {
      // Square-rooted so a few huge bins do not flatten the rest.
      final most = math.sqrt(bins.reduce(math.max).toDouble());
      if (most > 0) {
        final path = Path()..moveTo(0, size.height);
        for (var i = 0; i < 256; i++) {
          path.lineTo(
            i / 255 * size.width,
            size.height * (1 - math.sqrt(bins[i].toDouble()) / most),
          );
        }
        path
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(path, Paint()..color = grid.withValues(alpha: .6));
      }
    }
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4, y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final table = curveTable(points);
    final curve = Path();
    for (var i = 0; i < 256; i++) {
      final p = Offset(
        i / 255 * size.width,
        (1 - table[i] / 255) * size.height,
      );
      i == 0 ? curve.moveTo(p.dx, p.dy) : curve.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final p in points) {
      final centre = Offset(p.dx * size.width, (1 - p.dy) * size.height);
      canvas.drawCircle(centre, 6, Paint()..color = Colors.white);
      canvas.drawCircle(
        centre,
        6,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points ||
      old.color != color ||
      old.histogram != histogram ||
      old.grid != grid;
}

/// Gradient Map's bar: tap the bar to add a colour, tap a stop to change
/// it, drag it to move it, hold it to remove it (two stay).
class GradientEditor extends StatefulWidget {
  const GradientEditor({
    super.key,
    required this.stops,
    required this.onChangeStart,
    required this.onChanged,
    required this.onPick,
  });

  final GradientStops stops;
  final VoidCallback onChangeStart;
  final ValueChanged<GradientStops> onChanged;

  /// Asks for a new colour for stop [index].
  final void Function(int index) onPick;

  static const height = 44.0, handle = 22.0;

  /// Stops sit inside the bar's ends so the end handles show whole.
  static double toX(double position, double width) =>
      handle / 2 + position * (width - handle);

  static double toPosition(double x, double width) =>
      ((x - handle / 2) / (width - handle)).clamp(0.0, 1.0);

  @override
  State<GradientEditor> createState() => _GradientEditorState();
}

class _GradientEditorState extends State<GradientEditor> {
  int? _dragging;

  /// The latest stops: drag events can come before the rebuild.
  late GradientStops _stops = widget.stops;

  @override
  void didUpdateWidget(GradientEditor old) {
    super.didUpdateWidget(old);
    _stops = widget.stops;
  }

  void _emit(GradientStops stops) {
    _stops = stops;
    widget.onChanged(stops);
  }

  int? _stopAt(double x, double width) {
    int? best;
    var distance = GradientEditor.handle / 2 + 6;
    for (var i = 0; i < _stops.length; i++) {
      final d = (GradientEditor.toX(_stops[i].$1, width) - x).abs();
      if (d <= distance) {
        best = i;
        distance = d;
      }
    }
    return best;
  }

  void _tap(double x, double width) {
    final index = _stopAt(x, width);
    if (index != null) {
      widget.onPick(index);
      return;
    }
    final t = GradientEditor.toPosition(x, width);
    widget.onChangeStart();
    _emit(
      [..._stops, (t, gradientColor(_stops, t))]
        ..sort((a, b) => a.$1.compareTo(b.$1)),
    );
  }

  void _remove(double x, double width) {
    final index = _stopAt(x, width);
    if (index == null || _stops.length <= 2) return;
    widget.onChangeStart();
    _emit([..._stops]..removeAt(index));
  }

  void _drag(double x, double width) {
    final index = _dragging;
    if (index == null) return;
    final stops = [..._stops];
    stops[index] = (GradientEditor.toPosition(x, width), stops[index].$2);
    // Keep the order: the dragged stop is followed by its new index.
    final moved = stops[index];
    stops.sort((a, b) => a.$1.compareTo(b.$1));
    _dragging = stops.indexOf(moved);
    _emit(stops);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        key: const ValueKey('gradient-editor'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _tap(d.localPosition.dx, width),
        onLongPressStart: (d) => _remove(d.localPosition.dx, width),
        onHorizontalDragStart: (d) {
          _dragging = _stopAt(d.localPosition.dx, width);
          if (_dragging != null) widget.onChangeStart();
        },
        onHorizontalDragUpdate: (d) => _drag(d.localPosition.dx, width),
        onHorizontalDragEnd: (_) => _dragging = null,
        child: CustomPaint(
          size: Size(width, GradientEditor.height),
          painter: _GradientPainter(
            _stops,
            Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    },
  );
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(this.stops, this.outline);
  final GradientStops stops;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        GradientEditor.handle / 2,
        8,
        size.width - GradientEditor.handle,
        size.height - 16,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(GradientEditor.toX(0, size.width), 0),
          Offset(GradientEditor.toX(1, size.width), 0),
          [for (final s in stops) Color(s.$2 | 0xff000000)],
          [for (final s in stops) s.$1],
        ),
    );
    for (final (position, color) in stops) {
      final centre = Offset(
        GradientEditor.toX(position, size.width),
        size.height / 2,
      );
      canvas.drawCircle(
        centre,
        GradientEditor.handle / 2,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        centre,
        GradientEditor.handle / 2 - 3,
        Paint()..color = Color(color | 0xff000000),
      );
      canvas.drawCircle(
        centre,
        GradientEditor.handle / 2,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_GradientPainter old) =>
      old.stops != stops || old.outline != outline;
}

/// A small swatch of a gradient, for the presets.
class GradientSwatch extends StatelessWidget {
  const GradientSwatch(this.stops, {super.key});
  final GradientStops stops;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 18,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      gradient: LinearGradient(
        colors: [for (final s in stops) Color(s.$2 | 0xff000000)],
        stops: [for (final s in stops) s.$1],
      ),
    ),
  );
}
