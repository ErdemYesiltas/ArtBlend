import 'dart:typed_data';
import 'dart:ui';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the smudge tool drags paint across the layer as one undo step, '
      'even with a vector brush selected', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    // A black square at 300–400.
    final black = Uint8List(64 * 64 * 4);
    for (var i = 3; i < black.length; i += 4) {
      black[i] = 255;
    }
    await c.addImageLayer(
      encodeRgbaPng(black, 64, 64),
      'Black',
      at: const Rect.fromLTWH(300, 300, 100, 100),
    );
    for (final id in ['ink', 'mypaint-charcoal']) {
      c.selectBrush(initialBrushes.firstWhere((b) => b.id == id));
      c.selectTool(StudioTool.smudge);
      c.setSize(40);
      c.setOpacity(.9);
      final before = c.document;
      var t = const Duration(seconds: 1);
      expect(
        c.beginStroke(
          const InkPoint(360, 350, 1),
          simulatePressure: false,
          time: t,
        ),
        isTrue,
      );
      for (var x = 362.0; x <= 520; x += 2) {
        t += const Duration(milliseconds: 8);
        c.appendPoint(InkPoint(x, 350, 1), time: t);
      }
      c.finishStroke();
      await c.settleStroke();
      final pixels = (await renderNativeBase(
        c.document.activeLayer,
        c.document.grid,
        c.rasters.images,
      )).rgba;
      expect(alphaAt(pixels, 440, 350), greaterThan(40), reason: '$id drags');
      expect(
        pixels[(350 * 1024 + 440) * 4],
        lessThan(80),
        reason: 'black, not paint',
      );
      expect(alphaAt(pixels, 440, 200), 0, reason: id);
      expect(c.document.activeLayer.strokes, isEmpty, reason: 'native pixels');
      c.undo();
      expect(c.document, same(before));
    }
  });
}
