import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
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

void stroke(StudioController c, Offset from, Offset to) {
  c.beginStroke(InkPoint(from.dx, from.dy, 1), simulatePressure: false);
  for (var t = .1; t <= 1.0001; t += .1) {
    final p = Offset.lerp(from, to, t)!;
    c.appendPoint(InkPoint(p.dx, p.dy, 1));
  }
  c.finishStroke();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clone copies from the disc: aligned it follows the brush, locked '
      'every stroke starts at it; applied as one step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    for (final (rect, color) in [
      (const Rect.fromLTWH(0, 0, 512, 1024), 0xffff0000),
      (const Rect.fromLTWH(512, 0, 512, 1024), 0xff0000ff),
    ]) {
      c.selectColor(color);
      c.setSelection(SelectionRegion.rectangle(rect));
      await c.fillActiveLayer();
    }
    c.setSelection(null);
    c.setSize(40);
    c.setOpacity(1);
    expect(await c.startClone(), isTrue);
    c.moveCloneDisc(const Offset(200, 500));
    stroke(c, const Offset(700, 500), const Offset(800, 500));
    expect(at(c, await shown(c), 750, 500), [255, 0, 0, 255]);
    expect(at(c, await shown(c), 750, 600), [0, 0, 255, 255]);
    expect(c.clone!.disc, const Offset(300, 500), reason: 'it followed');
    // Aligned: the next stroke keeps the same distance.
    stroke(c, const Offset(700, 800), const Offset(720, 800));
    expect(at(c, await shown(c), 710, 800), [255, 0, 0, 255]);

    c.setCloneLocked(true);
    c.moveCloneDisc(const Offset(900, 300));
    stroke(c, const Offset(100, 100), const Offset(150, 100));
    // While a locked stroke paints, the disc stays; the sample point moves.
    c.beginStroke(const InkPoint(100, 300, 1), simulatePressure: false);
    c.appendPoint(const InkPoint(150, 300, 1));
    expect(c.clone!.shownDisc, const Offset(900, 300));
    expect(c.clone!.sampling, const Offset(950, 300));
    c.finishStroke();
    var pixels = await shown(c);
    expect(at(c, pixels, 120, 100), [0, 0, 255, 255]);
    expect(at(c, pixels, 120, 300), [0, 0, 255, 255]);
    expect(c.clone!.disc, const Offset(900, 300), reason: 'locked stays');
    // Aligned, a stroke that would carry the disc off the canvas leaves it
    // at the edge, where it stays visible.
    c.setCloneLocked(false);
    c.moveCloneDisc(const Offset(1000, 300));
    stroke(c, const Offset(100, 900), const Offset(300, 900));
    expect(c.clone!.disc.dx, 1024);
    expect(c.clone!.disc.dy, 300);
    c.undoClone();
    c.setCloneLocked(true);
    c.moveCloneDisc(const Offset(900, 300));
    c.undoClone();
    expect(at(c, await shown(c), 120, 300), [255, 0, 0, 255]);

    await c.applyClone();
    expect(c.clone, isNull);
    pixels = await shown(c);
    expect(at(c, pixels, 750, 500), [255, 0, 0, 255]);
    expect(at(c, pixels, 120, 100), [0, 0, 255, 255]);
    c.undo();
    await c.settleStroke();
    expect(at(c, await shown(c), 750, 500), [0, 0, 255, 255]);
  });

  testWidgets('the magic wand opens Clone; its bar locks and cancels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adjustments'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Clone'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Clone'));
      for (var i = 0; i < 20 && c.clone == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('clone-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clone-lock')));
    await tester.pump();
    expect(c.clone!.locked, isTrue);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(c.clone, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
