import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/editor/history_change.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Future<List<int>> pixelAt(StudioController c, int x, int y) async {
  final recorder = ui.PictureRecorder();
  paintDocument(
    ui.Canvas(recorder),
    c.document,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final image = await recorder.endRecording().toImage(1024, 1024);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final i = (y * 1024 + x) * 4;
  return data!.buffer.asUint8List().sublist(i, i + 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the background colour changes and hides; the drawing and its PNG '
      'go transparent; both are saved and undone', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setBackground(0xff203040);
    expect(await pixelAt(c, 10, 10), [0x20, 0x30, 0x40, 255]);
    c.toggleBackground();
    expect(c.document.backgroundHidden, isTrue);
    expect((await pixelAt(c, 10, 10))[3], 0);

    final png = await renderDocumentPng(c.document, c.rasters.images);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data!.getUint8(3), 0, reason: 'transparent PNG');

    final back = ArtDocument.fromJson(c.document.toJson());
    expect((back.background, back.backgroundHidden), (0xff203040, true));

    final notices = <HistoryChange>[];
    c.historyNotice.addListener(() => notices.add(c.historyNotice.value!.$3));
    c.undo();
    expect(c.document.backgroundHidden, isFalse);
    expect(notices, [HistoryChange.canvas]);
  });

  testWidgets('the layers panel ends with the background, whose box hides it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setPanel(EditorPanel.layers);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Background color'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('layer-background-visible')));
    await tester.pump();
    expect(c.document.backgroundHidden, isTrue);
    await tester.tap(find.text('Background color'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-disc')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
