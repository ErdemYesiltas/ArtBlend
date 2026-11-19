import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';

/// Crop & Resize's handles on a crop rectangle: corners from the top left
/// clockwise, then the sides from the top.
List<Offset> cropHandles(Rect r) => [
  r.topLeft,
  r.topRight,
  r.bottomRight,
  r.bottomLeft,
  r.topCenter,
  r.centerRight,
  r.bottomCenter,
  r.centerLeft,
];

/// The handle within [reach] of [point] (nearest first), -1 inside the
/// rectangle (to move it), null elsewhere.
int? cropHandleAt(Rect r, Offset point, double reach) {
  final handles = cropHandles(r);
  int? best;
  var distance = reach;
  for (var i = 0; i < handles.length; i++) {
    final d = (handles[i] - point).distance;
    if (d <= distance) {
      best = i;
      distance = d;
    }
  }
  return best ?? (r.contains(point) ? -1 : null);
}

/// [start] dragged by [delta] at [handle] (-1 moves it): edges within
/// [reach] of the canvas's edges or middle snap there; at least
/// [CanvasSize.minSide] and at most [CanvasSize.maxSide] a side.
Rect dragCrop(
  Rect start,
  int handle,
  Offset delta,
  CanvasSize canvas,
  double reach,
) {
  final xs = [0.0, canvas.width / 2, canvas.width.toDouble()];
  final ys = [0.0, canvas.height / 2, canvas.height.toDouble()];
  double snap(double v, List<double> lines) {
    for (final line in lines) {
      if ((v - line).abs() <= reach) return line;
    }
    return v.roundToDouble();
  }

  if (handle < 0) {
    var r = start.shift(delta);
    // The nearest edge or middle meets a line.
    double shiftFor(List<double> own, List<double> lines) {
      double? best;
      for (final o in own) {
        for (final l in lines) {
          final d = l - o;
          if (d.abs() <= reach && (best == null || d.abs() < best.abs())) {
            best = d;
          }
        }
      }
      return best ?? 0;
    }

    r = r.shift(
      Offset(
        shiftFor([r.left, r.center.dx, r.right], xs),
        shiftFor([r.top, r.center.dy, r.bottom], ys),
      ),
    );
    return Rect.fromLTWH(
      r.left.roundToDouble(),
      r.top.roundToDouble(),
      start.width,
      start.height,
    );
  }
  var left = start.left, top = start.top;
  var right = start.right, bottom = start.bottom;
  final moveLeft = handle == 0 || handle == 3 || handle == 7;
  final moveRight = handle == 1 || handle == 2 || handle == 5;
  final moveTop = handle == 0 || handle == 1 || handle == 4;
  final moveBottom = handle == 2 || handle == 3 || handle == 6;
  const min = CanvasSize.minSide + .0, max = CanvasSize.maxSide + .0;
  if (moveLeft) {
    left = snap(start.left + delta.dx, xs);
    left = left.clamp(right - max, right - min);
  }
  if (moveRight) {
    right = snap(start.right + delta.dx, xs);
    right = right.clamp(left + min, left + max);
  }
  if (moveTop) {
    top = snap(start.top + delta.dy, ys);
    top = top.clamp(bottom - max, bottom - min);
  }
  if (moveBottom) {
    bottom = snap(start.bottom + delta.dy, ys);
    bottom = bottom.clamp(top + min, top + max);
  }
  return Rect.fromLTRB(
    left,
    top,
    math.max(right, left + min),
    math.max(bottom, top + min),
  );
}
