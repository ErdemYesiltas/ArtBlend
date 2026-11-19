import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artblend_brush_engine/artblend_brush_engine.dart';
import 'package:test/test.dart';

String preset(Map<String, Object> settings) =>
    jsonEncode({'version': 3, 'settings': settings});
Map<String, Object> setting(
  double base, [
  Map<String, Object> inputs = const {},
]) => {'base_value': base, 'inputs': inputs};

void line(NativeBrushSurface s, double y, double pressure) {
  s.beginStroke();
  s.point(x: 16, y: y, pressure: 0, seconds: 0.1);
  for (int x = 16; x < 112; x++) {
    s.point(x: x.toDouble(), y: y, pressure: pressure);
  }
  s.point(x: 112, y: y, pressure: 0);
}

void main() {
  test(
    'upstream brush fixtures load and render without losing preset dynamics',
    () {
      for (final file in Directory(
        'test/fixtures',
      ).listSync().whereType<File>()) {
        final surface = NativeBrushSurface(width: 128, height: 128);
        try {
          surface.loadPreset(file.readAsStringSync());
          surface.configure(
            diameter: 20,
            hue: 0.4,
            saturation: 0.8,
            value: 0.7,
          );
          line(surface, 64, 0.8);
          expect(
            surface.readRgba().any((v) => v != 0),
            isTrue,
            reason: file.path,
          );
        } finally {
          surface.close();
        }
      }
    },
  );
  test('excessive dab workload invalidates partial output', () {
    final surface = NativeBrushSurface(width: 128, height: 128);
    addTearDown(surface.close);
    surface.loadPreset(preset({'dabs_per_actual_radius': setting(20)}));
    surface.configure(diameter: 1);
    surface.beginStroke();
    surface.point(x: 0, y: 64, pressure: 0);
    expect(() => surface.point(x: 4000, y: 64, pressure: 1), throwsStateError);
    expect(() => surface.readRgba(), throwsStateError);
  });
  test('native tiles remain sparse and real brush paints HSV red', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    expect(NativeBrushSurface.engineVersion, contains('libmypaint-1.6.1'));
    expect(s.allocatedTiles, 0);
    expect(s.readRgba().every((v) => v == 0), isTrue);
    s.configure(diameter: 12, hue: 0, saturation: 1, value: 1);
    line(s, 32, 1);
    final pixels = s.readRgba();
    final center = (32 * 128 + 64) * 4;
    expect(pixels[center], greaterThan(240));
    expect(pixels[center + 1], lessThan(10));
    expect(pixels[center + 3], greaterThan(200));
    expect(s.allocatedTiles, inInclusiveRange(1, 3));
    expect(pixels[(100 * 128 + 64) * 4 + 3], 0);
  });
  test('MyPaint pressure mapping changes actual stroke width', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    s.loadPreset(
      preset({
        'radius_logarithmic': setting(2, {
          'pressure': [
            [0, -2],
            [1, 0],
          ],
        }),
      }),
    );
    s.configure(diameter: 24);
    line(s, 32, 0.2);
    line(s, 96, 1);
    final rgba = s.readRgba();
    int coverage(int y) => [
      for (int row = y - 20; row <= y + 20; row++)
        rgba[(row * 128 + 64) * 4 + 3],
    ].where((a) => a > 20).length;
    expect(coverage(96), greaterThan(coverage(32) * 2));
  });
  test(
    'opacity scales the preset; pressure-to-opacity curves survive configure',
    () {
      final surface = NativeBrushSurface(width: 128, height: 128);
      addTearDown(surface.close);
      surface.loadPreset(
        preset({
          'opaque': setting(1),
          'hardness': setting(1),
          'opaque_multiply': setting(0, {
            'pressure': [
              [0, 0],
              [1, 1],
            ],
          }),
        }),
      );
      int alphaAfter(double pressure, double opacity, double y) {
        surface.configure(diameter: 12, value: 1, opacity: opacity);
        line(surface, y, pressure);
        return surface.readRgba()[((y.toInt()) * 128 + 64) * 4 + 3];
      }

      final light = alphaAfter(.1, 1, 20);
      final heavy = alphaAfter(1, 1, 50);
      final halfOpacity = alphaAfter(1, .5, 80);
      expect(light, greaterThan(0));
      expect(light, lessThan(heavy ~/ 2));
      expect(heavy, greaterThan(250));
      expect(halfOpacity, inInclusiveRange(40, 230));
    },
  );

  test('dirty tiles and rectangle IO cover exactly what dabs touched', () {
    final surface = NativeBrushSurface(width: 300, height: 200);
    addTearDown(surface.close);
    expect(surface.tileColumns, 5);
    expect(surface.tileRows, 4);
    final full = Uint8List(300 * 200 * 4);
    for (var i = 0; i < full.length; i += 4) {
      full.setAll(i, [10, 200, 30, i % 7 == 0 ? 3 : 180]);
    }
    surface.loadRgba(full);
    expect(surface.takeDirtyTiles().every((t) => t == 0), isTrue);
    surface.configure(diameter: 10, value: 1);
    surface.beginStroke();
    surface.point(x: 20, y: 20, pressure: 0, seconds: 1);
    for (var x = 20; x < 110; x++) {
      surface.point(x: x.toDouble(), y: 20, pressure: 1);
    }
    final dirty = surface.takeDirtyTiles();
    expect(dirty[0], 1);
    expect(dirty[1], 1);
    expect(dirty[4], 0);
    expect(dirty[5], 0);
    expect(surface.takeDirtyTiles().every((t) => t == 0), isTrue);
    final all = surface.readRgba();
    final rect = surface.readRgbaRect(250, 150, 50, 50);
    for (var y = 0; y < 50; y++) {
      final row = ((150 + y) * 300 + 250) * 4;
      expect(rect.sublist(y * 200, y * 200 + 200), all.sublist(row, row + 200));
    }
    final premultiplied = surface.readRgbaRect(
      0,
      0,
      300,
      200,
      premultiplied: true,
    );
    for (var i = 0; i < all.length; i += 4 * 37) {
      expect(premultiplied[i + 3], all[i + 3]);
      for (var c = 0; c < 3; c++) {
        expect(
          premultiplied[i + c],
          closeTo(all[i + c] * all[i + 3] / 255, 1.01),
        );
        expect(premultiplied[i + c], lessThanOrEqualTo(premultiplied[i + 3]));
      }
    }
    final patch = Uint8List(16 * 8 * 4)..fillRange(0, 16 * 8 * 4, 255);
    surface.loadRgbaRect(284, 192, 16, 8, patch);
    expect(surface.readRgbaRect(284, 192, 16, 8), patch);
    expect(surface.takeDirtyTiles().every((t) => t == 0), isTrue);
    expect(() => surface.readRgbaRect(290, 0, 16, 8), throwsRangeError);
    expect(
      () => surface.loadRgbaRect(0, 0, 2, 2, Uint8List(3)),
      throwsArgumentError,
    );
  });

  test('eraser removes existing layer pixels', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    final white = Uint8List(128 * 128 * 4)..fillRange(0, 128 * 128 * 4, 255);
    s.loadRgba(white);
    s.configure(diameter: 20, eraser: true);
    line(s, 64, 1);
    final rgba = s.readRgba();
    expect(rgba[(64 * 128 + 64) * 4 + 3], lessThan(30));
    expect(rgba[3], 255);
  });
  test(
    'straight alpha pixels survive conversion and load replaces old pixels',
    () {
      final s = NativeBrushSurface(width: 1, height: 1);
      addTearDown(s.close);
      for (int a = 1; a < 256; a++) {
        final source = Uint8List.fromList([173, 81, 24, a]);
        s.loadRgba(source);
        final actual = s.readRgba();
        expect(actual[3], a);
        for (int c = 0; c < 3; c++) {
          expect((actual[c] - source[c]).abs(), lessThanOrEqualTo(1));
        }
      }
      s.loadRgba(Uint8List(4));
      expect(s.readRgba(), [0, 0, 0, 0]);
    },
  );
  test('structurally broken presets are rejected', () {
    final s = NativeBrushSurface(width: 32, height: 32);
    addTearDown(s.close);
    for (final bad in [
      '{}',
      '[]',
      '{"version":2,"settings":{"opaque":{"base_value":1,"inputs":{}}}}',
      '{"version":3,"settings":[]}',
      preset({'unknown': setting(1)}),
      preset({'opaque': 'not a setting'}),
      '${preset({'opaque': setting(1)})}garbage',
      '${preset({'opaque': setting(1)})}\u0000',
    ]) {
      expect(() => s.loadPreset(bad), throwsFormatException, reason: bad);
    }
  });

  test('real-world deviations are sanitized before the fixed-array parser '
      'instead of rejecting the brush', () {
    for (final deviant in [
      preset({'opaque': setting(.7), 'from_a_newer_mypaint': setting(1)}),
      preset({
        'opaque': setting(.7, {
          'unknown': [
            [0, 0],
            [1, 1],
          ],
        }),
      }),
      preset({
        'opaque': setting(.7, {
          'pressure': [
            [0, 0],
          ],
        }),
      }),
      preset({
        'opaque': setting(.7, {
          'pressure': List.generate(65, (i) => [i, 1]),
        }),
      }),
      preset({
        'opaque': setting(.7, {
          'pressure': [
            [1, 0],
            [0, 1],
            [2, 1],
          ],
        }),
      }),
      preset({
        'opaque': setting(.7, {
          'pressure': [
            [0, 1],
            [0, 0],
            [1, 1],
          ],
        }),
      }),
      preset({
        'opaque': setting(.7, {
          'pressure': [
            [0],
            [0, 1],
            [1, 1],
          ],
        }),
      }),
      preset({'opaque': setting(1000)}),
    ]) {
      final s = NativeBrushSurface(width: 32, height: 32);
      s.loadPreset(deviant);
      s.configure(diameter: 5);
      line(s, 16, 1);
      expect(s.readRgba().any((v) => v != 0), isTrue, reason: deviant);
      s.close();
    }
  });

  test('native lifetime and invalid coordinates are guarded', () {
    expect(() => NativeBrushSurface(width: 0, height: 1), throwsArgumentError);
    final s = NativeBrushSurface(width: 8, height: 8);
    expect(() => s.point(x: double.nan, y: 0, pressure: 1), throwsStateError);
    expect(() => s.configure(diameter: double.infinity), throwsArgumentError);
    expect(() => s.loadRgba(Uint8List(2)), throwsArgumentError);
    s.close();
    s.close();
    expect(() => s.readRgba(), throwsStateError);
  });
}
