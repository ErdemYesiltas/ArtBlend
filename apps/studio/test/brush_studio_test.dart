import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final graphite = initialBrushes.firstWhere((b) => b.id == 'stamp-graphite');

  test('edited brushes are saved, reset, copied, renamed, moved and '
      'deleted; recent ones are remembered', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectBrush(graphite);
    final edited = graphite.copyWith(
      stamp: graphite.stamp!.copyWith(spacing: .5, followStroke: true),
      grain: 'builtin:canvas',
    );
    expect(
      BrushPreset.fromJson(edited.toJson()).stamp,
      edited.stamp,
      reason: 'settings survive saving',
    );
    c.saveBrush(edited);
    expect(c.brush.stamp!.spacing, .5, reason: 'the brush in use too');
    expect(
      c.isEdited(c.brushes.firstWhere((b) => b.id == graphite.id)),
      isTrue,
    );
    c.resetBrush(graphite.id);
    expect(
      c.brushes.firstWhere((b) => b.id == graphite.id).stamp,
      graphite.stamp,
    );
    expect(graphite.copyWith(clearGrain: true).grain, isNull);

    final count = c.brushes.length;
    c.duplicateBrush(graphite.id, 'Mine');
    final copy = c.brushes.firstWhere((b) => b.name == 'Mine');
    expect(c.brushes, hasLength(count + 1));
    expect(
      c.brushes.indexOf(copy),
      c.brushes.indexWhere((b) => b.id == graphite.id) + 1,
    );
    c.renameBrush(copy.id, 'Ours');
    c.moveBrush(c.brushes.indexWhere((b) => b.id == copy.id), 0);
    expect(c.brushes.first.name, 'Ours');
    c.selectBrush(c.brushes.first);
    c.deleteBrush(copy.id);
    expect(c.brushes.any((b) => b.id == copy.id), isFalse);
    expect(c.brush.id, isNot(copy.id), reason: 'the brush in use moved on');
    expect(c.recentBrushes.first, c.brush.id);
    expect(c.recentBrushes, contains(graphite.id));
  });

  test('the drawing pad draws the path drawn on it', () async {
    final image = await renderNativePreview(
      graphite,
      width: 200,
      height: 100,
      diameter: 12,
      path: [for (var x = 20.0; x <= 180; x += 4) (x, 30.0, .8)],
    );
    final data = await image.toByteData();
    int alpha(int x, int y) => data!.getUint8((y * 200 + x) * 4 + 3);
    expect(alpha(100, 30), greaterThan(0));
    expect(alpha(100, 80), 0);
  });

  testWidgets('Brush Studio: a typed spacing is saved on Done', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(c.initialize);
    c.setPanel(EditorPanel.brushes);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(ValueKey('brush-menu-${graphite.id}')),
    );
    await tester.tap(find.byKey(ValueKey('brush-menu-${graphite.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit in Brush Studio'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('brush-studio')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio-spacing-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('number-field')), '35');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-section-shape')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-follow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-done')));
    await tester.pumpAndSettle();
    final saved = c.brushes.firstWhere((b) => b.id == graphite.id).stamp!;
    expect(saved.spacing, closeTo(.35, 1e-9));
    expect(saved.followStroke, isTrue);
    expect(const StampSettings().copyWith(flow: .5).flow, .5);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
