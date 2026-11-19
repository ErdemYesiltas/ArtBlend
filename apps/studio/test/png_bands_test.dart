import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pattern(int width, int height, int seed) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      rgba
        ..[i] = (x * 7 + seed) & 255
        ..[i + 1] = (y * 3) & 255
        ..[i + 2] = (x ^ y) & 255
        ..[i + 3] = (x + y + seed) % 5 == 0 ? 0 : (x * y + seed) & 255;
    }
  }
  return rgba;
}

/// Straight RGBA exactly as stored in the PNG, via zlib (checks Adler-32).
Uint8List inflate(Uint8List png, int width, int height) {
  final data = ByteData.sublistView(png);
  var offset = 8;
  final idat = BytesBuilder();
  while (offset < png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') idat.add(png.sublist(offset + 8, offset + 8 + length));
    offset += 12 + length;
  }
  final filtered = ZLibDecoder().convert(idat.takeBytes());
  final stride = width * 4;
  final out = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    expect(filtered[y * (stride + 1)], 1);
    for (var x = 0; x < stride; x++) {
      final value = filtered[y * (stride + 1) + 1 + x];
      out[y * stride + x] =
          (value + (x < 4 ? 0 : out[y * stride + x - 4])) & 0xff;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'banded PNG is a valid single zlib stream and decodes losslessly',
    () async {
      const width = 300, height = 200;
      final source = pattern(width, height, 1);
      final png = encodeRgbaPng(source, width, height);
      expect(inflate(png, width, height), source);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect((image.width, image.height), (width, height));
      image.dispose();
      codec.dispose();
    },
  );

  test('replacing bands equals encoding the edited image from scratch', () {
    const width = 160, height = 300;
    final first = pattern(width, height, 1);
    final bands = encodePngBands(first, width, height);
    expect(bands.length, (height + pngBandRows - 1) ~/ pngBandRows);
    final edited = Uint8List.fromList(first);
    final edit = pattern(width, pngBandRows, 9);
    edited.setRange(pngBandRows * width * 4, 2 * pngBandRows * width * 4, edit);
    final patched = [...bands]
      ..replaceRange(1, 2, encodePngBands(edit, width, pngBandRows));
    expect(inflate(assemblePng(patched, width, height), width, height), edited);
  });

  test(
    'exact decode reads our PNG byte for byte and any-filter engine PNGs',
    () async {
      const width = 64, height = 40;
      final source = pattern(width, height, 3);
      expect(
        decodeRgbaPng(encodeRgbaPng(source, width, height), width, height),
        source,
      );
      expect(
        decodeRgbaPng(encodeRgbaPng(source, width, height), 63, height),
        isNull,
      );
      expect(decodeRgbaPng(Uint8List(40), width, height), isNull);
      // The engine's encoder picks its own filters; opaque pixels round-trip.
      final opaque = Uint8List.fromList(source);
      for (var i = 3; i < opaque.length; i += 4) {
        opaque[i] = 255;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        opaque,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(decodeRgbaPng(png!.buffer.asUint8List(), width, height), opaque);
    },
  );
}
