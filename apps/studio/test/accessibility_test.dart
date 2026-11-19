import 'package:atelier_studio/editor/canvas_navigation.dart';
import 'package:atelier_studio/editor/color_names.dart';
import 'package:atelier_studio/editor/drawing_surface.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/l10n/app_localizations_en.dart';
import 'package:atelier_studio/l10n/app_localizations_tr.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('colours get plain names, in both languages', () {
    final en = AppLocalizationsEn(), tr = AppLocalizationsTr();
    expect(colorName(en, 0xff000000), 'black');
    expect(colorName(en, 0xffffffff), 'white');
    expect(colorName(en, 0xff808080), 'grey');
    expect(colorName(en, 0xffff0000), 'red');
    expect(colorName(en, 0xff0000ff), 'blue');
    expect(colorName(en, 0xff003070), 'dark blue');
    expect(colorName(en, 0xffaad4ff), 'light blue');
    expect(colorName(en, 0xff7a4a20), 'brown');
    expect(colorName(en, 0xff20c040), 'green');
    expect(colorName(en, 0xffff9020), 'orange');
    expect(colorName(en, 0xff8a7f9c), 'greyish purple');
    expect(colorName(tr, 0xff003070), 'koyu mavi');
    expect(colorName(tr, 0xffff0000), 'kırmızı');
  });

  test('accessibility preferences are kept', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await c.initialize();
    c.setTextScale(3);
    c.setColorNames(true);
    c.setFeedbackSounds(true);
    c.setSingleTouch(true);
    c.setSingleTouchMode(SingleTouchMode.zoom);
    c.dispose();
    final again = StudioController(
      storage: MemoryStorage(),
      preferences: preferences,
    );
    await again.initialize();
    expect(again.textScale, 1.6);
    expect(
      (again.colorNames, again.feedbackSounds, again.singleTouch),
      (true, true, true),
    );
    expect(again.singleTouchMode, isNull, reason: 'a mode is for now only');
    again.dispose();
  });

  testWidgets('the single-touch pad moves, zooms and turns the canvas with '
      'one finger, without drawing; a picked swatch says its name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setSingleTouch(true);
    c.setColorNames(true);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final view = tester
        .widget<DrawingSurface>(find.byType(DrawingSurface))
        .transformation;
    Future<void> drag(Offset by) async {
      final g = await tester.startGesture(surface + const Offset(80, 0));
      for (var i = 1; i <= 5; i++) {
        await g.moveTo(surface + const Offset(80, 0) + by * (i / 5));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('single-move')));
    await tester.pump();
    await drag(const Offset(60, 30));
    expect(view.value.getTranslation().x, closeTo(60, 1));
    await tester.tap(find.byKey(const ValueKey('single-zoom')));
    await tester.pump();
    await drag(const Offset(0, -140));
    expect(CanvasNavigation.scaleOf(view.value), greaterThan(1.5));
    await tester.tap(find.byKey(const ValueKey('single-rotate')));
    await tester.pump();
    await drag(const Offset(0, 80));
    expect(CanvasNavigation.rotationOf(view.value).abs(), greaterThan(.3));
    expect(c.document.activeLayer.strokes, isEmpty, reason: 'no ink');
    await tester.tap(find.byKey(const ValueKey('single-fit')));
    await tester.pump();
    expect(view.value, Matrix4.identity());
    // Off again: a drag draws.
    await tester.tap(find.byKey(const ValueKey('single-rotate')));
    await tester.pump();
    final pen = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pen.down(surface);
    await pen.moveTo(surface + const Offset(40, 0));
    await pen.up();
    await tester.pumpAndSettle();
    expect(c.document.activeLayer.strokes, isNotEmpty);

    c.pickedColor(0xffff0000);
    await tester.pump();
    expect(find.text('red'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('color-name-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
