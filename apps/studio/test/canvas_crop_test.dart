import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/canvas_crop.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  const canvas = CanvasSize(1000, 800);
  final full = canvas.rect;

  test('handles resize their edges, snapping to the canvas lines', () {
    expect(cropHandleAt(full, const Offset(3, 2), 10), 0);
    expect(cropHandleAt(full, const Offset(500, 797), 10), 6);
    expect(cropHandleAt(full, const Offset(400, 300), 10), -1);
    expect(cropHandleAt(full, const Offset(-200, 300), 10), isNull);
    // The top-left corner dragged in; the right side dragged out.
    expect(
      dragCrop(full, 0, const Offset(120.4, 80.6), canvas, 10),
      const Rect.fromLTRB(120, 81, 1000, 800),
    );
    expect(
      dragCrop(full, 5, const Offset(300, 0), canvas, 10).right,
      1300,
      reason: 'a crop can grow the canvas',
    );
    // Near the middle: it snaps there.
    expect(dragCrop(full, 7, const Offset(496, 0), canvas, 10).left, 500);
    // Never smaller than the smallest canvas.
    expect(dragCrop(full, 1, const Offset(-990, 0), canvas, 10).width, 64);
  });

  test('moving keeps the size; an edge meets a line within reach', () {
    final r = dragCrop(
      const Rect.fromLTWH(100, 100, 300, 200),
      -1,
      const Offset(-95, 7),
      canvas,
      10,
    );
    expect(r, const Rect.fromLTWH(0, 107, 300, 200));
  });

  testWidgets('Crop & Resize: drag a corner, apply; canvas info shows it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(c.initialize);
    final before = c.document.dimensions;
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.setPanel(EditorPanel.actions);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crop & Resize'));
    await tester.tap(find.text('Crop & Resize'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crop-bar')), findsOneWidget);
    final board = find.byKey(const ValueKey('drawing-surface'));
    final factor = tester.getSize(board).width / before.width;
    final corner = tester.getTopLeft(board) + const Offset(2, 2);
    final drag = await tester.startGesture(corner);
    await drag.moveTo(corner + Offset(200 * factor, 100 * factor));
    await drag.up();
    await tester.pump();
    expect(c.canvasCrop!.rect.topLeft, const Offset(200, 100));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      for (var i = 0; i < 100 && c.document.dimensions == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(
      c.document.dimensions,
      CanvasSize(before.width - 200, before.height - 100),
    );
    c.setPanel(EditorPanel.actions);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Canvas info'));
    await tester.tap(find.text('Canvas info'));
    await tester.pumpAndSettle();
    expect(
      find.text('${before.width - 200} × ${before.height - 100} px'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
