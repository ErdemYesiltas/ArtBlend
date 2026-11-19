import 'dart:typed_data';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/mini_flipbook.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

TiledRaster ink() => TiledRaster(TileGrid(const CanvasSize(100, 100)), {
  0: RasterAsset(
    id: newId(),
    png: encodeRgbaPng(
      Uint8List(TiledRaster.size * TiledRaster.size * 4)..fillRange(0, 400, 9),
      TiledRaster.size,
      TiledRaster.size,
    ),
    width: TiledRaster.size,
    height: TiledRaster.size,
  ),
});

ArtDocument frames(
  int n, {
  Map<String, int> holds = const {},
  bool painted = true,
}) => ArtDocument(
  id: 'o',
  name: 'Flip',
  dimensions: const CanvasSize(100, 100),
  layers: [
    for (var i = 0; i < n; i++)
      ArtLayer(id: 'f$i', name: 'F$i', raster: painted ? ink() : null),
  ],
  activeLayerId: 'f0',
  animation: AnimationSettings(holds: holds, background: 'f0'),
);

List<String> order(StudioController c) => [
  for (final p in c.document.pages) ArtDocument.frameId(p),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('split, copy, clear, reverse, time and delete frames, each one undo '
      'step', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(frames(5, holds: {'f2': 3}));

    c.splitFrame(2, 'Split');
    final pages = c.document.pages;
    final copy = ArtDocument.frameId(pages[3]);
    expect(order(c).take(3), ['f0', 'f1', 'f2']);
    expect(
      (c.document.animation!.hold('f2'), c.document.animation!.hold(copy)),
      (1, 1),
      reason: '4 frames of time: 2 and 2',
    );
    expect(pages[3].single.raster, same(pages[2].single.raster));
    c.undo();
    expect(order(c), ['f0', 'f1', 'f2', 'f3', 'f4']);
    expect(c.document.animation!.hold('f2'), 3);
    c.splitFrame(1, 'x');
    expect(order(c), hasLength(5), reason: 'nothing held, nothing to split');

    c.duplicateFrames({1, 2}, (n) => 'Copy $n');
    expect(order(c).take(3), ['f0', 'f1', 'f2']);
    expect(c.document.pages[3].single.name, 'Copy 6');
    expect(c.document.animation!.hold(order(c)[4]), 3, reason: 'hold copied');
    c.undo();

    c.clearFrames({1, 3});
    expect(c.document.layers[1].raster, isNull);
    expect(c.document.layers[2].raster, isNotNull);
    expect(c.document.layers[3].raster, isNull);
    c.undo();
    expect(c.document.layers[1].raster, isNotNull);

    c.reverseFrames({1, 2, 4});
    expect(order(c), ['f0', 'f4', 'f2', 'f3', 'f1']);
    c.undo();

    c.setFrameDurations({1, 3}, 2);
    expect(
      [for (final id in order(c)) c.document.animation!.hold(id)],
      [0, 1, 3, 1, 0],
    );
    c.undo();

    c.deleteFrames({0, 2});
    expect(order(c), ['f1', 'f3', 'f4']);
    expect(c.document.animation!.holds.containsKey('f2'), isFalse);
    expect(c.document.animation!.background, isNull, reason: 'it was f0');
    c.deleteFrames({0, 1, 2});
    expect(order(c), hasLength(3), reason: 'a frame always stays');
    c.undo();
    expect(order(c), hasLength(5));
  });

  test('the mini Flipbook locks to edges, upright by the sides, and docks '
      'when dropped at the bottom', () {
    const workspace = Size(1000, 700), size = Size(56, 300);
    expect(
      miniFlipbookAxis(const Offset(10, 200), workspace, 0),
      Axis.vertical,
    );
    expect(
      miniFlipbookAxis(const Offset(400, 10), workspace, 0),
      Axis.horizontal,
    );
    expect(
      settleMiniFlipbook(const Offset(30, 200), workspace, size),
      const Offset(8, 200),
    );
    expect(
      settleMiniFlipbook(const Offset(930, 40), workspace, size),
      const Offset(936, 8),
    );
    expect(settleMiniFlipbook(const Offset(400, 380), workspace, size), isNull);
  });

  testWidgets('the timeline selects frames for bulk work, splits a held '
      'frame, and floats as the mini Flipbook', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.runAsync(
      () => c.replaceDocument(frames(4, holds: {'f0': 1}, painted: false)),
    );
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('frame-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frame-1')));
    await tester.tap(find.byKey(const ValueKey('frame-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frames-reverse')));
    await tester.pumpAndSettle();
    expect(order(c), ['f0', 'f3', 'f2', 'f1']);
    expect(find.byKey(const ValueKey('frames-done')), findsNothing);

    // The shown frame (f0, held) offers Split.
    await tester.tap(find.byKey(const ValueKey('frame-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frame-split')));
    await tester.pumpAndSettle();
    expect(order(c), hasLength(5));

    await tester.tap(find.byKey(const ValueKey('flipbook-mini')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('animation-bar')), findsNothing);
    expect(find.byKey(const ValueKey('mini-flipbook')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('mini-flipbook-handle')),
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();
    expect(c.miniFlipbook, isFalse);
    expect(find.byKey(const ValueKey('animation-bar')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
