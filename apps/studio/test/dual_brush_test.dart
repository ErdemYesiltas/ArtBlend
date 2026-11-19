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
  final data = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  final rgba = data.buffer.asUint8List();
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 32) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a dual brush is saved with its second tip; a damaged one is '
      'refused', () {
    final dual = graphite.copyWith(
      dual: const DualStamp(blend: DualBlend.screen, size: .5, scatter: 1),
      dualTip: 'builtin:splatter',
    );
    final back = BrushPreset.fromJson(dual.toJson());
    expect(back.dual, dual.dual);
    expect(back.dualTip, 'builtin:splatter');
    expect(BrushPreset.fromJson(graphite.toJson()).dual, isNull);
    final broken = dual.toJson()..['dual'] = {'size': 9};
    expect(() => BrushPreset.fromJson(broken), throwsFormatException);
    final cleared = dual.copyWith(clearDual: true);
    expect((cleared.dual, cleared.dualTip), (null, null));
  });

  test('the second tip changes what the brush paints', () async {
    final round = initialBrushes.firstWhere(
      (b) => b.isStamp && b.tip == 'builtin:round-hard',
      orElse: () => graphite.copyWith(tip: 'builtin:round-hard'),
    );
    final single = await painted(await renderNativePreview(round));
    final masked = await painted(
      await renderNativePreview(
        round.copyWith(
          dual: const DualStamp(size: .6, spacing: .5),
          dualTip: 'builtin:splatter',
        ),
      ),
    );
    final cut = await painted(
      await renderNativePreview(
        round.copyWith(
          dual: const DualStamp(blend: DualBlend.subtract, size: 2),
          dualTip: 'builtin:round-hard',
        ),
      ),
    );
    expect(single, greaterThan(500));
    expect(masked, lessThan(single * .9), reason: 'only where both paint');
    expect(masked, greaterThan(0));
    expect(cut, lessThan(single * .2), reason: 'a bigger round cuts it out');
  });

  testWidgets('Brush Studio turns a brush into a dual brush', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('studio-section-dual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-dual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-dual-tip-bristle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-dual-blend-multiply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Darken').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-done')));
    await tester.pumpAndSettle();
    final saved = c.brushes.firstWhere((b) => b.id == graphite.id);
    expect(saved.dualTip, 'builtin:bristle');
    expect(saved.dual!.blend, DualBlend.darken);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
