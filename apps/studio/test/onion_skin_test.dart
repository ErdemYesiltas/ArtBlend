import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/drawing_surface.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

ArtDocument frames(int n) => ArtDocument(
  id: 'o',
  name: 'Onion',
  dimensions: const CanvasSize(100, 100),
  layers: [for (var i = 0; i < n; i++) ArtLayer(id: 'f$i', name: 'F$i')],
  activeLayerId: 'f2',
);

List<List<String>> ids(OnionView v) => [
  for (final (doc, _, _) in v.onions) [for (final l in doc.layers) l.id],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('neighbours each side, nearer ones stronger, in their tints; the '
      'pinned background and foreground are not onions', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(frames(6));
    c.setAnimationAssist(true);
    c.setAnimation(c.document.animation!.copyWith(onionFrames: 0));
    expect(c.onionView, isNull, reason: 'nothing to blend');
    c.setAnimation(c.document.animation!.copyWith(onionFrames: 1));
    var view = c.onionView!;
    expect(ids(view), [
      ['f1'],
      ['f3'],
    ]);
    final settings = c.document.animation!;
    expect(view.onions[0].$2, settings.onionBehind);
    expect(view.onions[1].$2, settings.onionAhead);
    expect(view.top.layers.single.id, 'f2');
    expect(view.top.backgroundHidden, isTrue, reason: 'no paper over onions');

    c.setAnimation(
      settings.copyWith(onionFrames: 3, background: 'f0', foreground: 'f5'),
    );
    view = c.onionView!;
    expect(ids(view), [
      ['f4'],
      ['f1'],
      ['f3'],
    ], reason: 'farthest first; f0 and f5 are pinned');
    expect(view.under!.layers.single.id, 'f0');
    expect([for (final l in view.top.layers) l.id], ['f2', 'f5']);
    final far = view.onions.first.$3, near = view.onions.last.$3;
    expect(near, greaterThan(far));
  });

  test('the canvas shows a neighbouring frame tinted under the frame being '
      'drawn', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(frames(3));
    // Frame 1 filled black; frame 2 (shown) empty.
    c.selectLayer('f1');
    c.selectColor(0xff000000);
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 100, 100)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    c.selectLayer('f2');
    c.setAnimationAssist(true);
    c.setAnimation(
      c.document.animation!.copyWith(
        onionFrames: 1,
        onionOpacity: 1,
        onionBehind: 0xffff0000,
      ),
    );
    final recorder = ui.PictureRecorder();
    DocumentPainter(
      controller: c,
      engine: FreehandBrushEngine(),
      paths: {},
    ).paint(ui.Canvas(recorder), const ui.Size(100, 100));
    final image = await recorder.endRecording().toImage(100, 100);
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    final at = (50 * 100 + 50) * 4;
    expect(rgba.sublist(at, at + 3), [255, 0, 0], reason: 'black as red');
  });
}
