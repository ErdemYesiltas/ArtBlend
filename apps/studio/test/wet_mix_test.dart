import 'dart:ui' as ui;

import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

final graphite = initialBrushes.firstWhere((b) => b.id == 'stamp-graphite');

Future<int> painted(ui.Image image) async {
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!.buffer.asUint8List();
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 32) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a wet brush is saved with its mix; a dry one says nothing of it', () {
    final wet = graphite.copyWith(
      stamp: graphite.stamp!.copyWith(dilution: .4, charge: .3, pull: .7),
    );
    final back = BrushPreset.fromJson(wet.toJson());
    expect(
      (back.stamp!.dilution, back.stamp!.charge, back.stamp!.pull),
      (.4, .3, .7),
    );
    expect(back.stamp!.wet, isTrue);
    expect(graphite.stamp!.wet, isFalse);
    expect(back.stamp == graphite.stamp, isFalse);
  });

  test('with little charge the paint runs out along the stroke', () async {
    final round = graphite.copyWith(
      tip: 'builtin:round-hard',
      clearGrain: true,
    );
    final dry = await painted(await renderNativePreview(round));
    final short = await painted(
      await renderNativePreview(
        round.copyWith(stamp: round.stamp!.copyWith(charge: .05)),
      ),
    );
    expect(short, lessThan(dry * .7));
    expect(short, greaterThan(0));
  });

  testWidgets('Brush Studio sets the wet mix', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('studio-section-wetMix')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-wet-pull-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('number-field')), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-done')));
    await tester.pumpAndSettle();
    final saved = c.brushes.firstWhere((b) => b.id == graphite.id).stamp!;
    expect(saved.pull, closeTo(.6, 1e-9));
    expect(const StampSettings().wet, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
