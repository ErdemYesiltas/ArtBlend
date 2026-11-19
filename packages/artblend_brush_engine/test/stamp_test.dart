import 'dart:math' as math;
import 'dart:typed_data';

import 'package:artblend_brush_engine/artblend_brush_engine.dart';
import 'package:test/test.dart';

/// A hard round tip.
StampImage disc(int size) {
  final pixels = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = math.sqrt(
        math.pow(x + .5 - size / 2, 2) + math.pow(y + .5 - size / 2, 2),
      );
      pixels[y * size + x] = d <= size / 2 ? 255 : 0;
    }
  }
  return StampImage(pixels, size, size);
}

void stroke(NativeBrushSurface s, {double y = 64, double pressure = 1}) {
  s.beginStroke();
  for (var x = 16; x <= 112; x += 2) {
    s.point(x: x.toDouble(), y: y, pressure: pressure, seconds: .01);
  }
}

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 128 + x) * 4 + 3];

void main() {
  test('dabs build up to the stroke opacity and never beyond it', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    s.loadStamp(
      disc(32),
      const StampSettings(
        spacing: .05,
        flow: .3,
        pressureSize: 0,
        pressureOpacity: 0,
      ),
    );
    s.configure(diameter: 20, hue: 0, saturation: 1, value: 1, opacity: .5);
    stroke(s);
    final rgba = s.readRgba();
    final a = alphaAt(rgba, 64, 64);
    expect(a, inInclusiveRange(120, 128), reason: 'capped at 50%');
    expect(rgba[(64 * 128 + 64) * 4], 255, reason: 'pure red');
    expect(alphaAt(rgba, 64, 90), 0, reason: 'outside the tip');
    // A second stroke over the first builds on it, as strokes do.
    stroke(s);
    expect(alphaAt(s.readRgba(), 64, 64), greaterThan(a + 50));
  });

  test('a light touch shrinks and fades dabs; the eraser takes paint away', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    s.loadStamp(
      disc(32),
      const StampSettings(pressureSize: 1, pressureOpacity: 0),
    );
    s.configure(diameter: 30, value: 0);
    stroke(s, y: 40, pressure: .2);
    stroke(s, y: 90, pressure: 1);
    final rgba = s.readRgba();
    expect(alphaAt(rgba, 64, 40 + 8), 0, reason: 'light: about 6 px wide');
    expect(alphaAt(rgba, 64, 90 + 8), 255, reason: 'firm: 30 px wide');
    s.configure(diameter: 30, value: 0, opacity: .75, eraser: true);
    stroke(s, y: 90);
    expect(alphaAt(s.readRgba(), 64, 90), inInclusiveRange(62, 66));
  });

  test('grain leaves the texture\'s gaps unpainted', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    // Vertical stripes: every other 4-pixel column is empty.
    final grain = Uint8List(8 * 8);
    for (var i = 0; i < grain.length; i++) {
      grain[i] = (i % 8) < 4 ? 255 : 0;
    }
    s.loadStamp(
      disc(32),
      const StampSettings(grainDepth: 1, pressureSize: 0, pressureOpacity: 0),
      grain: StampImage(grain, 8, 8),
    );
    s.configure(diameter: 24, value: 0);
    stroke(s);
    final rgba = s.readRgba();
    expect(alphaAt(rgba, 65, 64), 255);
    expect(alphaAt(rgba, 69, 64), 0);
  });

  test('bad stamps are refused and the previous brush keeps working', () {
    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    s.loadStamp(disc(16), const StampSettings());
    expect(
      () => s.loadStamp(disc(16), const StampSettings(spacing: 0)),
      throwsFormatException,
    );
    s.configure(diameter: 20, value: 0);
    stroke(s);
    expect(alphaAt(s.readRgba(), 64, 64), greaterThan(0));
    // A MyPaint preset takes over again.
    s.loadPreset(
      '{"version":3,"settings":{"opaque":{"base_value":1,"inputs":{}}}}',
    );
    s.configure(diameter: 10, value: 0);
    stroke(s, y: 100);
    expect(alphaAt(s.readRgba(), 64, 100), greaterThan(0));
  });

  test('settings survive JSON and refuse out-of-range values', () {
    const settings = StampSettings(
      spacing: .2,
      followStroke: true,
      grainDepth: .7,
    );
    final back = StampSettings.fromJson(settings.toJson());
    expect(back.params, settings.params);
    expect(() => StampSettings.fromJson({'flow': 0}), throwsFormatException);
    expect(StampSettings.fromJson({}).params, const StampSettings().params);
  });

  test('symmetry draws mirrored copies for MyPaint and stamp brushes', () {
    for (final stamp in [false, true]) {
      final s = NativeBrushSurface(width: 128, height: 128);
      addTearDown(s.close);
      if (stamp) {
        s.loadStamp(
          disc(16),
          const StampSettings(pressureSize: 0, pressureOpacity: 0),
        );
      } else {
        s.loadPreset(
          '{"version":3,"settings":{"opaque":{"base_value":1,"inputs":{}}}}',
        );
      }
      // Mirror across the vertical axis x = 64.
      s.setSymmetry([(1, 0, 0, 1), (-1, 0, 0, 1)], 64, 64);
      s.configure(diameter: 8, value: 0);
      s.beginStroke();
      for (var y = 20; y <= 100; y += 2) {
        s.point(x: 30, y: y.toDouble(), pressure: 1, seconds: .01);
      }
      final rgba = s.readRgba();
      expect(alphaAt(rgba, 30, 60), greaterThan(100), reason: 'stamp $stamp');
      expect(alphaAt(rgba, 98, 60), greaterThan(100), reason: 'mirror $stamp');
      expect(alphaAt(rgba, 64, 60), 0, reason: 'nothing between $stamp');
      expect(() => s.setSymmetry([(2, 0, 0, 1)], 0, 0), throwsArgumentError);
      // One copy again: no mirror.
      s.setSymmetry([(1, 0, 0, 1)], 64, 64);
      s.beginStroke();
      s.point(x: 30, y: 120, pressure: 1, seconds: .01);
      s.point(x: 31, y: 120, pressure: 1, seconds: .01);
      expect(alphaAt(s.readRgba(), 98, 120), 0);
    }
  });

  test('smudge drags paint along the stroke for stamp and MyPaint brushes', () {
    for (final stamp in [true, false]) {
      final s = NativeBrushSurface(width: 128, height: 128);
      addTearDown(s.close);
      // A black bar at x 20–40 on transparency.
      final rgba = Uint8List(128 * 128 * 4);
      for (var y = 0; y < 128; y++) {
        for (var x = 20; x < 40; x++) {
          rgba[(y * 128 + x) * 4 + 3] = 255;
        }
      }
      s.loadRgba(rgba);
      if (stamp) {
        s.loadStamp(
          disc(32),
          const StampSettings(
            spacing: .05,
            pressureSize: 0,
            pressureOpacity: 0,
          ),
        );
      } else {
        s.loadPreset(
          '{"version":3,"settings":{"opaque":{"base_value":1,"inputs":{}},'
          '"smudge_length":{"base_value":0.9,"inputs":{}}}}',
        );
      }
      s.configure(diameter: 16, hue: .6, saturation: 1, value: 1, opacity: .9);
      s.setSmudge(true);
      s.beginStroke();
      for (var x = 30; x <= 90; x += 1) {
        s.point(x: x.toDouble(), y: 64, pressure: 1, seconds: .01);
      }
      final out = s.readRgba();
      expect(alphaAt(out, 55, 64), greaterThan(40), reason: 'dragged ($stamp)');
      expect(
        out[(64 * 128 + 55) * 4 + 2],
        lessThan(60),
        reason: 'not blue ($stamp)',
      );
      expect(alphaAt(out, 55, 100), 0, reason: 'only along the stroke');
      // Off again: paints.
      s.setSmudge(false);
      s.beginStroke();
      for (var x = 60; x <= 100; x += 2) {
        s.point(x: x.toDouble(), y: 20, pressure: 1, seconds: .01);
      }
      expect(alphaAt(s.readRgba(), 80, 20), greaterThan(100), reason: '$stamp');
    }
  });

  test('a dual brush combines its two tips: multiply paints only where both '
      'do, screen where either does; loading a single brush ends it', () {
    // The secondary tip: its top half only.
    final half = Uint8List(32 * 32);
    for (var i = 0; i < 32 * 16; i++) {
      half[i] = 255;
    }
    final top = StampImage(half, 32, 32);
    const flat = StampSettings(
      spacing: .05,
      pressureSize: 0,
      pressureOpacity: 0,
    );
    Uint8List paint(DualBlend? blend) {
      final s = NativeBrushSurface(width: 128, height: 128);
      addTearDown(s.close);
      s.loadStamp(
        disc(32),
        flat,
        dual: blend == null
            ? null
            : (top, DualStamp(blend: blend, size: 1, spacing: .05)),
      );
      s.configure(diameter: 30, value: 0);
      stroke(s);
      return s.readRgba();
    }

    final single = paint(null);
    expect(alphaAt(single, 64, 56), 255);
    expect(alphaAt(single, 64, 72), 255);
    final both = paint(DualBlend.multiply);
    expect(alphaAt(both, 64, 56), 255, reason: 'both tips cover the top');
    expect(alphaAt(both, 64, 72), 0, reason: 'the secondary leaves the bottom');
    final either = paint(DualBlend.screen);
    expect(alphaAt(either, 64, 72), 255);
    expect(alphaAt(either, 64, 50), 255);
    final cut = paint(DualBlend.subtract);
    expect(alphaAt(cut, 64, 56), 0, reason: 'the secondary cuts the top out');
    expect(alphaAt(cut, 64, 72), 255);

    final s = NativeBrushSurface(width: 128, height: 128);
    addTearDown(s.close);
    s.loadStamp(disc(32), flat, dual: (top, const DualStamp()));
    s.loadStamp(disc(32), flat);
    s.configure(diameter: 30, value: 0);
    stroke(s);
    expect(alphaAt(s.readRgba(), 64, 72), 255, reason: 'single again');
    expect(
      () => s.loadStamp(disc(32), flat, dual: (top, const DualStamp(size: 9))),
      throwsFormatException,
    );
  });

  test('wet mix: pull carries the colour it crosses, charge runs out, '
      'dilution thins the paint', () {
    // The left quarter blue, the rest empty.
    final blue = Uint8List(128 * 128 * 4);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 32; x++) {
        blue.setAll((y * 128 + x) * 4, [0, 0, 255, 255]);
      }
    }
    const flat = StampSettings(
      spacing: .05,
      pressureSize: 0,
      pressureOpacity: 0,
    );
    Uint8List paint(StampSettings settings, {bool onBlue = false}) {
      final s = NativeBrushSurface(width: 128, height: 128);
      addTearDown(s.close);
      if (onBlue) s.loadRgba(blue);
      s.loadStamp(disc(16), settings);
      s.configure(diameter: 14, hue: 0, saturation: 1, value: 1);
      stroke(s);
      return s.readRgba();
    }

    List<int> rgbaAt(Uint8List p, int x, int y) =>
        p.sublist((y * 128 + x) * 4, (y * 128 + x) * 4 + 4);

    final dry = paint(flat, onBlue: true);
    expect(rgbaAt(dry, 80, 64).sublist(0, 3), [255, 0, 0], reason: 'red');
    final pulled = paint(flat.copyWith(pull: .6), onBlue: true);
    final carried = rgbaAt(pulled, 80, 64);
    expect(carried[2], greaterThan(carried[0]), reason: 'blue carried on');
    expect(carried[3], 255);

    final short = paint(flat.copyWith(charge: .2));
    expect(alphaAt(short, 24, 64), 255, reason: 'loaded at first');
    expect(alphaAt(short, 104, 64), lessThan(60), reason: 'runs out');
    final thin = paint(flat.copyWith(dilution: 1));
    expect(alphaAt(thin, 64, 64), lessThan(alphaAt(paint(flat), 64, 64)));
    expect(alphaAt(thin, 64, 64), greaterThan(0));
    expect(
      StampSettings.fromJson(flat.copyWith(pull: .3, charge: .5).toJson()),
      flat.copyWith(pull: .3, charge: .5),
    );
    expect(flat.toJson().containsKey('pull'), isFalse, reason: 'dry');
  });
}
