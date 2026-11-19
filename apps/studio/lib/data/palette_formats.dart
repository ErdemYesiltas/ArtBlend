import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:color_palette_formats/color_palette_formats.dart' as formats;
import 'package:material_ui/material_ui.dart' show Color, HSVColor;

/// The [count] colours a picture is mostly made of, from straight RGBA
/// [rgba]: k-means (seeded, so the same picture gives the same palette)
/// over its visible pixels, sampled to at most [samples]; most common
/// first. Near-identical results are merged.
List<int> paletteFromPixels(
  Uint8List rgba, {
  int count = 12,
  int samples = 20000,
}) {
  final pixels = rgba.length ~/ 4;
  final step = math.max(1, pixels ~/ samples);
  final points = <(double, double, double)>[];
  for (var i = 0; i < pixels; i += step) {
    if (rgba[i * 4 + 3] < 128) continue;
    points.add((
      rgba[i * 4].toDouble(),
      rgba[i * 4 + 1].toDouble(),
      rgba[i * 4 + 2].toDouble(),
    ));
  }
  if (points.isEmpty) return const [];
  // Closeness as the eye sees it, roughly: green counts most.
  double distance((double, double, double) a, (double, double, double) b) {
    final dr = a.$1 - b.$1, dg = a.$2 - b.$2, db = a.$3 - b.$3;
    return 2 * dr * dr + 4 * dg * dg + 3 * db * db;
  }

  final random = math.Random(7);
  final k = math.min(count, points.length);
  // k-means++: each new centre far from those chosen.
  final centres = [points[random.nextInt(points.length)]];
  final nearest = List<double>.filled(points.length, double.infinity);
  while (centres.length < k) {
    var total = 0.0;
    for (var i = 0; i < points.length; i++) {
      nearest[i] = math.min(nearest[i], distance(points[i], centres.last));
      total += nearest[i];
    }
    if (total == 0) break;
    var pick = random.nextDouble() * total;
    var chosen = points.length - 1;
    for (var i = 0; i < points.length; i++) {
      pick -= nearest[i];
      if (pick <= 0) {
        chosen = i;
        break;
      }
    }
    centres.add(points[chosen]);
  }
  final owner = List<int>.filled(points.length, 0);
  for (var round = 0; round < 16; round++) {
    var moved = false;
    for (var i = 0; i < points.length; i++) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var c = 0; c < centres.length; c++) {
        final d = distance(points[i], centres[c]);
        if (d < bestDistance) {
          bestDistance = d;
          best = c;
        }
      }
      if (owner[i] != best) moved = true;
      owner[i] = best;
    }
    final sums = List.generate(centres.length, (_) => [0.0, 0.0, 0.0, 0.0]);
    for (var i = 0; i < points.length; i++) {
      final s = sums[owner[i]];
      s[0] += points[i].$1;
      s[1] += points[i].$2;
      s[2] += points[i].$3;
      s[3]++;
    }
    for (var c = 0; c < centres.length; c++) {
      final s = sums[c];
      if (s[3] > 0) centres[c] = (s[0] / s[3], s[1] / s[3], s[2] / s[3]);
    }
    if (!moved && round > 0) break;
  }
  final sizes = List<int>.filled(centres.length, 0);
  for (final o in owner) {
    sizes[o]++;
  }
  final order = [for (var c = 0; c < centres.length; c++) c]
    ..sort((a, b) => sizes[b].compareTo(sizes[a]));
  final colors = <int>[];
  final kept = <(double, double, double)>[];
  for (final c in order) {
    if (sizes[c] == 0) continue;
    final centre = centres[c];
    if (kept.any((k) => distance(k, centre) < 150)) continue;
    kept.add(centre);
    int channel(double v) => v.round().clamp(0, 255);
    colors.add(
      0xff000000 |
          channel(centre.$1) << 16 |
          channel(centre.$2) << 8 |
          channel(centre.$3),
    );
  }
  return colors;
}

/// The file formats a palette can be saved as.
enum PaletteFormat {
  swatches('swatches'),
  ase('ase'),
  gpl('gpl'),
  hex('hex');

  const PaletteFormat(this.extension);
  final String extension;
}

/// [colors] (ARGB) named [name] as a file of [format].
Uint8List encodePalette(String name, List<int> colors, PaletteFormat format) {
  double channel(int c, int shift) => (c >> shift & 0xff) / 255;
  switch (format) {
    case PaletteFormat.swatches:
      // Procreate's: a zip holding Swatches.json, HSB from 0 to 1.
      final swatches = [
        for (final c in colors)
          () {
            final hsv = HSVColor.fromColor(Color(c));
            return {
              'hue': hsv.hue / 360,
              'saturation': hsv.saturation,
              'brightness': hsv.value,
              'alpha': hsv.alpha,
              'colorSpace': 0,
            };
          }(),
      ];
      final json = utf8.encode(
        jsonEncode([
          {'name': name, 'swatches': swatches},
        ]),
      );
      final zip = Archive()..addFile(ArchiveFile.bytes('Swatches.json', json));
      return Uint8List.fromList(ZipEncoder().encode(zip));
    case PaletteFormat.ase:
      return Uint8List.fromList(
        formats.AdobeSwatchExchange(
          colors: [
            for (final c in colors)
              formats.AdobeSwatchExchangeColor(
                name: '#${(c & 0xffffff).toRadixString(16).padLeft(6, '0')}',
                model: formats.AdobeSwatchExchangeColorModel.rgb,
                values: [channel(c, 16), channel(c, 8), channel(c, 0)],
                type: formats.AdobeSwatchExchangeColorType.global,
              ),
          ],
        ).toBytes(),
      );
    case PaletteFormat.gpl:
      final lines = [
        'GIMP Palette',
        'Name: $name',
        'Columns: 10',
        '#',
        for (final c in colors)
          '${(c >> 16 & 0xff).toString().padLeft(3)} '
              '${(c >> 8 & 0xff).toString().padLeft(3)} '
              '${(c & 0xff).toString().padLeft(3)}\t'
              '#${(c & 0xffffff).toRadixString(16).padLeft(6, '0')}',
      ];
      return utf8.encode('${lines.join('\n')}\n');
    case PaletteFormat.hex:
      return utf8.encode(
        '${[for (final c in colors) (c & 0xffffff).toRadixString(16).padLeft(6, '0')].join('\n')}\n',
      );
  }
}
