import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Future<Uint8List> shown(StudioController c) async {
  final recorder = ui.PictureRecorder();
  final doc = c.document.copyWith(backgroundHidden: true);
  paintDocument(
    ui.Canvas(recorder),
    doc,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
    overrides: c.nativeOverrides,
  );
  final image = await recorder.endRecording().toImage(
    doc.dimensions.width,
    doc.dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

List<int> at(StudioController c, Uint8List pixels, int x, int y) {
  final i = (y * c.document.dimensions.width + x) * 4;
  return pixels.sublist(i, i + 4);
}

/// [rects] filled with their colours, in order.
Future<StudioController> painted(List<(Rect, int)> rects) async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  for (final (rect, color) in rects) {
    c.selectColor(color);
    c.setSelection(SelectionRegion.rectangle(rect));
    await c.fillActiveLayer();
  }
  c.setSelection(null);
  return c;
}

const all = Rect.fromLTWH(0, 0, 1024, 1024);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sharpen steepens an edge', () async {
    final c = await painted([
      (all, 0xff646464),
      (const Rect.fromLTWH(512, 0, 512, 1024), 0xffa0a0a0),
    ]);
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.sharpen);
    c.setAdjustmentValue('amount', 1);
    final pixels = await shown(c);
    expect(at(c, pixels, 510, 500)[0], lessThan(95));
    expect(at(c, pixels, 513, 500)[0], greaterThan(170));
    expect(at(c, pixels, 100, 500)[0], closeTo(100, 2));
  });

  test(
    'noise varies the colours and keeps the shape; its kinds differ',
    () async {
      final c = await painted([
        (const Rect.fromLTWH(0, 0, 512, 1024), 0xff808080),
      ]);
      addTearDown(c.dispose);
      await c.startAdjustment(AdjustmentKind.noise);
      c.setAdjustmentValue('amount', 1);
      final clouds = await shown(c);
      final values = [
        for (var x = 0; x < 500; x += 7) at(c, clouds, x, 300)[0],
      ];
      expect(
        values.reduce(math.max) - values.reduce(math.min),
        greaterThan(40),
      );
      expect(at(c, clouds, 700, 300)[3], 0, reason: 'still transparent');
      c.setAdjustmentValue('type', 1);
      final ridges = await shown(c);
      expect(at(c, ridges, 100, 300), isNot(at(c, clouds, 100, 300)));
    },
  );

  test('bloom lets light spill past bright shapes', () async {
    final c = await painted([
      (all, 0xff000000),
      (const Rect.fromLTWH(462, 462, 100, 100), 0xffffffff),
    ]);
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.bloom);
    expect(at(c, await shown(c), 570, 512)[0], 0);
    c.setAdjustmentValue('amount', 1);
    expect(at(c, await shown(c), 570, 512)[0], greaterThan(20));
  });

  test('glitch diverge and chromatic displace split red from blue', () async {
    final c = await painted([
      (all, 0xff000000),
      (const Rect.fromLTWH(500, 0, 24, 1024), 0xffffffff),
    ]);
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.glitch);
    c.setAdjustmentValue('type', 1);
    c.setAdjustmentValue('amount', 1);
    // Red is taken from 20 px to the right, blue from 20 px to the left.
    var pixels = await shown(c);
    expect(at(c, pixels, 485, 500).take(3), [255, 0, 0]);
    expect(at(c, pixels, 538, 500).take(3), [0, 0, 255]);
    await c.startAdjustment(AdjustmentKind.chromaticAberration);
    expect(c.adjustment!.adjustment.centred, isTrue);
    c.setAdjustmentValue('type', 1);
    expect(c.adjustment!.adjustment.centred, isFalse);
    c.setAdjustmentValue('amount', 1);
    pixels = await shown(c);
    expect(at(c, pixels, 490, 500)[0], 255);
    expect(at(c, pixels, 490, 500)[2], 0);
  });

  test('newspaper halftone turns grey into black and white dots', () async {
    final c = await painted([(all, 0xff808080)]);
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.halftone);
    c.setAdjustmentValue('type', 1);
    c.setAdjustmentValue('amount', .5);
    final pixels = await shown(c);
    final values = {for (var x = 0; x < 200; x++) at(c, pixels, x, 300)[0]};
    expect(values.any((v) => v < 30), isTrue);
    expect(values.any((v) => v > 225), isTrue);
  });

  testWidgets('filters open from the magic wand with their kinds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adjustments'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Noise'));
      for (var i = 0; i < 20 && c.adjustment == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    await tester.tap(find.text('Ridges'));
    await tester.pump();
    expect(c.adjustment!.adjustment['type'], 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adjustment-octaves-value')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    // Tapping the value types one.
    await tester.tap(find.byKey(const ValueKey('adjustment-octaves-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('number-field')), '8');
    await tester.tap(find.text('Apply').last);
    await tester.pumpAndSettle();
    expect(c.adjustment!.adjustment['octaves'], 1);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
