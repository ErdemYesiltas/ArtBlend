import 'dart:math' as math;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/guides.dart';
import 'package:atelier_studio/drawing/symmetry.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = Size(1000, 800);

  test('each guide draws its lines; settings survive JSON', () {
    expect(guideLines(const DrawingGuide(), canvas), isEmpty);
    final grid = guideLines(
      const DrawingGuide(kind: GuideKind.grid, gridSize: 100),
      canvas,
    );
    expect(grid, hasLength(9 + 7));
    expect(
      guideLines(const DrawingGuide(kind: GuideKind.isometric), canvas),
      isNotEmpty,
    );
    final perspective = guideLines(
      const DrawingGuide(
        kind: GuideKind.perspective,
        vanishing: [Offset(.2, .4), Offset(.8, .4)],
      ),
      canvas,
    );
    // The horizon passes through both points.
    final (a, b) = perspective.first;
    expect(a.dy, closeTo(320, 1e-6));
    expect(b.dy, closeTo(320, 1e-6));
    const guide = DrawingGuide(
      kind: GuideKind.perspective,
      color: 0xffff0000,
      opacity: .5,
      thickness: 2,
      vanishing: [Offset(.1, .2), Offset(.9, .2), Offset(.5, 2)],
      symmetryCentre: Offset(.3, .7),
      rotational: true,
    );
    final back = DrawingGuide.fromJson(guide.toJson());
    expect(back.toJson(), guide.toJson());
    expect(DrawingGuide.fromJson('nonsense').kind, GuideKind.none);
  });

  test('assist picks the nearest guide line and keeps points on it', () {
    final grid = assistDirections(
      const DrawingGuide(kind: GuideKind.grid),
      canvas,
      Offset.zero,
    );
    final d = nearestDirection(grid, const Offset(40, 9))!;
    expect(d, const Offset(1, 0));
    expect(
      projectOnto(const Offset(70, 12), Offset.zero, d),
      const Offset(70, 0),
    );
    final iso = nearestDirection(
      assistDirections(
        const DrawingGuide(kind: GuideKind.isometric),
        canvas,
        Offset.zero,
      ),
      const Offset(50, 25),
    )!;
    expect(math.atan2(iso.dy, iso.dx), closeTo(math.pi / 6, 1e-9));
  });

  test('rotational symmetry turns copies; the centre can move', () {
    expect(symmetryMatrices(SymmetryKind.vertical, rotational: true), const [
      (1, 0, 0, 1),
      (-1, 0, 0, -1),
    ]);
    expect(
      symmetryMatrices(SymmetryKind.quadrant, rotational: true),
      hasLength(4),
    );
    final copies = symmetricStrokes(
      InkStroke(
        id: 's',
        points: const [InkPoint(110, 205, .5)],
        color: 0xff000000,
        size: 4,
        opacity: 1,
      ),
      SymmetryKind.vertical,
      const Offset(100, 200),
      rotational: true,
    );
    final p = copies[1].points.single;
    expect((p.x, p.y), (90, 195));
  });

  test('on an assisted layer a wobbly stroke follows the grid', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectBrush(initialBrushes.firstWhere((b) => !b.isNative));
    c.setGuide(const DrawingGuide(kind: GuideKind.grid));
    c.toggleDrawingAssist(c.document.activeLayerId);
    expect(c.document.activeLayer.assisted, isTrue);
    c.beginStroke(const InkPoint(100, 100, .5), simulatePressure: false);
    for (final (x, y) in [(103.0, 101.0), (140.0, 108.0), (200.0, 93.0)]) {
      c.appendPoint(InkPoint(x, y, .5));
    }
    final points = c.pendingStroke!.points;
    expect(points.every((p) => (p.y - 100).abs() < 1e-9), isTrue);
    expect(points.last.x, closeTo(200, 1e-9));
    c.finishStroke();
    // Without assist it draws as it went.
    c.toggleDrawingAssist(c.document.activeLayerId);
    c.beginStroke(const InkPoint(100, 300, .5), simulatePressure: false);
    c.appendPoint(const InkPoint(200, 320, .5));
    expect(c.pendingStroke!.points.last.y, 320);
    c.finishStroke();
  });

  testWidgets('Edit Drawing Guide: a tap adds a vanishing point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await tester.runAsync(c.initialize);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.setPanel(EditorPanel.actions);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit drawing guide'));
    await tester.tap(find.text('Edit drawing guide'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-bar')), findsOneWidget);
    await tester.tap(find.byTooltip('Perspective'));
    await tester.pump();
    expect(c.guide.vanishing, hasLength(1));
    final board = find.byKey(const ValueKey('drawing-surface'));
    await tester.tapAt(
      tester.getTopLeft(board) +
          tester.getSize(board).bottomRight(Offset.zero) * .1,
    );
    await tester.pump();
    expect(c.guide.vanishing, hasLength(2));
    expect(c.document.activeLayer.strokes, isEmpty, reason: 'no ink');
    await tester.tap(find.byKey(const ValueKey('guide-done')));
    await tester.pump();
    expect(c.guideEditing, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
