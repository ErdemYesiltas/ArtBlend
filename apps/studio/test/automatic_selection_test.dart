import 'dart:ui';

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

Future<void> settle(StudioController c, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a tap selects the colour area; sliding the threshold widens it',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      for (final (rect, color) in [
        (const Rect.fromLTWH(0, 0, 512, 1024), 0xffcc2020),
        (const Rect.fromLTWH(512, 0, 512, 1024), 0xffd03030),
      ]) {
        c.selectColor(color);
        c.setSelection(SelectionRegion.rectangle(rect));
        await c.fillActiveLayer();
      }
      c.setSelection(null);
      c.selectTool(StudioTool.selection);
      c.setSelectionShape(SelectionShape.automatic);
      c.setAutoThreshold(.02);
      expect(c.beginSelection(const Offset(100, 100)), isTrue);
      await settle(c, () => c.selection != null);
      var path = c.selection!.path;
      expect(path.contains(const Offset(300, 500)), isTrue);
      expect(path.contains(const Offset(700, 500)), isFalse);
      c.setAutoThreshold(.2);
      await settle(c, () => c.selection!.path.contains(const Offset(700, 500)));
      expect(c.selection!.path.contains(const Offset(700, 500)), isTrue);
      c.finishSelection();
      c.cancelSelectionDraft();
      expect(c.selection, isNotNull, reason: 'finished, it stays');
    },
  );

  test('Select Contents follows the layer\'s pixels, holes included', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setSelection(
      SelectionRegion.ellipse(const Rect.fromLTWH(200, 200, 600, 600)),
    );
    await c.fillActiveLayer();
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(450, 450, 100, 100)),
    );
    await c.deleteSelectedPixels();
    await c.selectLayerContents(c.document.activeLayerId);
    final path = c.selection!.path;
    expect(path.contains(const Offset(300, 500)), isTrue);
    expect(path.contains(const Offset(500, 500)), isFalse, reason: 'hole');
    expect(path.contains(const Offset(50, 50)), isFalse);
  });

  test('polygon: taps place corners, a held corner moves, a tap on the '
      'first closes; a pinch keeps it', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectTool(StudioTool.selection);
    c.setSelectionShape(SelectionShape.polygon);
    void tap(Offset p) {
      expect(c.beginSelection(p, reach: 12), isTrue);
      c.finishSelection(tap: true);
    }

    tap(const Offset(100, 100));
    tap(const Offset(500, 100));
    tap(const Offset(450, 380));
    expect(c.selectionPolygonOpen, isTrue);
    expect(c.selection, isNull);
    // Take the third corner and move it.
    c.beginSelection(const Offset(452, 378), reach: 12);
    c.appendSelection(const Offset(500, 400));
    c.finishSelection();
    expect(c.selectionDraftShape, const [
      Offset(100, 100),
      Offset(500, 100),
      Offset(500, 400),
    ]);
    // A pinch's first finger places nothing.
    c.beginSelection(const Offset(300, 700), reach: 12);
    c.dropPolygonTouch();
    expect(c.selectionDraftShape, hasLength(3));
    tap(const Offset(100, 400));
    tap(const Offset(104, 97));
    expect(c.selectionPolygonOpen, isFalse);
    final path = c.selection!.path;
    expect(path.contains(const Offset(300, 250)), isTrue);
    expect(path.contains(const Offset(600, 250)), isFalse);

    // Or closed from the bar.
    c.setSelection(null);
    tap(const Offset(600, 600));
    tap(const Offset(900, 600));
    tap(const Offset(750, 900));
    c.closeSelectionPolygon();
    expect(c.selectionPolygonOpen, isFalse);
    expect(c.selection!.path.contains(const Offset(750, 700)), isTrue);
  });

  test('freehand is a plain drag again', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectTool(StudioTool.selection);
    c.setSelectionShape(SelectionShape.freehand);
    c.beginSelection(const Offset(100, 100));
    for (final p in const [
      Offset(400, 120),
      Offset(380, 400),
      Offset(120, 380),
    ]) {
      c.appendSelection(p);
    }
    c.finishSelection(tap: true);
    expect(c.selection!.path.contains(const Offset(250, 250)), isTrue);
  });
}
