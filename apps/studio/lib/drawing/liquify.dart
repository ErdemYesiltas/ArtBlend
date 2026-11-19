import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Procreate's Liquify brushes.
enum LiquifyMode {
  push,
  twirlRight,
  twirlLeft,
  pinch,
  expand,
  crystals,
  edge,
  reconstruct;

  /// Acts while held still, not only while moving.
  bool get continuous => this != push && this != edge;
}

/// Liquify on one layer: its pixels drawn across a grid whose points the
/// brushes move (each point keeps where it samples the layer from).
class LiquifySession {
  LiquifySession({
    required this.layerId,
    required this.source,
    this.cells = 128,
  }) : _rest = _grid(source.width, source.height, cells),
       positions = _grid(source.width, source.height, cells) {
    final n = cells;
    final indices = Uint16List(n * n * 6);
    var k = 0;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final a = j * (n + 1) + i, b = a + 1, c = a + n + 1, d = c + 1;
        indices.setAll(k, [a, b, c, b, d, c]);
        k += 6;
      }
    }
    _indices = indices;
  }

  final String layerId;

  /// The layer's own pixels at document size.
  final Image source;

  /// Grid cells per side; (cells + 1)² points, at most 65536.
  final int cells;

  /// Where each grid point is drawn now, x and y interleaved.
  final Float32List positions;

  /// Where each point samples the layer (and returns to on Reconstruct).
  final Float32List _rest;
  late final Uint16List _indices;

  LiquifyMode mode = LiquifyMode.push;

  /// 0–1: the brush from small to a quarter of the canvas.
  double size = .3;

  /// 0–1: how strongly each touch acts.
  double pressure = .5;

  /// 0–1: how wild Crystals are.
  double distortion = .5;

  /// 0–1: how far a push glides on after lifting.
  double momentum = 0;

  final List<Float32List> _history = [];
  bool get canUndo => _history.isNotEmpty;

  Offset? _last;
  double _force = 1;
  Offset _velocity = Offset.zero;
  final _random = math.Random(7);

  static Float32List _grid(int width, int height, int cells) {
    final out = Float32List((cells + 1) * (cells + 1) * 2);
    var k = 0;
    for (var j = 0; j <= cells; j++) {
      for (var i = 0; i <= cells; i++) {
        out[k++] = width * i / cells;
        out[k++] = height * j / cells;
      }
    }
    return out;
  }

  double get radius =>
      12 + size * .25 * math.max(source.width, source.height).toDouble();

  bool get isIdentity {
    for (var k = 0; k < positions.length; k++) {
      if ((positions[k] - _rest[k]).abs() > .01) return false;
    }
    return true;
  }

  /// A brush stroke begins at [point] (document pixels) with pen
  /// [force] 0–1.
  void begin(Offset point, double force) {
    _history.add(Float32List.fromList(positions));
    if (_history.length > 30) _history.removeAt(0);
    _last = point;
    _force = force;
    _velocity = Offset.zero;
    if (mode.continuous) _apply(point, Offset.zero);
  }

  void move(Offset point, double force) {
    final last = _last;
    if (last == null) return;
    _force = force;
    final delta = point - last;
    // Steps no longer than a fifth of the brush: fast strokes stay smooth.
    final steps = math.max(1, (delta.distance / (radius / 5)).ceil());
    for (var s = 1; s <= steps; s++) {
      _apply(last + delta * (s / steps), delta / steps.toDouble());
    }
    _velocity = delta;
    _last = point;
  }

  /// Held still: the continuous brushes keep acting (call per frame).
  void hold() {
    final last = _last;
    if (last != null && mode.continuous) _apply(last, Offset.zero);
  }

  /// The stroke ends; a push may glide on. Returns whether it glides.
  bool end() {
    _last = null;
    return mode == LiquifyMode.push && momentum > 0 && _velocity.distance > .5;
  }

  /// One frame of a push gliding after the stroke; false when it stops.
  bool glide(Offset at) {
    _velocity *= .55 + momentum * .4;
    if (_velocity.distance < .3) return false;
    _apply(at, _velocity);
    return true;
  }

  void undo() {
    if (_history.isEmpty) return;
    positions.setAll(0, _history.removeLast());
  }

  void reset() {
    _history.add(Float32List.fromList(positions));
    positions.setAll(0, _rest);
  }

  /// Moves every point [amount] (0–1) of the way back.
  void reconstructAll(double amount) {
    _history.add(Float32List.fromList(positions));
    for (var k = 0; k < positions.length; k++) {
      positions[k] += (_rest[k] - positions[k]) * amount;
    }
  }

  void _apply(Offset at, Offset delta) {
    final r = radius, r2 = r * r;
    final strength = pressure * (.35 + .65 * _force);
    final cx = at.dx, cy = at.dy;
    final along = delta.distance > 0 ? delta / delta.distance : Offset.zero;
    for (var k = 0; k < positions.length; k += 2) {
      final x = positions[k], y = positions[k + 1];
      final dx = x - cx, dy = y - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 >= r2) continue;
      final t = 1 - d2 / r2;
      final w = t * t * strength;
      switch (mode) {
        case LiquifyMode.push:
          positions[k] += delta.dx * w;
          positions[k + 1] += delta.dy * w;
        case LiquifyMode.twirlRight:
        case LiquifyMode.twirlLeft:
          final angle = (mode == LiquifyMode.twirlRight ? 1 : -1) * .12 * w;
          final c = math.cos(angle), s = math.sin(angle);
          positions[k] = cx + dx * c - dy * s;
          positions[k + 1] = cy + dx * s + dy * c;
        case LiquifyMode.pinch:
          positions[k] -= dx * .06 * w;
          positions[k + 1] -= dy * .06 * w;
        case LiquifyMode.expand:
          positions[k] += dx * .06 * w;
          positions[k + 1] += dy * .06 * w;
        case LiquifyMode.crystals:
          final jitter = r * .02 * (.3 + distortion) * w;
          positions[k] += (_random.nextDouble() * 2 - 1) * jitter;
          positions[k + 1] += (_random.nextDouble() * 2 - 1) * jitter;
        case LiquifyMode.edge:
          // Towards the stroke's line, across it: a crease along the path.
          if (along == Offset.zero) continue;
          final across = dx * -along.dy + dy * along.dx;
          positions[k] -= -along.dy * across * .15 * w;
          positions[k + 1] -= along.dx * across * .15 * w;
        case LiquifyMode.reconstruct:
          positions[k] += (_rest[k] - x) * .1 * w;
          positions[k + 1] += (_rest[k + 1] - y) * .1 * w;
      }
    }
  }

  /// Draws the layer across the grid as it is now.
  void paint(Canvas canvas) {
    final vertices = Vertices.raw(
      VertexMode.triangles,
      positions,
      textureCoordinates: _rest,
      indices: _indices,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..shader = ImageShader(
          source,
          TileMode.decal,
          TileMode.decal,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
          filterQuality: FilterQuality.medium,
        ),
    );
    vertices.dispose();
  }

  void dispose() => source.dispose();
}
