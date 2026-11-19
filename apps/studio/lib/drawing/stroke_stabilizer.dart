import 'dart:collection';
import 'dart:math' as math;

import '../domain/document.dart';

/// The three smoothing controls Procreate artists know, all 0…1.
class SmoothingSettings {
  const SmoothingSettings({
    this.streamLine = 0,
    this.stabilization = 0,
    this.motionFilter = 0,
    this.expression = 0,
  });

  /// Per brush: irons the line out; trails the pen, catches up on lift.
  final double streamLine;

  /// Averages recent movement; the faster the pen, the stronger the effect.
  final double stabilization;

  /// Cuts the extremes of wobble at any speed; [expression] adds some back.
  final double motionFilter, expression;

  bool get active => streamLine > 0 || stabilization > 0 || motionFilter > 0;

  Map<String, double> toJson() => {
    'streamLine': streamLine,
    'stabilization': stabilization,
    'motionFilter': motionFilter,
    'expression': expression,
  };
}

/// Runs pointer input through motion filtering, stabilization and StreamLine,
/// in that order, before it reaches either brush engine. Every stage is
/// time-based, so a 240 Hz pen and a 60 Hz mouse give the same curve. Pressure
/// and tilt are never delayed.
class StrokeStabilizer {
  StrokeStabilizer(this.settings);
  final SmoothingSettings settings;

  /// Time constant of the motion filter's trend at full strength.
  static const motionTrend = Duration(milliseconds: 30);

  /// Wobble closer than this to the trend survives at zero filtering.
  static const motionTolerance = 10.0;

  /// Averaging window at full stabilization and at or above [fastSpeed].
  static const stabilizationWindow = Duration(milliseconds: 120);
  static const fastSpeed = 1000.0;
  static const speedSpan = .05;

  /// StreamLine lag at 100%; it grows with the square of the amount so the
  /// lower half of the slider stays responsive.
  static const streamLineLag = Duration(milliseconds: 160);

  static const catchUpSpacing = 2.0;
  static const catchUpStep = Duration(milliseconds: 4);
  static const maxCatchUp = 96;
  static const _defaultStep = 1 / 120;

  InkPoint? _raw;
  Duration? _time;
  double _clock = 0;
  double _trendX = 0, _trendY = 0;
  double _lineX = 0, _lineY = 0;
  final Queue<(double, double, double)> _history = Queue();

  InkPoint start(InkPoint point, Duration? time) {
    _raw = point;
    _time = time;
    _clock = 0;
    _trendX = _lineX = point.x;
    _trendY = _lineY = point.y;
    _history
      ..clear()
      ..add((0, point.x, point.y));
    return point;
  }

  InkPoint add(InkPoint point, Duration? time) {
    final previous = _time;
    final dt = time == null || previous == null
        ? _defaultStep
        : math.max(0, (time - previous).inMicroseconds) / 1e6;
    _time = time ?? previous;
    _raw = point;
    _clock += dt;
    var (x, y) = _motionFilter(point.x, point.y, dt);
    (x, y) = _stabilize(x, y, dt);
    (x, y) = _streamLine(x, y, dt);
    return InkPoint(x, y, point.pressure);
  }

  static double _follow(double dt, double tau) =>
      tau <= 0 ? 1 : 1 - math.exp(-dt / tau);

  (double, double) _motionFilter(double x, double y, double dt) {
    final m = settings.motionFilter;
    if (m <= 0) return (x, y);
    final k = _follow(dt, m * motionTrend.inMicroseconds / 1e6);
    _trendX += (x - _trendX) * k;
    _trendY += (y - _trendY) * k;
    final dx = x - _trendX, dy = y - _trendY;
    final deviation = math.sqrt(dx * dx + dy * dy);
    final limit = (1 - m) * motionTolerance;
    if (deviation <= limit) return (x, y);
    // Keep the wobble up to the limit, cut the extreme beyond it, and let
    // Expression restore part of the cut; stronger filtering mutes it.
    final kept =
        limit + (deviation - limit) * settings.expression * (1 - .75 * m);
    return (_trendX + dx / deviation * kept, _trendY + dy / deviation * kept);
  }

  (double, double) _stabilize(double x, double y, double dt) {
    final s = settings.stabilization;
    if (s <= 0) return (x, y);
    _history.add((_clock, x, y));
    final horizon = stabilizationWindow.inMicroseconds / 1e6;
    while (_history.first.$1 < _clock - horizon) {
      _history.removeFirst();
    }
    // Net displacement over a short span: tremor goes back and forth and
    // cancels out, real motion does not.
    final (t0, x0, y0) = _history.firstWhere((h) => h.$1 >= _clock - speedSpan);
    final span = _clock - t0;
    final speed = span <= 0
        ? 0.0
        : math.sqrt(math.pow(x - x0, 2) + math.pow(y - y0, 2)) / span;
    final window = s * horizon * (speed / fastSpeed).clamp(0.0, 1.0);
    var sumX = 0.0, sumY = 0.0, count = 0;
    for (final (t, hx, hy) in _history) {
      if (t < _clock - window) continue;
      sumX += hx;
      sumY += hy;
      count++;
    }
    return (sumX / count, sumY / count);
  }

  (double, double) _streamLine(double x, double y, double dt) {
    final a = settings.streamLine;
    if (a <= 0) {
      _lineX = x;
      _lineY = y;
      return (x, y);
    }
    final k = _follow(dt, a * a * streamLineLag.inMicroseconds / 1e6);
    _lineX += (x - _lineX) * k;
    _lineY += (y - _lineY) * k;
    return (_lineX, _lineY);
  }

  /// Points from the last smoothed position to where the pen actually lifted.
  List<InkPoint> finish() {
    final raw = _raw;
    if (raw == null) return const [];
    final dx = raw.x - _lineX, dy = raw.y - _lineY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < .5) return const [];
    final count = math.min(maxCatchUp, (distance / catchUpSpacing).ceil());
    final points = [
      for (var i = 1; i <= count; i++)
        InkPoint(
          _lineX + dx * i / count,
          _lineY + dy * i / count,
          raw.pressure,
        ),
    ];
    _lineX = raw.x;
    _lineY = raw.y;
    return points;
  }

  Duration? get lastTime => _time;
}
