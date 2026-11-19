import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = SelectionRegion.rectangle(const Rect.fromLTWH(10, 10, 100, 100));
  final b = SelectionRegion.ellipse(const Rect.fromLTWH(300, 300, 200, 100));

  test('saved selections stay with the drawing and load back', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setSelection(a);
    c.saveSelection();
    c.saveSelection();
    c.setSelection(b);
    c.saveSelection();
    expect(c.document.savedSelections, [a, b], reason: 'each once');
    final back = ArtDocument.fromJson(c.document.toJson());
    expect(back.savedSelections.map((r) => r.id), [a.id, b.id]);
    expect(
      back.savedSelections.first.path.contains(const Offset(50, 50)),
      isTrue,
    );
    c.setSelection(null);
    c.loadSelection(0);
    expect(c.selection, same(a));
    c.deleteSavedSelection(0);
    expect(c.document.savedSelections, [b]);
    c.undo();
    expect(c.document.savedSelections, [a, b]);
  });

  test(
    'the previous selection comes back after Deselect or a new shape',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      c.setSelection(a);
      c.setSelection(null);
      c.restorePreviousSelection();
      expect(c.selection, same(a));
      c.selectTool(StudioTool.selection);
      c.setSelectionShape(SelectionShape.rectangle);
      c.beginSelection(const Offset(400, 400));
      c.appendSelection(const Offset(600, 600));
      c.finishSelection();
      expect(c.selection, isNot(same(a)));
      expect(c.previousSelection, same(a));
    },
  );

  test('Color Fill fills each shape drawn with the current colour', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectColor(0xff00a0ff);
    c.selectTool(StudioTool.selection);
    c.setSelectionShape(SelectionShape.rectangle);
    c.toggleSelectionColorFill();
    c.beginSelection(const Offset(100, 100));
    c.appendSelection(const Offset(300, 300));
    c.finishSelection();
    for (var i = 0; i < 100 && c.document.activeLayer.raster == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await c.settleStroke();
    expect(c.document.activeLayer.raster, isNotNull);
  });

  testWidgets('the selection bar copies the selection to a new layer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(() async {
      await c.initialize();
      c.selectColor(0xffff0000);
      await c.fillActiveLayer();
    });
    c.selectTool(StudioTool.selection);
    c.setSelection(a);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('selection-copy-paste')));
      for (var i = 0; i < 50 && c.document.layers.length == 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(c.document.layers, hasLength(2));
    expect(find.byKey(const ValueKey('selection-more')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
