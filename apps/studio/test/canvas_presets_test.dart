import 'package:atelier_studio/domain/canvas_preset.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

CanvasPreset builtIn(String id) =>
    CanvasPreset.builtIn.firstWhere((p) => p.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('print sizes become pixels at their DPI; a unit change keeps the '
      'pixels', () {
    expect(builtIn('a4').size, const CanvasSize(2480, 3508));
    expect(builtIn('letter').size, const CanvasSize(2550, 3300));
    expect(builtIn('photo').size, const CanvasSize(1800, 1200));
    expect(builtIn('4k').size, const CanvasSize(3840, 2160));
    for (final p in CanvasPreset.builtIn) {
      expect(p.size.isValid, isTrue, reason: p.id);
    }
    final a4 = builtIn('a4');
    for (final unit in CanvasUnit.values) {
      final size = a4.inUnit(unit).size;
      expect(
        (size.width - 2480).abs(),
        lessThanOrEqualTo(1),
        reason: unit.name,
      );
      expect((size.height - 3508).abs(), lessThanOrEqualTo(1));
    }
    expect(CanvasPreset.fromJson(a4.toJson())!.size, a4.size);
    expect(CanvasPreset.fromJson({'id': 'x', 'unit': 'furlong'}), isNull);
    expect(a4.copyWith(dpi: 5).dpi, CanvasPreset.minDpi);
  });

  test('the user\'s presets are kept across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await c.initialize();
    const card = CanvasPreset(
      id: 'card',
      name: 'Card',
      width: 10,
      height: 15,
      unit: CanvasUnit.cm,
      dpi: 200,
    );
    c.saveCanvasPreset(card);
    c.saveCanvasPreset(card.copyWith(name: 'Postcard'));
    c.saveCanvasPreset(
      const CanvasPreset(id: 'tmp', name: 'Tmp', width: 100, height: 100),
    );
    c.deleteCanvasPreset('tmp');
    c.dispose();
    final reopened = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await reopened.initialize();
    expect([for (final p in reopened.canvasPresets) p.name], ['Postcard']);
    expect(reopened.canvasPresets.single.size, const CanvasSize(787, 1181));
    reopened.dispose();
  });

  testWidgets('a new drawing from a print preset gets its pixels and DPI; '
      'a preset of one\'s own is saved, edited and deleted', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New drawing'));
    await tester.pumpAndSettle();

    String pixels() =>
        tester.widget<Text>(find.byKey(const ValueKey('canvas-pixels'))).data!;
    await tester.tap(find.byKey(const ValueKey('preset-a4')));
    await tester.pumpAndSettle();
    expect(pixels(), '2480 × 3508 px');
    // In centimetres: the same pixels.
    await tester.tap(find.byKey(const ValueKey('canvas-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cm').last);
    await tester.pumpAndSettle();
    expect(pixels(), '2480 × 3508 px');
    // Too large for the canvas: no drawing from it.
    await tester.enterText(find.byKey(const ValueKey('canvas-height')), '50');
    await tester.pump();
    expect(pixels(), startsWith('Too large'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('canvas-create')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('canvas-height')), '20');
    await tester.ensureVisible(find.byKey(const ValueKey('canvas-swap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-swap')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const ValueKey('preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-save')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('preset-name')), 'Sq');
    await tester.tap(find.text('Confirm').last);
    await tester.pumpAndSettle();
    final mine = c.canvasPresets.single;
    expect(
      (mine.name, mine.unit, mine.width, mine.height, mine.dpi),
      ('Sq', CanvasUnit.cm, 20.0, 21.0, 300),
    );
    await tester.tap(find.byKey(ValueKey('preset-edit-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('canvas-dpi')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('canvas-dpi')), '150');
    await tester.ensureVisible(find.byKey(const ValueKey('preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm').last);
    await tester.pumpAndSettle();
    expect(c.canvasPresets.single.dpi, 150, reason: 'updated, not added');
    await tester.tap(find.byKey(ValueKey('preset-delete-${mine.id}')));
    await tester.pumpAndSettle();
    expect(c.canvasPresets, isEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('preset-letter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-letter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-create')));
    for (var i = 0; i < 50 && c.document.dpi != 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(c.document.dimensions, const CanvasSize(2550, 3300));
    expect(c.document.dpi, 300);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
