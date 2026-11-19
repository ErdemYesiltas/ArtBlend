import 'dart:typed_data';
import 'dart:ui';

import 'package:atelier_studio/drawing/auto_select.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List mask(int w, int h, bool Function(int x, int y) inside) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x, y)) out[y * w + x] = 255;
    }
  }
  return out;
}

bool contains(List<Offset> polygon, Offset p) =>
    (Path()..addPolygon(polygon, true)).contains(p);

void main() {
  test('a square traces to its four corners', () {
    final loops = traceContours(
      mask(40, 40, (x, y) => x >= 10 && x < 30 && y >= 5 && y < 25),
      40,
      40,
    );
    expect(loops, hasLength(1));
    final (points, area) = loops.single;
    expect(area, 400);
    expect(points.toSet(), {
      const Offset(10, 5),
      const Offset(30, 5),
      const Offset(30, 25),
      const Offset(10, 25),
    });
  });

  test('a ring has an outline and a hole; islands come after', () {
    final loops = traceContours(
      mask(100, 100, (x, y) {
        final d = (Offset(x + .5, y + .5) - const Offset(50, 50)).distance;
        return (d < 40 && d > 20) || d < 8;
      }),
      100,
      100,
    );
    expect(loops, hasLength(3));
    expect(loops[0].$2, greaterThan(0), reason: 'outer ring first');
    expect(loops[1].$2, lessThan(0), reason: 'then the hole');
    expect(loops[2].$2, greaterThan(0), reason: 'then the island in it');
    expect(contains(loops[0].$1, const Offset(50, 15)), isTrue);
    expect(contains(loops[1].$1, const Offset(50, 35)), isTrue);
    expect(loops.every((l) => l.$1.length < 120), isTrue, reason: 'smoothed');
  });

  test('diagonal neighbours stay apart; specks are dropped', () {
    final loops = traceContours(
      mask(
        20,
        20,
        (x, y) =>
            (x >= 2 && x < 8 && y >= 2 && y < 8) ||
            (x >= 8 && x < 14 && y >= 8 && y < 14) ||
            (x == 18 && y == 18),
      ),
      20,
      20,
    );
    expect(loops.map((l) => l.$2), [36, 36]);
  });

  test('the worker selects by colour and threshold', () async {
    const w = 64, h = 64;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final v = x < 32 ? 100 : (x < 48 ? 130 : 250);
        rgba
          ..[i] = v
          ..[i + 1] = v
          ..[i + 2] = v
          ..[i + 3] = 255;
      }
    }
    final worker = await AutoSelectWorker.start(rgba, w, h);
    addTearDown(worker.dispose);
    final tight = await worker.select(5, 5, .05);
    expect(tight.single.$2, 32 * 64);
    final loose = await worker.select(5, 5, .2);
    expect(loose.single.$2, 48 * 64);
  });
}
