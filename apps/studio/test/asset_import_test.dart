import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/asset_importer.dart';
import 'package:color_palette_formats/color_palette_formats.dart' as formats;
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
void main() {
  test('HEX preserves order and converts RGBA alpha to internal ARGB', () {
    final result = AssetImporter.palettes(
      bytes('#123456\n#ff000080\n'),
      'Sunset.hex',
    ).single;
    expect(result.name, 'Sunset');
    expect(result.colors, [0xff123456, 0x80ff0000]);
    expect(
      () => AssetImporter.palettes(bytes('#123456\nnot-a-color'), 'bad.hex'),
      throwsFormatException,
    );
  });
  test('GPL is decoded using the ready-made palette library', () {
    final result = AssetImporter.palettes(
      bytes('GIMP Palette\nName: Test\n#\n255 0 128 Pink\n0 128 255 Blue\n'),
      'test.gpl',
    );
    expect(result.single.colors, [0xffff0080, 0xff0080ff]);
  });
  test('RGB ASE is preserved; CMYK is explicitly rejected', () {
    final rgb = formats.AdobeSwatchExchange(
      colors: [
        formats.AdobeSwatchExchangeColor(
          name: 'Red',
          model: formats.AdobeSwatchExchangeColorModel.rgb,
          values: [1, 0, 0],
        ),
      ],
    );
    expect(
      AssetImporter.palettes(
        Uint8List.fromList(rgb.toBytes()),
        'test.ase',
      ).single.colors,
      [0xffff0000],
    );
    final cmyk = formats.AdobeSwatchExchange(
      colors: [
        formats.AdobeSwatchExchangeColor(
          name: 'Cyan',
          model: formats.AdobeSwatchExchangeColorModel.cmyk,
          values: [1, 0, 0, 0],
        ),
      ],
    );
    expect(
      () => AssetImporter.palettes(
        Uint8List.fromList(cmyk.toBytes()),
        'test.ase',
      ),
      throwsFormatException,
    );
  });
  test('brush sets validate every preset before returning any results', () {
    final valid = {
      'format': 'atelier.brushes',
      'version': 1,
      'brushes': [
        {'name': 'Fine', 'size': 3, 'thinning': .2, 'smoothing': .6},
      ],
    };
    expect(AssetImporter.brushes(bytes(jsonEncode(valid))).single.name, 'Fine');
    (valid['brushes']! as List).add({'name': 'Bad', 'size': -1});
    expect(
      () => AssetImporter.brushes(bytes(jsonEncode(valid))),
      throwsFormatException,
    );
  });
  test('swatches archives reject unsafe paths before invoking the decoder', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('../outside.json', '[]'));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(
      () => AssetImporter.palettes(zip, 'unsafe.swatches'),
      throwsFormatException,
    );
  });
}
