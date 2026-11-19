import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/document.dart';
import 'color_profiles.dart';

/// Pixels to write: straight (not premultiplied) RGBA, row by row.
class RgbaPixels {
  const RgbaPixels(this.width, this.height, this.bytes);
  final int width, height;
  final Uint8List bytes;
}

img.Image _image(RgbaPixels p) => img.Image.fromBytes(
  width: p.width,
  height: p.height,
  bytes: p.bytes.buffer,
  bytesOffset: p.bytes.offsetInBytes,
  numChannels: 4,
);

/// [p] over an opaque [background] (ARGB): JPEG and PDF have no alpha.
img.Image _flatten(RgbaPixels p, int background) {
  final out = img.Image(width: p.width, height: p.height);
  final br = background >> 16 & 0xff,
      bg = background >> 8 & 0xff,
      bb = background & 0xff;
  final src = p.bytes;
  final dst = out.buffer.asUint8List();
  for (var i = 0, o = 0; i < src.length; i += 4, o += 3) {
    final a = src[i + 3];
    dst[o] = (src[i] * a + br * (255 - a) + 127) ~/ 255;
    dst[o + 1] = (src[i + 1] * a + bg * (255 - a) + 127) ~/ 255;
    dst[o + 2] = (src[i + 2] * a + bb * (255 - a) + 127) ~/ 255;
  }
  return out;
}

img.Image _profiled(img.Image image, Uint8List? icc) => icc == null
    ? image
    : (image
        ..iccProfile = img.IccProfile(
          'ICC',
          img.IccProfileCompression.none,
          icc,
        ));

/// With [icc], the colour profile goes in the file.
Uint8List encodeJpeg(
  RgbaPixels p, {
  int quality = 92,
  int background = 0xffffffff,
  Uint8List? icc,
}) => img.encodeJpg(_profiled(_flatten(p, background), icc), quality: quality);

/// Keeps transparency.
Uint8List encodeTiff(RgbaPixels p) => img.encodeTiff(_image(p));

Uint8List encodePngPixels(RgbaPixels p, {Uint8List? icc}) =>
    img.encodePng(_profiled(_image(p), icc));

/// One frame of an animation and how long it stays on screen.
typedef TimedFrame = ({RgbaPixels pixels, int ms});

/// An animated GIF: each frame on [background] (or, with
/// [alphaThreshold], see-through where its alpha is below it), reduced to
/// its own palette of [colors] (2–256), dithered unless [dither] is off.
/// Without [loop] it plays once (no looping block).
Uint8List encodeGif(
  List<TimedFrame> frames, {
  required bool loop,
  int background = 0xffffffff,
  int colors = 256,
  bool dither = true,
  double? alphaThreshold,
}) {
  final encoder = img.GifEncoder(
    numColors: colors.clamp(2, 256),
    dither: dither ? img.DitherKernel.floydSteinberg : img.DitherKernel.none,
  );
  img.Image picture(RgbaPixels p) {
    if (alphaThreshold == null) return _flatten(p, background);
    // A palette of its own with one see-through entry at the end (the
    // encoder marks a fully transparent palette entry as GIF transparency);
    // pixels below the threshold take it.
    final cut = (alphaThreshold * 255).round();
    final reduced = img.quantize(
      _flatten(p, background),
      numberOfColors: math.max(2, colors.clamp(2, 256) - 1),
      dither: dither ? img.DitherKernel.floydSteinberg : img.DitherKernel.none,
    );
    final source = reduced.palette!;
    // At most 255 colours, so the see-through one still fits a GIF palette.
    final n = math.min(source.numColors, 255);
    final palette = img.PaletteUint8(n + 1, 4);
    for (var i = 0; i < n; i++) {
      palette.setRgba(
        i,
        source.getRed(i),
        source.getGreen(i),
        source.getBlue(i),
        255,
      );
    }
    palette.setRgba(n, 0, 0, 0, 0);
    final out = img.Image(
      width: p.width,
      height: p.height,
      numChannels: 1,
      palette: palette,
    );
    for (final px in out) {
      final a = p.bytes[(px.y * p.width + px.x) * 4 + 3];
      px.index = a < cut
          ? n
          : math.min(reduced.getPixel(px.x, px.y).index.toInt(), n - 1);
    }
    return out;
  }

  for (final f in frames) {
    encoder.addFrame(
      picture(f.pixels),
      duration: math.max(2, (f.ms / 10).round()),
    );
  }
  final bytes = encoder.finish()!;
  if (loop) return bytes;
  final block = [0x21, 0xff, 0x0b, ...'NETSCAPE2.0'.codeUnits, 0x03, 0x01];
  for (var i = 0; i + block.length + 3 <= bytes.length; i++) {
    var hit = true;
    for (var k = 0; k < block.length && hit; k++) {
      hit = bytes[i + k] == block[k];
    }
    if (hit) {
      return Uint8List.fromList([
        ...bytes.sublist(0, i),
        ...bytes.sublist(i + block.length + 3),
      ]);
    }
  }
  return bytes;
}

/// An animated PNG: full colour and transparency. Without [loop] it plays
/// once.
Uint8List encodeApng(List<TimedFrame> frames, {required bool loop}) {
  final encoder = img.PngEncoder()
    ..start(frames.length)
    ..repeat = loop ? 0 : 1;
  for (final f in frames) {
    encoder.addFrame(_image(f.pixels)..frameDuration = f.ms);
  }
  return encoder.finish()!;
}

/// One PDF page: a JPEG shown at [dpi].
class PdfPage {
  const PdfPage(this.jpeg, this.width, this.height, this.dpi);
  final Uint8List jpeg;
  final int width, height, dpi;
}

/// A PDF whose pages are images, each its print size at its DPI.
/// With [icc] the page images are in that colour space (ICCBased).
Uint8List encodePdf(List<PdfPage> pages, {String title = '', Uint8List? icc}) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  void write(String s) => out.add(latin1.encode(s));
  void object(int id, void Function() body) {
    offsets.add(out.length);
    write('$id 0 obj\n');
    body();
    write('\nendobj\n');
  }

  String escaped(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .runes
      .map((r) => r < 128 ? String.fromCharCode(r) : '?')
      .join();

  write('%PDF-1.4\n%âãÏÓ\n');
  // 1 catalog, 2 pages, 3 info, 4 the profile; then per page: page,
  // content, image.
  final first = icc == null ? 4 : 5;
  final kids = [for (var i = 0; i < pages.length; i++) '${first + i * 3} 0 R'];
  object(1, () => write('<< /Type /Catalog /Pages 2 0 R >>'));
  object(
    2,
    () => write(
      '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>',
    ),
  );
  object(
    3,
    () => write('<< /Title (${escaped(title)}) /Producer (ArtBlend) >>'),
  );
  if (icc != null) {
    object(4, () {
      write('<< /N 3 /Alternate /DeviceRGB /Length ${icc.length} >>\nstream\n');
      out.add(icc);
      write('\nendstream');
    });
  }
  final space = icc == null ? '/DeviceRGB' : '[/ICCBased 4 0 R]';
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final id = first + i * 3;
    String pt(int px) => (px * 72 / page.dpi).toStringAsFixed(2);
    final w = pt(page.width), h = pt(page.height);
    object(
      id,
      () => write(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] '
        '/Resources << /XObject << /Im0 ${id + 2} 0 R >> >> '
        '/Contents ${id + 1} 0 R >>',
      ),
    );
    final content = 'q $w 0 0 $h 0 0 cm /Im0 Do Q';
    object(id + 1, () {
      write('<< /Length ${content.length} >>\nstream\n$content\nendstream');
    });
    object(id + 2, () {
      write(
        '<< /Type /XObject /Subtype /Image /Width ${page.width} '
        '/Height ${page.height} /ColorSpace $space /BitsPerComponent 8 '
        '/Filter /DCTDecode /Length ${page.jpeg.length} >>\nstream\n',
      );
      out.add(page.jpeg);
      write('\nendstream');
    });
  }
  final xref = out.length;
  write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info 3 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return out.takeBytes();
}

/// Photoshop's key for a blend mode.
String psdBlendKey(LayerBlend blend) => switch (blend) {
  LayerBlend.normal => 'norm',
  LayerBlend.darken => 'dark',
  LayerBlend.multiply => 'mul ',
  LayerBlend.colorBurn => 'idiv',
  LayerBlend.linearBurn => 'lbrn',
  LayerBlend.darkerColor => 'dkCl',
  LayerBlend.lighten => 'lite',
  LayerBlend.screen => 'scrn',
  LayerBlend.colorDodge => 'div ',
  LayerBlend.add => 'lddg',
  LayerBlend.lighterColor => 'lgCl',
  LayerBlend.overlay => 'over',
  LayerBlend.softLight => 'sLit',
  LayerBlend.hardLight => 'hLit',
  LayerBlend.vividLight => 'vLit',
  LayerBlend.linearLight => 'lLit',
  LayerBlend.pinLight => 'pLit',
  LayerBlend.hardMix => 'hMix',
  LayerBlend.difference => 'diff',
  LayerBlend.exclusion => 'smud',
  LayerBlend.subtract => 'fsub',
  LayerBlend.divide => 'fdiv',
  LayerBlend.hue => 'hue ',
  LayerBlend.saturation => 'sat ',
  LayerBlend.color => 'colr',
  LayerBlend.luminosity => 'lum ',
};

enum PsdSection { none, groupStart, groupEnd }

/// A layer record of a PSD, bottom to top. A group is a [PsdSection.groupEnd]
/// record below its layers and a [PsdSection.groupStart] record (the
/// folder, carrying the group's name, blend and opacity) above them.
/// A layer's pixels as Photoshop stores them: the rectangle holding its
/// visible pixels and, RLE-packed, its alpha, red, green and blue.
class PsdChannels {
  const PsdChannels(this.rect, this.planes);
  final (int, int, int, int)? rect;
  final List<(List<int>, Uint8List)> planes;
}

/// [p] packed for a PSD layer: kept small while the other layers render.
/// With [cmyk] the planes are alpha, cyan, magenta, yellow, black, the
/// inks stored as Photoshop keeps them (255 for none).
PsdChannels psdChannels(RgbaPixels p, {bool cmyk = false}) {
  final rect = _opaqueBounds(p);
  if (rect == null) return const PsdChannels(null, []);
  if (!cmyk) {
    return PsdChannels(rect, [
      for (final c in const [3, 0, 1, 2])
        _channel(p.bytes, p.width, 4, c, rect),
    ]);
  }
  final inks = rgbaToCmyka(p.bytes);
  return PsdChannels(rect, [
    _channel(inks, p.width, 5, 4, rect),
    for (final c in const [0, 1, 2, 3])
      _channel(inks, p.width, 5, c, rect, invert: true),
  ]);
}

/// [p] packed as a PSD's flattened picture: red, green, blue, alpha (or
/// with [cmyk] the four inks; transparency stays with the layers).
PsdChannels psdComposite(RgbaPixels p, {bool cmyk = false}) {
  final rect = (0, 0, p.width, p.height);
  if (!cmyk) {
    return PsdChannels(rect, [
      for (final c in const [0, 1, 2, 3])
        _channel(p.bytes, p.width, 4, c, rect),
    ]);
  }
  final inks = rgbaToCmyka(p.bytes);
  return PsdChannels(rect, [
    for (final c in const [0, 1, 2, 3])
      _channel(inks, p.width, 5, c, rect, invert: true),
  ]);
}

class PsdLayer {
  const PsdLayer({
    required this.name,
    this.pixels,
    this.channels,
    this.opacity = 1,
    this.blend = 'norm',
    this.visible = true,
    this.clipping = false,
    this.section = PsdSection.none,
  });
  final String name;

  /// The whole canvas, or already [channels]; neither for a group record.
  final RgbaPixels? pixels;
  final PsdChannels? channels;
  final double opacity;
  final String blend;
  final bool visible, clipping;
  final PsdSection section;
}

/// PackBits, Photoshop's RLE, of one row.
void _packBits(Uint8List row, BytesBuilder out) {
  var i = 0;
  final n = row.length;
  while (i < n) {
    var run = 1;
    while (i + run < n && run < 128 && row[i + run] == row[i]) {
      run++;
    }
    if (run > 1) {
      out
        ..addByte(257 - run)
        ..addByte(row[i]);
      i += run;
      continue;
    }
    var literal = 1;
    while (i + literal < n &&
        literal < 128 &&
        (i + literal + 1 >= n || row[i + literal] != row[i + literal + 1])) {
      literal++;
    }
    out.addByte(literal - 1);
    out.add(Uint8List.sublistView(row, i, i + literal));
    i += literal;
  }
}

/// One channel of [p] inside [rect] (left, top, right, bottom), RLE: row
/// lengths, then the rows.
(List<int>, Uint8List) _channel(
  Uint8List bytes,
  int imageWidth,
  int stride,
  int channel,
  (int, int, int, int) rect, {
  bool invert = false,
}) {
  final (left, top, right, bottom) = rect;
  final width = right - left;
  final row = Uint8List(width);
  final lengths = <int>[];
  final data = BytesBuilder(copy: false);
  for (var y = top; y < bottom; y++) {
    var o = (y * imageWidth + left) * stride + channel;
    for (var x = 0; x < width; x++, o += stride) {
      row[x] = invert ? 255 - bytes[o] : bytes[o];
    }
    final before = data.length;
    _packBits(row, data);
    lengths.add(data.length - before);
  }
  return (lengths, data.takeBytes());
}

/// The rectangle holding [p]'s visible pixels; null when there are none.
(int, int, int, int)? _opaqueBounds(RgbaPixels p) {
  var left = p.width, top = p.height, right = 0, bottom = 0;
  final b = p.bytes;
  for (var y = 0; y < p.height; y++) {
    final row = y * p.width * 4;
    for (var x = 0; x < p.width; x++) {
      if (b[row + x * 4 + 3] == 0) continue;
      if (x < left) left = x;
      if (x >= right) right = x + 1;
      if (y < top) top = y;
      bottom = y + 1;
    }
  }
  return right > left ? (left, top, right, bottom) : null;
}

class _Out {
  final b = BytesBuilder(copy: false);
  void bytes(List<int> v) => b.add(v);
  void ascii(String s) => b.add(latin1.encode(s));
  void u8(int v) => b.addByte(v & 0xff);
  void u16(int v) => bytes([v >> 8 & 0xff, v & 0xff]);
  void u32(int v) =>
      bytes([v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff]);
  int get length => b.length;
  Uint8List take() => b.takeBytes();
}

/// A layered Photoshop file: [layers] bottom to top, and [composite] (the
/// flattened picture, [RgbaPixels] or [psdComposite]) for readers that do
/// not read layers.
/// With [cmyk] a CMYK file (layers packed with `psdChannels(cmyk: true)`);
/// [icc] goes in as its colour profile.
Uint8List encodePsd(
  int width,
  int height,
  List<PsdLayer> layers,
  Object composite, {
  bool cmyk = false,
  Uint8List? icc,
}) {
  final ids = cmyk ? const [-1, 0, 1, 2, 3] : const [-1, 0, 1, 2];
  final records = _Out();
  final channelData = _Out();
  records.u16(layers.length);
  for (final layer in layers) {
    final packed =
        layer.channels ??
        (layer.pixels == null ? null : psdChannels(layer.pixels!, cmyk: cmyk));
    final rect = packed?.rect;
    final (left, top, right, bottom) = rect ?? (0, 0, 0, 0);
    records
      ..u32(top)
      ..u32(left)
      ..u32(bottom)
      ..u32(right)
      ..u16(ids.length);
    // Alpha first, then red, green, blue (or the four inks).
    for (final (i, id) in ids.indexed) {
      records.u16(id & 0xffff);
      if (rect == null) {
        records.u32(2);
        channelData.u16(0);
        continue;
      }
      final (lengths, data) = packed!.planes[i];
      records.u32(2 + lengths.length * 2 + data.length);
      channelData.u16(1);
      for (final l in lengths) {
        channelData.u16(l);
      }
      channelData.bytes(data);
    }
    final blend = layer.section == PsdSection.groupEnd ? 'norm' : layer.blend;
    records
      ..ascii('8BIM')
      ..ascii(blend)
      ..u8((layer.opacity.clamp(0, 1) * 255).round())
      ..u8(layer.clipping ? 1 : 0)
      ..u8(layer.visible ? 0 : 2)
      ..u8(0);
    final extra = _Out()
      ..u32(0) // no layer mask
      ..u32(0); // no blending ranges
    final name = latin1.encode(
      layer.name.runes
          .map((r) => r < 256 ? String.fromCharCode(r) : '?')
          .join(),
    );
    final short = name.length > 255 ? name.sublist(0, 255) : name;
    extra
      ..u8(short.length)
      ..bytes(short);
    for (var pad = (4 - (1 + short.length) % 4) % 4; pad > 0; pad--) {
      extra.u8(0);
    }
    // The name in full Unicode.
    final units = layer.name.codeUnits;
    final luni = _Out()..u32(units.length);
    for (final u in units) {
      luni.u16(u);
    }
    if (luni.length.isOdd) luni.u8(0);
    final luniBytes = luni.take();
    extra
      ..ascii('8BIMluni')
      ..u32(luniBytes.length)
      ..bytes(luniBytes);
    if (layer.section != PsdSection.none) {
      extra
        ..ascii('8BIMlsct')
        ..u32(layer.section == PsdSection.groupStart ? 12 : 4)
        ..u32(layer.section == PsdSection.groupStart ? 1 : 3);
      if (layer.section == PsdSection.groupStart) {
        extra
          ..ascii('8BIM')
          ..ascii(layer.blend);
      }
    }
    final extraBytes = extra.take();
    records
      ..u32(extraBytes.length)
      ..bytes(extraBytes);
  }
  final layerInfo = _Out()
    ..bytes(records.take())
    ..bytes(channelData.take());
  if (layerInfo.length.isOdd) layerInfo.u8(0);
  final layerInfoBytes = layerInfo.take();

  // The colour profile, as image resource 1039.
  final resources = _Out();
  if (icc != null) {
    resources
      ..ascii('8BIM')
      ..u16(1039)
      ..u16(0) // no name
      ..u32(icc.length)
      ..bytes(icc);
    if (icc.length.isOdd) resources.u8(0);
  }
  final resourceBytes = resources.take();
  final out = _Out()
    ..ascii('8BPS')
    ..u16(1)
    ..bytes(List.filled(6, 0))
    ..u16(4)
    ..u32(height)
    ..u32(width)
    ..u16(8)
    ..u16(cmyk ? 4 : 3) // CMYK or RGB
    ..u32(0) // colour mode data
    ..u32(resourceBytes.length)
    ..bytes(resourceBytes)
    ..u32(4 + layerInfoBytes.length + 4)
    ..u32(layerInfoBytes.length)
    ..bytes(layerInfoBytes)
    ..u32(0); // global layer mask
  // The composite: RLE, planar R, G, B, A.
  final planes = switch (composite) {
    PsdChannels(:final planes) => planes,
    RgbaPixels() => psdComposite(composite, cmyk: cmyk).planes,
    _ => throw ArgumentError.value(composite, 'composite'),
  };
  out.u16(1);
  for (final (lengths, _) in planes) {
    for (final l in lengths) {
      out.u16(l);
    }
  }
  for (final (_, data) in planes) {
    out.bytes(data);
  }
  return out.take();
}
