import 'package:atelier_studio/editor/quick_menu.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each button is found where it is drawn; the middle and far away '
      'are no button', () {
    const centre = Offset(300, 300);
    for (var i = 0; i < QuickMenuProfile.size; i++) {
      expect(quickMenuSlotAt(centre, quickMenuSlot(centre, i)), i);
    }
    expect(quickMenuSlot(centre, 0).dy, lessThan(centre.dy), reason: 'top');
    expect(quickMenuSlotAt(centre, centre + const Offset(5, 5)), isNull);
    expect(quickMenuSlotAt(centre, centre + const Offset(400, 0)), isNull);
  });

  test('profiles, their buttons and the trigger are kept across '
      'restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await c.initialize();
    expect(c.quickMenu.slots, QuickMenuProfile.initial.slots);
    c.assignQuickAction(2, QuickAction.addText);
    c.addQuickMenu('Inking');
    c.assignQuickAction(0, QuickAction.eraser);
    c.renameQuickMenu(c.quickMenuActive, 'Ink');
    c.addQuickMenu('Spare');
    c.deleteQuickMenu(c.quickMenuActive);
    c.setQuickMenuTrigger(QuickMenuTrigger.fourFingerTap);
    c.dispose();

    final reopened = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await reopened.initialize();
    expect(
      [for (final p in reopened.quickMenuProfiles) p.name],
      ['Default', 'Ink'],
    );
    expect(reopened.quickMenu.name, 'Default', reason: 'after a deletion');
    expect(reopened.quickMenu.slots[2], QuickAction.addText);
    reopened.nextQuickMenu();
    expect(reopened.quickMenu.slots[0], QuickAction.eraser);
    expect(reopened.quickMenuTrigger, QuickMenuTrigger.fourFingerTap);
    reopened.deleteQuickMenu(reopened.quickMenuActive);
    expect(
      () => reopened.deleteQuickMenu(reopened.quickMenuActive),
      returnsNormally,
    );
    expect(reopened.quickMenuProfiles, hasLength(1), reason: 'one stays');
    expect(QuickMenuProfile.fromJson({'id': 1}), isNull);
    reopened.dispose();
  });

  testWidgets('a finger held still opens the QuickMenu and slides onto a '
      'button; a right click opens it too; a button can be reassigned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final layers = c.document.layers.length;

    // A finger that moves draws; no menu.
    final stroke = await tester.startGesture(surface);
    for (var i = 1; i <= 6; i++) {
      await stroke.moveTo(surface + Offset(i * 12.0, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await stroke.up();
    await tester.pumpAndSettle();
    expect(c.quickMenuAt, isNull);
    final strokes = c.document.activeLayer.strokes.length;

    // Held still: the menu, and the dot it began is gone.
    final hold = await tester.startGesture(surface + const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.quickMenuAt, isNotNull);
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-slot-0')), findsOneWidget);
    final first = tester.getCenter(find.byKey(const ValueKey('quick-slot-0')));
    await hold.moveTo(first);
    await tester.pump();
    expect(c.quickMenuHover, 0);
    await hold.up();
    await tester.pumpAndSettle();
    expect(c.quickMenuAt, isNull);
    expect(c.document.layers.length, layers + 1, reason: 'New layer');
    expect(
      c.document.layers[c.document.layers.length - 2].strokes.length,
      strokes,
      reason: 'no dot from the hold',
    );

    // A right click; a long press on a button changes what it does.
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(surface);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-hub')), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('quick-slot-5')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quick-assign-addText')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('quick-assign-addText')));
    await tester.pumpAndSettle();
    expect(c.quickMenu.slots[5], QuickAction.addText);
    await tester.tap(find.byKey(const ValueKey('quick-slot-5')));
    await tester.pumpAndSettle();
    expect(c.textEditing, isNotNull, reason: 'the new action ran');
    expect(c.quickMenuAt, isNull);
    c.finishText();

    // A new profile gets buttons of its own, set from the profiles list.
    c.openQuickMenu(surface);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('quick-hub')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-profile-add')));
    await tester.pumpAndSettle();
    final added = c.quickMenuProfiles.last;
    expect(c.quickMenu.id, added.id);
    await tester.tap(find.byKey(ValueKey('quick-profile-${added.id}-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-assign-eraser')));
    await tester.pumpAndSettle();
    expect(c.quickMenuProfiles.last.slots[1], QuickAction.eraser);
    expect(c.quickMenuProfiles.first.slots[1], QuickAction.flipHorizontal);
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    c.closeQuickMenu();
    await tester.pumpAndSettle();

    // Tapping away closes it.
    c.openQuickMenu(surface);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 880));
    await tester.pumpAndSettle();
    expect(c.quickMenuAt, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
