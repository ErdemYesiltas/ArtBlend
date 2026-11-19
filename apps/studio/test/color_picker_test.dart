import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

HSVColor hsv(int argb) => HSVColor.fromColor(Color(argb));

void main() {
  testWidgets('the disc picks hue on its ring and saturation × brightness '
      'in its square; sliders set HSB and RGB; strokes remember colours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.selectColor(0xff3366cc);
    c.setPanel(EditorPanel.colors);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();

    final disc = find.byKey(const ValueKey('color-disc'));
    final box = tester.getRect(disc);
    // Hue 0° sits on the right of the ring, 90° at the bottom.
    await tester.tapAt(Offset(box.right - 6, box.center.dy));
    await tester.pump();
    expect(hsv(c.color).hue, closeTo(0, 2));
    await tester.tapAt(Offset(box.center.dx, box.bottom - 6));
    await tester.pump();
    expect(hsv(c.color).hue, closeTo(90, 2));
    // The square's top-right corner: full saturation and brightness.
    final half = box.width / 2 * (1 - .28) / 1.4142 * .94;
    await tester.tapAt(box.center + Offset(half - 1, -half + 1));
    await tester.pump();
    expect(hsv(c.color).saturation, greaterThan(.97));
    expect(hsv(c.color).value, greaterThan(.97));
    // Bottom-left is black, and the ring keeps its hue.
    await tester.tapAt(box.center + Offset(-half + 1, half - 1));
    await tester.pump();
    expect(hsv(c.color).value, lessThan(.03));
    await tester.tapAt(box.center + Offset(half - 1, -half + 1));
    await tester.pump();
    expect(hsv(c.color).hue, closeTo(90, 2), reason: 'hue survives black');

    await tester.tap(find.byTooltip('Values'));
    await tester.pumpAndSettle();
    final red = tester.getRect(find.byKey(const ValueKey('color-slider-red')));
    await tester.tapAt(Offset(red.left + 1, red.center.dy));
    await tester.pump();
    expect(Color(c.color).r, lessThan(.01));
    final hue = tester.getRect(find.byKey(const ValueKey('color-slider-hue')));
    await tester.tapAt(Offset(hue.left + hue.width * 2 / 3, hue.center.dy));
    await tester.pump();
    expect(hsv(c.color).hue, closeTo(240, 3));

    c.setPanel(null);
    for (final color in [0xffaa0000, 0xff00aa00, 0xffaa0000]) {
      c.selectColor(color);
      c.beginStroke(const InkPoint(100, 100, .5), simulatePressure: true);
      c.finishStroke();
    }
    expect(c.recentColors.take(2), [0xffaa0000, 0xff00aa00]);
    c.setPanel(EditorPanel.colors);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recent-color-1')));
    await tester.pump();
    expect(c.color, 0xff00aa00);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
