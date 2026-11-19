import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/drawing/stamp_shapes.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every built-in stamp brush draws textured native pixels', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final stamps = initialBrushes.where((b) => b.isStamp).toList();
    expect(stamps, hasLength(5));
    for (final (i, brush) in stamps.indexed) {
      c.selectBrush(brush);
      c.selectColor(0xff204080);
      final y = 120.0 + i * 160;
      var t = const Duration(seconds: 1);
      expect(
        c.beginStroke(InkPoint(100, y, .8), simulatePressure: false, time: t),
        isTrue,
      );
      for (var x = 104.0; x <= 900; x += 4) {
        t += const Duration(milliseconds: 8);
        c.appendPoint(InkPoint(x, y, .8), time: t);
      }
      c.finishStroke();
      await c.settleStroke();
    }
    final layer = c.document.activeLayer;
    expect(layer.raster!.tiles, isNotEmpty);
    expect(layer.strokes, isEmpty);
    final rgba = (await renderNativeBase(
      layer,
      c.document.grid,
      c.rasters.images,
    )).rgba;
    for (final (i, brush) in stamps.indexed) {
      final y = 120 + i * 160;
      var painted = 0;
      final levels = <int>{};
      for (var x = 300; x < 700; x++) {
        final a = alphaAt(rgba, x, y);
        if (a > 0) painted++;
        levels.add(a);
      }
      // Splatter drops land apart; the others paint a continuous line.
      expect(
        painted,
        greaterThan(brush.id == 'stamp-splatter' ? 5 : 100),
        reason: brush.id,
      );
      // Grain textures the line, however much paint builds up.
      if (brush.grain != null) {
        expect(levels.length, greaterThan(30), reason: brush.id);
      }
    }
    c.undo();
    expect(
      c.document.activeLayer.raster?.tiles.length ?? 0,
      lessThan(layer.raster!.tiles.length + 1),
    );
  });

  test('stamp brushes survive the library, and a PNG becomes a tip', () async {
    final graphite = initialBrushes.firstWhere((b) => b.id == 'stamp-graphite');
    final back = BrushPreset.fromJson(
      jsonDecode(jsonEncode(graphite.toJson())) as Map<String, dynamic>,
    );
    expect(back.isStamp, isTrue);
    expect(
      (back.tip, back.grain, back.stamp),
      (graphite.tip, graphite.grain, graphite.stamp),
    );
    expect(
      () => BrushPreset.fromJson({
        ...graphite.toJson(),
        'tip': 'https://example.com/tip.png',
      }),
      throwsFormatException,
    );

    // A star-ish white mark on black: opaque, so light paints.
    final rgba = Uint8List(64 * 64 * 4);
    for (var i = 0; i < 64 * 64; i++) {
      final x = i % 64, y = i ~/ 64;
      final v = (x - 32).abs() + (y - 32).abs() < 20 ? 255 : 0;
      rgba
        ..[i * 4] = v
        ..[i * 4 + 1] = v
        ..[i * 4 + 2] = v
        ..[i * 4 + 3] = 255;
    }
    final brush = await pngTipBrush(encodeRgbaPng(rgba, 64, 64), 'Star.png');
    expect((brush.name, brush.isStamp), ('Star', true));
    final tip = await decodeStampShape(brush.tip!, grain: false);
    expect((tip.width, tip.height), (64, 64));
    expect(tip.pixels[32 * 64 + 32], 255);
    expect(tip.pixels[0], 0);
    final preview = await renderNativePreview(brush);
    final data = await preview.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data!.buffer.asUint8List().any((v) => v != 0), isTrue);
  });

  test('built-in grains tile without seams', () {
    for (final name in ['paper', 'rough', 'canvas']) {
      final grain = builtinStampImage(name);
      final n = grain.width;
      var jump = 0, inside = 0;
      for (var y = 0; y < n; y++) {
        jump += (grain.pixels[y * n] - grain.pixels[y * n + n - 1]).abs();
        inside +=
            (grain.pixels[y * n + n ~/ 2] - grain.pixels[y * n + n ~/ 2 - 1])
                .abs();
      }
      // Across the wrap no rougher than between any two neighbours.
      expect(jump, lessThan(inside * 2 + n * 4), reason: name);
    }
  });
}
