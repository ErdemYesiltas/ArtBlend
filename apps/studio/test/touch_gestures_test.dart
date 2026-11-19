import 'dart:io';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/editor/touch_gestures.dart';
import 'package:atelier_studio/main.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  test('taps, holds, scrubs and quick pinches are told apart', () {
    fakeAsync((async) {
      final seen = <TouchGesture>[];
      final t = TouchGestureTracker(onGesture: seen.add);
      void tap(int fingers, {int hold = 80}) {
        for (var i = 0; i < fingers; i++) {
          t.down(i, Offset(100.0 + i * 50, 100), ms(0));
        }
        async.elapse(ms(hold));
        for (var i = 0; i < fingers; i++) {
          t.up(i, ms(hold));
        }
      }

      tap(2);
      tap(3);
      tap(4);
      expect(seen, [
        TouchGesture.undo,
        TouchGesture.redo,
        TouchGesture.fullScreen,
      ]);
      seen.clear();
      // Held still: undo now and again every 120 ms until lifted.
      tap(2, hold: 800);
      expect(seen.length, inInclusiveRange(3, 4));
      expect(seen.toSet(), {TouchGesture.undo});
      seen.clear();
      // Moved: a pinch, not a tap.
      t.down(0, const Offset(100, 100), ms(0));
      t.down(1, const Offset(200, 100), ms(0));
      t.move(1, const Offset(300, 100), ms(60));
      t.up(0, ms(400));
      t.up(1, ms(400));
      expect(seen, isEmpty);
      // Three fingers rubbed sideways: clear once.
      for (var i = 0; i < 3; i++) {
        t.down(i, Offset(100.0 + i * 40, 300), ms(0));
      }
      var x = 0.0;
      for (final step in [60, -60, 60, -60, 60]) {
        x += step;
        for (var i = 0; i < 3; i++) {
          t.move(i, Offset(100.0 + i * 40 + x, 300), ms(100));
        }
      }
      for (var i = 0; i < 3; i++) {
        t.up(i, ms(300));
      }
      expect(seen, [TouchGesture.clearLayer]);
      seen.clear();
      // Three fingers swiped down are the system's (screenshot): nothing.
      for (var i = 0; i < 3; i++) {
        t.down(i, Offset(100.0 + i * 40, 100), ms(0));
      }
      for (var i = 0; i < 3; i++) {
        t.move(i, Offset(105.0 + i * 40, 230), ms(120));
      }
      for (var i = 0; i < 3; i++) {
        t.up(i, ms(150));
      }
      expect(seen, isEmpty);
      // Swiped up: the Copy & Paste menu.
      for (var i = 0; i < 3; i++) {
        t.down(i, Offset(100.0 + i * 40, 300), ms(0));
      }
      for (var i = 0; i < 3; i++) {
        t.move(i, Offset(105.0 + i * 40, 170), ms(120));
      }
      for (var i = 0; i < 3; i++) {
        t.up(i, ms(150));
      }
      expect(seen, [TouchGesture.copyPasteMenu]);
      seen.clear();
      // A fast pinch in fits the canvas.
      t.down(0, const Offset(100, 100), ms(0));
      t.down(1, const Offset(400, 100), ms(0));
      t.move(0, const Offset(220, 100), ms(150));
      t.move(1, const Offset(280, 100), ms(150));
      t.up(0, ms(200));
      t.up(1, ms(200));
      expect(seen, [TouchGesture.fitCanvas]);
      t.dispose();
    });
  });

  testWidgets('finger taps undo, redo and go full screen; a scrub clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.addLayer('Second');
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    Future<void> fingers(int count, {List<double> sweep = const []}) async {
      final touches = [
        for (var i = 0; i < count; i++)
          await tester.createGesture(
            kind: PointerDeviceKind.touch,
            pointer: 10 + i,
          ),
      ];
      for (final (i, g) in touches.indexed) {
        await g.down(center + Offset(i * 40.0, 0));
      }
      var x = 0.0;
      for (final step in sweep) {
        x += step;
        for (final (i, g) in touches.indexed) {
          await g.moveTo(center + Offset(i * 40.0 + x, 0));
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (final g in touches) {
        await g.up();
      }
      await tester.pump();
    }

    expect(c.document.layers, hasLength(2));
    await fingers(2);
    expect(c.document.layers, hasLength(1), reason: 'two fingers undo');
    await fingers(3);
    expect(c.document.layers, hasLength(2), reason: 'three fingers redo');

    c.beginStroke(const InkPoint(300, 300, .5), simulatePressure: true);
    c.appendPoint(const InkPoint(400, 320, .5));
    c.finishStroke();
    expect(c.document.activeLayer.strokes, isNotEmpty);
    await fingers(3, sweep: [60, -60, 60, -60, 60]);
    expect(c.document.activeLayer.strokes, isEmpty, reason: 'scrubbed clear');

    await fingers(4);
    await tester.pumpAndSettle();
    expect(c.fullScreen, isTrue);
    expect(find.text('Gallery'), findsNothing);
    // The canvas still fills the screen, under the one button left.
    expect(
      tester.getSize(find.byKey(const ValueKey('drawing-workspace'))).width,
      1100,
    );
    await tester.tap(find.byKey(const ValueKey('exit-full-screen')));
    await tester.pumpAndSettle();
    expect(find.text('Gallery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('keyboard shortcuts pick tools, sizes and colours, but not '
      'while typing', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final cmd = Platform.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    expect(c.tool, StudioTool.eraser);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(c.tool, StudioTool.brush);
    final size = c.size;
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    expect(c.size, closeTo(size + 6.35, .01));
    c.selectColor(0xffff0000);
    c.setPanel(null);
    c.selectColor(0xff00ff00);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    expect(c.color, 0xffff0000, reason: 'previous colour');
    await tester.sendKeyDownEvent(cmd);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(cmd);
    expect(c.document.layers, hasLength(2), reason: '⌘J duplicates');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(c.panel, EditorPanel.layers);

    // Typing a layer name: the letters go into the field.
    c.setPanel(EditorPanel.actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    // A blinking caret never settles: pump a fixed time.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).last, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(c.tool, StudioTool.brush, reason: 'E typed, not a shortcut');
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await c.save();
    // Let tooltips and the autosave delay run out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
