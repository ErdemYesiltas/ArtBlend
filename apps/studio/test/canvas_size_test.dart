import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/editor/editor_screen.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

final charcoal = initialBrushes.firstWhere((b) => b.id == 'mypaint-charcoal');

Future<Uint8List> raw(StudioController c) async => (await renderNativeBase(
  c.document.activeLayer,
  c.document.grid,
  c.rasters.images,
)).rgba;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a drawing keeps its own size through JSON; earlier files are 1024²',
    () {
      final doc = ArtDocument.empty(dimensions: const CanvasSize(1500, 900));
      final json = doc.toJson();
      expect(json['version'], 6);
      expect([json['width'], json['height']], [1500, 900]);
      expect(
        ArtDocument.fromJson(jsonDecode(jsonEncode(json))).dimensions,
        const CanvasSize(1500, 900),
      );
      final legacy = ArtDocument.empty().toJson()
        ..remove('width')
        ..remove('height')
        ..['extent'] = 1024.0;
      expect(ArtDocument.fromJson(legacy).dimensions, CanvasSize.legacy);
      for (final bad in [
        {...json, 'width': 5000},
        {...json, 'height': 10},
        {...legacy, 'extent': 2048.0},
      ]) {
        expect(() => ArtDocument.fromJson(bad), throwsFormatException);
      }
    },
  );

  test('a native stroke across an edge tile of a 1000×700 canvas commits, '
      'saves and reopens exactly', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-size-');
    addTearDown(() => dir.delete(recursive: true));
    final c = StudioController(storage: LocalStudioStorage(dir));
    await c.initialize();
    await c.replaceDocument(
      ArtDocument.empty(dimensions: const CanvasSize(1000, 700)),
    );
    c.selectBrush(charcoal);
    c.setSize(30);
    var t = const Duration(seconds: 1);
    c.beginStroke(
      const InkPoint(700, 650, .8),
      simulatePressure: false,
      time: t,
    );
    for (var x = 704.0; x <= 1040; x += 4) {
      t += const Duration(milliseconds: 8);
      c.appendPoint(InkPoint(x, 650 + (x - 700) / 10, .8), time: t);
    }
    c.finishStroke();
    await c.settleStroke();
    final raster = c.document.activeLayer.raster!;
    // 4 columns × 3 rows; the stroke ends in the cut bottom-right tile.
    expect(raster.grid.columns, 4);
    expect(raster.grid.rows, 3);
    expect(raster.tiles.keys, contains(11));
    final painted = await raw(c);
    expect(painted.length, 1000 * 700 * 4);
    expect(painted[(680 * 1000 + 980) * 4 + 3], greaterThan(0));
    await c.save();
    c.dispose();
    final reopened = StudioController(storage: LocalStudioStorage(dir));
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.document.dimensions, const CanvasSize(1000, 700));
    expect(await raw(reopened), painted);
  });

  testWidgets('a new drawing gets the size chosen in the dialog', (
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
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New drawing'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NewDocumentDialog), findsOneWidget);
    await tester.tap(find.text('Custom'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('canvas-width')), '1600');
    await tester.enterText(find.byKey(const ValueKey('canvas-height')), '900');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm'));
    // Replacing the drawing saves first: real async work outside fake time.
    for (var i = 0; i < 50 && c.document.dimensions == CanvasSize.legacy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.document.dimensions, const CanvasSize(1600, 900));
    expect(find.text('1600 × 900 · sRGB'), findsOneWidget);

    // The canvas keeps the drawing's aspect; a pen point maps to its pixels.
    final board = tester.getRect(find.byKey(const ValueKey('drawing-surface')));
    expect(board.width / board.height, closeTo(1600 / 900, .01));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(board.topLeft + Offset(board.width / 4, board.height / 2));
    await mouse.moveTo(
      board.center,
      timeStamp: const Duration(milliseconds: 20),
    );
    await mouse.up();
    await tester.pump();
    final stroke = c.document.activeLayer.strokes.single;
    expect(stroke.points.first.x, closeTo(400, 2));
    expect(stroke.points.last.x, closeTo(800, 2));
    expect(stroke.points.last.y, closeTo(450, 2));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('the screen option fits the display into the largest canvas', () {
    expect(
      const NewDocumentDialog(screen: Size(1600, 2560)).screenCanvas,
      const CanvasSize(2560, 1600),
    );
    expect(
      const NewDocumentDialog(screen: Size(6000, 3000)).screenCanvas,
      const CanvasSize(4096, 2048),
    );
  });
}
