import 'dart:math' as math;

import 'package:atelier_studio/editor/canvas_navigation.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Offset apply(Matrix4 m, Offset p) => MatrixUtils.transformPoint(m, p);

void main() {
  test('a pinch keeps the canvas points under both fingers', () {
    final start = Matrix4.identity()..translateByDouble(30, -10, 0, 1);
    const a0 = Offset(100, 100), b0 = Offset(300, 100);
    const a1 = Offset(120, 140), b1 = Offset(120, 440); // turned 90°, ×1.5
    final m = CanvasNavigation.pinch(start, a0, b0, a1, b1);
    final inverse = Matrix4.inverted(start);
    for (final (from, to) in [(a0, a1), (b0, b1)]) {
      final canvasPoint = apply(inverse, from);
      expect((apply(m, canvasPoint) - to).distance, lessThan(1e-6));
    }
    expect(CanvasNavigation.rotationOf(m), closeTo(math.pi / 2, 1e-9));
    expect(CanvasNavigation.scaleOf(m), closeTo(1.5, 1e-9));
  });

  test('zoom stays within limits and near quarter turns snap', () {
    final far = CanvasNavigation.around(
      Matrix4.identity(),
      Offset.zero,
      scale: 100,
    );
    expect(CanvasNavigation.scaleOf(far), CanvasNavigation.maxScale);
    final tilted = CanvasNavigation.around(
      Matrix4.identity(),
      const Offset(200, 200),
      rotation: math.pi / 2 + .05,
    );
    final snapped = CanvasNavigation.snapped(tilted, const Offset(200, 200));
    expect(CanvasNavigation.rotationOf(snapped), closeTo(math.pi / 2, 1e-9));
    final free = CanvasNavigation.around(
      Matrix4.identity(),
      Offset.zero,
      rotation: .5,
    );
    expect(CanvasNavigation.snapped(free, Offset.zero), same(free));
  });

  testWidgets('two fingers turn and zoom the canvas in the brush tool; '
      'strokes still land where the pen is', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final a = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 1,
    );
    final b = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 2,
    );
    await a.down(surface - const Offset(100, 0));
    await b.down(surface + const Offset(100, 0));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      final angle = math.pi / 2 * i / 10;
      final r = 100 + 50 * i / 10;
      final d = Offset(math.cos(angle) * r, math.sin(angle) * r);
      await a.moveTo(surface - d);
      await b.moveTo(surface + d);
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(c.document.layers.single.strokes, isEmpty, reason: 'no ink');
    final surfaceFinder = find.byKey(const ValueKey('drawing-surface'));
    final box = tester.renderObject<RenderBox>(surfaceFinder);
    // The view turned a quarter (snapped) and zoomed 1.5×.
    final x =
        box.localToGlobal(const Offset(100, 0)) -
        box.localToGlobal(Offset.zero);
    expect(x.direction, closeTo(math.pi / 2, 1e-6));
    expect(x.distance, closeTo(150, 1));
    // A mouse stroke drawn rightwards on screen runs down the drawing.
    final pen = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pen.down(surface);
    for (var i = 1; i <= 10; i++) {
      await pen.moveTo(surface + Offset(i * 10.0, 0));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    final points = c.document.activeLayer.strokes.single.points;
    expect((points.last.x - points.first.x).abs(), lessThan(2));
    expect(points.last.y - points.first.y, lessThan(0));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a zoomed-in canvas never paints over the menus, which stay '
      'usable', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setTheme(ThemeMode.dark);
    const key = ValueKey('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final menu = tester.getCenter(find.text('Gallery')) + const Offset(60, 0);
    Future<double> brightness() async {
      final data = await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final bytes = await image.toByteData();
        image.dispose();
        return bytes!;
      });
      final i = (menu.dy.round() * 1100 + menu.dx.round()) * 4;
      return (data!.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) /
          3;
    }

    final before = await brightness();
    final surface = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final a = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 1,
    );
    final b = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 2,
    );
    await a.down(surface - const Offset(20, 0));
    await b.down(surface + const Offset(20, 0));
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(surface - Offset(20.0 + 20 * i, 0));
      await b.moveTo(surface + Offset(20.0 + 20 * i, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // The paper now spans far past the workspace, yet the dark menu bar
    // shows as before, and it answers.
    expect(before, lessThan(100));
    expect(await brightness(), closeTo(before, 2));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(c.panel, EditorPanel.gallery);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
