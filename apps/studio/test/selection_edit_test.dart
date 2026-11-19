import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

void drag(StudioController c, Offset from, Offset to) {
  expect(c.beginSelection(from), isTrue);
  c.appendSelection(Offset.lerp(from, to, .5)!);
  c.appendSelection(to);
  c.finishSelection();
}

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shapes add to and cut from a selection, in order, and survive saving',
    () {
      final square = SelectionRegion.rectangle(
        const Rect.fromLTWH(100, 100, 400, 400),
      );
      final edited = square
          .combine(
            SelectionOp.add,
            SelectionRegion.rectanglePoints(
              const Rect.fromLTWH(450, 100, 200, 200),
            ),
          )
          .combine(
            SelectionOp.subtract,
            SelectionRegion.ellipsePoints(
              const Rect.fromLTWH(200, 200, 100, 100),
            ),
          )
          .withFeather(12);
      expect(edited.path.contains(const Offset(120, 120)), isTrue);
      expect(
        edited.path.contains(const Offset(600, 150)),
        isTrue,
        reason: 'added',
      );
      expect(
        edited.path.contains(const Offset(250, 250)),
        isFalse,
        reason: 'cut',
      );
      expect(edited.path.contains(const Offset(600, 400)), isFalse);
      expect(edited.bounds, const Rect.fromLTRB(88, 88, 662, 512));

      final back = SelectionRegion.fromJson(
        jsonDecode(jsonEncode(edited.toJson())) as Map<String, dynamic>,
      );
      expect(back.edits.map((e) => e.op), [
        SelectionOp.add,
        SelectionOp.subtract,
      ]);
      expect(back.feather, 12);
      expect(back.path.contains(const Offset(250, 250)), isFalse);
      // Files written before edits read unchanged.
      expect(SelectionRegion.fromJson(square.toJson()).edits, isEmpty);

      final inverted = edited.invert();
      expect(inverted.path.contains(const Offset(250, 250)), isTrue);
      expect(inverted.path.contains(const Offset(120, 120)), isFalse);
      expect(inverted.invert().edits, hasLength(2), reason: 'invert undone');
      expect(square.invert().edits, isEmpty, reason: 'a lone shape flips');

      final registry = <String, SelectionRegion>{};
      registerSelection(edited, registry);
      expect(
        () => registerSelection(
          SelectionRegion(id: edited.id, points: edited.points),
          registry,
        ),
        throwsFormatException,
      );
    },
  );

  test('the selection tool adds, removes and draws ellipses', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectTool(StudioTool.selection);
    drag(c, const Offset(100, 100), const Offset(400, 400));
    c.setSelectionMode(SelectionMode.add);
    drag(c, const Offset(500, 100), const Offset(700, 300));
    expect(c.selection!.edits, hasLength(1));
    expect(c.selection!.path.contains(const Offset(600, 200)), isTrue);
    c.setSelectionMode(SelectionMode.subtract);
    c.setSelectionShape(SelectionShape.ellipse);
    drag(c, const Offset(150, 150), const Offset(350, 350));
    final cut = c.selection!;
    expect(cut.path.contains(const Offset(250, 250)), isFalse);
    expect(
      cut.path.contains(const Offset(110, 110)),
      isTrue,
      reason: 'corner kept',
    );
    // A slip too small to be a shape leaves the selection as it was.
    drag(c, const Offset(10, 10), const Offset(10.2, 10.2));
    expect(c.selection, same(cut));
    c.setSelectionMode(SelectionMode.replace);
    drag(c, const Offset(600, 600), const Offset(800, 700));
    expect(c.selection!.edits, isEmpty);
    expect(c.selection!.path.contains(const Offset(700, 650)), isTrue);
    expect(
      c.selection!.path.contains(const Offset(610, 610)),
      isFalse,
      reason: 'ellipse',
    );
  });

  test('a soft edge fades coverage, native strokes and deleting', () async {
    final hard = SelectionRegion.rectangle(
      const Rect.fromLTWH(200, 0, 600, 1024),
    );
    final soft = hard.withFeather(40);
    final edge = await renderSelectionCoverage(soft, CanvasSize.legacy);
    final sharp = await renderSelectionCoverage(hard, CanvasSize.legacy);
    int at(Uint8List c, int x) => c[512 * 1024 + x];
    expect((at(sharp, 190), at(sharp, 210)), (0, 255));
    expect(
      at(edge, 200),
      inInclusiveRange(100, 155),
      reason: 'half at the line',
    );
    expect(at(edge, 175), inInclusiveRange(1, 80));
    expect(at(edge, 240), 255);

    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final rgba = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 255);
    await c.addImageLayer(encodeRgbaPng(rgba, 64, 64), 'White');
    c.setSelection(soft);
    await c.deleteSelectedPixels();
    final layer = c.document.activeLayer;
    final pixels = (await renderNativeBase(
      layer,
      c.document.grid,
      c.rasters.images,
    )).rgba;
    expect(alphaAt(pixels, 100, 500), 255, reason: 'outside kept');
    expect(alphaAt(pixels, 500, 500), 0, reason: 'inside deleted');
    expect(
      alphaAt(pixels, 200, 500),
      inInclusiveRange(100, 155),
      reason: 'faded',
    );

    c.selectBrush(initialBrushes.firstWhere((b) => b.id == 'stamp-gouache'));
    c.setSelection(soft);
    c.selectTool(StudioTool.brush);
    c.addLayer('Paint');
    var t = const Duration(seconds: 1);
    c.beginStroke(const InkPoint(60, 300, 1), simulatePressure: false, time: t);
    for (var x = 64.0; x < 400; x += 4) {
      t += const Duration(milliseconds: 8);
      c.appendPoint(InkPoint(x, 300, 1), time: t);
    }
    c.finishStroke();
    await c.settleStroke();
    final painted = (await renderNativeBase(
      c.document.activeLayer,
      c.document.grid,
      c.rasters.images,
    )).rgba;
    expect(alphaAt(painted, 120, 300), 0, reason: 'outside the soft edge');
    expect(alphaAt(painted, 300, 300), greaterThan(200));
    final middle = alphaAt(painted, 200, 300);
    expect(
      middle,
      inExclusiveRange(20, alphaAt(painted, 300, 300)),
      reason: 'fades in',
    );
  });
}
