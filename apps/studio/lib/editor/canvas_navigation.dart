import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart' show Matrix4;

/// The view of the canvas in the workspace: pan, zoom and rotation as one
/// matrix in workspace pixels. The drawing itself never changes.
abstract final class CanvasNavigation {
  static const minScale = .25, maxScale = 8.0;

  /// Rotations this close to a quarter turn settle onto it.
  static const snapAngle = 5 * math.pi / 180;

  static double scaleOf(Matrix4 m) => m.getMaxScaleOnAxis();
  static double rotationOf(Matrix4 m) =>
      math.atan2(m.entry(1, 0), m.entry(0, 0));

  /// [start] moved so the point under [focal] follows [pan], scaled by
  /// [scale] (within [minScale]…[maxScale] overall) and turned by
  /// [rotation] around it.
  static Matrix4 around(
    Matrix4 start,
    Offset focal, {
    Offset pan = Offset.zero,
    double scale = 1,
    double rotation = 0,
  }) {
    final current = scaleOf(start);
    final s = (current * scale).clamp(minScale, maxScale) / current;
    final target = focal + pan;
    return Matrix4.identity()
      ..translateByDouble(target.dx, target.dy, 0, 1)
      ..rotateZ(rotation)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
      ..multiply(start);
  }

  /// Two fingers from [a0], [b0] to [a1], [b1]: they keep the same canvas
  /// points under them (pan, pinch and twist at once).
  static Matrix4 pinch(
    Matrix4 start,
    Offset a0,
    Offset b0,
    Offset a1,
    Offset b1,
  ) {
    final v0 = b0 - a0, v1 = b1 - a1;
    if (v0.distance < 1) return start;
    final mid0 = (a0 + b0) / 2, mid1 = (a1 + b1) / 2;
    return around(
      start,
      mid0,
      pan: mid1 - mid0,
      scale: v1.distance / v0.distance,
      rotation: v1.direction - v0.direction,
    );
  }

  /// [m] turned onto the nearest quarter turn around [center] when it is
  /// within [snapAngle] of it.
  static Matrix4 snapped(Matrix4 m, Offset center) {
    final angle = rotationOf(m);
    final quarter = (angle / (math.pi / 2)).round() * (math.pi / 2);
    final off = quarter - angle;
    if (off.abs() > snapAngle || off.abs() < 1e-9) return m;
    return around(m, center, rotation: off);
  }
}
