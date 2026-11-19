import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/asset_importer.dart';
import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Offset, Size, SizedBox, ValueKey;

import 'support/memory_storage.dart';

final charcoal = initialBrushes.firstWhere((b) => b.id == 'mypaint-charcoal');

Future<StudioController> nativeController([StudioStorage? storage]) async {
  final c = StudioController(storage: storage ?? MemoryStorage());
  await c.initialize();
  c.selectBrush(charcoal);
  c.setSize(24);
  c.selectColor(0xffd02020);
  return c;
}

/// Raw layer pixels before mask, opacity and blend, straight RGBA.
Future<Uint8List> raw(StudioController c, [String? layerId]) async {
  final layer = c.document.layers.firstWhere(
    (l) => l.id == (layerId ?? c.document.activeLayerId),
  );
  return (await renderNativeBase(
    layer,
    c.document.grid,
    c.rasters.images,
  )).rgba;
}

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

/// Painted rows in one column: a proxy for stroke width.
int coverage(Uint8List rgba, int x) {
  var n = 0;
  for (var y = 0; y < 1024; y++) {
    if (alphaAt(rgba, x, y) > 32) n++;
  }
  return n;
}

void line(
  StudioController c,
  double x1,
  double x2,
  double y, {
  double pressure = .8,
  bool finish = true,
}) {
  var t = const Duration(seconds: 1);
  expect(
    c.beginStroke(
      InkPoint(x1, y, pressure),
      simulatePressure: false,
      tiltX: .3,
      tiltY: -.2,
      time: t,
    ),
    isTrue,
  );
  for (var x = x1 + 4; x <= x2; x += 4) {
    t += const Duration(milliseconds: 8);
    c.appendPoint(InkPoint(x, y, pressure), tiltX: .3, tiltY: -.2, time: t);
  }
  if (finish) c.finishStroke();
}

Future<ArtDocument> withInk(StudioController c) async {
  // A legacy vector stroke, so the first native stroke must bake it exactly.
  c.selectBrush(initialBrushes.first);
  c.setSize(40);
  c.selectColor(0x80204080);
  c.beginStroke(const InkPoint(100, 800, .5), simulatePressure: false);
  c.appendPoint(const InkPoint(900, 800, .5));
  c.finishStroke();
  c.selectBrush(charcoal);
  c.setSize(24);
  c.selectColor(0xffd02020);
  return c.document;
}

class RecordingController extends StudioController {
  RecordingController() : super(storage: MemoryStorage());
  final tilts = <(double, double)>[];
  final times = <Duration?>[];
  @override
  bool beginStroke(
    InkPoint point, {
    required bool simulatePressure,
    double tiltX = 0,
    double tiltY = 0,
    Duration? time,
    StudioTool? as,
  }) {
    tilts.add((tiltX, tiltY));
    times.add(time);
    return super.beginStroke(
      point,
      simulatePressure: simulatePressure,
      tiltX: tiltX,
      tiltY: tiltY,
      time: time,
      as: as,
    );
  }

  @override
  void appendPoint(
    InkPoint point, {
    double tiltX = 0,
    double tiltY = 0,
    Duration? time,
  }) {
    tilts.add((tiltX, tiltY));
    times.add(time);
    super.appendPoint(point, tiltX: tiltX, tiltY: tiltY, time: time);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stylus pointer events draw a native stroke with tilt, preview and one undo',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = RecordingController();
      await c.initialize();
      c.selectBrush(charcoal);
      await tester.pumpWidget(StudioApp(controller: c));
      await tester.pump();
      final board = find.byKey(const ValueKey('drawing-surface'));
      final start = tester.getCenter(board) - const Offset(60, 0);
      var t = const Duration(seconds: 10);
      tester.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: 7,
          kind: PointerDeviceKind.stylus,
          position: start,
          pressure: .7,
          pressureMax: 1,
          tilt: math.pi / 4,
          orientation: math.pi / 2,
          timeStamp: t,
        ),
      );
      for (var i = 1; i <= 30; i++) {
        t += const Duration(milliseconds: 8);
        tester.binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: 7,
            kind: PointerDeviceKind.stylus,
            position: start + Offset(i * 4, 0),
            pressure: .7,
            pressureMax: 1,
            tilt: math.pi / 4,
            orientation: math.pi / 2,
            timeStamp: t,
          ),
        );
      }
      // Queue continuations live in the fake-async zone: alternate real time
      // for the worker isolate with pumps that flush those microtasks.
      Future<void> waitFor(bool Function() done) async {
        for (var i = 0; i < 200 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await waitFor(() => c.nativePreview?.tiles.isNotEmpty == true);
      expect(c.nativePreview?.tiles, isNotEmpty);
      tester.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: 7,
          kind: PointerDeviceKind.stylus,
          position: start + const Offset(120, 0),
          timeStamp: t,
        ),
      );
      await waitFor(() => !c.strokeBusy);
      await tester.pump();
      // 45° tilt pointing right: half of full tilt along +x, none along y.
      expect(c.tilts.first.$1, closeTo(.5, 1e-6));
      expect(c.tilts.first.$2, closeTo(0, 1e-6));
      expect(c.times.first, const Duration(seconds: 10));
      final raster = c.document.activeLayer.raster;
      expect(raster, isNotNull);
      expect(c.canUndo, isTrue);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(c.document.activeLayer.raster, isNull);
      expect(c.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('a native stroke paints raw layer pixels as one undo step and keeps untouched pixels exact', () async {
    final c = await nativeController();
    addTearDown(c.dispose);
    final before = await withInk(c);
    final source = await raw(c);
    line(c, 100, 900, 300);
    expect(c.strokeBusy, isTrue);
    await c.settleStroke();
    expect(c.strokeBusy, isFalse);
    final layer = c.document.activeLayer;
    expect(layer.raster!.tiles, isNotEmpty);
    expect(layer.strokes, isEmpty);
    final after = await raw(c);
    expect(alphaAt(after, 500, 300), greaterThan(100));
    expect(after[(300 * 1024 + 500) * 4], greaterThan(150));
    var unchanged = 0, changedOutsideStroke = 0;
    for (var y = 0; y < 1024; y++) {
      for (var x = 0; x < 1024; x += 3) {
        final i = (y * 1024 + x) * 4;
        final same =
            after[i] == source[i] &&
            after[i + 1] == source[i + 1] &&
            after[i + 2] == source[i + 2] &&
            after[i + 3] == source[i + 3];
        if (same) unchanged++;
        if (!same && (y < 240 || y > 360)) changedOutsideStroke++;
      }
    }
    // Semi-transparent legacy ink is baked byte-identically: no round-trip drift.
    expect(changedOutsideStroke, 0);
    expect(unchanged, greaterThan(300000));
    expect(c.lastNativeStats, isNotNull);
    c.undo();
    expect(c.document, same(before));
    c.redo();
    expect(c.document.activeLayer.raster, same(layer.raster));
  });

  test('pressure and tilt reach the native brush; a tap leaves a dab', () async {
    // Deterministic presets: opacity follows exactly one input.
    String preset(String input, String curve) =>
        '{"version":3,"settings":{'
        '"opaque":{"base_value":1,"inputs":{}},'
        '"hardness":{"base_value":1,"inputs":{}},'
        '"dabs_per_actual_radius":{"base_value":2,"inputs":{}},'
        '"opaque_multiply":{"base_value":0,"inputs":{"$input":$curve}}}}';
    final c = await nativeController();
    addTearDown(c.dispose);
    c.selectBrush(
      BrushPreset(
        id: 'pressure',
        name: 'pressure',
        engine: BrushEngineKind.mypaint,
        mypaint: preset('pressure', '[[0,0],[1,1]]'),
      ),
    );
    c.setSize(24);
    line(c, 100, 900, 200, pressure: .2);
    line(c, 100, 900, 600, pressure: 1);
    c.beginStroke(
      const InkPoint(500, 900, .9),
      simulatePressure: false,
      time: const Duration(seconds: 3),
    );
    c.finishStroke();
    await c.settleStroke();
    final pixels = await raw(c);
    expect(alphaAt(pixels, 500, 200), inInclusiveRange(20, 200));
    expect(alphaAt(pixels, 500, 600), greaterThan(250));
    var dab = 0;
    for (var y = 880; y < 920; y++) {
      for (var x = 480; x < 520; x++) {
        if (alphaAt(pixels, x, y) > 0) dab++;
      }
    }
    expect(dab, greaterThan(50));

    // Opacity follows the x tilt axis: upright and tilted strokes must differ.
    Future<int> tiltedAlpha(double tilt) async {
      c.selectBrush(
        BrushPreset(
          id: 'tilt',
          name: 'tilt',
          engine: BrushEngineKind.mypaint,
          mypaint: preset('tilt_declinationx', '[[-60,1],[60,0]]'),
        ),
      );
      c.addLayer('tilt $tilt');
      await c.settleStroke();
      c.beginStroke(
        const InkPoint(100, 400, 1),
        simulatePressure: false,
        tiltX: tilt,
      );
      for (var x = 104.0; x < 900; x += 4) {
        c.appendPoint(InkPoint(x, 400, 1), tiltX: tilt);
      }
      c.finishStroke();
      await c.settleStroke();
      return alphaAt(await raw(c), 500, 400);
    }

    final upright = await tiltedAlpha(0), tilted = await tiltedAlpha(1);
    expect((upright - tilted).abs(), greaterThan(30));
  });

  test(
    'translucent native color is stored without premultiplication drift',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      c.selectColor(0xff3366cc);
      c.setOpacity(.35);
      line(c, 100, 900, 512, pressure: 1);
      await c.settleStroke();
      final pixels = await raw(c);
      var checked = 0;
      for (var x = 300; x < 700; x++) {
        final i = (512 * 1024 + x) * 4;
        final a = pixels[i + 3];
        if (a < 40) continue;
        checked++;
        // Straight color stays the brush color; a double unpremultiply would
        // push channels towards 255.
        expect(pixels[i], closeTo(0x33, 12));
        expect(pixels[i + 1], closeTo(0x66, 12));
        expect(pixels[i + 2], closeTo(0xcc, 12));
      }
      expect(checked, greaterThan(50));
    },
  );

  test(
    'selection and inverted selection keep every outside pixel exact',
    () async {
      for (final invert in [false, true]) {
        final c = await nativeController();
        addTearDown(c.dispose);
        await withInk(c);
        final left = SelectionRegion.rectangle(
          const ui.Rect.fromLTWH(0, 0, 512, 1024),
        );
        c.setSelection(invert ? left.invert() : left);
        final source = await raw(c);
        line(c, 100, 900, 800);
        await c.settleStroke();
        final after = await raw(c);
        var inside = 0;
        for (var y = 0; y < 1024; y++) {
          for (var x = 0; x < 1024; x++) {
            final outside = invert ? x < 511 : x > 512;
            final i = (y * 1024 + x) * 4;
            final same = List.generate(4, (k) => after[i + k] == source[i + k]);
            if (outside) {
              expect(same.every((v) => v), isTrue, reason: 'pixel $x,$y');
            } else if (!same.every((v) => v)) {
              inside++;
            }
          }
        }
        expect(inside, greaterThan(500));
      }
    },
  );

  test('the editable mask stays editable and hidden content survives native strokes', () async {
    final c = await nativeController();
    addTearDown(c.dispose);
    await withInk(c);
    c.setSelection(
      SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 512, 1024)),
    );
    expect(c.maskLayerFromSelection(), isTrue);
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(opacity: .5, blend: LayerBlend.multiply),
    );
    line(c, 100, 900, 300);
    await c.settleStroke();
    final layer = c.document.activeLayer;
    expect(layer.mask, isNotNull);
    expect(layer.opacity, .5);
    expect(layer.blend, LayerBlend.multiply);
    final pixels = await raw(c);
    // Raw content keeps the hidden ink and the hidden part of the new stroke.
    expect(alphaAt(pixels, 800, 800), greaterThan(100));
    expect(alphaAt(pixels, 800, 300), greaterThan(100));
    c.updateLayer(layer.id, (l) => l.copyWith(clearMask: true));
    await c.settleStroke();
    expect(c.document.activeLayer.mask, isNull);
    expect(c.document.activeLayer.raster, same(layer.raster));
  });

  test(
    'native eraser removes existing pixels of the target layer only',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      await withInk(c);
      final bottom = c.document.activeLayerId;
      c.addLayer('Top');
      c.selectLayer(bottom);
      c.selectTool(StudioTool.eraser);
      c.setSize(80);
      line(c, 100, 900, 800, pressure: 1);
      await c.settleStroke();
      final erased = await raw(c);
      expect(alphaAt(erased, 500, 800), lessThan(40));
      expect(alphaAt(erased, 500, 780), lessThan(128));
      expect(c.document.layers.last.raster, isNull);
      expect(c.document.layers.last.strokes, isEmpty);
    },
  );

  test(
    'cancel, dispose and layer deletion never commit a stale native result',
    () async {
      final c = await nativeController();
      final before = c.document;
      line(c, 100, 900, 300, finish: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      c.cancelStroke();
      await c.settleStroke();
      expect(c.document, same(before));
      expect(c.nativePreview, isNull);

      // Edits issued while a stroke finalizes run afterwards, in user order.
      line(c, 100, 900, 300);
      final layerId = c.document.activeLayerId;
      c.addLayer('Second');
      c.deleteLayer(layerId);
      expect(c.document, same(before));
      await c.settleStroke();
      expect(c.document.layers.map((l) => l.id), isNot(contains(layerId)));
      c.undo();
      final restored = c.document.layers.firstWhere((l) => l.id == layerId);
      expect(restored.raster, isNotNull);
      c.undo();
      c.undo();
      expect(c.document.layers.single.raster, isNull);

      line(c, 100, 900, 500);
      final pending = c.document;
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.document, same(pending));
    },
  );

  test(
    'following strokes continue from the worker surface and stay exact',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      await withInk(c);
      line(c, 100, 900, 300);
      await c.settleStroke();
      expect(c.lastNativeStats!.loadBytes, 1024 * 1024 * 4);
      line(c, 100, 900, 500);
      await c.settleStroke();
      final second = c.lastNativeStats!;
      // The surface already holds the first stroke: nothing is reloaded.
      expect(second.loadBytes, 0);
      expect(second.dirty!.$4, lessThan(400));

      // Dabs that fell outside a selection must never reach the layer, nor
      // come back with the next stroke.
      c.setSelection(
        SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 10, 10)),
      );
      final beforeHidden = await raw(c);
      line(c, 100, 900, 700);
      await c.settleStroke();
      expect(await raw(c), beforeHidden);
      c.setSelection(null);
      line(c, 100, 300, 900);
      await c.settleStroke();
      // The worker took them back off its surface itself: nothing reloads.
      expect(c.lastNativeStats!.loadBytes, 0);
      final after = await raw(c);
      for (var x = 400; x < 900; x++) {
        expect(alphaAt(after, x, 700), alphaAt(beforeHidden, x, 700));
      }
      expect(alphaAt(after, 200, 900), greaterThan(100));

      // After undo the worker's layer no longer matches: it reloads the
      // layer from its tiles (compressed, far less than raw pixels).
      c.undo();
      line(c, 100, 900, 600);
      await c.settleStroke();
      expect(c.lastNativeStats!.loadBytes, greaterThan(0));
      expect(c.lastNativeStats!.loadBytes, lessThan(1024 * 1024));
    },
  );

  test(
    'an undo between strokes is honoured before the next stroke starts',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      line(c, 100, 900, 300);
      // Issued while the first stroke is still committing.
      c.undo();
      line(c, 100, 900, 600);
      await c.settleStroke();
      final pixels = await raw(c);
      expect(alphaAt(pixels, 500, 300), 0);
      expect(alphaAt(pixels, 500, 600), greaterThan(100));
      expect(c.canUndo, isTrue);
      c.undo();
      await c.settleStroke();
      expect(c.document.activeLayer.raster, isNull);
      expect(c.canRedo, isTrue);
    },
  );

  test(
    'a stroke started during the previous commit does not wait for it',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      line(c, 100, 900, 300);
      await c.settleStroke();
      line(c, 100, 900, 500);
      // Begin the next stroke immediately: it continues on the worker lane.
      line(c, 100, 900, 700, finish: false);
      for (
        var i = 0;
        i < 200 && (c.nativePreview?.tiles.isEmpty ?? true);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(c.nativePreview!.tiles, isNotEmpty);
      c.finishStroke();
      await c.settleStroke();
      expect(c.lastNativeStats!.loadBytes, 0);
      final pixels = await raw(c);
      for (final y in [300, 500, 700]) {
        expect(alphaAt(pixels, 500, y), greaterThan(100));
      }
      c.undo();
      await c.settleStroke();
      expect(alphaAt(await raw(c), 500, 700), 0);
      expect(alphaAt(await raw(c), 500, 500), greaterThan(100));
    },
  );

  test('rapid consecutive strokes each become one undo step', () async {
    final c = await nativeController();
    addTearDown(c.dispose);
    for (var i = 0; i < 5; i++) {
      line(c, 100, 900, 100 + i * 180.0);
    }
    await c.settleStroke();
    final pixels = await raw(c);
    for (var i = 0; i < 5; i++) {
      expect(alphaAt(pixels, 500, 100 + i * 180), greaterThan(100));
    }
    // Five undos in a row: steps outside the decoded window restore through
    // the ordered queue, so the burst still lands on the empty drawing.
    for (var i = 0; i < 5; i++) {
      c.undo();
    }
    await c.settleStroke();
    expect(c.canUndo, isFalse);
    expect(c.document.activeLayer.raster, isNull);
  });

  test(
    'history keeps a small decoded window and restores older steps exactly',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      final steps = <ArtDocument>[c.document];
      for (var i = 0; i < 8; i++) {
        line(c, 100, 900, 80 + i * 110.0);
        await c.settleStroke();
        steps.add(c.document);
      }
      // Current drawing + 2 undo steps decoded, not the whole history.
      final window = [
        c.document,
        ...steps.reversed.skip(1).take(StudioController.decodedUndoSteps),
      ].expand(documentRasters).toSet();
      expect(c.rasters.images.keys.toSet().difference(window), isEmpty);
      expect(
        steps.expand(documentRasters).toSet().length,
        greaterThan(window.length),
      );
      final latest = await raw(c);
      for (var i = steps.length - 2; i >= 0; i--) {
        c.undo();
        await c.settleStroke();
        expect(c.document, same(steps[i]));
        for (final tile in documentRasters(c.document)) {
          expect(c.rasters.images[tile], isNotNull);
        }
      }
      for (var i = 1; i < steps.length; i++) {
        c.redo();
        await c.settleStroke();
        expect(c.document, same(steps[i]));
      }
      expect(await raw(c), latest);
      // An edit issued while an older step decodes runs after it, in order.
      c.undo();
      c.undo();
      c.undo();
      c.addLayer('after undos');
      await c.settleStroke();
      expect(c.document.layers.length, 2);
      expect(
        c.document.layers.first.raster,
        same(steps[steps.length - 4].activeLayer.raster),
      );
      expect(c.canRedo, isFalse);
    },
  );

  test(
    'live preview replaces the active layer content while drawing',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      line(c, 100, 900, 512, finish: false);
      for (
        var i = 0;
        i < 100 && (c.nativePreview?.tiles.isEmpty ?? true);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.nativePreviewLayerId, c.document.activeLayerId);
      expect(c.nativePreview!.tiles, isNotEmpty);
      // Only the blocks the brush crossed travel to the GPU, not the surface.
      expect(c.nativePreview!.tiles.length, lessThan(64));
      expect(c.document.activeLayer.raster, isNull);
      final recorder = ui.PictureRecorder();
      paintDocument(
        ui.Canvas(recorder),
        c.document,
        FreehandBrushEngine(),
        rasterImages: c.rasters.images,
        overrides: c.nativeOverrides,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, 1024);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final i = (512 * 1024 + 500) * 4;
      expect(data!.getUint8(i), greaterThan(data.getUint8(i + 2)));
      c.finishStroke();
      await c.settleStroke();
      expect(c.nativePreview, isNull);
    },
  );

  test('native strokes save, reopen from disk and export', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-native-');
    addTearDown(() => dir.delete(recursive: true));
    final c = await nativeController(LocalStudioStorage(dir));
    line(c, 100, 900, 512);
    await c.settleStroke();
    await c.save();
    final painted = await raw(c);
    Map<int, Uint8List> pngs(ArtLayer layer) => {
      for (final MapEntry(:key, :value) in layer.raster!.tiles.entries)
        key: value.png,
    };
    final png = pngs(c.document.activeLayer);
    c.dispose();
    final reopened = StudioController(storage: LocalStudioStorage(dir));
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(pngs(reopened.document.activeLayer), png);
    expect(await raw(reopened), painted);
    final exported = await renderDocumentPng(
      reopened.document,
      reopened.rasters.images,
    );
    expect(exported.length, greaterThan(1000));
    final roundTrip = ArtDocument.fromJson(
      jsonDecode(jsonEncode(reopened.document.toJson()))
          as Map<String, dynamic>,
    );
    expect(pngs(roundTrip.activeLayer), png);
  });

  test(
    '.myb import validates natively, persists and reopens as a native brush',
    () async {
      final bytes = await File(
        '../../packages/artblend_brush_engine/test/fixtures/impressionism.myb',
      ).readAsBytes();
      final imported = decodeMypaintImport((bytes, 'Impressionism.myb')).single;
      expect(imported.isNative, isTrue);
      expect(imported.name, 'Impressionism');
      expect(imported.size, inInclusiveRange(1, 128));
      expect(
        () => decodeMypaintImport((utf8.encode('{"version":3}'), 'bad.myb')),
        throwsFormatException,
      );
      // MyPaint 1.0 brush kits use the line format; stored as version 3.
      final legacy = decodeMypaintImport((
        utf8.encode(
          'version 2\nopaque 0.8\nradius_logarithmic 1.5\n'
          'opaque_multiply 0.0 | pressure (0.0 0.0), (1.0 1.0)\n',
        ),
        'Old pencil.myb',
      )).single;
      expect(legacy.name, 'Old pencil');
      expect(jsonDecode(legacy.mypaint!)['version'], 3);
      expect(legacy.size, closeTo(2 * math.exp(1.5), .01));
      final storage = MemoryStorage()
        ..library = {
          'brushes': [initialBrushes.first.toJson()],
          'palettes': [],
        };
      final c = StudioController(storage: storage);
      await c.initialize();
      // Saved libraries from before native brushes still offer the built-ins.
      expect(
        c.brushes.where((b) => b.isNative).map((b) => b.id),
        initialBrushes.where((b) => b.isNative).map((b) => b.id),
      );
      c.addBrushes([imported]);
      await c.save();
      c.dispose();
      final reopened = StudioController(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.initialize();
      final restored = reopened.brushes.lastWhere(
        (b) => b.name == 'Impressionism',
      );
      expect(restored.isNative, isTrue);
      expect(restored.mypaint, imported.mypaint);
      expect(restored.id, isNot(imported.id));
      reopened.selectBrush(restored);
      line(reopened, 100, 900, 512);
      await reopened.settleStroke();
      final painted = await raw(reopened);
      var marked = 0;
      for (var y = 412; y < 612; y++) {
        for (var x = 300; x < 700; x++) {
          if (alphaAt(painted, x, y) > 0) marked++;
        }
      }
      expect(marked, greaterThan(500));
      expect(
        () => BrushPreset.fromJson({
          'name': 'x',
          'size': 4,
          'engine': BrushPreset.mypaintEngineId,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'a failing native preset reports the error and leaves the drawing intact',
    () async {
      final c = await nativeController();
      addTearDown(c.dispose);
      final failures = <Object>[];
      final sub = c.strokeFailures.listen(failures.add);
      addTearDown(sub.cancel);
      c.selectBrush(
        const BrushPreset(
          id: 'broken',
          name: 'broken',
          engine: BrushEngineKind.mypaint,
          mypaint: '{"version": 3, "settings": {"nope": {}}}',
        ),
      );
      final before = c.document;
      line(c, 100, 900, 512);
      await c.settleStroke();
      expect(c.document, same(before));
      expect(failures, isNotEmpty);
      c.selectBrush(charcoal);
      line(c, 100, 900, 512);
      await c.settleStroke();
      expect(c.document.activeLayer.raster, isNotNull);
    },
  );
}
