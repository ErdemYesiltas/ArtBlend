import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/liquify.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

ui.Image blank(int size) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint(),
  );
  return recorder.endRecording().toImageSync(size, size);
}

/// The grid point nearest (x, y) at rest.
Offset point(LiquifySession s, double x, double y) {
  final n = s.cells, w = s.source.width / n, h = s.source.height / n;
  final k = ((y / h).round() * (n + 1) + (x / w).round()) * 2;
  return Offset(s.positions[k], s.positions[k + 1]);
}

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

int alpha(StudioController c, Uint8List pixels, int x, int y) =>
    pixels[(y * c.document.dimensions.width + x) * 4 + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('push moves what is under the brush; twirl turns, pinch draws in, '
      'reconstruct and undo take back', () {
    final s = LiquifySession(layerId: 'l', source: blank(400), cells: 40)
      ..size = .1
      ..pressure = 1;
    expect(s.isIdentity, isTrue);
    s.begin(const Offset(200, 200), 1);
    s.move(const Offset(240, 200), 1);
    s.end();
    final centre = point(s, 200, 200);
    expect(centre.dx, greaterThan(220));
    expect(centre.dy, closeTo(200, 1));
    expect(point(s, 20, 20), const Offset(20, 20), reason: 'out of reach');
    s.undo();
    expect(s.isIdentity, isTrue);

    s.mode = LiquifyMode.twirlRight;
    s.begin(const Offset(200, 200), 1);
    for (var i = 0; i < 10; i++) {
      s.hold();
    }
    s.end();
    final turned = point(s, 210, 200);
    expect((turned - const Offset(200, 200)).distance, closeTo(10, .2));
    expect(turned.dy, greaterThan(203), reason: 'clockwise on screen');

    s.reset();
    s.mode = LiquifyMode.pinch;
    s.begin(const Offset(200, 200), 1);
    s.end();
    expect(point(s, 220, 200).dx, lessThan(220));

    s.mode = LiquifyMode.reconstruct;
    final before = (point(s, 220, 200).dx - 220).abs();
    s.begin(const Offset(200, 200), 1);
    for (var i = 0; i < 20; i++) {
      s.hold();
    }
    s.end();
    expect((point(s, 220, 200).dx - 220).abs(), lessThan(before));
    s.reconstructAll(1);
    expect(s.isIdentity, isTrue);
    s.dispose();
  });

  test('a push glides on with momentum, and stops', () {
    final s = LiquifySession(layerId: 'l', source: blank(400), cells: 40)
      ..momentum = .8;
    s.begin(const Offset(200, 200), 1);
    s.move(const Offset(230, 200), 1);
    final after = point(s, 200, 200).dx;
    expect(s.end(), isTrue);
    var frames = 0;
    while (s.glide(const Offset(230, 200)) && frames < 200) {
      frames++;
    }
    expect(frames, inInclusiveRange(1, 199));
    expect(point(s, 200, 200).dx, greaterThan(after));
    s.dispose();
  });

  test('Liquify previews on the layer and applies as one step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.selectColor(0xffff0000);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 500, 1024)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    expect(await c.startLiquify(), isTrue);
    c.setLiquify(mode: LiquifyMode.push, size: .2, pressure: 1);
    c.beginLiquify(const Offset(480, 500), 1);
    c.moveLiquify(const Offset(600, 500), 1);
    c.endLiquify();
    expect(alpha(c, await shown(c), 540, 500), 255, reason: 'previewed');
    await c.applyLiquify();
    expect(c.liquify, isNull);
    expect(alpha(c, await shown(c), 540, 500), 255);
    c.undo();
    await c.settleStroke();
    expect(alpha(c, await shown(c), 540, 500), 0);
  });

  testWidgets('the magic wand opens Liquify; its bar picks a brush', (
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
    await tester.ensureVisible(find.text('Liquify'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Liquify'));
      for (var i = 0; i < 20 && c.liquify == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('liquify-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('liquify-mode-pinch')));
    await tester.pump();
    expect(c.liquify!.mode, LiquifyMode.pinch);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(c.liquify, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
