import 'dart:math' as math;
import 'dart:typed_data';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/flood_fill.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

/// A 1024² black ring (radius 200–206 around 512, 512), anti-aliased edge.
Uint8List ring() {
  final rgba = Uint8List(1024 * 1024 * 4);
  for (var y = 0; y < 1024; y++) {
    for (var x = 0; x < 1024; x++) {
      final d = math.sqrt(
        math.pow(x + .5 - 512, 2) + math.pow(y + .5 - 512, 2),
      );
      final edge = (3.5 - (d - 203).abs()).clamp(0.0, 1.0);
      rgba[(y * 1024 + x) * 4 + 3] = (edge * 255).round();
    }
  }
  return rgba;
}

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

Future<Uint8List> layerPixels(StudioController c, ArtLayer layer) async =>
    (await renderNativeBase(layer, c.document.grid, c.rasters.images)).rgba;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a flood fill stays inside lines, tucks under their soft edge and '
      'respects a clip', () {
    final rgba = ring();
    final inside = floodFill(rgba, 1024, 1024, 512, 512, threshold: .3);
    expect(inside[512 * 1024 + 512], 255);
    expect(inside[512 * 1024 + 512 + 150], 255);
    expect(inside[512 * 1024 + 512 + 260], 0, reason: 'outside the ring');
    // Grown one pixel under the anti-aliased inner edge.
    expect(inside[512 * 1024 + 512 + 199], 255);
    final clip = Uint8List(1024 * 1024)..fillRange(0, 512 * 1024, 255);
    final clipped = floodFill(
      rgba,
      1024,
      1024,
      512,
      400,
      threshold: .3,
      clip: clip,
    );
    expect(clipped[400 * 1024 + 512], 255);
    expect(clipped[600 * 1024 + 512], 0, reason: 'below the clip');
    expect(
      floodFill(rgba, 1024, 1024, 5000, 5, threshold: .3).any((v) => v != 0),
      isFalse,
    );
  });

  test('ColorDrop fills by the reference layer\'s lines; the threshold '
      'redoes the last fill as one step; more drops fill more areas', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.addImageLayer(encodeRgbaPng(ring(), 1024, 1024), 'Lines');
    final lines = c.document.activeLayer;
    c.toggleReferenceLayer(lines.id);
    expect(c.document.activeLayer.reference, isTrue);
    c.addLayer('Colour');
    final beforeFill = c.document;
    c.selectColor(0xffd02020);
    await c.colorDrop(const Offset(512, 512));
    var colour = await layerPixels(c, c.document.activeLayer);
    expect(alphaAt(colour, 512, 512), 255);
    expect(colour[(512 * 1024 + 512) * 4], 0xd0);
    expect(
      alphaAt(colour, 512 + 260, 512),
      0,
      reason: 'lines on another layer',
    );
    expect(
      alphaAt(await layerPixels(c, lines), 512, 512),
      0,
      reason: 'lines untouched',
    );

    c.setFillThreshold(.9);
    for (var i = 0; i < 100 && c.documentTransition; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Refilled: still one step from the drawing before the fill.
    final refilled = c.document;
    expect(refilled, isNot(same(beforeFill)));
    c.undo();
    expect(c.document, same(beforeFill));
    c.redo();
    expect(c.document, same(refilled));
    // Outside the ring with another colour, in the same session.
    await c.colorDrop(const Offset(40, 40), color: 0xff2040d0);
    colour = await layerPixels(c, c.document.activeLayer);
    expect(colour[(40 * 1024 + 40) * 4 + 2], 0xd0);
    expect(colour[(512 * 1024 + 512) * 4], 0xd0, reason: 'first fill kept');
    c.endFill();
    expect(c.fillSession, isNull);
  });

  testWidgets('dragging the colour button onto the canvas fills there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.selectColor(0xff20a040);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.byKey(const ValueKey('color-button')));
    final to = tester.getCenter(find.byKey(const ValueKey('drawing-surface')));
    final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    for (
      var i = 0;
      i < 200 && c.fillSession != null && c.document.activeLayer.raster == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump();
    expect(c.document.activeLayer.raster, isNotNull, reason: 'filled');
    expect(find.byKey(const ValueKey('fill-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fill-done')));
    await tester.pump();
    expect(c.fillSession, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('the highest threshold still stops at solid lines', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.addImageLayer(encodeRgbaPng(ring(), 1024, 1024), 'Lines');
    c.setFillThreshold(1);
    expect(c.fillThreshold, StudioController.maxFillThreshold);
    await c.colorDrop(const Offset(512, 512), color: 0xffd02020);
    final pixels = await layerPixels(c, c.document.activeLayer);
    expect(alphaAt(pixels, 512, 512), 255);
    expect(alphaAt(pixels, 40, 40), 0, reason: 'the ring held');
  });
}
