import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the pressure curve, the cursor setting and each brush\'s size and '
      'opacity survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await c.initialize();
    expect(c.mapPressure(.5), closeTo(.5, .01), reason: 'straight at first');
    c.setPressureCurve(const [Offset.zero, Offset(.5, .8), Offset(1, 1)]);
    expect(c.mapPressure(.5), closeTo(.8, .01));
    expect(c.mapPressure(0), 0);
    expect(c.mapPressure(1), closeTo(1, .01));
    c.setBrushCursor(false);
    c.setCursor(const Offset(10, 10));
    expect(c.cursor, isNull, reason: 'no outline when it is off');

    final ink = c.brushes.first, other = c.brushes[1];
    c.selectBrush(ink);
    c.size = 40;
    c.opacity = .5;
    c.selectBrush(other);
    expect(c.size, other.size.clamp(1, 128), reason: 'its own size');
    c.size = 7;
    c.selectBrush(ink);
    expect((c.size, c.opacity), (40, .5));
    c.dispose();

    final reopened = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await reopened.initialize();
    expect(reopened.mapPressure(.5), closeTo(.8, .01));
    expect(reopened.brushCursor, isFalse);
    reopened.selectBrush(other);
    expect(reopened.size, 7);
    reopened.setPressureCurve(Adjustment.straight);
    expect(reopened.mapPressure(.3), closeTo(.3, .01));
    reopened.dispose();
  });

  testWidgets('pen pressure goes through the curve; the brush outline '
      'follows a hovering pointer and leaves with it', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setPressureCurve(const [Offset.zero, Offset(.5, .1), Offset(1, 1)]);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: surface);
    await mouse.moveTo(surface + const Offset(5, 0));
    await tester.pump();
    expect(c.cursor, isNotNull);
    await mouse.moveTo(const Offset(2, 2));
    await tester.pump();
    expect(c.cursor, isNull, reason: 'off the canvas');
    await mouse.removePointer();

    // A pen at half pressure (a test gesture has no pressure range).
    Future<void> send(PointerEvent e) => tester.sendEventToBinding(e);
    await send(
      PointerDownEvent(
        pointer: 9,
        kind: PointerDeviceKind.stylus,
        position: surface,
        pressure: .5,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i <= 8; i++) {
      await send(
        PointerMoveEvent(
          pointer: 9,
          kind: PointerDeviceKind.stylus,
          position: surface + Offset(i * 8.0, 0),
          delta: const Offset(8, 0),
          pressure: .5,
          pressureMin: 0,
          pressureMax: 1,
          timeStamp: Duration(milliseconds: 8 * i),
        ),
      );
      await tester.pump();
    }
    expect(c.cursor, isNotNull, reason: 'shown while drawing');
    await send(
      PointerUpEvent(
        pointer: 9,
        kind: PointerDeviceKind.stylus,
        position: surface + const Offset(64, 0),
        timeStamp: const Duration(milliseconds: 80),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.cursor, isNull, reason: 'gone when the pen lifts');
    final points = c.document.activeLayer.strokes.single.points;
    // Half pressure (the test pen's) comes out low on this curve.
    expect(points.map((p) => p.pressure), everyElement(closeTo(.1, .02)));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
