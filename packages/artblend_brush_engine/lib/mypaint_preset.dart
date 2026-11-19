import 'dart:convert';
import 'dart:math' as math;

/// The brush file version libmypaint reads: JSON.
const mypaintPresetVersion = 3;

/// A MyPaint brush file as the version 3 JSON libmypaint reads.
///
/// Version 3 JSON is returned unchanged. The line-based files written by
/// MyPaint 1.0 and earlier (versions 1 and 2, e.g. widely shared brush kits)
/// are translated: `name value | input (x y), (x y)` lines become settings,
/// renamed settings move to their current names with their scale, obsolete
/// ones are dropped, and anti-aliasing stays off unless the file sets it, as
/// those brushes were painted without it. Unknown settings are left for the
/// engine to skip.
String normalizeMypaintPreset(String text) {
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  if (body.trimLeft().startsWith('{')) return body;
  var version = 1;
  final raw = <(String, String)>[];
  for (final line in const LineSplitter().convert(body)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final space = trimmed.indexOf(' ');
    final name = space < 0 ? trimmed : trimmed.substring(0, space);
    final value = space < 0 ? '' : trimmed.substring(space + 1).trim();
    if (name == 'version') {
      version =
          int.tryParse(value) ??
          (throw const FormatException('Invalid MyPaint brush version'));
      if (version < 1 || version > 2) {
        throw FormatException('Unsupported MyPaint brush version $version');
      }
    } else {
      raw.add((name, value));
    }
  }
  final preset = <String, Object>{'version': mypaintPresetVersion};
  final settings = <String, Map<String, Object>>{};
  for (final (name, value) in raw) {
    if (_textFields.contains(name)) {
      preset[name] = value;
      continue;
    }
    try {
      settings.addAll(_legacySetting(name, value, version));
    } on FormatException {
      // MyPaint skipped lines it could not read; so do we.
    }
  }
  if (settings.isEmpty) {
    throw const FormatException('No MyPaint brush settings found');
  }
  settings.putIfAbsent(
    'anti_aliasing',
    () => {'base_value': 0.0, 'inputs': <String, Object>{}},
  );
  preset['settings'] = settings;
  return jsonEncode(preset);
}

const _textFields = {'parent_brush_name', 'group', 'comment'};

/// Old name → current name and the scale applied to its values.
final Map<String, (String, double Function(double))> _renamed = {
  'color_hue': ('change_color_h', (y) => y * 64 / 360),
  'color_saturation': ('change_color_hsv_s', (y) => y * 128 / 256),
  'color_value': ('change_color_v', (y) => y * 128 / 256),
  'speed_slowness': ('speed1_slowness', (y) => y),
  'change_color_s': ('change_color_hsv_s', (y) => y),
  'stroke_treshold': ('stroke_threshold', (y) => y),
};

/// Settings that no longer exist; MyPaint ignored them too.
const _obsolete = {'adapt_color_from_image', 'change_radius', 'painting_time'};

Map<String, Map<String, Object>> _legacySetting(
  String name,
  String value,
  int version,
) {
  if (_obsolete.contains(name)) return const {};
  if (version == 1 && name == 'color') {
    final rgb = value.split(RegExp(r'\s+')).map((c) => int.parse(c) / 255);
    final (h, s, v) = _hsv(
      rgb.elementAt(0),
      rgb.elementAt(1),
      rgb.elementAt(2),
    );
    return {
      'color_h': _setting(h, const {}),
      'color_s': _setting(s, const {}),
      'color_v': _setting(v, const {}),
    };
  }
  var target = version == 1 && name == 'speed' ? 'speed1' : name;
  var scale = (double y) => y;
  final renamed = _renamed[target];
  if (renamed != null) (target, scale) = renamed;
  final parts = value.split('|');
  final base = double.parse(parts.first.trim());
  final inputs = <String, List<List<double>>>{};
  for (final part in parts.skip(1)) {
    final text = part.trim();
    final space = text.indexOf(' ');
    if (space < 0) throw const FormatException('Missing input points');
    var input = text.substring(0, space);
    if (version == 1 && input == 'speed') input = 'speed1';
    final points = version == 1
        ? _pointsV1(text.substring(space + 1))
        : _pointsV2(text.substring(space + 1));
    inputs[input] = [
      for (final (x, y) in points) [x, scale(y)],
    ];
  }
  return {target: _setting(scale(base), inputs)};
}

Map<String, Object> _setting(double base, Map<String, Object> inputs) => {
  'base_value': base,
  'inputs': inputs,
};

/// `(x y), (x y), …`
List<(double, double)> _pointsV2(String text) => [
  for (final match in RegExp(r'\(\s*(\S+)\s+(\S+)\s*\)').allMatches(text))
    (double.parse(match.group(1)!), double.parse(match.group(2)!)),
];

/// Flat `x y x y …` after an implied (0, 0), ending at the first x of 0.
List<(double, double)> _pointsV1(String text) {
  final numbers = text.trim().split(RegExp(r'\s+')).map(double.parse).toList();
  final points = [(0.0, 0.0)];
  for (var i = 0; i + 1 < numbers.length; i += 2) {
    if (numbers[i] == 0) break;
    points.add((numbers[i], numbers[i + 1]));
  }
  return points;
}

(double, double, double) _hsv(double r, double g, double b) {
  final maximum = math.max(r, math.max(g, b));
  final minimum = math.min(r, math.min(g, b));
  final delta = maximum - minimum;
  var hue = 0.0;
  if (delta > 0) {
    if (maximum == r) {
      hue = ((g - b) / delta) % 6;
    } else if (maximum == g) {
      hue = (b - r) / delta + 2;
    } else {
      hue = (r - g) / delta + 4;
    }
    hue /= 6;
    if (hue < 0) hue += 1;
  }
  return (hue, maximum == 0 ? 0 : delta / maximum, maximum);
}
