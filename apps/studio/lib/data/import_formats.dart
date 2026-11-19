import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../domain/document.dart';
import 'export_formats.dart';

/// A layer read from another app's file: straight RGBA over the whole
/// canvas.
class ImportedLayer {
  const ImportedLayer({
    required this.name,
    required this.rgba,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.visible = true,
    this.clipping = false,
    this.group,
  });
  final String name;
  final Uint8List rgba;
  final double opacity;
  final LayerBlend blend;
  final bool visible, clipping;
  final String? group;
}

class ImportedGroup {
  const ImportedGroup({
    required this.id,
    required this.name,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.visible = true,
    this.passThrough = false,
  });
  final String id, name;
  final double opacity;
  final LayerBlend blend;
  final bool visible, passThrough;
}

/// A drawing read from a file: layers bottom to top.
class ImportedDrawing {
  const ImportedDrawing({
    required this.size,
    required this.layers,
    this.groups = const [],
    this.dpi = 132,
    this.scaled = false,
    this.partial = false,
  });
  final CanvasSize size;
  final List<ImportedLayer> layers;
  final List<ImportedGroup> groups;
  final int dpi;

  /// Larger than a canvas may be: made smaller to fit.
  final bool scaled;

  /// Only part of the file could be read (a `.procreate` preview).
  final bool partial;
}

/// The file types a drawing can be opened from besides ArtBlend's own.
const importExtensions = ['psd', 'tif', 'tiff', 'gif', 'pdf', 'procreate'];

/// Reads [bytes] by [extension]; throws [FormatException] when it cannot.
ImportedDrawing decodeDrawing(Uint8List bytes, String extension) =>
    switch (extension.toLowerCase()) {
      'psd' => decodePsdDrawing(bytes),
      'tif' || 'tiff' => _frames(img.TiffDecoder(), bytes, 'Page'),
      'gif' => _frames(img.GifDecoder(), bytes, 'Frame'),
      'pdf' => decodePdfImages(bytes),
      'procreate' => decodeProcreate(bytes),
      _ => throw FormatException('Unsupported file: .$extension'),
    };

/// How much smaller [width]×[height] must be to fit a canvas.
double _fit(int width, int height) =>
    math.min(1.0, CanvasSize.maxSide / math.max(width, height));

CanvasSize _canvas(int width, int height, double scale) => CanvasSize(
  math.max(CanvasSize.minSide, (width * scale).round()),
  math.max(CanvasSize.minSide, (height * scale).round()),
);

/// [image] (any format) as straight 8-bit RGBA, placed at [left], [top] on
/// a [size] canvas after scaling by [scale].
Uint8List _place(
  img.Image image,
  CanvasSize size, {
  int left = 0,
  int top = 0,
  double scale = 1,
}) {
  var source = image.convert(format: img.Format.uint8, numChannels: 4);
  if (scale != 1) {
    source = img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }
  final canvas = img.Image(
    width: size.width,
    height: size.height,
    numChannels: 4,
  );
  img.compositeImage(
    canvas,
    source,
    dstX: (left * scale).round(),
    dstY: (top * scale).round(),
    blend: img.BlendMode.direct,
  );
  return canvas.getBytes(order: img.ChannelOrder.rgba);
}

final _blendByKey = {
  for (final blend in LayerBlend.values) psdBlendKey(blend): blend,
};

String _key(int value) => String.fromCharCodes([
  value >> 24 & 0xff,
  value >> 16 & 0xff,
  value >> 8 & 0xff,
  value & 0xff,
]);

/// A layer's Unicode name (`luni`), else its Latin-1 one.
String _name(img.PsdLayer layer) {
  final luni = layer.additionalData['luni'];
  if (luni is img.PsdLayerAdditionalData) {
    final b = luni.data.toUint8List();
    if (b.length >= 4) {
      final count = b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
      if (4 + count * 2 <= b.length) {
        return String.fromCharCodes([
          for (var i = 0; i < count; i++) b[4 + i * 2] << 8 | b[5 + i * 2],
        ]).replaceAll('\u0000', '');
      }
    }
  }
  return layer.name ?? '';
}

/// Photoshop layers, groups (one level deep: deeper ones join the outer
/// group), blend modes, opacity, clipping and visibility.
ImportedDrawing decodePsdDrawing(Uint8List bytes) {
  final psd = img.PsdImage(bytes);
  if (!psd.isValid || !psd.decode()) {
    throw const FormatException('Not a Photoshop file');
  }
  final scale = _fit(psd.width, psd.height);
  final size = _canvas(psd.width, psd.height, scale);
  final layers = <ImportedLayer>[];
  final groups = <ImportedGroup>[];
  final open = <String>[];
  var next = 0;
  for (final layer in psd.layers) {
    final section = layer.additionalData['lsct'];
    final type = section is img.PsdLayerSectionDivider ? section.type : 0;
    if (type == img.PsdLayerSectionDivider.sectionDivider) {
      open.add('g${next++}');
      continue;
    }
    if (type == img.PsdLayerSectionDivider.openFolder ||
        type == img.PsdLayerSectionDivider.closedFolder) {
      if (open.isEmpty) continue;
      final id = open.removeLast();
      if (open.isNotEmpty) continue;
      final key = section is img.PsdLayerSectionDivider
          ? section.key ?? _key(layer.blendMode ?? 0)
          : _key(layer.blendMode ?? 0);
      groups.add(
        ImportedGroup(
          id: id,
          name: _name(layer),
          opacity: layer.opacity / 255,
          blend: _blendByKey[key] ?? LayerBlend.normal,
          passThrough: key == 'pass',
          visible: layer.isVisible(),
        ),
      );
      continue;
    }
    final image = layer.layerImage;
    layers.add(
      ImportedLayer(
        name: _name(layer),
        rgba: image == null || layer.width <= 0 || layer.height <= 0
            ? Uint8List(size.width * size.height * 4)
            : _place(
                image,
                size,
                left: layer.left ?? 0,
                top: layer.top ?? 0,
                scale: scale,
              ),
        opacity: layer.opacity / 255,
        blend: _blendByKey[_key(layer.blendMode ?? 0)] ?? LayerBlend.normal,
        visible: layer.isVisible(),
        clipping: (layer.clipping ?? 0) != 0,
        group: open.isEmpty ? null : open.first,
      ),
    );
  }
  if (layers.isEmpty) {
    // No layer records: the flattened picture.
    final merged = psd.renderImage();
    layers.add(
      ImportedLayer(
        name: 'Layer 1',
        rgba: _place(merged, size, scale: scale),
      ),
    );
  }
  final resolution = psd.imageResources[1005]?.data;
  var dpi = 132;
  if (resolution != null && resolution.length >= 4) {
    final r = resolution;
    final fixed = r[0] << 24 | r[1] << 16 | r[2] << 8 | r[3];
    dpi = (fixed / 65536).round().clamp(36, 1200);
  }
  return ImportedDrawing(
    size: size,
    layers: layers,
    groups: groups,
    dpi: dpi,
    scaled: scale < 1,
  );
}

/// A multi-page TIFF or an animated GIF: a layer a page or frame.
ImportedDrawing _frames(img.Decoder decoder, Uint8List bytes, String name) {
  final image = decoder.decode(bytes);
  if (image == null) throw const FormatException('The image is unreadable');
  final scale = _fit(image.width, image.height);
  final size = _canvas(image.width, image.height, scale);
  final frames = image.frames.isEmpty ? [image] : image.frames;
  return ImportedDrawing(
    size: size,
    scaled: scale < 1,
    layers: [
      for (final (i, frame) in frames.indexed)
        ImportedLayer(
          name: frames.length == 1 ? 'Layer 1' : '$name ${i + 1}',
          rgba: _place(frame, size, scale: scale),
        ),
    ],
  );
}

/// PDF pages drawn by the platform ([pages]: PNG files, a page each) as a
/// drawing: a layer a page, the first page's size the canvas.
ImportedDrawing pdfPagesDrawing(List<Uint8List> pages) {
  final images = [for (final png in pages) ?img.decodePng(png)];
  if (images.isEmpty) throw const FormatException('No pages');
  final first = images.first;
  final scale = _fit(first.width, first.height);
  final size = _canvas(first.width, first.height, scale);
  return ImportedDrawing(
    size: size,
    scaled: scale < 1,
    layers: [
      for (final (i, page) in images.indexed)
        ImportedLayer(
          name: 'Page ${i + 1}',
          rgba: _place(page, size, scale: size.width / page.width),
        ),
    ],
  );
}

/// A picture file (PNG, JPEG, WebP, BMP, GIF …) as a drawing: one layer,
/// or a layer a frame for an animation.
ImportedDrawing decodePicture(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) throw const FormatException('The image is unreadable');
  return _frames(decoder, bytes, 'Frame');
}

/// How long each frame of an animated GIF shows (milliseconds).
List<int> gifDurations(Uint8List bytes) => [
  for (final f in img.decodeGif(bytes)?.frames ?? const <img.Image>[])
    f.frameDuration,
];

/// A PDF's images (JPEG, or 8-bit RGB / grey compressed with Flate), a
/// layer each, the first one's size the canvas. Vector pages are not drawn.
ImportedDrawing decodePdfImages(Uint8List bytes) {
  final text = latin1.decode(bytes);
  if (!text.startsWith('%PDF')) throw const FormatException('Not a PDF');
  final images = <img.Image>[];
  final dictionary = RegExp(
    r'<<((?:[^<>]|<<(?:[^<>]|<<[^<>]*>>)*>>)*)>>\s*stream\r?\n',
  );
  for (final match in dictionary.allMatches(text)) {
    final dict = match.group(1)!;
    if (!dict.contains('/Subtype /Image') && !dict.contains('/Subtype/Image')) {
      continue;
    }
    final length = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)').firstMatch(dict);
    final start = match.end;
    final end = length != null
        ? start + int.parse(length.group(1)!)
        : text.indexOf('endstream', start);
    if (end > bytes.length || end <= start) continue;
    final data = Uint8List.sublistView(bytes, start, end);
    try {
      if (dict.contains('/DCTDecode')) {
        final image = img.decodeJpg(data);
        if (image != null) images.add(image);
      } else if (dict.contains('/FlateDecode')) {
        final width = int.parse(
          RegExp(r'/Width\s+(\d+)').firstMatch(dict)!.group(1)!,
        );
        final height = int.parse(
          RegExp(r'/Height\s+(\d+)').firstMatch(dict)!.group(1)!,
        );
        final grey = dict.contains('/DeviceGray');
        if (!dict.contains('/BitsPerComponent 8') ||
            !(grey || dict.contains('/DeviceRGB')) ||
            dict.contains('/DecodeParms')) {
          continue;
        }
        final raw = const ZLibDecoder().decodeBytes(data);
        final channels = grey ? 1 : 3;
        if (raw.length < width * height * channels) continue;
        images.add(
          img.Image.fromBytes(
            width: width,
            height: height,
            bytes: Uint8List.fromList(raw).buffer,
            numChannels: channels,
          ),
        );
      }
    } on Object {
      // An image this reader does not understand is left out.
    }
  }
  if (images.isEmpty) {
    throw const FormatException('The PDF has no images ArtBlend can read');
  }
  final first = images.first;
  final scale = _fit(first.width, first.height);
  final size = _canvas(first.width, first.height, scale);
  return ImportedDrawing(
    size: size,
    scaled: scale < 1,
    layers: [
      for (final (i, image) in images.indexed)
        ImportedLayer(
          name: 'Page ${i + 1}',
          rgba: _place(
            image,
            size,
            scale: math.min(
              size.width / image.width,
              size.height / image.height,
            ),
          ),
        ),
    ],
  );
}

/// A `.procreate` file's own preview: its layers are in a format ArtBlend
/// does not read, so the picture comes in as one layer.
ImportedDrawing decodeProcreate(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final thumbnail = archive.files
      .where((f) => f.name.toLowerCase() == 'quicklook/thumbnail.png')
      .firstOrNull;
  final image = thumbnail == null ? null : img.decodePng(thumbnail.content);
  if (image == null) {
    throw const FormatException('The Procreate file has no preview');
  }
  final size = _canvas(
    image.width,
    image.height,
    _fit(image.width, image.height),
  );
  return ImportedDrawing(
    size: size,
    partial: true,
    layers: [ImportedLayer(name: 'Procreate', rgba: _place(image, size))],
  );
}

/// One picture from a file the platform cannot decode itself (PSD, TIFF),
/// as PNG: its flattened image, or first page.
Uint8List flatImagePng(Uint8List bytes, String extension) {
  final image = switch (extension.toLowerCase()) {
    'psd' => () {
      final psd = img.PsdImage(bytes);
      if (!psd.isValid || !psd.decode()) return null;
      return psd.renderImage();
    }(),
    'tif' || 'tiff' => img.decodeTiff(bytes),
    _ => null,
  };
  if (image == null) throw const FormatException('The image is unreadable');
  return img.encodePng(image);
}
