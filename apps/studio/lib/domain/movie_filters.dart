import 'dart:ui';

import 'keyframes.dart';

/// One of a filter's settings (0–1), and where it starts.
class FilterParam {
  const FilterParam(this.id, [this.initial = 0]);
  final String id;
  final double initial;
}

/// Dreams' live filters: changed per content, keyframed, nothing baked.
enum FilterKind {
  opacity([FilterParam('amount', 1)]),
  gaussianBlur([FilterParam('amount')]),
  sharpen([FilterParam('amount')]),
  hsb([
    FilterParam('hue', .5),
    FilterParam('saturation', .5),
    FilterParam('brightness', .5),
  ]),
  noise([
    FilterParam('amount', .3),
    FilterParam('type'),
    FilterParam('scale', .4),
    FilterParam('octaves', .5),
    FilterParam('turbulence', .2),
    FilterParam('offsetX', .5),
    FilterParam('offsetY', .5),
    FilterParam('travelX', .5),
    FilterParam('travelY', .5),
  ]),
  lensBlur([
    FilterParam('radius'),
    FilterParam('brightness', .5),
    FilterParam('contrast', .5),
  ]);

  const FilterKind(this.params);
  final List<FilterParam> params;
}

/// A filter in a content's stack; its settings are keyframes of the
/// content named `<id>.<param>`.
class ContentFilter {
  const ContentFilter({required this.id, required this.kind});
  final String id;
  final FilterKind kind;

  String key(String param) => '$id.$param';

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name};

  static ContentFilter? fromJson(Object? json) =>
      json is Map &&
          json['id'] is String &&
          FilterKind.values.asNameMap()[json['kind']] != null
      ? ContentFilter(
          id: json['id'] as String,
          kind: FilterKind.values.asNameMap()[json['kind']]!,
        )
      : null;
}

/// Distort's corners (top left, top right, bottom right, bottom left),
/// each moved by a share of the content's width and height.
const distortCorners = 4;
String distortKey(int corner, String axis) => 'distort.$corner$axis';

/// Warp's nodes on a [cols] × [rows] grid, each moved by a share of the
/// content's width and height.
String warpKey(int col, int row, String axis) => 'warp.$col.$row$axis';

/// The value of keyframed parameter [id] at [local] (frames from the
/// content's start), or [fallback].
double keyedValue(
  Map<String, Keys> keys,
  String id,
  int local, [
  double fallback = 0,
]) => keyValue(keys[id] ?? const [], local) ?? fallback;

/// [keys] with [id] set to [value] at [local]: a parameter with at most
/// one keyframe just takes the value (it is still constant) unless
/// [keying]; otherwise it gets a keyframe at [local].
Map<String, Keys> setKeyed(
  Map<String, Keys> keys,
  String id,
  int local,
  double value, {
  required bool keying,
  KeyEasing easing = KeyEasing.linear,
}) {
  final current = keys[id] ?? const <Keyframe>[];
  if (!keying && current.length <= 1) {
    return {
      ...keys,
      id: [
        Keyframe(
          current.firstOrNull?.frame ?? 0,
          value,
          easing: current.firstOrNull?.easing ?? easing,
        ),
      ],
    };
  }
  final there = current.where((k) => k.frame == local).firstOrNull;
  return {
    ...keys,
    id: withKey(
      current,
      Keyframe(local, value, easing: there?.easing ?? easing),
    ),
  };
}

/// Where the point at [u], [v] (0–1 across the content) lands, in the
/// content's pixels, at [local]: Distort's corners spread over the whole,
/// then Warp's [cols] × [rows] nodes (none when [cols] is 0), each node's
/// move shared with the points around it.
Offset meshPoint(
  Map<String, Keys> keys,
  int local,
  Size size,
  double u,
  double v, {
  int cols = 0,
  int rows = 0,
}) {
  Offset corner(int i) => Offset(
    keyedValue(keys, distortKey(i, 'x'), local),
    keyedValue(keys, distortKey(i, 'y'), local),
  );
  final top = Offset.lerp(corner(0), corner(1), u)!;
  final bottom = Offset.lerp(corner(3), corner(2), u)!;
  var shift = Offset.lerp(top, bottom, v)!;
  if (cols >= 2 && rows >= 2) {
    Offset node(int c, int r) => Offset(
      keyedValue(keys, warpKey(c, r, 'x'), local),
      keyedValue(keys, warpKey(c, r, 'y'), local),
    );
    final gx = (u * (cols - 1)).clamp(0.0, cols - 1.0);
    final gy = (v * (rows - 1)).clamp(0.0, rows - 1.0);
    final c0 = gx.floor().clamp(0, cols - 2),
        r0 = gy.floor().clamp(0, rows - 2);
    final fx = gx - c0, fy = gy - r0;
    final upper = Offset.lerp(node(c0, r0), node(c0 + 1, r0), fx)!;
    final lower = Offset.lerp(node(c0, r0 + 1), node(c0 + 1, r0 + 1), fx)!;
    shift += Offset.lerp(upper, lower, fy)!;
  }
  return Offset((u + shift.dx) * size.width, (v + shift.dy) * size.height);
}
