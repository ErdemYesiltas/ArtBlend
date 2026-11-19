import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// Field diagnostics for physical pen tests; compiled out unless the app is
/// built with `--dart-define=ARTBLEND_PEN_LOG=true`. One JSON line per stroke
/// is printed with the `ARTBLEND_PEN ` prefix (read it from `adb logcat`).
const penLogging = bool.fromEnvironment('ARTBLEND_PEN_LOG');

class PenProbe {
  PenProbe._();
  static final PenProbe instance = PenProbe._();

  int _stroke = 0;
  _StrokeLog? _current;
  final List<FrameTiming> _frames = [];
  bool _listening = false;

  void _onTimings(List<FrameTiming> timings) {
    if (_current != null) _frames.addAll(timings);
    _window.addAll(timings);
  }

  /// Every frame, not only those during strokes: panning, zooming and layer
  /// changes matter too. Summarised every few seconds while frames arrive.
  final List<FrameTiming> _window = [];
  Timer? _summary;
  String Function()? _scene;

  /// Starts the periodic `ARTBLEND_FRAMES` line; [scene] describes what is on
  /// screen (canvas size, layers, whether layers are flattened).
  void watchFrames(String Function() scene) {
    if (!penLogging || _summary != null) return;
    _scene = scene;
    if (!_listening) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _listening = true;
    }
    _summary = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_window.isEmpty) return;
      final totals = [for (final f in _window) f.totalSpan.inMicroseconds]
        ..sort();
      final rasters = [for (final f in _window) f.rasterDuration.inMicroseconds]
        ..sort();
      final worst = _window.reduce((a, b) => a.totalSpan > b.totalSpan ? a : b);
      debugPrint(
        'ARTBLEND_FRAMES ${jsonEncode({
          'frames': _window.length,
          'over16ms': totals.where((v) => v > 16667).length,
          'totalP95Ms': totals[(totals.length * .95).floor().clamp(0, totals.length - 1)] ~/ 1000,
          'rasterP95Ms': rasters[(rasters.length * .95).floor().clamp(0, rasters.length - 1)] ~/ 1000,
          'worst': [worst.buildDuration.inMilliseconds, worst.rasterDuration.inMilliseconds, worst.totalSpan.inMilliseconds],
          'scene': _scene?.call(),
        })}',
      );
      _window.clear();
    });
  }

  void begin(
    PointerEvent event, {
    required String brush,
    Map<String, double> smoothing = const {},
  }) {
    if (!penLogging) return;
    if (!_listening) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _listening = true;
    }
    _frames.clear();
    _current = _StrokeLog(++_stroke, event, brush, smoothing)..add(event);
  }

  final Stopwatch _clock = Stopwatch()..start();
  int? _lastUpMs;

  /// Every pointer down and up on the canvas with what it did, so a stroke
  /// that never started (event lost, wrong kind, rejected) is visible.
  void pointer(PointerEvent event, String result) {
    if (!penLogging) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastUpMs;
    if (event is PointerUpEvent || event is PointerCancelEvent) _lastUpMs = now;
    debugPrint(
      'ARTBLEND_PTR ${jsonEncode({'t': now, 'type': event is PointerDownEvent
          ? 'down'
          : event is PointerUpEvent
          ? 'up'
          : 'cancel', 'kind': event.kind.name, 'pointer': event.pointer, 'result': result, if (event is PointerDownEvent && last != null) 'sinceUpMs': now - last})}',
    );
  }

  void sample(PointerEvent event) {
    if (!penLogging) return;
    _current?.add(event);
  }

  /// A touch that landed while the stylus was drawing (palm, second finger).
  void foreignTouch(PointerEvent event) {
    if (!penLogging) return;
    final log = _current;
    if (log == null) return;
    log.foreign++;
    log.foreignKinds.add(event.kind.name);
  }

  /// [awaitNative]: a finished native stroke prints when its commit reports.
  void end(String outcome, {bool awaitNative = false}) {
    if (!penLogging) return;
    final log = _current;
    _current = null;
    if (log == null) return;
    log.outcome = outcome;
    log.frames = List.of(_frames);
    _frames.clear();
    if (awaitNative) {
      _pending.add(log);
    } else {
      _print(log, null);
    }
  }

  final List<_StrokeLog> _pending = [];

  /// Native commits complete in stroke order; each reports once.
  void nativeResult(Map<String, Object?>? native) {
    if (!penLogging || _pending.isEmpty) return;
    _print(_pending.removeAt(0), native);
  }

  void _print(_StrokeLog log, Map<String, Object?>? native) =>
      debugPrint('ARTBLEND_PEN ${jsonEncode(log.toJson(native))}');
}

class _StrokeLog {
  _StrokeLog(this.id, PointerEvent first, this.brush, this.smoothing)
    : kind = first.kind.name,
      device = first.device,
      pressureMin = first.pressureMin,
      pressureMax = first.pressureMax,
      start = first.timeStamp;
  final int id, device;
  final String kind, brush;
  final Map<String, double> smoothing;
  final double pressureMin, pressureMax;
  final Duration start;
  final List<double> pressures = [], tilts = [], orientations = [];
  final List<int> intervalsUs = [];
  Duration? _last;
  double distance = 0;
  Offset? _position;
  int foreign = 0, sameTime = 0;
  final Set<String> foreignKinds = {};
  String outcome = '';
  List<FrameTiming> frames = const [];

  void add(PointerEvent e) {
    final last = _last;
    if (last != null) {
      final dt = (e.timeStamp - last).inMicroseconds;
      if (dt <= 0) sameTime++;
      intervalsUs.add(dt);
    }
    _last = e.timeStamp;
    final p = _position;
    if (p != null) distance += (e.localPosition - p).distance;
    _position = e.localPosition;
    pressures.add(e.pressure);
    tilts.add(e.tilt);
    orientations.add(e.orientation);
  }

  static num _q(List<num> values, double q) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * q).floor())];
  }

  static double _r(num v, [int digits = 3]) =>
      double.parse(v.toStringAsFixed(digits));

  Map<String, Object?> toJson(Map<String, Object?>? native) {
    final duration = (_last ?? start) - start;
    final positive = intervalsUs.where((v) => v > 0).toList();
    final buildUs = [for (final f in frames) f.buildDuration.inMicroseconds];
    final rasterUs = [for (final f in frames) f.rasterDuration.inMicroseconds];
    final totalUs = [for (final f in frames) f.totalSpan.inMicroseconds];
    return {
      'stroke': id,
      'outcome': outcome,
      'kind': kind,
      'device': device,
      'brush': brush,
      'smoothing': smoothing,
      'samples': pressures.length,
      'ms': duration.inMilliseconds,
      'hz': positive.isEmpty
          ? 0
          : _r(1e6 / (positive.reduce((a, b) => a + b) / positive.length), 1),
      'dtUs': {
        'p50': _q(positive, .5),
        'p95': _q(positive, .95),
        'max': positive.isEmpty ? 0 : positive.reduce(math.max),
        'zero': sameTime,
      },
      'distancePx': _r(distance, 1),
      'pressureRange': [pressureMin, pressureMax],
      'pressure': {
        'min': _r(pressures.reduce(math.min)),
        'p50': _r(_q(pressures, .5)),
        'max': _r(pressures.reduce(math.max)),
        'distinct': pressures.map((p) => _r(p)).toSet().length,
      },
      'tiltDeg': {
        'min': _r(tilts.reduce(math.min) * 180 / math.pi, 1),
        'p50': _r(_q(tilts, .5) * 180 / math.pi, 1),
        'max': _r(tilts.reduce(math.max) * 180 / math.pi, 1),
      },
      'orientationDeg': {
        'min': _r(orientations.reduce(math.min) * 180 / math.pi, 1),
        'p50': _r(_q(orientations, .5) * 180 / math.pi, 1),
        'max': _r(orientations.reduce(math.max) * 180 / math.pi, 1),
      },
      'foreignTouches': foreign,
      if (foreignKinds.isNotEmpty) 'foreignKinds': foreignKinds.toList(),
      'frames': {
        'count': frames.length,
        'buildP95Us': _q(buildUs, .95),
        'rasterP95Us': _q(rasterUs, .95),
        'totalP95Us': _q(totalUs, .95),
        'over16ms': totalUs.where((v) => v > 16667).length,
        // Each slow frame as [build, raster, total] ms: tells UI-thread
        // work (rebuilds, encoding) from GPU work (texture uploads, toImage).
        'slow': [
          for (final f in frames)
            if (f.totalSpan.inMicroseconds > 16667)
              [
                f.buildDuration.inMilliseconds,
                f.rasterDuration.inMilliseconds,
                f.totalSpan.inMilliseconds,
              ],
        ],
      },
      'native': ?native,
    };
  }
}
