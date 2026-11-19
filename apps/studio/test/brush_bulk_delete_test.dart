import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting brushes together keeps one and picks another', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final all = {for (final b in c.brushes) b.id};
    c.selectBrush(c.brushes[1]);
    c.deleteBrushes({c.brushes[0].id, c.brushes[1].id});
    expect(c.brushes.length, all.length - 2);
    expect(c.brushes.any((b) => b.id == c.brush.id), isTrue);
    c.deleteBrushes({for (final b in c.brushes) b.id});
    expect(c.brushes, hasLength(1), reason: 'one always stays');
  });

  testWidgets('brushes are chosen in the library and deleted together after '
      'asking', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    c.setPanel(EditorPanel.brushes);
    await tester.pumpAndSettle();
    final count = c.brushes.length;
    final [first, second, ...] = c.brushes;
    await tester.tap(find.byKey(const ValueKey('brush-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('brush-menu-${first.id}')), findsNothing);
    for (final b in [first, second]) {
      await tester.ensureVisible(find.byKey(ValueKey('brush-${b.id}')));
      await tester.tap(find.byKey(ValueKey('brush-${b.id}')));
      await tester.pumpAndSettle();
    }
    expect(c.panel, EditorPanel.brushes, reason: 'choosing, not picking');
    await tester.tap(find.byKey(const ValueKey('brush-delete-chosen')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(c.brushes.length, count, reason: 'nothing without a yes');
    await tester.tap(find.byKey(const ValueKey('brush-delete-chosen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brush-delete-yes')));
    await tester.pumpAndSettle();
    expect(c.brushes.length, count - 2);
    expect(
      c.brushes.any((b) => b.id == first.id || b.id == second.id),
      isFalse,
    );
    expect(find.byKey(const ValueKey('brush-select')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brush-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brush-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('${c.brushes.length} selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('brush-select-done')));
    await tester.pumpAndSettle();
    expect(c.brushes.length, count - 2, reason: 'closed without deleting');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
