import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/quick_shape.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
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
  );
  final image = await recorder.endRecording().toImage(
    doc.dimensions.width,
    doc.dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

int alpha(StudioController c, Uint8List pixels, double x, double y) =>
    pixels[(y.round() * c.document.dimensions.width + x.round()) * 4 + 3];

/// A wobbly hand-drawn oval around (500, 500), held at its end.
void drawOval(StudioController c) {
  var t = Duration.zero;
  InkPoint at(double a) => InkPoint(
    500 + math.cos(a) * 200 + math.sin(a * 9) * 3,
    500 + math.sin(a) * 140 + math.cos(a * 7) * 3,
    .6,
  );
  c.beginStroke(at(0), simulatePressure: false, time: t);
  for (var a = .05; a <= 2 * math.pi + .1; a += .05) {
    t += const Duration(milliseconds: 8);
    c.appendPoint(at(a), time: t);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('held, a stroke becomes a shape that follows the pen; a second '
      'finger makes it perfect; lifting draws it with the brush', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectColor(0xff202020);
    c.setSize(12);
    drawOval(c);
    expect(c.holdStroke(), isTrue);
    expect(c.quickShape!.current.kind, QuickShapeKind.ellipse);
    expect(c.strokeBusy, isFalse, reason: 'the brush preview is gone');
    c.setQuickShapePerfect(true);
    final circle = c.quickShape!.current;
    final [centre, a, b] = circle.points;
    expect((a - centre).distance, closeTo((b - centre).distance, 1e-6));
    c.finishStroke();
    await c.settleStroke();
    expect(c.quickShape, isNull);
    expect(c.lastQuickShape, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(c.lastQuickShape!.revision, c.document.revision);
    final r = (a - centre).distance;
    final pixels = await shown(c);
    expect(alpha(c, pixels, centre.dx + r, centre.dy), greaterThan(200));
    expect(alpha(c, pixels, centre.dx, centre.dy - r), greaterThan(200));
    expect(alpha(c, pixels, centre.dx, centre.dy), 0);

    // Edit Shape: off the layer, a node moved, back on.
    expect(await c.editQuickShape(), isTrue);
    expect(c.shapeEdit, isNotNull);
    expect(alpha(c, await shown(c), centre.dx + r, centre.dy), 0);
    c.moveShapeNode(4, centre + const Offset(100, 0));
    c.finishShapeEdit();
    await c.settleStroke();
    final moved = await shown(c);
    expect(alpha(c, moved, centre.dx + 100 + r, centre.dy), greaterThan(200));
    expect(alpha(c, moved, centre.dx - r, centre.dy), 0);
    c.undo();
    await c.settleStroke();
    expect(
      alpha(c, await shown(c), centre.dx + r, centre.dy),
      0,
      reason: 'one step: the edit replaced the first shape',
    );
  });

  test('Perfect replaces the shape just drawn, as one step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setSize(12);
    drawOval(c);
    expect(c.holdStroke(), isTrue);
    c.finishStroke();
    await c.settleStroke();
    await Future<void>.delayed(Duration.zero);
    final before = c.lastQuickShape!.shape;
    await c.perfectQuickShape();
    await c.settleStroke();
    await Future<void>.delayed(Duration.zero);
    final [centre, a, b] = c.lastQuickShape!.shape.points;
    expect((a - centre).distance, closeTo((b - centre).distance, 1e-6));
    expect(c.lastQuickShape!.revision, c.document.revision);
    final r = (a - centre).distance;
    final pixels = await shown(c);
    expect(alpha(c, pixels, centre.dx, centre.dy - r), greaterThan(200));
    c.undo();
    await c.settleStroke();
    expect(alpha(c, await shown(c), centre.dx, centre.dy - r), 0);
    expect(before.kind, QuickShapeKind.ellipse);
  });

  test('a line held then moved: its end follows the pen', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.beginStroke(const InkPoint(100, 100, .5), simulatePressure: false);
    for (var x = 110.0; x <= 400; x += 10) {
      c.appendPoint(InkPoint(x, 100 + math.sin(x) * 2, .5));
    }
    expect(c.holdStroke(), isTrue);
    expect(c.quickShape!.current.kind, QuickShapeKind.line);
    c.appendPoint(const InkPoint(100, 500, .5));
    final line = c.quickShape!.current;
    expect((line.points.last - const Offset(100, 500)).distance, lessThan(1));
    c.cancelStroke();
    expect(c.quickShape, isNull);
    c.beginStroke(const InkPoint(5, 5, .5), simulatePressure: false);
    c.appendPoint(const InkPoint(6, 6, .5));
    expect(c.holdStroke(), isFalse, reason: 'too small to be a shape');
    c.cancelStroke();
  });

  testWidgets('holding the pen still on the canvas snaps; Edit Shape shows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.selectBrush(initialBrushes.firstWhere((b) => !b.isNative));
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final start = canvas.center - const Offset(150, 0);
    final pen = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 30; i++) {
      await pen.moveTo(start + Offset(i * 10.0, math.sin(i.toDouble())));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.quickShape?.current.kind, QuickShapeKind.line);
    await pen.up();
    await tester.pump();
    expect(c.document.activeLayer.strokes, hasLength(1));
    expect(find.byKey(const ValueKey('edit-shape')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
