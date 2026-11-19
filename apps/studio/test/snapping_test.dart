import 'dart:math' as math;

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/layer_transform.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  const canvas = Rect.fromLTWH(0, 0, 1000, 800);

  test('a box snaps its nearest edge or middle within reach, with guides', () {
    final (move, guides) = snapBounds(
      const Rect.fromLTWH(395, 100, 200, 100),
      [0, 500, 1000],
      [0, 400, 800],
      10,
      canvas,
    );
    // Its middle (495) is 5 from 500; nothing vertical is within 10.
    expect(move, const Offset(5, 0));
    expect(guides, [(const Offset(500, 0), const Offset(500, 800))]);
    final (far, none) = snapBounds(
      const Rect.fromLTWH(420, 300, 50, 50),
      [0, 500, 1000],
      [0, 400, 800],
      10,
      canvas,
    );
    expect(far, Offset.zero);
    expect(none, isEmpty);
    final (both, two) = snapBounds(
      const Rect.fromLTWH(-6, 793, 100, 10),
      [0, 500, 1000],
      [0, 400, 800],
      10,
      canvas,
    );
    expect(both, const Offset(6, 2), reason: "its middle is nearest");
    expect(two, hasLength(2));
  });

  test('magnetics lock moves to axes and angles to 15° steps', () {
    expect(lockToAxis(const Offset(100, 8)).dy, closeTo(0, 1e-9));
    expect(lockToAxis(const Offset(-6, 90)).dx, closeTo(0, 1e-9));
    final diagonal = lockToAxis(const Offset(100, 90));
    expect(diagonal.dx, closeTo(diagonal.dy, 1e-9));
    expect(snapAngle(.27), closeTo(math.pi / 12, 1e-9));
    expect(snapAngle(-.4), closeTo(-2 * math.pi / 12, 1e-9));
  });

  testWidgets('a slow drag snaps the layer to the canvas middle with a '
      'guide; a fast one does not; magnetics keep it on an axis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(() async {
      await c.initialize();
      c.setSelection(
        SelectionRegion.rectangle(const Rect.fromLTWH(100, 100, 200, 200)),
      );
      await c.fillActiveLayer();
      c.setSelection(null);
    });
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(c.beginTransform(), isTrue);
    c.setTransformSnapping(true);
    c.setSnapSettings(distance: 20);
    await tester.pumpAndSettle();
    final board = find.byKey(const ValueKey('drawing-surface'));
    final dims = c.document.dimensions;
    final factor = tester.getSize(board).width / dims.width;
    Offset screen(Offset doc) => tester.getTopLeft(board) + doc * factor;
    final middle = Offset(dims.width / 2, dims.height / 2);

    // Slow (no time between moves): the square's middle lands on the
    // canvas middle, a few pixels off.
    var drag = await tester.startGesture(screen(const Offset(200, 200)));
    await drag.moveTo(screen(const Offset(230, 210)));
    await drag.moveTo(screen(middle + Offset(5 / factor, -6 / factor)));
    await tester.pump();
    expect(c.snapGuides, hasLength(2));
    expect(c.transformDraft!.shownBounds.center.dx, closeTo(middle.dx, .01));
    expect(c.transformDraft!.shownBounds.center.dy, closeTo(middle.dy, .01));
    await drag.up();
    await tester.pump();
    expect(c.snapGuides, isEmpty);

    // Fast: no snapping.
    c.resetTransform();
    drag = await tester.startGesture(screen(const Offset(200, 200)));
    await drag.moveTo(
      screen(middle + Offset(5 / factor, -6 / factor)),
      timeStamp: const Duration(milliseconds: 5),
    );
    await tester.pump();
    expect(
      c.transformDraft!.shownBounds.center.dx,
      isNot(closeTo(middle.dx, .01)),
    );
    await drag.up();

    // Magnetics: a nearly flat drag stays flat.
    c.resetTransform();
    c.setTransformSnapping(false);
    c.setTransformMagnetics(true);
    drag = await tester.startGesture(screen(const Offset(200, 200)));
    await drag.moveTo(screen(const Offset(400, 215)));
    await tester.pump();
    expect(c.transformDraft!.translation.dy, closeTo(0, 1e-6));
    expect(c.transformDraft!.translation.dx, greaterThan(150));
    await drag.up();
    c.cancelTransform();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
