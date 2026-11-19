import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'flood_fill.dart';

/// One outline of a pixel area: its points and signed area (positive
/// around what is inside, negative around a hole).
typedef Contour = (List<Offset>, double);

/// The outlines of the non-zero pixels of [mask] ([width] × [height]),
/// largest first, along pixel edges then simplified to within
/// [tolerance] pixels, each at most [maxPoints] points. Areas under
/// [minArea] square pixels are dropped.
List<Contour> traceContours(
  Uint8List mask,
  int width,
  int height, {
  double tolerance = .7,
  int maxPoints = 4096,
  double minArea = 4,
}) {
  bool inside(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] != 0;
  final stride = width + 1;
  // Directed pixel edges, inside on their right (clockwise on screen):
  // start vertex → end vertices.
  final next = <int, List<int>>{};
  void edge(int x0, int y0, int x1, int y1) =>
      (next[y0 * stride + x0] ??= []).add(y1 * stride + x1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (mask[y * width + x] == 0) continue;
      if (!inside(x, y - 1)) edge(x, y, x + 1, y);
      if (!inside(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
      if (!inside(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
      if (!inside(x - 1, y)) edge(x, y + 1, x, y);
    }
  }
  final loops = <Contour>[];
  Offset at(int v) => Offset((v % stride).toDouble(), (v ~/ stride).toDouble());
  while (next.isNotEmpty) {
    final start = next.keys.first;
    final points = <Offset>[];
    var from = start, previous = start;
    while (true) {
      final outs = next[from];
      if (outs == null || outs.isEmpty) break;
      var pick = 0;
      if (outs.length > 1 && previous != from) {
        // Where two areas meet at a corner, turn right: keep to this area.
        final d = at(from) - at(previous);
        for (var i = 0; i < outs.length; i++) {
          final o = at(outs[i]) - at(from);
          if (d.dx * o.dy - d.dy * o.dx > 0) pick = i;
        }
      }
      final to = outs.removeAt(pick);
      if (outs.isEmpty) next.remove(from);
      points.add(at(from));
      previous = from;
      from = to;
      if (from == start && (next[start]?.isEmpty ?? true)) break;
      if (from == start) break;
    }
    if (points.length < 4) continue;
    final area = _area(points);
    if (area.abs() < minArea) continue;
    var tight = tolerance;
    var simple = _simplifyClosed(points, tight);
    while (simple.length > maxPoints) {
      tight *= 1.6;
      simple = _simplifyClosed(points, tight);
    }
    if (simple.length >= 3) loops.add((simple, area));
  }
  loops.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
  return loops;
}

double _area(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s / 2;
}

/// Ramer–Douglas–Peucker for a closed loop, split at its farthest points.
List<Offset> _simplifyClosed(List<Offset> loop, double tolerance) {
  var far = 0;
  var best = 0.0;
  for (var i = 1; i < loop.length; i++) {
    final d = (loop[i] - loop[0]).distance;
    if (d > best) {
      best = d;
      far = i;
    }
  }
  final a = _simplify(loop.sublist(0, far + 1), tolerance);
  final b = _simplify([...loop.sublist(far), loop[0]], tolerance);
  return [...a.sublist(0, a.length - 1), ...b.sublist(0, b.length - 1)];
}

List<Offset> _simplify(List<Offset> points, double tolerance) {
  if (points.length < 3) return points;
  final keep = List<bool>.filled(points.length, false)
    ..[0] = true
    ..[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    var worst = 0.0;
    var index = -1;
    final a = points[first], b = points[last];
    final d = b - a;
    final length = d.distance;
    for (var i = first + 1; i < last; i++) {
      final p = points[i] - a;
      final dist = length < 1e-9
          ? p.distance
          : (p.dx * d.dy - p.dy * d.dx).abs() / length;
      if (dist > worst) {
        worst = dist;
        index = i;
      }
    }
    if (index >= 0 && worst > tolerance) {
      keep[index] = true;
      stack
        ..add((first, index))
        ..add((index, last));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

/// The contours of the area ColorDrop would fill from ([x], [y]).
List<Contour> autoSelectArea(
  Uint8List rgba,
  int width,
  int height,
  int x,
  int y,
  double threshold,
) {
  final area = floodFill(
    rgba,
    width,
    height,
    x,
    y,
    threshold: threshold,
    grow: 0,
  );
  return traceContours(area, width, height);
}

/// The contours of where straight RGBA [rgba] has any pixels.
List<Contour> contentContours(Uint8List rgba, int width, int height) {
  final mask = Uint8List(width * height);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = rgba[i * 4 + 3] > 8 ? 255 : 0;
  }
  return traceContours(mask, width, height);
}

/// [contentContours] on a background isolate.
Future<List<Contour>> contentContoursOffThread(
  Uint8List rgba,
  int width,
  int height,
) => Isolate.run(() => contentContours(rgba, width, height));

/// Automatic selection on a background isolate that keeps one image, so
/// dragging the threshold re-selects without sending it again.
class AutoSelectWorker {
  AutoSelectWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final Map<int, Completer<List<Contour>>> _waiting = {};
  int _next = 0;

  static Future<AutoSelectWorker> start(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_serve, (
      replies.sendPort,
      TransferableTypedData.fromList([rgba]),
      width,
      height,
    ));
    final ready = Completer<SendPort>();
    late final AutoSelectWorker worker;
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final (int id, List<(Float32List, double)> loops) =
          message as (int, List<(Float32List, double)>);
      worker._waiting.remove(id)?.complete([
        for (final (flat, area) in loops)
          (
            [
              for (var i = 0; i < flat.length; i += 2)
                Offset(flat[i], flat[i + 1]),
            ],
            area,
          ),
      ]);
    });
    worker = AutoSelectWorker._(isolate, await ready.future, replies);
    return worker;
  }

  Future<List<Contour>> select(int x, int y, double threshold) {
    final id = _next++;
    final done = Completer<List<Contour>>();
    _waiting[id] = done;
    _send.send((id, x, y, threshold));
    return done.future;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final waiting in _waiting.values) {
      waiting.completeError(StateError('Automatic selection stopped'));
    }
    _waiting.clear();
  }
}

void _serve((SendPort, TransferableTypedData, int, int) start) {
  final (reply, data, width, height) = start;
  final rgba = data.materialize().asUint8List();
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) {
    final (int id, int x, int y, double threshold) =
        message as (int, int, int, double);
    final loops = autoSelectArea(rgba, width, height, x, y, threshold);
    reply.send((
      id,
      [
        for (final (points, area) in loops)
          (
            Float32List.fromList([
              for (final p in points) ...[p.dx, p.dy],
            ]),
            area,
          ),
      ],
    ));
  });
}
