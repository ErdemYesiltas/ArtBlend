import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/layer_transform.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void expectPoint(Offset actual, Offset expected) {
  expect((actual - expected).distance, lessThan(1e-6), reason: '$actual');
}

Future<Uint8List> shown(StudioController c) async {
  final recorder = ui.PictureRecorder();
  final doc = c.document.copyWith(backgroundHidden: true);
  paintDocument(
    ui.Canvas(recorder),
    doc,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
    transform: c.transformDraft,
    transformLayerId: c.transformLayerId,
    transformSelection: c.transformSelection,
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

/// A 200×200 square at (100, 100): red on the left, blue on the right.
Future<StudioController> squares() async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  for (final (rect, color) in [
    (const Rect.fromLTWH(100, 100, 100, 200), 0xffff0000),
    (const Rect.fromLTWH(200, 100, 100, 200), 0xff0000ff),
  ]) {
    c.selectColor(color);
    c.setSelection(SelectionRegion.rectangle(rect));
    await c.fillActiveLayer();
  }
  c.setSelection(null);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const box = Rect.fromLTWH(0, 0, 100, 50);

  test('freeform stretches each axis; uniform keeps proportions; the '
      'opposite corner or side stays', () {
    const t = LayerTransform(bounds: box);
    final free = t.resizedByCorner(2, const Offset(200, 150), uniform: false);
    expect((free.scaleX, free.scaleY), (2, 3));
    expectPoint(free.map(box.topLeft), box.topLeft);
    final even = t.resizedByCorner(2, const Offset(200, 150), uniform: true);
    expect(even.scaleX, closeTo(even.scaleY, 1e-9));
    expectPoint(even.map(box.topLeft), box.topLeft);
    final side = t.resizedBySide(1, const Offset(300, 25));
    expect((side.scaleX, side.scaleY), (3, 1));
    expectPoint(side.map(box.centerLeft), box.centerLeft);
    final flipped = t.flipped(horizontal: true);
    expectPoint(flipped.map(box.topLeft), box.topRight);
    expect(t.rotatedBy(math.pi / 4).rotation, closeTo(math.pi / 4, 1e-9));
    final fitted = free.fittedTo(const Rect.fromLTWH(0, 0, 500, 500));
    final corners = fitted.corners;
    expect(corners.map((p) => p.dx).reduce(math.min), closeTo(0, 1e-6));
    expect(corners.map((p) => p.dx).reduce(math.max), closeTo(500, 1e-6));
    expect(corners.map((p) => p.dy).reduce(math.min), closeTo(62.5, 1e-6));
  });

  test('distort maps the box onto a quad in perspective; warp bends a '
      'Bézier mesh through the place held', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(box, ui.Paint());
    final image = recorder.endRecording().toImageSync(100, 50);
    addTearDown(image.dispose);
    const t = LayerTransform(bounds: box, scaleX: 2);
    final quad = t.toDistort(image);
    expect(quad.mesh, t.corners);
    expect(quad.isIdentity, isFalse);
    final trapezoid = quad.withCorner(1, const Offset(250, -50));
    // A quad's middle in perspective is where its diagonals cross.
    final c = trapezoid.corners;
    final centre = trapezoid.surface(.5, .5);
    double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
    expect(cross(c[2] - c[0], centre - c[0]).abs(), lessThan(1e-6));
    expect(cross(c[3] - c[1], centre - c[1]).abs(), lessThan(1e-6));
    final skewed = quad.withSideMoved(0, const Offset(30, 0));
    expectPoint(skewed.corners[0], quad.corners[0] + const Offset(30, 0));
    expectPoint(skewed.corners[3], quad.corners[3]);

    final warp = t.toWarp(image);
    for (final (u, v) in [(0.0, 0.0), (.3, .7), (1.0, .5)]) {
      expectPoint(
        warp.surface(u, v),
        t.map(Offset(box.width * u, box.height * v)),
      );
    }
    final bent = warp.warped(.3, .7, const Offset(12, -8));
    expectPoint(
      bent.surface(.3, .7),
      warp.surface(.3, .7) + const Offset(12, -8),
    );
    expect((bent.surface(0, 0) - warp.surface(0, 0)).distance, lessThan(12));
    final (u, v) = bent.meshAt(bent.surface(.5, .5))!;
    expect(u, closeTo(.5, .03));
    expect(v, closeTo(.5, .03));
    expect(bent.meshAt(const Offset(-500, -500)), isNull);
  });

  test('flip, distort and warp apply to the layer as one step', () async {
    final c = await squares();
    addTearDown(c.dispose);
    expect(c.beginTransform(), isTrue);
    c.previewTransform(c.transformDraft!.flipped(horizontal: true));
    await c.applyTransform();
    var pixels = await shown(c);
    expect(at(c, pixels, 150, 200), [0, 0, 255, 255]);
    expect(at(c, pixels, 250, 200), [255, 0, 0, 255]);
    c.undo();
    await c.settleStroke();

    c.setTransformMode(TransformMode.distort);
    expect(c.beginTransform(), isTrue);
    expect(c.transformDraft!.mesh, hasLength(4), reason: 'mode is kept');
    c.previewTransform(c.transformDraft!.withCorner(2, const Offset(500, 500)));
    pixels = await shown(c);
    expect(at(c, pixels, 380, 380)[3], 255, reason: 'previewed');
    await c.applyTransform();
    pixels = await shown(c);
    expect(at(c, pixels, 380, 380)[3], 255);
    expect(at(c, pixels, 120, 120), [255, 0, 0, 255]);
    expect(c.transformDraft, isNull);

    c.setTransformMode(TransformMode.warp);
    expect(c.beginTransform(), isTrue);
    expect(c.transformDraft!.mesh, hasLength(16));
    c.setTransformFilter(FilterQuality.none);
    c.previewTransform(c.transformDraft!.translated(const Offset(400, 0)));
    expect(c.transformDraft!.filter, FilterQuality.none);
    await c.applyTransform();
    pixels = await shown(c);
    expect(at(c, pixels, 120, 120)[3], 0);
    expect(at(c, pixels, 520, 120), [255, 0, 0, 255]);
  });

  test('a transform inside a selection leaves the rest where it was', () async {
    final c = await squares();
    addTearDown(c.dispose);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(100, 100, 100, 200)),
    );
    c.setTransformMode(TransformMode.warp);
    expect(c.beginTransform(), isTrue);
    c.previewTransform(c.transformDraft!.translated(const Offset(0, 400)));
    await c.applyTransform();
    final pixels = await shown(c);
    expect(at(c, pixels, 150, 200)[3], 0);
    expect(at(c, pixels, 150, 600), [255, 0, 0, 255]);
    expect(at(c, pixels, 250, 200), [0, 0, 255, 255]);
  });

  testWidgets('the bar switches modes and takes a typed scale', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late StudioController c;
    await tester.runAsync(() async => c = await squares());
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(c.beginTransform(), isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Freeform'));
    await tester.pump();
    expect(c.transformMode, TransformMode.freeform);
    await tester.tap(find.byKey(const ValueKey('transform-scale-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('number-field')), '50');
    await tester.tap(find.text('Apply').last);
    await tester.pumpAndSettle();
    expect(c.transformDraft!.scale, closeTo(.5, 1e-9));
    await tester.tap(find.byKey(const ValueKey('transform-flip-h')));
    await tester.pump();
    expect(c.transformDraft!.scaleX, closeTo(-.5, 1e-9));
    await tester.tap(find.byTooltip('Warp'));
    await tester.pump();
    expect(c.transformDraft!.mesh, hasLength(16));
    // The sliders stay: a mesh is resized and turned as a whole.
    expect(find.byKey(const ValueKey('transform-scale')), findsOneWidget);
    final before = c.transformDraft!.shownScale;
    final draft = c.transformDraft!.withShownScale(before * 2);
    expect(draft.shownScale, closeTo(before * 2, 1e-6));
    expect(
      c.transformDraft!.withShownRotation(.5).shownRotation,
      closeTo(.5, 1e-6),
    );
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(c.transformDraft, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
