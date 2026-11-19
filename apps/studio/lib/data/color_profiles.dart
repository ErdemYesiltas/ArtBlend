import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/document.dart';
import 'export_formats.dart';

/// Primaries as XYZ (D50, as ICC profiles keep them).
typedef _Colorants = (
  (double, double, double),
  (double, double, double),
  (double, double, double),
);

const _srgb = (
  (0.4360747, 0.2225045, 0.0139322),
  (0.3850649, 0.7168786, 0.0971045),
  (0.1430804, 0.0606169, 0.7141733),
);
const _displayP3 = (
  (0.515102, 0.241182, -0.001050),
  (0.291965, 0.692236, 0.041882),
  (0.157153, 0.066582, 0.784073),
);

final _profiles = <ColorProfile, Uint8List>{};

/// The ICC profile of an RGB [profile] (sRGB or Display P3): primaries
/// and the sRGB tone curve, version 2, made here rather than shipped.
/// Null for CMYK, which has no profile of ArtBlend's own.
Uint8List? iccProfile(ColorProfile profile) => switch (profile) {
  ColorProfile.cmyk => null,
  ColorProfile.srgb => _profiles[profile] ??= _rgbIcc('sRGB', _srgb),
  ColorProfile.displayP3 => _profiles[profile] ??= _rgbIcc(
    'Display P3',
    _displayP3,
  ),
};

Uint8List _rgbIcc(String name, _Colorants colorants) {
  final tags = <(String, Uint8List)>[];
  Uint8List bytes(void Function(ByteData d) write, int length) {
    final d = ByteData(length);
    write(d);
    return d.buffer.asUint8List();
  }

  int fixed(double v) => (v * 65536).round();
  Uint8List xyz(double x, double y, double z) => bytes((d) {
    d
      ..setUint32(0, 0x58595A20) // 'XYZ '
      ..setInt32(8, fixed(x))
      ..setInt32(12, fixed(y))
      ..setInt32(16, fixed(z));
  }, 20);

  final ascii = latin1.encode(name);
  final desc = bytes((d) {
    d
      ..setUint32(0, 0x64657363) // 'desc'
      ..setUint32(8, ascii.length + 1);
    for (var i = 0; i < ascii.length; i++) {
      d.setUint8(12 + i, ascii[i]);
    }
  }, 12 + ascii.length + 1 + 4 + 4 + 2 + 1 + 67);
  final copyright = latin1.encode('No copyright, use freely');
  final text = bytes((d) {
    d.setUint32(0, 0x74657874); // 'text'
    for (var i = 0; i < copyright.length; i++) {
      d.setUint8(8 + i, copyright[i]);
    }
  }, 8 + copyright.length + 1);
  // The sRGB transfer curve (Display P3 uses it too), 1024 steps.
  const steps = 1024;
  final curve = bytes((d) {
    d
      ..setUint32(0, 0x63757276) // 'curv'
      ..setUint32(8, steps);
    for (var i = 0; i < steps; i++) {
      final v = i / (steps - 1);
      final linear = v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      d.setUint16(12 + i * 2, (linear * 65535).round());
    }
  }, 12 + steps * 2);
  final (r, g, b) = colorants;
  tags
    ..add(('desc', desc))
    ..add(('cprt', text))
    ..add(('wtpt', xyz(0.9642, 1.0, 0.8249)))
    ..add(('rXYZ', xyz(r.$1, r.$2, r.$3)))
    ..add(('gXYZ', xyz(g.$1, g.$2, g.$3)))
    ..add(('bXYZ', xyz(b.$1, b.$2, b.$3)))
    ..add(('rTRC', curve))
    ..add(('gTRC', curve))
    ..add(('bTRC', curve));

  // Header, tag table, then the data (the three curves shared).
  final tableSize = 4 + tags.length * 12;
  final offsets = <String, (int, int)>{};
  final body = BytesBuilder();
  var at = 128 + tableSize;
  final placed = <Uint8List, int>{};
  for (final (sig, data) in tags) {
    final known = placed[data];
    if (known != null) {
      offsets[sig] = (known, data.length);
      continue;
    }
    placed[data] = at;
    offsets[sig] = (at, data.length);
    body.add(data);
    at += data.length;
    while (at % 4 != 0) {
      body.addByte(0);
      at++;
    }
  }
  final total = at;
  final out = ByteData(total);
  int sig(String s) => s.codeUnits.fold(0, (v, c) => v << 8 | c);
  out
    ..setUint32(0, total)
    ..setUint32(8, 0x02100000)
    ..setUint32(12, sig('mntr'))
    ..setUint32(16, sig('RGB '))
    ..setUint32(20, sig('XYZ '))
    ..setUint16(24, 2026)
    ..setUint16(26, 1)
    ..setUint16(28, 1)
    ..setUint32(36, sig('acsp'))
    ..setInt32(68, fixed(0.9642))
    ..setInt32(72, fixed(1.0))
    ..setInt32(76, fixed(0.8249))
    ..setUint32(128, tags.length);
  for (final (i, (s, _)) in tags.indexed) {
    final (offset, size) = offsets[s]!;
    out
      ..setUint32(132 + i * 12, sig(s))
      ..setUint32(136 + i * 12, offset)
      ..setUint32(140 + i * 12, size);
  }
  final result = out.buffer.asUint8List();
  result.setAll(128 + tableSize, body.takeBytes());
  return result;
}

/// Straight RGBA as C, M, Y, K, alpha (0–255 ink), a byte each: grey
/// replaced by black, the total ink kept under 300%. A plain model, not a
/// press profile.
Uint8List rgbaToCmyka(Uint8List rgba) {
  final out = Uint8List(rgba.length ~/ 4 * 5);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 5) {
    final r = rgba[i] / 255, g = rgba[i + 1] / 255, b = rgba[i + 2] / 255;
    final k = 1 - math.max(r, math.max(g, b));
    var c = 0.0, m = 0.0, y = 0.0;
    if (k < 1) {
      c = (1 - r - k) / (1 - k);
      m = (1 - g - k) / (1 - k);
      y = (1 - b - k) / (1 - k);
    }
    final ink = c + m + y + k;
    if (ink > 3) {
      final f = (3 - k) / (c + m + y);
      c *= f;
      m *= f;
      y *= f;
    }
    out
      ..[o] = (c * 255).round()
      ..[o + 1] = (m * 255).round()
      ..[o + 2] = (y * 255).round()
      ..[o + 3] = (k * 255).round()
      ..[o + 4] = rgba[i + 3];
  }
  return out;
}

/// An uncompressed TIFF: RGBA with [icc] embedded, or with [cmyk] the
/// pixels separated (C, M, Y, K and alpha).
Uint8List encodeProfiledTiff(
  RgbaPixels p, {
  Uint8List? icc,
  bool cmyk = false,
}) {
  final channels = cmyk ? 5 : 4;
  final pixels = cmyk ? rgbaToCmyka(p.bytes) : p.bytes;
  final entries = <(int, int, int, Object)>[
    // tag, type (3 short, 4 long, 7 undefined), count, value
    (256, 4, 1, p.width),
    (257, 4, 1, p.height),
    (258, 3, channels, List.filled(channels, 8)),
    (259, 3, 1, 1),
    (262, 3, 1, cmyk ? 5 : 2),
    (273, 4, 1, 0), // strip offset: filled in below
    (277, 3, 1, channels),
    (278, 4, 1, p.height),
    (279, 4, 1, pixels.length),
    (284, 3, 1, 1),
    (338, 3, 1, 2), // the extra sample: unassociated alpha
    if (cmyk) (332, 3, 1, 1), // ink set: CMYK
    if (icc != null) (34675, 7, icc.length, icc),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  const header = 8;
  final ifdSize = 2 + entries.length * 12 + 4;
  var extra = header + ifdSize;
  final blobs = <int, (int, List<int>)>{};
  for (final (tag, type, count, value) in entries) {
    final size =
        (type == 3
            ? 2
            : type == 4
            ? 4
            : 1) *
        count;
    if (size > 4) {
      final data = value is Uint8List
          ? value
          : [
              for (final v in value as List<int>) ...[v & 0xff, v >> 8],
            ];
      blobs[tag] = (extra, data);
      extra += data.length + data.length % 2;
    }
  }
  final stripAt = extra;
  final out = ByteData(stripAt + pixels.length);
  out
    ..setUint16(0, 0x4949, Endian.little)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, header, Endian.little)
    ..setUint16(header, entries.length, Endian.little);
  for (final (i, (tag, type, count, value)) in entries.indexed) {
    final at = header + 2 + i * 12;
    out
      ..setUint16(at, tag, Endian.little)
      ..setUint16(at + 2, type, Endian.little)
      ..setUint32(at + 4, count, Endian.little);
    final blob = blobs[tag];
    if (blob != null) {
      out.setUint32(at + 8, blob.$1, Endian.little);
      final bytes = out.buffer.asUint8List();
      bytes.setAll(blob.$1, blob.$2);
    } else if (tag == 273) {
      out.setUint32(at + 8, stripAt, Endian.little);
    } else if (type == 3) {
      out.setUint16(at + 8, value as int, Endian.little);
    } else {
      out.setUint32(at + 8, value as int, Endian.little);
    }
  }
  out.setUint32(header + 2 + entries.length * 12, 0, Endian.little);
  final result = out.buffer.asUint8List();
  result.setAll(stripAt, pixels);
  return result;
}
