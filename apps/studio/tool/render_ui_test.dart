import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:atelier_studio/editor/brush_studio.dart';
import 'package:atelier_studio/drawing/guides.dart';
import 'package:atelier_studio/drawing/liquify.dart';
import 'package:atelier_studio/drawing/layer_transform.dart';
import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/domain/canvas_preset.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/editor_screen.dart';
import 'package:atelier_studio/domain/gallery.dart';
import 'package:atelier_studio/drawing/symmetry.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/hub_fixture.dart';
import '../test/support/memory_storage.dart';

Future<Uint8List> landscape() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xfff4e9d7), ui.BlendMode.src);
  canvas.drawCircle(
    const ui.Offset(335, 110),
    65,
    ui.Paint()..color = const ui.Color(0xffdc946d),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 240)
      ..lineTo(160, 110)
      ..lineTo(290, 248)
      ..lineTo(415, 160)
      ..lineTo(512, 260)
      ..lineTo(512, 512)
      ..lineTo(0, 512)
      ..close(),
    ui.Paint()..color = const ui.Color(0xff87a297),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 310)
      ..cubicTo(150, 210, 260, 440, 512, 270)
      ..lineTo(512, 512)
      ..lineTo(0, 512)
      ..close(),
    ui.Paint()..color = const ui.Color(0xff326c70),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 430)
      ..cubicTo(190, 300, 340, 490, 512, 390)
      ..lineTo(512, 512)
      ..lineTo(0, 512)
      ..close(),
    ui.Paint()..color = const ui.Color(0xff234b4c),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 512);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets(
    'render actual ArtBlend raster and layer controls without user data',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final config = File('.dart_tool/package_config.json');
        final packages =
            (jsonDecode(await config.readAsString()) as Map)['packages']
                as List;
        final flutter =
            packages.firstWhere((p) => p['name'] == 'flutter') as Map;
        final packageDirectory = Directory.fromUri(
          config.absolute.uri.resolve(flutter['rootUri'] as String),
        );
        final fontFile = File.fromUri(
          packageDirectory.uri.resolve(
            '../../bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ),
        );
        final roboto = FontLoader(
          'Roboto',
        )..addFont(fontFile.readAsBytes().then((b) => ByteData.sublistView(b)));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await roboto.load();
        await icons.load();
      });
      // Paired with a hub in memory, so the AI panel is shown; nothing
      // leaves the test.
      final hub = fakeHub(
        session: fakeHubSession(),
        models: [
          {
            'id': 'comfyui/inpaint',
            'capabilities': ['image.edit', 'image.create'],
          },
          {
            'id': 'lmstudio/qwen',
            'capabilities': ['chat'],
          },
        ],
      );
      await tester.runAsync(hub.refresh);
      final c = StudioController(storage: MemoryStorage(), hub: hub);
      await c.initialize();
      await tester.runAsync(() async {
        await c.addImageLayer(await landscape(), 'Dağların ardında');
      });
      c.renameDocument('Sessiz vadi');
      c.setLanguage('tr');
      c.setTheme(ThemeMode.dark);
      await c.save();
      const key = ValueKey('qa-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: StudioApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File('../../.qa/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await capture('artblend-canvas');
      c.setPanel(EditorPanel.layers);
      await tester.pumpAndSettle();
      expect(find.text('Dağların ardında'), findsOneWidget);
      await capture('artblend-layers');
      c.setPanel(EditorPanel.connections);
      await tester.pumpAndSettle();
      await capture('artblend-ai');
      expect(c.beginTransform(), isTrue);
      c.previewTransform(
        c.transformDraft!.copyWith(
          scale: .72,
          rotation: -.18,
          translation: const Offset(80, -70),
        ),
      );
      await tester.pumpAndSettle();
      await capture('artblend-transform');
      c.cancelTransform();
      c.selectTool(StudioTool.selection);
      c.setSelectionShape(SelectionShape.freehand);
      c.setSelection(
        SelectionRegion.lasso(const [
          Offset(220, 140),
          Offset(750, 200),
          Offset(840, 620),
          Offset(340, 810),
        ]),
      );
      await tester.pumpAndSettle();
      await capture('artblend-selection');
      c.maskLayerFromSelection();
      c.setPanel(EditorPanel.layers);
      await tester.pumpAndSettle();
      await capture('artblend-mask');
      c.setPanel(EditorPanel.connections);
      await tester.pumpAndSettle();
      await capture('artblend-hub-panel');
      c.setPanel(null);
      c.selectTool(StudioTool.selection);
      c.setSelection(c.document.activeLayer.mask);
      c.hubJob.show();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('generative-prompt')),
        'Sisli mavi dağlar, yumuşak ışık',
      );
      await tester.pumpAndSettle();
      await capture('artblend-generative-ask');
      final client = hub.client as FakeHubClient;
      await tester.tap(find.byKey(const ValueKey('generative-run')));
      for (var i = 0; i < 300 && client.lastEdit == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(Durations.short1));
        await tester.pump();
      }
      client.jobs.add({
        'id': 'job-1',
        'status': 'in_progress',
        'progress': .4,
        'current_node': 'KSampler 8/20',
        'eta_seconds': 50,
      });
      await tester.pump();
      await capture('artblend-generative-progress');
      await tester.runAsync(() async {
        client.contents['out'] = await landscape();
      });
      client.jobs.add({
        'id': 'job-1',
        'status': 'completed',
        'output_file_ids': ['out'],
      });
      for (var i = 0; i < 300 && !c.hubJob.pending; i++) {
        await tester.runAsync(() => Future<void>.delayed(Durations.short1));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await capture('artblend-generative-result');
      c.hubJob.done();
      await c.save();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('render native MyPaint strokes and the brush library', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setLanguage('tr');
    c.setTheme(ThemeMode.light);
    // Real native strokes; runAsync keeps the worker and queue on real time.
    await tester.runAsync(() async {
      final strokes = [
        ('mypaint-charcoal', 0xff2b3034, 30.0, 1.0),
        ('mypaint-modelling', 0xffbc6261, 46.0, .8),
        ('mypaint-charcoal', 0xff346b70, 18.0, .55),
        ('mypaint-modelling', 0xffedc6a3, 70.0, .45),
      ];
      for (var s = 0; s < strokes.length; s++) {
        final (id, color, size, opacity) = strokes[s];
        c.selectBrush(initialBrushes.firstWhere((b) => b.id == id));
        c.selectColor(color);
        c.setSize(size);
        c.setOpacity(opacity);
        var t = Duration(seconds: 10 * s);
        double y(double x) => 260 + s * 150 + math.sin(x / 90 + s) * 70;
        c.beginStroke(
          InkPoint(120, y(120), .3),
          simulatePressure: false,
          time: t,
        );
        for (var x = 124.0; x <= 900; x += 4) {
          t += const Duration(milliseconds: 8);
          final pressure = .25 + .7 * math.sin(math.pi * (x - 120) / 780);
          c.appendPoint(InkPoint(x, y(x), pressure), time: t);
        }
        c.finishStroke();
      }
    });
    // Commits hop between real isolates and the test zone; let both run.
    for (var i = 0; i < 400 && c.strokeBusy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(c.document.activeLayer.raster, isNotNull);
    const key = ValueKey('qa-native');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('../../.qa/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await capture('artblend-native-canvas');
    c.setPanel(EditorPanel.brushes);
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.text('Kömür'), findsOneWidget);
    expect(find.byType(RawImage), findsWidgets);
    await capture('artblend-native-brushes');
    c.setPanel(EditorPanel.brushes);
    c.selectTool(StudioTool.eyedropper);
    c.beginPick(Offset(500, 260 + 150 + math.sin(500 / 90 + 1) * 70));
    for (var i = 0; i < 40 && c.pickColor == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(c.pickColor, isNotNull);
    await capture('artblend-eyedropper');
    c.cancelPick();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('render textured stamp brushes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setLanguage('tr');
    c.setTheme(ThemeMode.light);
    await tester.runAsync(() async {
      final strokes = [
        ('stamp-graphite', 0xff2b3034, 10.0),
        ('stamp-pastel', 0xffbc6261, 56.0),
        ('stamp-dry-brush', 0xff346b70, 60.0),
        ('stamp-gouache', 0xffe0a040, 48.0),
        ('stamp-splatter', 0xff6b4a9a, 70.0),
      ];
      for (var s = 0; s < strokes.length; s++) {
        final (id, color, size) = strokes[s];
        c.selectBrush(initialBrushes.firstWhere((b) => b.id == id));
        c.selectColor(color);
        c.setSize(size);
        var t = Duration(seconds: 10 * s);
        double y(double x) => 130 + s * 180 + math.sin(x / 90 + s) * 50;
        c.beginStroke(
          InkPoint(120, y(120), .3),
          simulatePressure: false,
          time: t,
        );
        for (var x = 124.0; x <= 900; x += 4) {
          t += const Duration(milliseconds: 8);
          final pressure = .25 + .7 * math.sin(math.pi * (x - 120) / 780);
          c.appendPoint(InkPoint(x, y(x), pressure), time: t);
        }
        c.finishStroke();
      }
    });
    for (var i = 0; i < 400 && c.strokeBusy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    const key = ValueKey('qa-stamp');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('../../.qa/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await capture('artblend-stamp-canvas');
    c.setPanel(EditorPanel.brushes);
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await capture('artblend-stamp-brushes');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('render symmetry and the drawing guide', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setLanguage('tr');
    c.setTheme(ThemeMode.dark);
    c.setSymmetry(SymmetryKind.radial);
    c.setGrid(visible: true, size: 128);
    await tester.runAsync(() async {
      c.selectBrush(
        initialBrushes.firstWhere((b) => b.id == 'stamp-dry-brush'),
      );
      c.selectColor(0xffd06a3a);
      c.setSize(40);
      var t = const Duration(seconds: 1);
      c.beginStroke(
        const InkPoint(560, 380, .3),
        simulatePressure: false,
        time: t,
      );
      for (var i = 1; i <= 60; i++) {
        t += const Duration(milliseconds: 8);
        final a = i / 60 * math.pi;
        c.appendPoint(
          InkPoint(
            560 + 180 * math.sin(a),
            380 - 120 * math.sin(a * 2),
            .3 + .6 * math.sin(a),
          ),
          time: t,
        );
      }
      c.finishStroke();
    });
    for (var i = 0; i < 400 && c.strokeBusy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    const key = ValueKey('qa-guide');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('../../.qa/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await capture('artblend-symmetry');
    c.setPanel(EditorPanel.actions);
    await tester.pumpAndSettle();
    await capture('artblend-guide-panel');
    c.setPanel(EditorPanel.colors);
    await tester.pumpAndSettle();
    await capture('artblend-color-disc');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('render adjustments', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.setLanguage('tr');
    c.setTheme(ThemeMode.dark);
    await tester.runAsync(() async {
      c.selectColor(0xff3a7bd5);
      c.setSelection(
        SelectionRegion.ellipse(const Rect.fromLTWH(200, 200, 600, 600)),
      );
      await c.fillActiveLayer();
      c.setSelection(null);
    });
    const key = ValueKey('qa-adjust');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StudioApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pump();
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('../../.qa/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    c.setPanel(EditorPanel.adjustments);
    await tester.pumpAndSettle();
    await capture('artblend-adjust-menu');
    await tester.runAsync(() async {
      await c.startAdjustment(AdjustmentKind.curves);
      for (var i = 0; i < 50 && c.adjustment!.histogram == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    c.setAdjustment(
      c.adjustment!.adjustment.withCurve(CurveChannel.gamma, const [
        Offset.zero,
        Offset(.3, .55),
        Offset(.7, .8),
        Offset(1, 1),
      ]),
    );
    await capture('artblend-adjust-curves');
    await tester.runAsync(() => c.startAdjustment(AdjustmentKind.gradientMap));
    c.setAdjustment(
      c.adjustment!.adjustment.withGradient(GradientPreset.sunset.stops),
    );
    await capture('artblend-adjust-gradient');
    await tester.runAsync(() => c.startAdjustment(AdjustmentKind.colorBalance));
    await capture('artblend-adjust-balance');
    await tester.runAsync(
      () => c.startAdjustment(AdjustmentKind.perspectiveBlur),
    );
    c.moveAdjustmentCentre(const Offset(420, 380));
    c.setAdjustmentValue('amount', .5);
    c.setAdjustmentValue('directional', 1);
    c.setAdjustmentValue('angle', .1);
    await capture('artblend-adjust-perspective');
    c.cancelAdjustment();
    c.setTransformMode(TransformMode.warp);
    c.beginTransform();
    c.previewTransform(
      c.transformDraft!.warped(.5, .3, const Offset(160, -90)),
    );
    await tester.pumpAndSettle();
    await capture('artblend-transform-warp');
    c.setTransformMode(TransformMode.freeform);
    c.cancelTransform();
    c.setTransformMode(TransformMode.distort);
    c.beginTransform();
    c.previewTransform(c.transformDraft!.withCorner(1, const Offset(980, 120)));
    await tester.pumpAndSettle();
    await capture('artblend-transform-distort');
    c.cancelTransform();
    c.setTransformMode(TransformMode.uniform);
    c.addLayer('Gölge');
    c.addLayer('Işık');
    c.addLayer('Çizgi');
    c.groupLayers(
      'Boyama',
      ids: [c.document.layers[1].id, c.document.layers[2].id],
    );
    c.updateGroup(c.document.groups.single.id, (g) => g.copyWith(opacity: .7));
    c.selectLayer(c.document.layers.last.id);
    c.toggleLayerChoice(c.document.layers[1].id);
    c.setPanel(EditorPanel.layers);
    await tester.pumpAndSettle();
    await capture('artblend-layer-groups');
    c.setPanel(null);
    c.selectLayer(c.document.layers.first.id);
    await tester.runAsync(() => c.startLiquify());
    c.setLiquify(mode: LiquifyMode.twirlRight, size: .35, pressure: .8);
    c.beginLiquify(const Offset(500, 450), 1);
    for (var i = 0; i < 25; i++) {
      c.liquify!.hold();
    }
    c.endLiquify();
    c.setLiquify(mode: LiquifyMode.push);
    c.beginLiquify(const Offset(700, 650), 1);
    c.moveLiquify(const Offset(820, 760), 1);
    c.endLiquify();
    await tester.pumpAndSettle();
    await capture('artblend-liquify');
    c.cancelLiquify();
    c.selectTool(StudioTool.selection);
    c.setSelection(
      SelectionRegion.ellipse(const Rect.fromLTWH(300, 300, 400, 300)),
    );
    await tester.pumpAndSettle();
    await capture('artblend-selection-bar');
    c.setSelection(null);
    c.selectTool(StudioTool.brush);
    c.setGuide(
      const DrawingGuide(
        kind: GuideKind.perspective,
        vanishing: [Offset(.15, .35), Offset(.85, .35)],
        color: 0xffe0602f,
        opacity: .45,
      ),
    );
    c.setSymmetry(SymmetryKind.vertical);
    c.setGuideEditing(true);
    await tester.pumpAndSettle();
    await capture('artblend-guide-perspective');
    c.setGuideEditing(false);
    c.setSymmetry(SymmetryKind.off);
    c.setGuide(const DrawingGuide());
    c.selectColor(0xfff2c14e);
    c.addText('ArtBlend\nmetin katmanı');
    c.setText((t) => t.copyWith(weight: 700, outline: false));
    await tester.pumpAndSettle();
    await capture('artblend-text');
    c.finishText();
    await tester.pumpAndSettle();
    final storage = c.storage as MemoryStorage;
    await tester.runAsync(() async {
      await c.save();
      for (final name in ['Kedi eskizi', 'Portre', 'Manzara', 'Doku']) {
        await storage.saveToGallery(
          c.document.copyWith(id: newId(), name: name),
        );
      }
      final ids = storage.documents.keys.toList();
      await storage.saveGallery(
        GalleryLayout()
            .stackUp(newId(), 'Eskizler', ids.sublist(1, 3), ids)
            .toJson(),
      );
    });
    c.setPanel(EditorPanel.gallery);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await capture('artblend-gallery');
    c.setPanel(null);
    await tester.pumpAndSettle();
    c.toggleReference(true);
    await tester.pumpAndSettle();
    await capture('artblend-reference');
    c.toggleReference(false);
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(Scaffold).first);
    c.saveCanvasPreset(
      const CanvasPreset(
        id: 'card',
        name: 'Kartpostal',
        width: 15,
        height: 10,
        unit: CanvasUnit.cm,
        dpi: 300,
      ),
    );
    unawaited(
      showDialog<void>(
        context: ctx,
        builder: (_) =>
            NewDocumentDialog(screen: const Size(2560, 1600), controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-a4')));
    await tester.pumpAndSettle();
    await capture('artblend-new-canvas');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    unawaited(
      showBrushStudio(
        ctx,
        c,
        initialBrushes.firstWhere((b) => b.id == 'stamp-pastel'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await capture('artblend-brush-studio');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
