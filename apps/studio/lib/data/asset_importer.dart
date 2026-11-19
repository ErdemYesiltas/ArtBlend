import 'dart:convert';
import 'dart:typed_data';

import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:artblend_brush_engine/artblend_brush_engine.dart';
import 'package:artblend_brush_engine/mypaint_preset.dart';
import 'package:color_palette_formats/color_palette_formats.dart' as formats;
import 'package:material_ui/material_ui.dart' show HSVColor;

import '../domain/document.dart';

const maxImportBytes = 4 * 1024 * 1024;

class AssetImporter {
  static List<BrushPreset> brushes(Uint8List bytes) {
    _sizeCheck(bytes);
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['format'] != 'atelier.brushes' ||
        data['version'] != 1) {
      throw const FormatException('Expected ArtBlend brush presets v1 (.json)');
    }
    final entries = data['brushes'];
    if (entries is! List || entries.isEmpty || entries.length > 128) {
      throw const FormatException('A brush set must contain 1–128 presets');
    }
    return entries
        .map((b) => BrushPreset.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();
  }

  static List<ColorPalette> palettes(Uint8List bytes, String filename) {
    _sizeCheck(bytes);
    final extension = filename.split('.').last.toLowerCase();
    final name = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final colors = <int>[];
    switch (extension) {
      case 'hex':
        final rows = const LineSplitter().convert(utf8.decode(bytes));
        for (final row in rows) {
          if (row.trim().isEmpty) continue;
          colors.add(parseHex(row.trim()));
        }
      case 'json':
        final data = jsonDecode(utf8.decode(bytes));
        return [ColorPalette.fromJson(Map<String, dynamic>.from(data as Map))];
      case 'gpl':
        final palette = formats.GimpPalette.fromBytes(bytes);
        for (final c in palette.colors) {
          colors.add(_rgb(c.red / 255, c.green / 255, c.blue / 255));
        }
      case 'ase':
        final palette = formats.AdobeSwatchExchange.fromBytes(bytes);
        for (final c in palette.colors) {
          if (c.type == formats.AdobeSwatchExchangeColorType.spot) {
            throw const FormatException(
              'Spot colors are not supported in this milestone',
            );
          }
          switch (c.model) {
            case formats.AdobeSwatchExchangeColorModel.rgb:
              colors.add(_rgb(c.values[0], c.values[1], c.values[2]));
            case formats.AdobeSwatchExchangeColorModel.gray:
              colors.add(_rgb(c.values[0], c.values[0], c.values[0]));
            default:
              throw const FormatException(
                'Only RGB and gray ASE colors are supported',
              );
          }
        }
      case 'aco':
        final palette = formats.AdobeColorSwatch.fromBytes(bytes);
        for (final c in palette.colors) {
          switch (c.colorSpace) {
            case formats.AdobeColorSwatchColorSpace.rgb:
              colors.add(
                _rgb(c.values[0] / 255, c.values[1] / 255, c.values[2] / 255),
              );
            case formats.AdobeColorSwatchColorSpace.hsb:
              colors.add(
                _hsv(
                  c.values[0] / 360,
                  c.values[1] / 100,
                  c.values[2] / 100,
                  1,
                ),
              );
            default:
              throw const FormatException(
                'Only RGB and HSB ACO v1 colors are supported',
              );
          }
        }
      case 'swatches':
        // Inspect metadata before asking the ready-made decoder to decompress.
        final archive = ZipDecoder().decodeBytes(bytes, verify: true);
        if (archive.isEmpty ||
            archive.length > 16 ||
            archive.any(
              (f) =>
                  f.size > maxImportBytes ||
                  f.name.contains('..') ||
                  f.name.startsWith('/'),
            ) ||
            archive.fold<int>(0, (sum, f) => sum + f.size) > maxImportBytes) {
          throw const FormatException('Invalid or oversized swatches archive');
        }
        // Procreate's Swatches.json, read as UTF-8; empty slots are null.
        final entry = archive.files
            .where((f) => f.isFile && f.name.toLowerCase().endsWith('.json'))
            .firstOrNull;
        if (entry == null) throw const FormatException('No Swatches.json');
        final list = jsonDecode(utf8.decode(entry.content));
        if (list is! List) throw const FormatException('Invalid swatches');
        double number(Object? v) => v is num
            ? v.toDouble()
            : throw const FormatException('Invalid swatch');
        return [
          for (final p in list)
            if (p is Map)
              _palette(
                p['name'] is String && (p['name'] as String).trim().isNotEmpty
                    ? (p['name'] as String).trim()
                    : name,
                [
                  for (final c in (p['swatches'] as List? ?? const []))
                    if (c is Map)
                      _hsv(
                        number(c['hue']),
                        number(c['saturation']),
                        number(c['brightness']),
                        number(c['alpha'] ?? 1),
                      ),
                ],
              ),
        ];
      default:
        throw const FormatException('Unsupported palette format');
    }
    return [_palette(name, colors)];
  }

  static void _sizeCheck(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxImportBytes) {
      throw const FormatException(
        'Import size must be between 1 byte and 4 MiB',
      );
    }
  }

  static ColorPalette _palette(String name, List<int> colors) {
    if (colors.isEmpty || colors.length > 1024) {
      throw const FormatException('A palette must contain 1–1024 colors');
    }
    return ColorPalette(id: newId(), name: name, colors: colors);
  }

  static int _rgb(double r, double g, double b) {
    for (final value in [r, g, b]) {
      if (!value.isFinite || value < 0 || value > 1) {
        throw const FormatException('Invalid RGB color component');
      }
    }
    return 0xff000000 |
        ((r * 255).round() << 16) |
        ((g * 255).round() << 8) |
        (b * 255).round();
  }

  static int _hsv(double h, double s, double v, double a) {
    if ([h, s, v, a].any((c) => !c.isFinite || c < 0 || c > 1)) {
      throw const FormatException('Invalid HSV color component');
    }
    return HSVColor.fromAHSV(a, h * 360, s, v).toColor().toARGB32();
  }
}

/// HEX files use RRGGBB or RRGGBBAA. Internal storage always uses ARGB.
int parseHex(String input) {
  final value = input.replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^(?:[a-fA-F0-9]{6}|[a-fA-F0-9]{8})$').hasMatch(value)) {
    throw const FormatException('Invalid hex color');
  }
  if (value.length == 6) return 0xff000000 | int.parse(value, radix: 16);
  final rgba = int.parse(value, radix: 16);
  return ((rgba & 0xff) << 24) | (rgba >> 8);
}

List<ColorPalette> decodePaletteImport((Uint8List, String) request) =>
    AssetImporter.palettes(request.$1, request.$2);
List<BrushPreset> decodeBrushImport(Uint8List bytes) =>
    AssetImporter.brushes(bytes);

/// MyPaint v3 `.myb`; the native loader validates it, so run off the UI isolate.
List<BrushPreset> decodeMypaintImport((Uint8List, String) input) {
  final (bytes, filename) = input;
  if (bytes.isEmpty || bytes.length > BrushPreset.maxMypaintBytes) {
    throw const FormatException('MyPaint brush exceeds size limit');
  }
  // MyPaint 1.0 brush kits use the older line format; store version 3 JSON.
  final text = normalizeMypaintPreset(utf8.decode(bytes));
  final surface = NativeBrushSurface(width: 1, height: 1);
  try {
    surface.loadPreset(text);
  } finally {
    surface.close();
  }
  final radius =
      (((jsonDecode(text) as Map)['settings'] as Map?)?['radius_logarithmic']
          as Map?)?['base_value'];
  final diameter = radius is num ? 2 * math.exp(radius.toDouble()) : 12.0;
  var name = filename.replaceFirst(RegExp(r'\.myb$', caseSensitive: false), '');
  name = name.trim().isEmpty ? 'MyPaint' : name.trim();
  if (name.length > 64) name = name.substring(0, 64);
  return [
    BrushPreset(
      id: newId(),
      name: name,
      size: diameter.isFinite ? diameter.clamp(1.0, 128.0) : 12,
      engine: BrushEngineKind.mypaint,
      mypaint: text,
    ),
  ];
}
