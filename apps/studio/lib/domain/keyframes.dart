import 'dart:math' as math;

/// How a value travels from one keyframe to the next (Dreams' easing).
enum KeyEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut;

  /// Progress [t] (0–1) eased.
  double apply(double t) => switch (this) {
    linear => t,
    easeIn => t * t * t,
    easeOut => 1 - math.pow(1 - t, 3).toDouble(),
    easeInOut =>
      t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2,
  };

  /// The same easing run backwards (reversed keyframes).
  KeyEasing get reversed => switch (this) {
    easeIn => easeOut,
    easeOut => easeIn,
    _ => this,
  };
}

/// A value at a frame of its content (counted from the content's start),
/// and how it eases toward the next keyframe.
class Keyframe {
  const Keyframe(this.frame, this.value, {this.easing = KeyEasing.linear});
  final int frame;
  final double value;
  final KeyEasing easing;

  Keyframe copyWith({int? frame, double? value, KeyEasing? easing}) => Keyframe(
    frame ?? this.frame,
    value ?? this.value,
    easing: easing ?? this.easing,
  );

  Map<String, dynamic> toJson() => {
    'frame': frame,
    'value': value,
    if (easing != KeyEasing.linear) 'easing': easing.name,
  };

  static Keyframe? fromJson(Object? json) {
    if (json is! Map || json['frame'] is! num || json['value'] is! num) {
      return null;
    }
    return Keyframe(
      (json['frame'] as num).round(),
      (json['value'] as num).toDouble(),
      easing: KeyEasing.values.asNameMap()[json['easing']] ?? KeyEasing.linear,
    );
  }
}

/// What Move & Scale keyframes animate.
enum MoveParam { x, y, scale, rotation }

/// One parameter's keyframes in time order, one at a frame.
typedef Keys = List<Keyframe>;

/// The value of [keys] at [frame]: held before the first and after the
/// last, eased between them; null without keyframes.
double? keyValue(Keys keys, int frame) {
  if (keys.isEmpty) return null;
  if (frame <= keys.first.frame) return keys.first.value;
  if (frame >= keys.last.frame) return keys.last.value;
  for (var i = 1; i < keys.length; i++) {
    final b = keys[i];
    if (frame > b.frame) continue;
    final a = keys[i - 1];
    final t = (frame - a.frame) / (b.frame - a.frame);
    return a.value + (b.value - a.value) * a.easing.apply(t);
  }
  return keys.last.value;
}

/// [keys] with [key] at its frame (replacing one already there).
Keys withKey(Keys keys, Keyframe key) =>
    [...keys.where((k) => k.frame != key.frame), key]
      ..sort((a, b) => a.frame.compareTo(b.frame));

/// [keys] with the keyframe at [from] moved to [to] (one already at [to]
/// gives way).
Keys moveKey(Keys keys, int from, int to) {
  final key = keys.where((k) => k.frame == from).firstOrNull;
  if (key == null || from == to) return keys;
  return withKey([
    ...keys.where((k) => k.frame != from && k.frame != to),
  ], key.copyWith(frame: to));
}

/// [keys] mirrored over frames [from]–[to]: the same motion played
/// backwards, each stretch keeping its easing run the other way.
Keys reverseKeys(Keys keys, int from, int to) {
  if (keys.length < 2) {
    return [for (final k in keys) k.copyWith(frame: from + to - k.frame)];
  }
  final mirrored = [
    for (final k in keys.reversed) k.copyWith(frame: from + to - k.frame),
  ];
  // The stretch from new key i to i+1 is old stretch (n-2-i) backwards.
  final n = keys.length;
  return [
    for (final (i, k) in mirrored.indexed)
      k.copyWith(
        easing: i < n - 1 ? keys[n - 2 - i].easing.reversed : KeyEasing.linear,
      ),
  ];
}
