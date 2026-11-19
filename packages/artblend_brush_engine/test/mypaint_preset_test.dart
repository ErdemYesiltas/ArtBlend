import 'dart:convert';

import 'package:artblend_brush_engine/artblend_brush_engine.dart';
import 'package:artblend_brush_engine/mypaint_preset.dart';
import 'package:test/test.dart';

// Written for these tests in the line format of MyPaint 1.0 brush files.
const version2 = '''
# mypaint brush file
version 2
parent_brush_name classic/pencil
opaque 0.6
opaque_multiply 0.0 | pressure (0.000000 0.000000), (1.000000 1.000000)
radius_logarithmic 1.2 | pressure (0.000000 -0.300000), (0.500000 0.000000), (1.000000 0.400000) | speed1 (0.000000 0.000000), (2.000000 0.200000)
hardness 0.8
color_h 0.6
color_s 0.7
color_v 0.5
adapt_color_from_image 0.0
stroke_treshold 0.1
this line is not a setting
''';

const version1 = '''
version 1
color 255 0 0
opaque 0.9
opaque_multiply 0.0 | pressure 1.0 1.0
radius_logarithmic 1.0 | speed 1.0 0.5 0 0
color_hue 0.0 | pressure 1.0 90.0
painting_time 0.0
''';

Map<String, dynamic> settingsOf(String text) =>
    (jsonDecode(normalizeMypaintPreset(text)) as Map)['settings']
        as Map<String, dynamic>;

void main() {
  test('version 3 JSON passes through unchanged', () {
    const json =
        '{"version":3,"settings":{"opaque":{"base_value":1,"inputs":{}}}}';
    expect(normalizeMypaintPreset(json), json);
    expect(normalizeMypaintPreset('\uFEFF$json'), json);
  });

  test('a version 2 line file becomes version 3 JSON the engine loads', () {
    final converted = jsonDecode(normalizeMypaintPreset(version2)) as Map;
    expect(converted['version'], 3);
    expect(converted['parent_brush_name'], 'classic/pencil');
    final settings = converted['settings'] as Map;
    expect(settings['opaque'], {'base_value': .6, 'inputs': {}});
    expect(settings['radius_logarithmic']['inputs'], {
      'pressure': [
        [0.0, -0.3],
        [0.5, 0.0],
        [1.0, 0.4],
      ],
      'speed1': [
        [0.0, 0.0],
        [2.0, 0.2],
      ],
    });
    expect(settings['stroke_threshold']['base_value'], .1);
    expect(settings.containsKey('adapt_color_from_image'), isFalse);
    // Old brushes were painted without anti-aliasing.
    expect(settings['anti_aliasing']['base_value'], 0.0);

    final surface = NativeBrushSurface(width: 64, height: 64);
    addTearDown(surface.close);
    surface.loadPreset(normalizeMypaintPreset(version2));
    surface.configure(diameter: 8);
    surface.beginStroke();
    for (var x = 8; x < 56; x++) {
      surface.point(x: x.toDouble(), y: 32, pressure: .8, seconds: .01);
    }
    expect(surface.readRgba().any((v) => v != 0), isTrue);
  });

  test('version 1 values move to their current names and scale', () {
    final settings = settingsOf(version1);
    expect(settings['color_h']['base_value'], 0.0);
    expect(settings['color_s']['base_value'], 1.0);
    expect(settings['color_v']['base_value'], 1.0);
    // Version 1 curves start at an implied (0, 0) and end at x = 0.
    expect(settings['opaque_multiply']['inputs']['pressure'], [
      [0.0, 0.0],
      [1.0, 1.0],
    ]);
    expect(settings['radius_logarithmic']['inputs']['speed1'], [
      [0.0, 0.0],
      [1.0, 0.5],
    ]);
    expect(settings['change_color_h']['inputs']['pressure'][1][1], 16.0);
    expect(settings.containsKey('painting_time'), isFalse);
    NativeBrushSurface(width: 8, height: 8)
      ..loadPreset(normalizeMypaintPreset(version1))
      ..close();
  });

  test('files that are not brushes are refused', () {
    expect(() => normalizeMypaintPreset('hello'), throwsFormatException);
    expect(
      () => normalizeMypaintPreset('version 9\nopaque 1.0'),
      throwsFormatException,
    );
    expect(
      () => normalizeMypaintPreset('# only a comment'),
      throwsFormatException,
    );
  });
}
