import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:image/image.dart' as img;

import '../domain/document.dart';
import 'plist.dart';

/// Edges imported tips and grains are fitted to before they are kept.
const _tipSide = 256, _grainSide = 512;

/// [png] (any size) as a smaller PNG, for a brush to keep.
Uint8List _fitPng(Uint8List png, int side) {
  final image = img.decodeImage(png);
  if (image == null) throw const FormatException('Unreadable brush image');
  if (math.max(image.width, image.height) <= side) return png;
  final scale = side / math.max(image.width, image.height);
  return img.encodePng(
    img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
      interpolation: img.Interpolation.average,
    ),
  );
}

double _number(Map<String, Object?> o, List<String> keys, double fallback) {
  for (final k in keys) {
    final v = o[k];
    if (v is num && v.isFinite) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
  }
  return fallback;
}

/// Procreate brushes: a `.brush` (one brush) or a `.brushset` (several in
/// folders). Each keeps its shape and grain images and, from its settings,
/// what ArtBlend's stamp engine has: spacing, scatter, jitters, rotation,
/// pressure, grain depth and scale.
List<BrushPreset> decodeProcreateBrushes(Uint8List bytes, String filename) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final f in zip.files)
      if (f.isFile) f.name.replaceAll(r'\', '/'): f,
  };
  // A brush is a folder (or the root) holding Brush.archive.
  final folders = [
    for (final name in files.keys)
      if (name == 'Brush.archive' || name.endsWith('/Brush.archive'))
        name.substring(0, name.length - 'Brush.archive'.length),
  ]..sort();
  if (folders.isEmpty) throw const FormatException('No Procreate brush found');
  // A brushset lists its brushes' order.
  final listing = files['brushset.plist'];
  if (listing != null) {
    try {
      final plist = readBinaryPlist(listing.content);
      final order = plist is Map ? plist['brushes'] : null;
      if (order is List) {
        final rank = {for (final (i, id) in order.indexed) '$id/': i};
        folders.sort(
          (a, b) => (rank[a] ?? 1 << 20).compareTo(rank[b] ?? 1 << 20),
        );
      }
    } on Object {
      // Unordered.
    }
  }
  final stem = filename.replaceFirst(
    RegExp(r'\.(brush|brushset)$', caseSensitive: false),
    '',
  );
  final brushes = <BrushPreset>[];
  for (final (i, folder) in folders.indexed) {
    Map<String, Object?> settings = const {};
    try {
      settings = unarchiveRoot(
        readBinaryPlist(files['${folder}Brush.archive']!.content),
      );
    } on Object {
      // Settings unreadable: the images still make the brush.
    }
    final shape = files['${folder}Shape.png'];
    final grain = files['${folder}Grain.png'];
    final name = switch (settings['name']) {
      final String n when n.trim().isNotEmpty => n.trim(),
      _ => folders.length == 1 ? stem : '$stem ${i + 1}',
    };
    final rotation = _number(settings, ['shapeRotation'], 0);
    brushes.add(
      BrushPreset(
        id: newId(),
        name: name.length > 64 ? name.substring(0, 64) : name,
        size: (_number(settings, ['paintSize'], .3) * 100).clamp(2, 128),
        engine: BrushEngineKind.stamp,
        tip: shape == null
            ? 'builtin:round-soft'
            : 'png:${base64Encode(_fitPng(shape.content, _tipSide))}',
        grain: grain == null
            ? null
            : 'png:${base64Encode(_fitPng(grain.content, _grainSide))}',
        stamp: StampSettings(
          spacing: _number(settings, ['plotSpacing'], .1).clamp(.01, 4),
          scatter: _number(settings, ['plotJitter'], 0).clamp(0, 4),
          sizeJitter: _number(settings, ['dynamicsJitterSize'], 0).clamp(0, 1),
          opacityJitter: _number(settings, [
            'dynamicsJitterOpacity',
          ], 0).clamp(0, 1),
          followStroke: rotation >= .99,
          rotationJitter: _number(settings, ['shapeScatter'], 0).clamp(0, 1),
          pressureSize: _number(settings, [
            'dynamicsPressureSize',
          ], .6).clamp(0, 1),
          pressureOpacity: _number(settings, [
            'dynamicsPressureOpacity',
          ], .3).clamp(0, 1),
          flow: _number(settings, [
            'plotFlow',
            'paintFlow',
            'stampFlow',
          ], 1).clamp(.01, 1),
          grainDepth: grain == null
              ? 0
              : _number(settings, ['textureDepth'], .5).clamp(0, 1),
          grainScale: (_number(settings, ['textureScale'], .5) * 2).clamp(
            .1,
            8,
          ),
        ),
      ),
    );
  }
  return brushes;
}

/// [brush]'s settings in Procreate's names.
Map<String, Object> _procreateSettings(BrushPreset brush) {
  final s = brush.stamp ?? const StampSettings();
  return {
    'name': brush.name,
    'paintSize': (brush.size / 100).clamp(0.0, 1.0),
    'paintOpacity': 1.0,
    'plotSpacing': s.spacing,
    'plotJitter': s.scatter,
    'plotFlow': s.flow,
    'dynamicsJitterSize': s.sizeJitter,
    'dynamicsJitterOpacity': s.opacityJitter,
    'dynamicsPressureSize': s.pressureSize,
    'dynamicsPressureOpacity': s.pressureOpacity,
    'shapeRotation': s.followStroke ? 1.0 : 0.0,
    'shapeScatter': s.rotationJitter,
    'textureDepth': s.grainDepth,
    'textureScale': s.grainScale / 2,
    'authorName': 'ArtBlend',
  };
}

/// A brush's files inside a `.brush` (at the root) or a `.brushset` (in
/// [folder]): settings, shape, grain and preview.
void _addBrush(
  Archive zip,
  String folder,
  BrushPreset brush,
  Uint8List shape,
  Uint8List? grain,
) {
  zip.addFile(
    ArchiveFile.bytes(
      '${folder}Brush.archive',
      archiveObject('SilicaBrush', _procreateSettings(brush)),
    ),
  );
  zip.addFile(ArchiveFile.bytes('${folder}Shape.png', shape));
  if (grain != null) {
    zip.addFile(ArchiveFile.bytes('${folder}Grain.png', grain));
  }
  zip.addFile(ArchiveFile.bytes('${folder}QuickLook/Thumbnail.png', shape));
}

/// Shape and grain PNGs (white paints) for each brush, already rendered.
typedef BrushImages = ({BrushPreset brush, Uint8List shape, Uint8List? grain});

Uint8List encodeProcreateBrush(BrushImages b) {
  final zip = Archive();
  _addBrush(zip, '', b.brush, b.shape, b.grain);
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

Uint8List encodeProcreateBrushset(String name, List<BrushImages> brushes) {
  final zip = Archive();
  final ids = [for (final _ in brushes) newId().toUpperCase()];
  for (final (i, b) in brushes.indexed) {
    _addBrush(zip, '${ids[i]}/', b.brush, b.shape, b.grain);
  }
  zip.addFile(
    ArchiveFile.bytes(
      'brushset.plist',
      writeBinaryPlist({'name': name, 'brushes': ids}),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

/// A grayscale stamp image as a PNG, white where it paints.
Uint8List stampPng(StampImage image) {
  final out = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 1,
  );
  out.buffer.asUint8List().setAll(0, image.pixels);
  return img.encodePng(out);
}

// ---- Photoshop .abr ----

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int at = 0;
  bool get done => at >= bytes.length;
  void need(int n) {
    if (at + n > bytes.length) throw const FormatException('Damaged .abr');
  }

  int u8() {
    need(1);
    return bytes[at++];
  }

  int u16() {
    need(2);
    final v = data.getUint16(at);
    at += 2;
    return v;
  }

  int i16() {
    need(2);
    final v = data.getInt16(at);
    at += 2;
    return v;
  }

  int u32() {
    need(4);
    final v = data.getUint32(at);
    at += 4;
    return v;
  }

  int i32() {
    need(4);
    final v = data.getInt32(at);
    at += 4;
    return v;
  }

  String ascii(int n) {
    need(n);
    final s = latin1.decode(bytes.sublist(at, at + n));
    at += n;
    return s;
  }

  Uint8List take(int n) {
    need(n);
    final v = Uint8List.sublistView(bytes, at, at + n);
    at += n;
    return v;
  }
}

/// Photoshop's PackBits, [height] rows of [width].
Uint8List _unpackRows(_Reader r, int width, int height) {
  final lengths = [for (var y = 0; y < height; y++) r.u16()];
  final out = Uint8List(width * height);
  var o = 0;
  for (final length in lengths) {
    final end = r.at + length;
    final rowEnd = o + width;
    while (r.at < end && o < rowEnd) {
      final n = r.u8();
      if (n < 128) {
        for (var i = 0; i <= n && o < rowEnd; i++) {
          out[o++] = r.u8();
        }
      } else if (n > 128) {
        final v = r.u8();
        for (var i = 0; i < 257 - n && o < rowEnd; i++) {
          out[o++] = v;
        }
      }
    }
    r.at = end;
    o = rowEnd;
  }
  return out;
}

/// A sampled brush's pixels: [depth]-bit, RLE when [compressed].
StampImage? _sample(
  _Reader r,
  int width,
  int height,
  int depth,
  bool compressed,
) {
  if (width <= 0 || height <= 0 || width > 5000 || height > 5000) return null;
  if (depth != 8 && depth != 16) return null;
  Uint8List pixels;
  if (compressed) {
    pixels = _unpackRows(r, width * depth ~/ 8, height);
  } else {
    pixels = Uint8List.fromList(r.take(width * height * depth ~/ 8));
  }
  if (depth == 16) {
    pixels = Uint8List.fromList([
      for (var i = 0; i < pixels.length; i += 2) pixels[i],
    ]);
  }
  return StampImage(pixels, width, height);
}

/// The sampled brushes (tips) of a Photoshop `.abr` file, versions 1, 2
/// and 6–10. Computed (procedural) brushes and brush settings are left out.
List<StampImage> decodeAbrTips(Uint8List bytes) {
  final r = _Reader(bytes);
  final version = r.u16();
  final tips = <StampImage>[];
  if (version == 1 || version == 2) {
    final count = r.u16();
    for (var i = 0; i < count && !r.done; i++) {
      final type = r.u16();
      final size = r.u32();
      final end = r.at + size;
      if (type == 2) {
        r
          ..u32() // misc
          ..u16(); // spacing
        if (version == 2) {
          final chars = r.u32();
          r.take(chars * 2);
        }
        r
          ..u8() // antialias
          ..take(8); // short bounds
        final top = r.i32(), left = r.i32(), bottom = r.i32(), right = r.i32();
        final depth = r.u16();
        final compressed = r.u8() == 1;
        final tip = _sample(r, right - left, bottom - top, depth, compressed);
        if (tip != null) tips.add(tip);
      }
      r.at = end;
    }
  } else if (version >= 6 && version <= 10) {
    final subversion = r.u16();
    while (!r.done) {
      if (r.ascii(4) != '8BIM') break;
      final key = r.ascii(4);
      final size = r.u32();
      final end = r.at + size;
      if (key != 'samp') {
        r.at = end;
        continue;
      }
      while (r.at < end) {
        var length = r.u32();
        length = (length + 3) & ~3;
        final next = r.at + length;
        // The brush's id and header before its bounds.
        r.at += subversion == 1 ? 47 : 301;
        final top = r.i32(), left = r.i32(), bottom = r.i32(), right = r.i32();
        final depth = r.i16();
        final compressed = r.u8() == 1;
        try {
          final tip = _sample(r, right - left, bottom - top, depth, compressed);
          if (tip != null) tips.add(tip);
        } on FormatException {
          // A brush this reader does not follow is left out.
        }
        r.at = next;
      }
      r.at = end;
    }
  } else {
    throw FormatException('Unsupported .abr version $version');
  }
  if (tips.isEmpty) {
    throw const FormatException('No sampled brushes in the file');
  }
  return tips;
}

/// A stamp brush for each sampled tip of a `.abr` file.
List<BrushPreset> decodeAbrBrushes(Uint8List bytes, String filename) {
  final stem = filename.replaceFirst(
    RegExp(r'\.abr$', caseSensitive: false),
    '',
  );
  final tips = decodeAbrTips(bytes);
  return [
    for (final (i, tip) in tips.indexed)
      BrushPreset(
        id: newId(),
        name: tips.length == 1 ? stem : '$stem ${i + 1}',
        size: 40,
        engine: BrushEngineKind.stamp,
        tip: 'png:${base64Encode(_fitPng(stampPng(tip), _tipSide))}',
        stamp: const StampSettings(spacing: .15, pressureSize: .7),
      ),
  ];
}
