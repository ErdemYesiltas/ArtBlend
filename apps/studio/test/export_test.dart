import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

/// [width]×[height] of one colour, the left half only when [half].
RgbaPixels solid(int width, int height, List<int> rgba, {bool half = false}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < (half ? width ~/ 2 : width); x++) {
      bytes.setRange((y * width + x) * 4, (y * width + x) * 4 + 4, rgba);
    }
  }
  return RgbaPixels(width, height, bytes);
}

int key(String k) => k.codeUnits.fold(0, (v, c) => v << 8 | c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a PSD keeps layers, groups, names, opacity, blend, clipping, '
      'visibility and its pixels', () {
    final red = solid(64, 32, [255, 0, 0, 255], half: true);
    final blue = solid(64, 32, [0, 0, 255, 128]);
    final bytes = encodePsd(64, 32, [
      PsdLayer(name: 'Kâğıt', pixels: solid(64, 32, [255, 255, 255, 255])),
      const PsdLayer(name: '</Layer group>', section: PsdSection.groupEnd),
      PsdLayer(name: 'Kırmızı', pixels: red, opacity: .5, blend: 'mul '),
      PsdLayer(
        name: 'Mavi',
        pixels: blue,
        clipping: true,
        visible: false,
        blend: psdBlendKey(LayerBlend.screen),
      ),
      const PsdLayer(
        name: 'Grup',
        opacity: .8,
        blend: 'pass',
        section: PsdSection.groupStart,
      ),
      PsdLayer(name: 'Empty', pixels: solid(64, 32, [0, 0, 0, 0])),
    ], solid(64, 32, [10, 20, 30, 255]));
    final psd = img.PsdImage(bytes);
    expect(psd.isValid, isTrue);
    expect(psd.decode(), isTrue);
    expect((psd.width, psd.height), (64, 32));
    final layers = psd.layers;
    expect(layers.length, 6);
    final redLayer = layers[2];
    expect(redLayer.name, 'K?rm?z?', reason: 'Latin-1 name; Unicode in luni');
    expect(redLayer.opacity, 128);
    expect(redLayer.blendMode, key('mul '));
    expect(
      (redLayer.left, redLayer.right, redLayer.top, redLayer.bottom),
      (0, 32, 0, 32),
      reason: 'cropped to its pixels',
    );
    final pixel = redLayer.layerImage!.getPixel(5, 5);
    expect((pixel.r, pixel.g, pixel.b, pixel.a), (255, 0, 0, 255));
    expect(layers[3].clipping, 1);
    expect(layers[3].isVisible(), isFalse);
    expect(layers[3].blendMode, key('scrn'));
    expect(layers[4].blendMode, key('pass'));
    expect(layers[4].opacity, 204);
    expect(layers[4].additionalData.containsKey('lsct'), isTrue);
    expect(layers[5].width, 0, reason: 'nothing on it');
    final merged = psd.renderImage();
    final m = merged.getPixel(40, 10);
    expect((m.r, m.g, m.b), (10, 20, 30));
  });

  test('JPEG sits on the paper; TIFF keeps transparency', () {
    final half = solid(40, 20, [0, 128, 255, 255], half: true);
    final jpeg = img.decodeJpg(encodeJpeg(half, background: 0xffffffff))!;
    expect((jpeg.width, jpeg.height), (40, 20));
    final paper = jpeg.getPixel(35, 10);
    expect(paper.r, greaterThan(245));
    final blue = jpeg.getPixel(5, 10);
    expect(blue.b, greaterThan(235));
    expect(blue.r, lessThan(20));
    final tiff = img.decodeTiff(encodeTiff(half))!;
    expect(tiff.getPixel(35, 10).a, 0);
    expect(tiff.getPixel(5, 10).a, 255);
  });

  test('a PDF page is the drawing\'s print size; its cross references point '
      'at its objects', () {
    final jpeg = encodeJpeg(solid(16, 16, [0, 0, 0, 255]));
    final pdf = encodePdf([
      PdfPage(jpeg, 2480, 3508, 300),
      PdfPage(jpeg, 2480, 3508, 300),
    ], title: 'Çizim (1)');
    final text = latin1.decode(pdf);
    expect(text, startsWith('%PDF-1.4'));
    expect(text, contains('/Count 2'));
    expect(text, contains('/MediaBox [0 0 595.20 841.92]'));
    expect(text, contains(r'/Title (?izim \(1\))'));
    final start = int.parse(
      RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
    );
    expect(text.substring(start), startsWith('xref'));
    final entries = RegExp(r'(\d{10}) 00000 n')
        .allMatches(text.substring(start))
        .toList();
    for (final (i, e) in entries.indexed) {
      expect(
        text.substring(int.parse(e.group(1)!)),
        startsWith('${i + 1} 0 obj'),
      );
    }
  });

  test('the drawing exports in every format; its layers as PNG files and '
      'as a layered PSD', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(
      ArtDocument.empty(name: 'Test', dimensions: const CanvasSize(128, 96)),
    );
    c.selectColor(0xffcc2200);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 64, 96)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    c.addLayer('Üst');
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(opacity: .4, blend: LayerBlend.multiply),
    );
    c.groupLayers('Grup');
    final exporter = Exporter(c);

    final png = img.decodePng(await exporter.export(ExportFormat.png))!;
    expect((png.width, png.height), (128, 96));
    final left = png.getPixel(10, 10), right = png.getPixel(100, 10);
    expect((left.r, left.g, left.b), (204, 34, 0));
    expect(right.g, greaterThan(240), reason: 'the paper');
    expect(img.decodeJpg(await exporter.export(ExportFormat.jpeg)), isNotNull);
    expect(img.decodeTiff(await exporter.export(ExportFormat.tiff)), isNotNull);
    expect(
      latin1.decode(await exporter.export(ExportFormat.layersPdf)),
      contains('/Count 2'),
    );
    final zip = ZipDecoder().decodeBytes(
      await exporter.export(ExportFormat.layersPng),
    );
    expect([for (final f in zip.files) f.name], ['1 Layer 1.png', '2 Üst.png']);

    final psd = img.PsdImage(await exporter.export(ExportFormat.psd))..decode();
    expect(
      psd.layers.length,
      5,
      reason: 'paper, layer 1, group end, the grouped layer, group',
    );
    expect(psd.layers[2].additionalData.containsKey('lsct'), isTrue);
    expect(psd.layers[3].opacity, 102);
    expect(psd.layers[3].blendMode, key('mul '));
    expect(psd.layers[4].name, 'Grup');
    final drawn = psd.layers[1].layerImage!.getPixel(10, 10);
    expect((drawn.r, drawn.g, drawn.b, drawn.a), (204, 34, 0, 255));
  });
}
