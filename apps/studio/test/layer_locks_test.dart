import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

Uint8List solid(int r, int g, int b) {
  final rgba = Uint8List(64 * 64 * 4);
  for (var i = 0; i < 64 * 64; i++) {
    rgba
      ..[i * 4] = r
      ..[i * 4 + 1] = g
      ..[i * 4 + 2] = b
      ..[i * 4 + 3] = 255;
  }
  return encodeRgbaPng(rgba, 64, 64);
}

Future<Uint8List> screen(StudioController c) async {
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
  return data!.buffer.asUint8List();
}

List<int> rgbAt(Uint8List rgba, int x, int y) {
  final i = (y * 1024 + x) * 4;
  return [rgba[i], rgba[i + 1], rgba[i + 2]];
}

Future<Uint8List> raw(StudioController c) async => (await renderNativeBase(
  c.document.activeLayer,
  c.document.grid,
  c.rasters.images,
)).rgba;

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

void stroke(StudioController c, double y) {
  var t = const Duration(seconds: 1);
  c.beginStroke(InkPoint(100, y, 1), simulatePressure: false, time: t);
  for (var x = 104.0; x <= 900; x += 4) {
    t += const Duration(milliseconds: 8);
    c.appendPoint(InkPoint(x, y, 1), time: t);
  }
  c.finishStroke();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a clipping layer shows only over its base, in its own blend mode',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      await c.addImageLayer(
        solid(200, 40, 40),
        'Base',
        at: const Rect.fromLTWH(300, 300, 400, 400),
      );
      await c.addImageLayer(solid(40, 40, 200), 'Clipped');
      c.toggleClipping(c.document.activeLayerId);
      var pixels = await screen(c);
      expect(rgbAt(pixels, 500, 500), [40, 40, 200], reason: 'over the base');
      expect(rgbAt(pixels, 100, 100), [255, 253, 248], reason: 'paper');
      // Multiply: blue × red, still only over the base.
      c.updateLayer(
        c.document.activeLayerId,
        (l) => l.copyWith(blend: LayerBlend.multiply),
      );
      pixels = await screen(c);
      expect(rgbAt(pixels, 500, 500), [31, 6, 31]);
      expect(rgbAt(pixels, 100, 100), [255, 253, 248]);
      // The bottom layer cannot clip; a hidden base hides its clipped layer.
      c.toggleClipping(c.document.layers.first.id);
      expect(c.document.layers.first.clipping, isFalse);
      c.updateLayer(c.document.layers[1].id, (l) => l.copyWith(visible: false));
      pixels = await screen(c);
      expect(rgbAt(pixels, 500, 500), [255, 253, 248]);
      // The live compositor leaves a clipping group to the full draw.
      expect(c.compositor.frame(c.document, c.rasters.images), isNull);
    },
  );

  test('alpha lock recolours pixels already there and adds none, for '
      'native and vector strokes, fills and ColorDrop', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.addImageLayer(
      solid(200, 200, 200),
      'Shape',
      at: const Rect.fromLTWH(300, 300, 400, 400),
    );
    c.toggleAlphaLock(c.document.activeLayerId);
    for (final id in ['stamp-gouache', 'ink']) {
      c.selectBrush(initialBrushes.firstWhere((b) => b.id == id));
      c.selectColor(0xffd02020);
      c.setSize(30);
      stroke(c, id == 'ink' ? 450 : 500);
      await c.settleStroke();
    }
    var pixels = await screen(c);
    expect(
      rgbAt(pixels, 500, 500)[0],
      greaterThan(rgbAt(pixels, 500, 500)[1] + 60),
    );
    expect(rgbAt(pixels, 150, 500), [
      255,
      253,
      248,
    ], reason: 'native: none added');
    expect(rgbAt(pixels, 150, 450), [
      255,
      253,
      248,
    ], reason: 'vector: none added');

    c.selectColor(0xff2040d0);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 1024, 400)),
    );
    await c.fillActiveLayer();
    final layer = await raw(c);
    expect(alphaAt(layer, 500, 350), 255);
    expect(layer[(350 * 1024 + 500) * 4 + 2], 0xd0, reason: 'filled inside');
    expect(
      alphaAt(layer, 100, 100),
      0,
      reason: 'nothing new outside the shape',
    );
    expect(
      layer[(600 * 1024 + 500) * 4 + 2],
      lessThan(0xd0),
      reason: 'below the selection',
    );
    c.setSelection(null);

    await c.invertActiveLayer();
    final inverted = await raw(c);
    expect(inverted[(350 * 1024 + 500) * 4], 255 - 0x20);
    expect(alphaAt(inverted, 100, 100), 0);
  });

  test('solo shows one layer and brings the others back', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.addLayer('Two');
    c.addLayer('Three');
    c.updateLayer(c.document.layers[1].id, (l) => l.copyWith(visible: false));
    final three = c.document.activeLayerId;
    c.toggleSolo(three);
    expect(
      [for (final l in c.document.layers) l.visible],
      [false, false, true],
    );
    c.toggleSolo(three);
    expect([for (final l in c.document.layers) l.visible], [true, false, true]);
  });
}
