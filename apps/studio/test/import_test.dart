import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/data/import_formats.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

RgbaPixels square(int width, int height, Rect area, List<int> rgba) {
  final bytes = Uint8List(width * height * 4);
  for (var y = area.top; y < area.bottom; y++) {
    for (var x = area.left; x < area.right; x++) {
      bytes.setRange((y * width + x) * 4, (y * width + x) * 4 + 4, rgba);
    }
  }
  return RgbaPixels(width, height, bytes);
}

class Rect {
  const Rect(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
}

List<int> at(Uint8List rgba, int width, int x, int y) =>
    rgba.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a PSD comes back with its layers, group, names, blend, opacity, '
      'clipping, visibility and pixels in place', () {
    final psd = encodePsd(80, 60, [
      PsdLayer(
        name: 'Kağıt',
        pixels: square(80, 60, const Rect(0, 0, 80, 60), [255, 255, 255, 255]),
      ),
      const PsdLayer(name: '</Layer group>', section: PsdSection.groupEnd),
      PsdLayer(
        name: 'Gölge',
        pixels: square(80, 60, const Rect(30, 20, 50, 40), [0, 0, 255, 255]),
        opacity: .6,
        blend: psdBlendKey(LayerBlend.multiply),
      ),
      PsdLayer(
        name: 'Işık',
        pixels: square(80, 60, const Rect(0, 0, 10, 10), [255, 0, 0, 255]),
        clipping: true,
        visible: false,
      ),
      PsdLayer(
        name: 'Çizgiler',
        opacity: .5,
        blend: psdBlendKey(LayerBlend.screen),
        section: PsdSection.groupStart,
      ),
    ], square(80, 60, const Rect(0, 0, 80, 60), [9, 9, 9, 255]));
    final drawing = decodeDrawing(psd, 'psd');
    expect(drawing.size, const CanvasSize(80, 64), reason: 'at least 64');
    expect(
      [for (final l in drawing.layers) l.name],
      ['Kağıt', 'Gölge', 'Işık'],
    );
    final shadow = drawing.layers[1];
    expect(shadow.opacity, closeTo(.6, .01));
    expect(shadow.blend, LayerBlend.multiply);
    expect(at(shadow.rgba, 80, 35, 25), [0, 0, 255, 255]);
    expect(at(shadow.rgba, 80, 5, 5)[3], 0, reason: 'placed, not stretched');
    expect(drawing.layers[2].clipping, isTrue);
    expect(drawing.layers[2].visible, isFalse);
    final group = drawing.groups.single;
    expect((group.name, group.blend), ('Çizgiler', LayerBlend.screen));
    expect(group.opacity, closeTo(.5, .01));
    expect(shadow.group, group.id);
    expect(drawing.layers[0].group, isNull);
  });

  test('a picture larger than a canvas is made smaller to fit', () {
    final psd = encodePsd(5000, 100, [
      PsdLayer(
        name: 'Wide',
        pixels: square(5000, 100, const Rect(0, 0, 5000, 100), [1, 2, 3, 255]),
      ),
    ], square(5000, 100, const Rect(0, 0, 5000, 100), [1, 2, 3, 255]));
    final drawing = decodeDrawing(psd, 'psd');
    expect(drawing.scaled, isTrue);
    expect(drawing.size, const CanvasSize(4096, 82));
  });

  test('GIF frames and TIFF pages become layers', () {
    final first = img.Image(width: 20, height: 10, numChannels: 4)
      ..clear(img.ColorRgba8(255, 0, 0, 255));
    final second = img.Image(width: 20, height: 10, numChannels: 4)
      ..clear(img.ColorRgba8(0, 255, 0, 255));
    first.addFrame(second);
    final gif = decodeDrawing(img.encodeGif(first), 'gif');
    expect([for (final l in gif.layers) l.name], ['Frame 1', 'Frame 2']);
    expect(at(gif.layers[1].rgba, 64, 3, 3).sublist(0, 2), [0, 255]);
    final tiff = decodeDrawing(img.encodeTiff(second), 'tiff');
    expect(tiff.layers.single.name, 'Layer 1');
    expect(tiff.size, const CanvasSize(64, 64), reason: 'at least 64 a side');
  });

  test('a PDF\'s images become layers: JPEG and Flate-compressed RGB', () {
    final jpeg = encodeJpeg(
      square(100, 50, const Rect(0, 0, 100, 50), [200, 10, 10, 255]),
    );
    final ours = decodeDrawing(
      encodePdf([PdfPage(jpeg, 100, 50, 72), PdfPage(jpeg, 100, 50, 72)]),
      'pdf',
    );
    expect([for (final l in ours.layers) l.name], ['Page 1', 'Page 2']);
    expect(ours.size, const CanvasSize(100, 64));
    expect(at(ours.layers[0].rgba, 100, 50, 25)[0], greaterThan(180));

    final rgb = Uint8List(4 * 4 * 3)..fillRange(0, 48, 77);
    final flate = const ZLibEncoder().encodeBytes(rgb);
    final head = latin1.encode(
      '%PDF-1.4\n1 0 obj\n<< /Type /XObject /Subtype /Image /Width 4 '
      '/Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8 '
      '/Filter /FlateDecode /Length ${flate.length} >>\nstream\n',
    );
    final pdf = Uint8List.fromList([
      ...head,
      ...flate,
      ...latin1.encode('\nendstream\nendobj\n%%EOF\n'),
    ]);
    final flat = decodeDrawing(pdf, 'pdf');
    expect(at(flat.layers.single.rgba, 64, 10, 10), [77, 77, 77, 255]);
    expect(
      () => decodeDrawing(latin1.encode('%PDF-1.4\n%%EOF'), 'pdf'),
      throwsFormatException,
    );
  });

  test('a .procreate file comes in as its preview', () {
    final preview = img.encodePng(
      img.Image(width: 120, height: 90)..clear(img.ColorRgb8(5, 6, 7)),
    );
    final zip = Archive()
      ..addFile(ArchiveFile.bytes('QuickLook/Thumbnail.png', preview))
      ..addFile(ArchiveFile.bytes('Document.archive', Uint8List(8)));
    final drawing = decodeDrawing(
      Uint8List.fromList(ZipEncoder().encode(zip)),
      'procreate',
    );
    expect(drawing.partial, isTrue);
    expect(drawing.size, const CanvasSize(120, 90));
    expect(at(drawing.layers.single.rgba, 120, 60, 45), [5, 6, 7, 255]);
    expect(() => decodeDrawing(Uint8List(4), 'xyz'), throwsFormatException);
  });

  test('an imported drawing opens with its layers and group; an exported '
      'PSD opens again the same', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final psd = encodePsd(64, 64, [
      const PsdLayer(name: '</Layer group>', section: PsdSection.groupEnd),
      PsdLayer(
        name: 'A',
        pixels: square(64, 64, const Rect(0, 0, 32, 64), [0, 128, 0, 255]),
        opacity: .5,
      ),
      PsdLayer(
        name: 'B',
        pixels: square(64, 64, const Rect(32, 0, 64, 64), [0, 0, 0, 255]),
        blend: psdBlendKey(LayerBlend.overlay),
      ),
      const PsdLayer(
        name: 'G',
        blend: 'norm',
        opacity: .7,
        section: PsdSection.groupStart,
      ),
    ], square(64, 64, const Rect(0, 0, 64, 64), [0, 0, 0, 255]));
    expect(await c.openImported(decodeDrawing(psd, 'psd'), 'Imported'), isTrue);
    final doc = c.document;
    expect(doc.name, 'Imported');
    expect([for (final l in doc.layers) l.name], ['A', 'B']);
    expect(doc.layers[0].opacity, closeTo(.5, .01));
    expect(doc.layers[1].blend, LayerBlend.overlay);
    expect(doc.groups.single.opacity, closeTo(.7, .01));
    expect(doc.layers.every((l) => l.group == doc.groups.single.id), isTrue);

    final again = decodeDrawing(
      await Exporter(c).export(ExportFormat.psd),
      'psd',
    );
    expect([for (final l in again.layers) l.name], ['A', 'B']);
    expect(at(again.layers[0].rgba, 64, 10, 10), [0, 128, 0, 255]);

    final many = ImportedDrawing(
      size: const CanvasSize(64, 64),
      layers: [
        for (var i = 0; i < StudioController.maxLayers + 2; i++)
          ImportedLayer(name: 'L$i', rgba: Uint8List(64 * 64 * 4)),
      ],
    );
    expect(await c.openImported(many, 'Many'), isFalse);
    expect(c.document.layers.length, StudioController.maxLayers);
    expect(c.document.layers.last.name, 'L${StudioController.maxLayers + 1}');
  });
}
