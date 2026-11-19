import 'dart:math' as math;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/stroke_stabilizer.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

const pen = Duration(microseconds: 4167);

List<InkPoint> run(SmoothingSettings settings, List<InkPoint> input) {
  final s = StrokeStabilizer(settings);
  final out = [s.start(input.first, Duration.zero)];
  for (var i = 1; i < input.length; i++) {
    out.add(s.add(input[i], pen * i));
  }
  return out;
}

/// A straight line along x at [speed] document px/s with seeded hand tremor.
List<InkPoint> shaky(double speed, {int count = 240, double tremor = 12}) {
  final random = math.Random(7);
  final step = speed * pen.inMicroseconds / 1e6;
  return [
    for (var i = 0; i < count; i++)
      InkPoint(i * step, 300 + (random.nextDouble() - .5) * tremor, i / count),
  ];
}

double wobble(List<InkPoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += (points[i].y - points[i - 1].y).abs();
  }
  return sum;
}

double maxLag(List<InkPoint> out, List<InkPoint> input) {
  var lag = 0.0;
  for (var i = 0; i < out.length; i++) {
    lag = math.max(lag, (input[i].x - out[i].x).abs());
  }
  return lag;
}

void main() {
  test('with every control at zero input passes through unchanged', () {
    final input = shaky(300, count: 30);
    const settings = SmoothingSettings();
    expect(settings.active, isFalse);
    final out = run(settings, input);
    for (var i = 0; i < input.length; i++) {
      expect(out[i].x, input[i].x);
      expect(out[i].y, input[i].y);
    }
  });

  test('StreamLine irons out tremor, keeps pressure live and lags less in '
      'the lower half of the slider', () {
    final input = shaky(300);
    final half = run(const SmoothingSettings(streamLine: .5), input);
    final full = run(const SmoothingSettings(streamLine: 1), input);
    expect(wobble(full), lessThan(wobble(input) * .15));
    expect(wobble(half), lessThan(wobble(input) * .5));
    expect(full.last.pressure, input.last.pressure);
    expect(maxLag(half, input), lessThan(maxLag(full, input) * .4));
  });

  test(
    'stabilization leaves slow drawing precise and smooths fast strokes',
    () {
      const settings = SmoothingSettings(stabilization: 1);
      final slow = shaky(60);
      final fast = shaky(1500);
      final slowOut = run(settings, slow);
      final fastOut = run(settings, fast);
      expect(maxLag(slowOut, slow), lessThan(2));
      final slowKept = wobble(slowOut) / wobble(slow);
      final fastKept = wobble(fastOut) / wobble(fast);
      expect(fastKept, lessThan(.3));
      expect(slowKept, greaterThan(fastKept * 2));
    },
  );

  test('motion filtering cuts wobble extremes at any speed and expression '
      'brings some back', () {
    final slow = shaky(60, tremor: 30);
    final fast = shaky(1500, tremor: 30);
    final filtered = run(const SmoothingSettings(motionFilter: .8), slow);
    final filteredFast = run(const SmoothingSettings(motionFilter: .8), fast);
    final expressive = run(
      const SmoothingSettings(motionFilter: .8, expression: 1),
      slow,
    );
    expect(wobble(filtered), lessThan(wobble(slow) * .5));
    expect(wobble(filteredFast), lessThan(wobble(fast) * .5));
    expect(wobble(expressive), greaterThan(wobble(filtered) * 1.2));
    expect(wobble(expressive), lessThan(wobble(slow)));
  });

  test('the curve depends on time, not on how often the device reports', () {
    InkPoint at(Duration t) => InkPoint(t.inMicroseconds / 1000, 0, .5);
    InkPoint endAfter(Duration step) {
      final s = StrokeStabilizer(
        const SmoothingSettings(streamLine: .8, stabilization: .5),
      );
      s.start(at(Duration.zero), Duration.zero);
      late InkPoint last;
      for (var t = step; t <= const Duration(milliseconds: 240); t += step) {
        last = s.add(at(t), t);
      }
      return last;
    }

    final stylus = endAfter(pen);
    final mouse = endAfter(const Duration(microseconds: 16667));
    expect(stylus.x, lessThan(240));
    expect((stylus.x - mouse.x).abs(), lessThan(10));
  });

  test('lifting the pen catches the line up to where it lifted', () {
    final s = StrokeStabilizer(
      const SmoothingSettings(streamLine: 1, stabilization: 1, motionFilter: 1),
    );
    s.start(const InkPoint(0, 0, .5), Duration.zero);
    final trailing = s.add(
      const InkPoint(100, 40, .8),
      const Duration(milliseconds: 20),
    );
    expect(trailing.x, lessThan(20));
    final tail = s.finish();
    expect(tail.last.x, 100);
    expect(tail.last.y, 40);
    expect(tail.last.pressure, .8);
    var previous = trailing;
    for (final point in tail) {
      final gap = math.sqrt(
        math.pow(point.x - previous.x, 2) + math.pow(point.y - previous.y, 2),
      );
      expect(gap, lessThanOrEqualTo(StrokeStabilizer.catchUpSpacing + 1e-9));
      previous = point;
    }
    expect(s.finish(), isEmpty);
  });

  test(
    'StreamLine is kept per brush and smoothing survives a restart',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final c = StudioController(
        storage: MemoryStorage(),
        preferences: preferences,
      );
      await c.initialize();
      final ink = c.brushes.first, other = c.brushes[1];
      c.selectBrush(ink);
      c.setStreamLine(.7);
      c.setSmoothing(stabilization: .4, motionFilter: .3, expression: .5);
      c.selectBrush(other);
      expect(c.streamLine, 0);
      expect(c.smoothing.stabilization, .4);
      c.dispose();

      final reopened = StudioController(
        storage: MemoryStorage(),
        preferences: preferences,
      );
      await reopened.initialize();
      reopened.selectBrush(ink);
      expect(reopened.smoothing.toJson(), {
        'streamLine': .7,
        'stabilization': .4,
        'motionFilter': .3,
        'expression': .5,
      });
      reopened.dispose();
    },
  );
}
