import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/harmony.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('harmonies and presets', () {
    expect(harmonyHues(HarmonyMode.complementary, 30), [30, 210]);
    expect(harmonyHues(HarmonyMode.splitComplementary, 300), [300, 90, 150]);
    expect(harmonyHues(HarmonyMode.analogous, 10), [10, 340, 40]);
    expect(harmonyHues(HarmonyMode.triadic, 0), [0, 120, 240]);
    expect(harmonyHues(HarmonyMode.tetradic, 45), [45, 135, 225, 315]);
    expect(snapToPreset(44, .6, .9), (30, .5, 1));
    expect(snapToPreset(350, .1, .13), (0, 0, .25));
  });

  test('palettes: new, swatches added, replaced, moved, removed; copy, '
      'rename, default first, delete', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final id = c.createPalette('Mine');
    ColorPalette mine() => c.palettes.firstWhere((p) => p.id == id);
    expect(mine().colors, isEmpty);
    expect(ColorPalette.fromJson(mine().toJson()).colors, isEmpty);
    c.addSwatch(id, 0xffff0000);
    c.addSwatch(id, 0xff00ff00);
    c.addSwatch(id, 0xff0000ff, index: 0);
    expect(mine().colors, [0xff0000ff, 0xffff0000, 0xff00ff00]);
    c.replaceSwatch(id, 1, 0xffffffff);
    c.moveSwatch(id, 0, 2);
    expect(mine().colors, [0xffffffff, 0xff00ff00, 0xff0000ff]);
    c.removeSwatch(id, 1);
    expect(mine().colors, [0xffffffff, 0xff0000ff]);
    c.renamePalette(id, 'Ours');
    c.duplicatePalette(id, 'Ours copy');
    expect(
      c.palettes.map((p) => p.name),
      containsAllInOrder(['Ours', 'Ours copy']),
    );
    c.setDefaultPalette(id);
    expect(c.orderedPalettes.first.id, id);
    expect(c.libraryDirty, isTrue);
    c.deletePalette(id);
    expect(c.palettes.any((p) => p.id == id), isFalse);
    expect(c.defaultPaletteId, isNull);
  });

  testWidgets('colour views: classic square, harmony swatches; palette + '
      'and hold to delete', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(c.initialize);
    c.selectColor(0xffff0000);
    c.setPanel(EditorPanel.colors);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-classic')));
    await tester.pump();
    var hsv = HSVColor.fromColor(Color(c.color));
    expect(hsv.saturation, closeTo(.5, .02));
    expect(hsv.value, closeTo(.5, .02));

    c.selectColor(0xffff0000);
    await tester.tap(find.byTooltip('Harmony'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('harmony-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Triadic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('harmony-swatch-1')));
    await tester.pump();
    hsv = HSVColor.fromColor(Color(c.color));
    expect(hsv.hue, closeTo(120, 1));

    await tester.tap(find.byKey(const ValueKey('palette-new')));
    await tester.pumpAndSettle();
    final id = c.palettes.last.id;
    await tester.ensureVisible(find.byKey(ValueKey('swatch-add-$id')));
    await tester.tap(find.byKey(ValueKey('swatch-add-$id')));
    await tester.pumpAndSettle();
    expect(c.palettes.last.colors, [c.color]);
    await tester.longPress(find.byKey(ValueKey('swatch-$id-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(c.palettes.last.colors, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
