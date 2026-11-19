import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

/// The drawing as shown, an open adjustment's preview included.
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

Future<StudioController> redCanvas([int color = 0xffff0000]) async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  c.selectColor(color);
  await c.fillActiveLayer();
  return c;
}

void expectNear(List<int> actual, List<int> expected, {int tolerance = 3}) {
  for (var i = 0; i < expected.length; i++) {
    expect(
      (actual[i] - expected[i]).abs() <= tolerance,
      isTrue,
      reason: '$actual ≉ $expected',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hue, saturation and brightness preview live, apply as one step, '
      'and undo', () async {
    final c = await redCanvas();
    addTearDown(c.dispose);
    expect(
      await c.startAdjustment(AdjustmentKind.hueSaturationBrightness),
      isTrue,
    );
    expectNear(at(c, await shown(c), 20, 20), [255, 0, 0, 255]);

    c.setAdjustmentValue('hue', .5 + 1 / 3);
    expectNear(at(c, await shown(c), 20, 20), [0, 255, 0, 255]);
    c.setAdjustmentValue('hue', .5);
    c.setAdjustmentValue('saturation', 0);
    expectNear(at(c, await shown(c), 20, 20), [54, 54, 54, 255]);
    c.setAdjustmentValue('saturation', .5);
    c.setAdjustmentValue('brightness', 0);
    expectNear(at(c, await shown(c), 20, 20), [0, 0, 0, 255]);

    final steps = c.canUndo;
    await c.applyAdjustment();
    expect(c.adjustment, isNull);
    expect(steps, isTrue);
    expectNear(at(c, await shown(c), 20, 20), [0, 0, 0, 255]);
    c.undo();
    await c.settleStroke();
    expectNear(at(c, await shown(c), 20, 20), [255, 0, 0, 255]);
  });

  test('gaussian blur softens an edge; a slide changes the amount', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectColor(0xff0000ff);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 200, 1024)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    await c.startAdjustment(AdjustmentKind.gaussianBlur);
    expect(at(c, await shown(c), 210, 500)[3], 0);
    c.beginAdjustmentChange();
    c.adjustAmountBy(.4);
    expect(c.adjustment!.adjustment['amount'], closeTo(.4, 1e-9));
    final blurred = await shown(c);
    expect(at(c, blurred, 210, 500)[3], greaterThan(20));
    expect(at(c, blurred, 190, 500)[3], lessThan(250));
    c.undoAdjustment();
    expect(c.adjustment!.adjustment['amount'], 0);
    c.cancelAdjustment();
    expect(at(c, await shown(c), 210, 500)[3], 0);
  });

  test('the adjustment stays inside the selection', () async {
    final c = await redCanvas();
    addTearDown(c.dispose);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    await c.startAdjustment(AdjustmentKind.hueSaturationBrightness);
    c.setAdjustmentValue('brightness', 0);
    await c.applyAdjustment();
    final pixels = await shown(c);
    expectNear(at(c, pixels, 50, 50), [0, 0, 0, 255]);
    expectNear(at(c, pixels, 300, 300), [255, 0, 0, 255]);
  });

  test('in pencil mode only painted places change; undo takes a stroke '
      'back', () async {
    final c = await redCanvas();
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.hueSaturationBrightness);
    c.setAdjustmentValue('brightness', 0);
    c.setAdjustmentPencil(true);
    expectNear(at(c, await shown(c), 500, 500), [255, 0, 0, 255]);
    c.setSize(40);
    c.setOpacity(1);
    expect(
      c.beginStroke(const InkPoint(400, 500, 1), simulatePressure: false),
      isTrue,
    );
    for (var x = 410; x <= 600; x += 10) {
      c.appendPoint(InkPoint(x.toDouble(), 500, 1));
    }
    c.finishStroke();
    expect(c.adjustment!.strokes, hasLength(1));
    var pixels = await shown(c);
    expectNear(at(c, pixels, 500, 500), [0, 0, 0, 255]);
    expectNear(at(c, pixels, 500, 800), [255, 0, 0, 255]);

    c.undo();
    expect(c.adjustment!.strokes, isEmpty);
    expect(c.adjustment!.pencil, isTrue);
    expectNear(at(c, await shown(c), 500, 500), [255, 0, 0, 255]);
  });

  test(
    'preview shows the original; reset and cancel leave the layer',
    () async {
      final c = await redCanvas();
      addTearDown(c.dispose);
      final before = c.document;
      await c.startAdjustment(AdjustmentKind.hueSaturationBrightness);
      c.setAdjustmentValue('brightness', 0);
      c.previewOriginal(true);
      expectNear(at(c, await shown(c), 20, 20), [255, 0, 0, 255]);
      c.previewOriginal(false);
      c.resetAdjustment();
      expect(c.adjustment!.adjustment.isNeutral, isTrue);
      await c.applyAdjustment();
      expect(identical(c.document, before), isTrue, reason: 'nothing to apply');
      await c.startAdjustment(AdjustmentKind.gaussianBlur);
      c.cancelAdjustment();
      expect(identical(c.document, before), isTrue);
    },
  );

  testWidgets('the magic wand opens adjustments; the bar applies one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
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
      await tester.tap(find.text('Gaussian Blur'));
      for (var i = 0; i < 20 && c.adjustment == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('adjustment-bar')), findsOneWidget);
    expect(
      find.byTooltip('Slide left or right on the canvas to change the amount.'),
      findsOneWidget,
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('adjustment-preview'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.adjustment!.showOriginal, isTrue, reason: 'held');
    await hold.up();
    await tester.pump();
    expect(c.adjustment!.showOriginal, isFalse);
    await tester.tap(find.byTooltip('Pencil'));
    await tester.pump();
    expect(c.adjustment!.pencil, isTrue);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(c.adjustment, isNull);
    expect(find.byKey(const ValueKey('adjustment-bar')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('a curve table follows its points without overshooting', () {
    expect(curveTable(Adjustment.straight), [for (var i = 0; i < 256; i++) i]);
    final inverted = curveTable(const [Offset(0, 1), Offset(1, 0)]);
    expect((inverted.first, inverted[128], inverted.last), (255, 127, 0));
    final s = curveTable(const [
      Offset.zero,
      Offset(.25, .1),
      Offset(.75, .9),
      Offset(1, 1),
    ]);
    for (var i = 1; i < 256; i++) {
      expect(s[i] >= s[i - 1], isTrue, reason: 'monotone at $i');
    }
    expect(s[64], closeTo(26, 2));
  });

  test(
    'curves map each channel after gamma; the histogram is counted',
    () async {
      final c = await redCanvas(0xff808080);
      addTearDown(c.dispose);
      await c.startAdjustment(AdjustmentKind.curves);
      final adjustment = c.adjustment!.adjustment;
      expect(adjustment.isNeutral, isTrue);
      c.setAdjustment(
        adjustment.withCurve(CurveChannel.red, const [
          Offset(0, 1),
          Offset(1, 0),
        ]),
      );
      expectNear(at(c, await shown(c), 20, 20), [127, 128, 128, 255]);
      c.setAdjustment(
        c.adjustment!.adjustment.withCurve(CurveChannel.gamma, const [
          Offset.zero,
          Offset(.5, 1),
          Offset(1, 1),
        ]),
      );
      expectNear(at(c, await shown(c), 20, 20), [0, 255, 255, 255]);
      for (var i = 0; i < 50 && c.adjustment!.histogram == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final bins = c.adjustment!.histogram!;
      expect(
        bins[(128 * 256) >> 8],
        c.document.dimensions.width * c.document.dimensions.height,
      );
    },
  );

  test('color balance shifts one tonal range', () async {
    final c = await redCanvas(0xff808080);
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.colorBalance);
    c.setAdjustmentValue('midtonesRed', 1);
    expectNear(at(c, await shown(c), 20, 20), [255, 128, 128, 255]);
    c.setAdjustmentValue('midtonesRed', .5);
    c.setAdjustmentValue('shadowsBlue', 1);
    expectNear(at(c, await shown(c), 20, 20), [
      128,
      128,
      128,
      255,
    ], tolerance: 4);
  });

  test('gradient map colours by lightness from its first preset', () async {
    final c = await redCanvas();
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.gradientMap);
    expect(
      c.adjustment!.adjustment.isNeutral,
      isFalse,
      reason: 'shows at once',
    );
    expectNear(at(c, await shown(c), 20, 20), [54, 54, 54, 255]);
    c.setAdjustment(
      c.adjustment!.adjustment.withGradient(GradientPreset.ocean.stops),
    );
    final expected = gradientColor(GradientPreset.ocean.stops, 54 / 255);
    expectNear(at(c, await shown(c), 20, 20), [
      (expected >> 16) & 0xff,
      (expected >> 8) & 0xff,
      expected & 0xff,
      255,
    ], tolerance: 4);
    c.setAdjustmentValue('amount', 0);
    expectNear(at(c, await shown(c), 20, 20), [255, 0, 0, 255]);
    c.resetAdjustment();
    expect(c.adjustment!.adjustment.gradient, GradientPreset.noir.stops);
    expect(c.adjustment!.adjustment['amount'], 1);
  });

  testWidgets('curves: a drag on the graph adds a point; gradient presets '
      'switch', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    Future<void> open(AdjustmentKind kind) async {
      await tester.runAsync(() async {
        await c.startAdjustment(kind);
      });
      await tester.pump();
    }

    await open(AdjustmentKind.curves);
    final graph = find.byKey(const ValueKey('curve-editor'));
    expect(graph, findsOneWidget);
    final box = tester.getRect(graph);
    await tester.dragFrom(box.center, const Offset(0, -40));
    await tester.pump();
    final gamma = c.adjustment!.adjustment.curve(CurveChannel.gamma);
    expect(gamma, hasLength(3));
    expect(gamma[1].dy, greaterThan(.6));
    await tester.tap(find.text('Red'));
    await tester.pump();
    await tester.dragFrom(box.center, const Offset(0, 40));
    await tester.pump();
    expect(c.adjustment!.adjustment.curve(CurveChannel.red), hasLength(3));
    expect(c.adjustment!.adjustment.curve(CurveChannel.gamma), hasLength(3));

    await open(AdjustmentKind.gradientMap);
    await tester.tap(find.byKey(const ValueKey('gradient-sunset')));
    await tester.pump();
    expect(c.adjustment!.adjustment.gradient, GradientPreset.sunset.stops);
    final strip = tester.getRect(find.byKey(const ValueKey('gradient-editor')));
    await tester.tapAt(Offset(strip.left + strip.width * .2, strip.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.adjustment!.adjustment.gradient, hasLength(5));

    await open(AdjustmentKind.colorBalance);
    await tester.ensureVisible(find.text('Shadows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shadows'));
    await tester.pump();
    expect(find.byKey(const ValueKey('adjustment-shadowsRed')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('motion blur streaks along the slide; perspective blur pulls '
      'towards its centre', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectColor(0xff0000ff);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 1024, 200)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    await c.startAdjustment(AdjustmentKind.motionBlur);
    c.beginAdjustmentChange();
    c.slideMotionBlur(const Offset(120, 0));
    expect(c.adjustment!.adjustment['angle'], 0);
    expect(c.adjustment!.adjustment['amount'], closeTo(120 / 256, 1e-9));
    expect(at(c, await shown(c), 500, 215)[3], 0, reason: 'sideways only');
    c.slideMotionBlur(const Offset(0, -120));
    expect(c.adjustment!.adjustment['angle'], closeTo(.5, 1e-9));
    expect(at(c, await shown(c), 500, 215)[3], greaterThan(20));
    c.undoAdjustment();
    expect(c.adjustment!.adjustment['amount'], 0);

    await c.startAdjustment(AdjustmentKind.perspectiveBlur);
    c.selectColor(0xff0000ff);
    c.moveAdjustmentCentre(const Offset(512, 100));
    expect(c.adjustment!.adjustment['x'], .5);
    expect(c.adjustment!.adjustment['y'], closeTo(100 / 1024, 1e-9));
    expect(c.adjustment!.adjustment.isNeutral, isTrue, reason: 'no amount');
    c.setAdjustmentValue('amount', 1);
    final pulled = await shown(c);
    // Each pixel gathers the way to the centre: just below the band some
    // of it, far below none.
    expect(at(c, pulled, 512, 240)[3], greaterThan(20));
    expect(at(c, pulled, 512, 900)[3], 0);
    c.setAdjustmentValue('directional', 1);
    c.setAdjustmentValue('angle', .25);
    expect(at(c, await shown(c), 512, 240)[3], greaterThan(20));
    c.setAdjustmentValue('angle', .75);
    expect(at(c, await shown(c), 512, 240)[3], 0, reason: 'gathers below');
  });
}
