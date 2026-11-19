import 'package:atelier_studio/editor/quick_menu.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

Future<StudioController> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  // A vector brush: its strokes stay in the document to look at.
  c.selectBrush(c.brushes.firstWhere((b) => !b.isNative));
  await tester.pumpWidget(StudioApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

Future<void> drag(
  WidgetTester tester,
  Offset from, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  int pointer = 1,
}) async {
  final g = await tester.startGesture(from, kind: kind, pointer: pointer);
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(from + Offset(i * 12.0, 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gesture and interface preferences are kept; touch and hold opens '
      'one thing only', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await c.initialize();
    expect(c.quickMenuTrigger, QuickMenuTrigger.touchHold);
    c.setEyedropperHold(true);
    expect(c.quickMenuTrigger, QuickMenuTrigger.fourFingerTap);
    c.setFingerTool(FingerTool.eraser);
    c.setQuickShapeDelay(0);
    c.setUndoDelay(9);
    c.setTouchGestures(false);
    c.setSelectionMask(.5);
    c.setSidebarPosition(-1);
    c.setAutoHideInterface(true);
    c.dispose();
    final again = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await again.initialize();
    expect(again.eyedropperHold, isTrue);
    expect(again.fingerTool, FingerTool.eraser);
    expect(again.quickShapeDelay, 0);
    expect(again.undoDelay, 1.5);
    expect(again.touchGestures, isFalse);
    expect(again.selectionMask, .5);
    expect(again.sidebarPosition, 0);
    expect(again.autoHideInterface, isTrue);
    again.setQuickMenuTrigger(QuickMenuTrigger.touchHold);
    expect(again.eyedropperHold, isFalse);
    again.dispose();
  });

  testWidgets('a finger erases while the mouse (or pen) draws', (tester) async {
    final c = await open(tester);
    c.setFingerTool(FingerTool.eraser);
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    await drag(tester, surface, kind: PointerDeviceKind.mouse);
    await drag(tester, surface + const Offset(0, 40));
    final strokes = c.document.activeLayer.strokes;
    expect([for (final s in strokes) s.eraser], [false, true]);
    expect(c.tool, StudioTool.brush, reason: 'the tool itself stays');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('touch and hold picks a colour; with gestures off two fingers '
      'do not undo; the sidebar grip moves it', (tester) async {
    final c = await open(tester);
    c.setEyedropperHold(true);
    c.selectColor(0xff123456);
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final hold = await tester.startGesture(surface);
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.pickPoint, isNotNull);
    expect(c.quickMenuAt, isNull);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await hold.up();
    for (var i = 0; i < 20 && c.color == 0xff123456; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(c.color, c.document.background, reason: 'the paper');
    expect(c.document.activeLayer.strokes, isEmpty);

    c.setTouchGestures(false);
    await drag(tester, surface, kind: PointerDeviceKind.mouse);
    final a = await tester.startGesture(surface, pointer: 7);
    final b = await tester.startGesture(
      surface + const Offset(80, 0),
      pointer: 8,
    );
    await tester.pump(const Duration(milliseconds: 60));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(c.document.activeLayer.strokes, hasLength(1), reason: 'no undo');

    final before = c.sidebarPosition;
    await tester.drag(
      find.byKey(const ValueKey('sidebar-grip')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(c.sidebarPosition, lessThan(before));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
