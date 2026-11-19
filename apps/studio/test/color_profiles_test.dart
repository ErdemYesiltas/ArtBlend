import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:atelier_studio/data/color_profiles.dart';
import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

RgbaPixels pixels(List<int> rgba, {int w = 8, int h = 4}) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes.setAll(i * 4, rgba);
  }
  return RgbaPixels(w, h, bytes);
}

int u32(Uint8List b, int at) =>
    b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sRGB and Display P3 profiles are well-formed ICC version 2 '
      'profiles with their own primaries; CMYK has none', () {
    final srgb = iccProfile(ColorProfile.srgb)!;
    final p3 = iccProfile(ColorProfile.displayP3)!;
    for (final icc in [srgb, p3]) {
      expect(u32(icc, 0), icc.length);
      expect(latin1.decode(icc.sublist(36, 40)), 'acsp');
      expect(latin1.decode(icc.sublist(12, 20)), 'mntrRGB ');
      final tags = u32(icc, 128);
      expect(tags, 9);
      for (var i = 0; i < tags; i++) {
        final offset = u32(icc, 136 + i * 12), size = u32(icc, 140 + i * 12);
        expect(offset % 4, 0);
        expect(offset + size, lessThanOrEqualTo(icc.length));
      }
    }
    expect(srgb, isNot(p3));
    expect(identical(iccProfile(ColorProfile.srgb), srgb), isTrue);
    expect(iccProfile(ColorProfile.cmyk), isNull);
  });

  test('inks: white none, black only black, red magenta and yellow, never '
      'over 300%', () {
    final inks = rgbaToCmyka(
      Uint8List.fromList([
        255, 255, 255, 255, //
        0, 0, 0, 255,
        255, 0, 0, 128,
        30, 40, 20, 255,
      ]),
    );
    expect(inks.sublist(0, 5), [0, 0, 0, 0, 255]);
    expect(inks.sublist(5, 10), [0, 0, 0, 255, 255]);
    expect(inks.sublist(10, 15), [0, 255, 255, 0, 128]);
    final dark = inks.sublist(15, 19);
    expect(dark.reduce((a, b) => a + b), lessThanOrEqualTo(765 + 2));
  });

  test('the profile goes into PNG, JPEG, TIFF, PDF and PSD files', () {
    final icc = iccProfile(ColorProfile.displayP3)!;
    final red = pixels([255, 0, 0, 255]);
    expect(
      img.decodePng(encodePngPixels(red, icc: icc))!.iccProfile!.decompressed(),
      icc,
    );
    expect(
      img.decodeJpg(encodeJpeg(red, icc: icc))!.iccProfile!.decompressed(),
      icc,
    );
    final tiff = encodeProfiledTiff(red, icc: icc);
    final decoded = img.decodeTiff(tiff)!;
    expect(decoded.getPixel(3, 2).r, 255);
    expect(
      latin1.decode(tiff).contains(latin1.decode(icc.sublist(36, 40))),
      isTrue,
    );
    expect(
      latin1.decode(encodePdf([PdfPage(encodeJpeg(red), 8, 4, 72)], icc: icc)),
      contains('/ICCBased 4 0 R'),
    );
    final psd = img.PsdImage(
      encodePsd(
        8,
        4,
        [PsdLayer(name: 'r', pixels: red)],
        red,
        icc: icc,
      ),
    )..decode();
    expect(psd.imageResources.containsKey(1039), isTrue);
  });

  test('CMYK PSD and TIFF files carry the four inks', () {
    final red = pixels([255, 0, 0, 255]);
    final psd = img.PsdImage(
      encodePsd(8, 4, [PsdLayer(name: 'r', pixels: red)], red, cmyk: true),
    );
    expect(psd.decode(), isTrue);
    expect(psd.colorMode, img.PsdColorMode.cmyk);
    expect(psd.layers.single.channels.length, 5);
    final back = psd.renderImage().getPixel(4, 2);
    expect(back.r, greaterThan(230));
    expect(back.g, lessThan(30));
    final tiff = encodeProfiledTiff(red, cmyk: true);
    final data = ByteData.sublistView(tiff);
    final entries = data.getUint16(8, Endian.little);
    final photometric = [
      for (var i = 0; i < entries; i++)
        if (data.getUint16(10 + i * 12, Endian.little) == 262)
          data.getUint16(18 + i * 12, Endian.little),
    ];
    expect(photometric, [5]);
    expect(tiff.length, greaterThan(8 * 4 * 5));
  });

  test('a drawing keeps its profile; its exports follow it', () async {
    final doc = ArtDocument.empty(
      name: 'P',
      dimensions: const CanvasSize(64, 64),
    ).copyWith(colorProfile: ColorProfile.displayP3);
    expect(
      ArtDocument.fromJson(jsonDecode(jsonEncode(doc.toJson()))).colorProfile,
      ColorProfile.displayP3,
    );
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(doc);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 64, 64)),
    );
    await c.fillActiveLayer();
    final png = img.decodePng(await Exporter(c).export(ExportFormat.png))!;
    expect(png.iccProfile!.decompressed(), iccProfile(ColorProfile.displayP3));
    c.setColorProfile(ColorProfile.cmyk);
    final psd = img.PsdImage(await Exporter(c).export(ExportFormat.psd))
      ..decode();
    expect(psd.colorMode, img.PsdColorMode.cmyk);
    final rgb = img.decodePng(await Exporter(c).export(ExportFormat.png))!;
    expect(rgb.iccProfile!.decompressed(), iccProfile(ColorProfile.srgb));
    c.undo();
    expect(c.document.colorProfile, ColorProfile.displayP3);
  });
}
