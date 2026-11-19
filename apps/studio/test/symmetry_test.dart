import 'dart:typed_data';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/symmetry.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

void stroke(StudioController c, double x, double y1, double y2) {
  var t = const Duration(seconds: 1);
  expect(
    c.beginStroke(InkPoint(x, y1, .9), simulatePressure: false, time: t),
    isTrue,
  );
  for (var y = y1 + 4; y <= y2; y += 4) {
    t += const Duration(milliseconds: 8);
    c.appendPoint(InkPoint(x, y, .9), time: t);
  }
  c.finishStroke();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native strokes draw their mirror in the same undo step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    for (final id in ['mypaint-charcoal', 'stamp-gouache']) {
      c.selectBrush(initialBrushes.firstWhere((b) => b.id == id));
      c.setSymmetry(SymmetryKind.vertical);
      c.addLayer(id);
      final before = c.document;
      stroke(c, 200, 300, 700);
      await c.settleStroke();
      final pixels = (await renderNativeBase(
        c.document.activeLayer,
        c.document.grid,
        c.rasters.images,
      )).rgba;
      expect(alphaAt(pixels, 200, 500), greaterThan(100), reason: id);
      expect(alphaAt(pixels, 824, 500), greaterThan(100), reason: '$id mirror');
      expect(alphaAt(pixels, 512, 500), 0, reason: id);
      c.undo();
      expect(c.document, same(before));
      // Off again: a single stroke.
      c.setSymmetry(SymmetryKind.off);
      stroke(c, 200, 300, 700);
      await c.settleStroke();
      final single = (await renderNativeBase(
        c.document.activeLayer,
        c.document.grid,
        c.rasters.images,
      )).rgba;
      expect(alphaAt(single, 824, 500), 0, reason: id);
    }
  });

  test('vector strokes get their copies as one undo step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setSymmetry(SymmetryKind.quadrant);
    stroke(c, 100, 100, 200);
    final strokes = c.document.activeLayer.strokes;
    expect(strokes, hasLength(4));
    final starts = {
      for (final s in strokes)
        (s.points.first.x.round(), s.points.first.y.round()),
    };
    expect(starts, {(100, 100), (924, 100), (100, 924), (924, 924)});
    c.undo();
    expect(c.document.activeLayer.strokes, isEmpty);
    expect(symmetryMatrices(SymmetryKind.radial), hasLength(8));
  });
}
