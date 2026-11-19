import 'dart:ui' as ui;

import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:flutter/services.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:atelier_studio/drawing/png_bands.dart';

import 'support/hub_fixture.dart';
import 'support/memory_storage.dart';

/// Drawings made by these tests use the default 1024² canvas.
const legacyExtent = 1024.0;

void main() {
  testWidgets('actual mouse drawing commits editable ink and undo removes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final shell = tester.widget(find.byType(MaterialApp));
    final board = find.byKey(const ValueKey('drawing-surface'));
    final center = tester.getCenter(board);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(center - const Offset(40, 0));
    await gesture.moveTo(center);
    await gesture.moveTo(center + const Offset(40, 0));
    await gesture.up();
    await tester.pump();
    expect(c.document.activeLayer.strokes.length, 1);
    expect(
      tester.widget(find.byType(MaterialApp)),
      same(shell),
      reason: 'drawing must not rebuild the app shell',
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(c.document.activeLayer.strokes, isEmpty);
    await c.save();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'StreamLine smooths a shaky stroke and still ends where the pen lifted',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      c.setStreamLine(.8);
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('drawing-surface'));
      final start = tester.getCenter(board) - const Offset(120, 0);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(start);
      final raw = <Offset>[];
      for (var i = 1; i <= 60; i++) {
        final point = start + Offset(i * 4.0, i.isEven ? 6 : -6);
        raw.add(point);
        await gesture.moveTo(point, timeStamp: Duration(milliseconds: i * 8));
      }
      await gesture.up();
      await tester.pump();
      final stroke = c.document.activeLayer.strokes.single;
      final box = tester.getRect(board);
      final scale = legacyExtent / box.width;
      final end = (raw.last - box.topLeft) * scale;
      expect(stroke.points.last.x, closeTo(end.dx, 1e-6));
      expect(stroke.points.last.y, closeTo(end.dy, 1e-6));
      final middle = stroke.points[30];
      final centerline = (start.dy - box.top) * scale;
      expect((middle.y - centerline).abs(), lessThan(6 * scale * .3));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'the eyedropper picks the colour shown and returns to the brush',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      c.selectColor(0xffd0302a);
      c.setSize(60);
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('drawing-surface'));
      final center = tester.getCenter(board);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(center - const Offset(60, 0));
      await gesture.moveTo(center, timeStamp: const Duration(milliseconds: 20));
      await gesture.moveTo(
        center + const Offset(60, 0),
        timeStamp: const Duration(milliseconds: 40),
      );
      await gesture.up();
      await tester.pump();
      c.selectColor(0xff000000);

      await tester.tap(find.byTooltip('Eyedropper'));
      await tester.pump();
      expect(c.tool, StudioTool.eyedropper);
      final pick = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pick.down(center);
      await settle(tester, () => c.pickColor != null);
      expect(c.pickPoint, isNotNull);
      await pick.up();
      await tester.pump();
      expect(c.color, 0xffd0302a);
      expect(c.tool, StudioTool.brush);
      expect(c.pickPoint, isNull);
      expect(c.document.activeLayer.strokes, hasLength(1));

      // Option/Alt + click picks without leaving the brush; a quick tap still
      // picks once the canvas has been read.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(tester.getRect(board).topLeft + const Offset(8, 8));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await settle(tester, () => c.pickPoint == null);
      expect(c.color, c.document.background);
      expect(c.tool, StudioTool.brush);
      expect(c.document.activeLayer.strokes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('a pen stroke may start beside the canvas and draw once it '
      'enters; the sidebar never draws', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final outside = Offset(canvas.right + 30, canvas.center.dy);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('drawing-workspace')))
          .contains(outside),
      isTrue,
    );
    await pen.down(outside);
    await pen.moveTo(canvas.center + const Offset(120, 0));
    await pen.moveTo(canvas.center);
    await pen.up();
    await tester.pump();
    final stroke = c.document.activeLayer.strokes.single;
    final scale = legacyExtent / canvas.width;
    expect(stroke.points.first.x, greaterThan(legacyExtent));
    expect(stroke.points.last.x, closeTo(legacyExtent / 2, 1));
    expect(
      stroke.points.last.y,
      closeTo((canvas.center.dy - canvas.top) * scale, 1),
    );

    final sidebarSlider = find.byType(Slider).first;
    final onSidebar = tester.getCenter(sidebarSlider);
    final second = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await second.down(onSidebar + const Offset(0, 30));
    await second.moveTo(canvas.center);
    await second.up();
    await tester.pump();
    expect(c.document.activeLayer.strokes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a resting hand never cancels or adds to a pen stroke', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('drawing-surface')),
    );
    final pen = await tester.createGesture(
      kind: PointerDeviceKind.stylus,
      pointer: 21,
    );
    await pen.down(center - const Offset(60, 0));
    await pen.moveTo(center - const Offset(20, 0));
    // Two palm contacts land mid-stroke and move a little.
    final palmA = await tester.createGesture(pointer: 22);
    final palmB = await tester.createGesture(pointer: 23);
    await palmA.down(center + const Offset(80, 120));
    await palmB.down(center + const Offset(110, 140));
    await palmA.moveTo(center + const Offset(90, 125));
    await pen.moveTo(center + const Offset(60, 0));
    await pen.up();
    await palmA.up();
    await palmB.up();
    await tester.pump();
    expect(c.document.activeLayer.strokes, hasLength(1));
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.canUndo, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'transform drag, two-finger scaling and rotation work without creating ink',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      c.beginStroke(const InkPoint(400, 400, .5), simulatePressure: false);
      c.appendPoint(const InkPoint(600, 400, .5));
      c.finishStroke();
      final source = c.document;
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Transform layer'));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('drawing-surface'));
      final center = tester.getCenter(board) - const Offset(0, 80);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(center);
      await gesture.moveTo(center + const Offset(25, 0));
      await tester.pump();
      await gesture.moveTo(center + const Offset(85, 0));
      await gesture.up();
      await tester.pump();
      expect(c.transformDraft!.translation.dx, greaterThan(80));
      expect(c.document, same(source));
      await tester.tap(find.byTooltip('Reset'));
      await tester.pump();
      final resizeCorner =
          tester.getTopLeft(board) +
          c.transformDraft!.corners[1] *
              (tester.getSize(board).width / legacyExtent);
      final resize = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 3,
      );
      await resize.down(resizeCorner);
      await resize.moveTo(resizeCorner + const Offset(25, 0));
      await resize.moveTo(resizeCorner + const Offset(100, 0));
      await resize.up();
      await tester.pump();
      expect(c.transformDraft!.scale, greaterThan(1.5));
      await tester.tap(find.byTooltip('Reset'));
      await tester.pump();
      final first = await tester.createGesture(pointer: 10);
      final second = await tester.createGesture(pointer: 11);
      await first.down(center - const Offset(50, 0));
      await second.down(center + const Offset(50, 0));
      await first.moveTo(center - const Offset(100, 0));
      await second.moveTo(center + const Offset(100, 0));
      await tester.pump();
      expect(c.transformDraft!.scale, greaterThan(1.8));
      await second.moveTo(center + const Offset(100, 60));
      await tester.pump();
      expect(c.transformDraft!.rotation.abs(), greaterThan(.15));
      await first.up();
      await second.up();
      expect(c.document, same(source));
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(c.transformDraft, isNull);
      expect(c.document.activeLayer.strokes, hasLength(1));
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'rectangle and lasso selection gestures, palm separation and layer masking are usable',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      c.setFingerDrawing(false);
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selection'));
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('drawing-surface'));
      Offset point(double x, double y) =>
          tester.getTopLeft(board) +
          Offset(x, y) * (tester.getSize(board).width / legacyExtent);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(point(256, 200));
      await mouse.moveTo(point(768, 500));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c.selection!.path.contains(const Offset(512, 350)), isTrue);
      expect(c.document.activeLayer.strokes, isEmpty);
      final rectangle = c.selection;
      await tester.tap(find.byKey(const ValueKey('selection-done')));
      await tester.pumpAndSettle();
      await mouse.down(point(100, 350));
      await mouse.moveTo(point(900, 350));
      await mouse.up();
      await tester.pump();
      expect(c.document.activeLayer.strokes.single.clip, same(rectangle));
      await tester.tap(find.byTooltip('Selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Freehand'));
      await tester.pump();
      final pen = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
        pointer: 3,
      );
      await pen.down(point(400, 200));
      await pen.moveTo(point(700, 200));
      await pen.moveTo(point(550, 500));
      await pen.up();
      await tester.pumpAndSettle();
      expect(c.selection!.points, hasLength(3));
      expect(c.selection!.path.contains(const Offset(550, 300)), isTrue);
      final triangle = c.selection;
      final finger = await tester.createGesture(pointer: 10);
      final palm = await tester.createGesture(pointer: 11);
      await finger.down(point(300, 200));
      await finger.moveTo(point(500, 350));
      expect(c.selectionDrawing, isTrue);
      await palm.down(point(700, 350));
      await finger.up();
      await palm.up();
      await tester.pumpAndSettle();
      expect(c.selectionDrawing, isFalse);
      expect(c.selection, same(triangle));
      await tester.tap(find.byKey(const ValueKey('selection-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layer mask'));
      await tester.pumpAndSettle();
      expect(c.document.activeLayer.mask, same(triangle));
      expect(c.selection, isNull);
      await tester.tap(find.byTooltip('Selection'));
      await tester.pumpAndSettle();
      c.setSelection(rectangle);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.selection, isNull);
      expect(c.tool, StudioTool.brush);
      await c.save();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('AI stays behind LocalHub pairing and never calls the hub '
      'unpaired', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hub = fakeHub();
    final client = hub.client as FakeHubClient;
    final c = StudioController(storage: MemoryStorage(), hub: hub);
    await c.initialize();
    c.setPanel(EditorPanel.connections);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Pair device'), findsOneWidget);
    expect(find.text('Repaint selection'), findsNothing);
    expect(find.text('Files on the hub'), findsNothing);
    expect(client.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('generative fill sends only the selection\'s surroundings, '
      'puts each variation on one masked layer, and the panel keeps files '
      'and the assistant', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hub = fakeHub(
      session: fakeHubSession(scopes: ['chat', 'image.edit']),
      models: [
        {
          'id': 'comfyui/inpaint',
          'capabilities': ['image.edit'],
        },
        {
          'id': 'lmstudio/qwen',
          'capabilities': ['chat'],
        },
      ],
    );
    final client = hub.client as FakeHubClient;
    client.stored.add({
      'id': 'file-1',
      'filename': 'reference.png',
      'bytes': 2048,
      'mime_type': 'image/png',
      'source': 'upload',
      'created_at': 1,
    });
    client.contents['file-1'] = encodeRgbaPng(Uint8List(16 * 16 * 4), 16, 16);
    await hub.refresh();
    final c = StudioController(storage: MemoryStorage(), hub: hub);
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(Durations.short1));
        await tester.pump();
      }
      expect(done(), isTrue);
      await tester.pump();
    }

    int pngSide(Uint8List png, int offset) =>
        ByteData.sublistView(png).getUint32(offset);

    c.selectTool(StudioTool.selection);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(256, 256, 512, 512)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-generative-fill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('generative-bar')), findsOneWidget);
    // Keywords become a detailed prompt from the chat model, streamed in.
    await tester.enterText(
      find.byKey(const ValueKey('generative-prompt')),
      'kaplan, gerçekçi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('generative-write')));
    // The area is rendered for the model first: real time for the image.
    for (
      var i = 0;
      i < 100 && find.text('Try hatching.').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(Durations.short1));
      await tester.pump();
    }
    expect(find.text('Try hatching.'), findsOneWidget);
    expect(client.lastChat!.first['content'], contains('image generation'));
    expect(client.lastChat!.first['content'], contains('selected area'));
    // With a selection the model also sees the area, outlined.
    final asked = client.lastChat!.last['content'] as List;
    expect((asked.first as Map)['text'], startsWith('kaplan, gerçekçi'));
    expect(
      ((asked.last as Map)['image_url'] as Map)['url'],
      startsWith('data:image/png;base64,'),
    );
    // A model that reads no images is asked again with words only.
    client.rejectImages = true;
    await tester.enterText(
      find.byKey(const ValueKey('generative-prompt')),
      'kaplan',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('generative-write')));
    for (
      var i = 0;
      i < 100 && client.lastChat!.last['content'] != 'kaplan';
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(Durations.short1));
      await tester.pump();
    }
    expect(client.lastChat!.last['content'], 'kaplan');
    await tester.pumpAndSettle();
    expect(find.text('Try hatching.'), findsOneWidget);
    client.rejectImages = false;
    expect(client.lastChatBody!['max_tokens'], greaterThanOrEqualTo(2048));
    await tester.enterText(
      find.byKey(const ValueKey('generative-prompt')),
      'A real tiger',
    );
    await tester.tap(find.byKey(const ValueKey('generative-run')));
    await until(() => client.lastEdit != null || c.hubJob.error != null);
    expect(c.hubJob.error, isNull);
    expect(client.lastEdit!['prompt'], 'A real tiger');
    // The selection plus 15% context, at about a megapixel; never the canvas.
    final sent = client.lastImage!.bytes!;
    // One image, the selection in its alpha: works with or without a mask
    // input in the workflow.
    expect(client.lastMask, isNull);
    final area = c.hubJob.source!.area;
    expect(area, const Rect.fromLTRB(179, 179, 845, 845));
    expect((pngSide(sent, 16), pngSide(sent, 20)), (1024, 1024));
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(sent);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      return data!;
    });
    int alphaAt(int x, int y) => decoded!.getUint8((y * 1024 + x) * 4 + 3);
    expect(alphaAt(512, 512), 0, reason: 'selection: repaint');
    expect(alphaAt(10, 10), 255, reason: 'context: keep');

    client.jobs.add({'id': 'job-1', 'status': 'in_progress', 'progress': .5});
    await tester.pump();
    expect(find.textContaining('Generating on the Mac…'), findsOneWidget);

    final layers = c.document.layers.length;
    Future<void> deliver(String file, int shade) async {
      final rgba = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, shade);
      client.contents[file] = encodeRgbaPng(rgba, 64, 64);
      client.jobs.add({
        'id': 'job-1',
        'status': 'completed',
        'progress': 1,
        'output_file_ids': [file],
      });
    }

    await deliver('out-1', 200);
    await until(() => c.hubJob.pending && !c.hubJob.busy);
    expect(c.document.layers.length, layers + 1);
    final layer = c.document.activeLayer;
    expect(layer.id, c.hubJob.layerId);
    expect(layer.mask, isNotNull);
    expect(layer.name, 'A real tiger');
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('generative-more')));
    await until(() => c.hubJob.busy);
    await deliver('out-2', 90);
    await until(() => c.hubJob.variations.length == 2 && !c.hubJob.busy);
    expect(c.document.layers.length, layers + 1, reason: 'one layer');
    expect(find.text('2 / 2'), findsOneWidget);
    final second = c.document.activeLayer.raster;
    await tester.tap(find.byTooltip('Previous variation'));
    await until(() => c.document.activeLayer.raster != second);
    await tester.tap(find.byKey(const ValueKey('generative-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('generative-bar')), findsNothing);
    expect(c.document.layers.length, layers + 1);

    c.selectTool(StudioTool.brush);
    c.setPanel(EditorPanel.connections);
    await tester.pumpAndSettle();
    expect(find.text('Paired with Unit Mac'), findsOneWidget);
    final ask = find.widgetWithText(
      TextField,
      'Ask about color, composition or your next idea…',
    );
    await tester.enterText(ask, 'How do I shade?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Try hatching.'), findsOneWidget);
    expect(client.lastChat!.first['role'], 'system');
    expect(client.lastChat!.last['content'], 'How do I shade?');
    // A provider failing mid-stream is shown, not left as an empty answer.
    client.chatError = 'Insufficient GPU memory';
    await tester.enterText(ask, 'And blending?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Insufficient GPU memory'), findsOneWidget);
    expect(find.text('…'), findsNothing);

    await tester.tap(find.text('Files'));
    await tester.runAsync(() => Future<void>.delayed(Durations.short2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hub-file-file-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(client.calls, contains('delete file-1'));
    expect(find.text('reference.png'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'tablet and compact layouts keep every panel usable in TR/EN and themes',
    (tester) async {
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(1024, 768), const Size(320, 740)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(StudioApp(controller: c));
        await tester.pumpAndSettle();
        c.beginStroke(const InkPoint(300, 300, .5), simulatePressure: false);
        c.finishStroke();
        expect(c.beginTransform(), isTrue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Transform at $size');
        c.cancelTransform();
        await tester.pumpAndSettle();
        c.selectTool(StudioTool.selection);
        c.setSelection(
          SelectionRegion.rectangle(const Rect.fromLTWH(200, 200, 500, 400)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Selection at $size');
        if (size.width < 480) {
          // Every action stays reachable as an icon, even on a phone.
          await tester.tap(find.byKey(const ValueKey('selection-invert')));
          await tester.pumpAndSettle();
          expect(c.selection!.inverted, isTrue);
        }
        c.setSelection(null);
        c.selectTool(StudioTool.brush);
        await tester.pumpAndSettle();
        for (final panel in EditorPanel.values) {
          c.setPanel(panel);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$panel at $size');
          if (panel == EditorPanel.layers) {
            await tester.tap(
              find.byKey(ValueKey('layer-blend-${c.document.activeLayerId}')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('blend-dropdown')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Multiply').last);
            await tester.pumpAndSettle();
            expect(c.document.activeLayer.blend, LayerBlend.multiply);
            c.undo();
            await tester.pumpAndSettle();
          }
          c.setPanel(null);
          await tester.pumpAndSettle();
        }
        c.setLanguage('tr');
        c.setTheme(ThemeMode.dark);
        await tester.pumpAndSettle();
        expect(find.text('Galeri'), findsOneWidget);
        c.setLanguage('en');
        c.setTheme(ThemeMode.light);
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
