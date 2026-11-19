import 'dart:io' show RawZLibFilter, ZLibDecoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getAdler32, getCrc32;

/// Rows per independently compressed PNG band. A native stroke re-encodes
/// only the bands it touched; the rest of the layer's IDAT is reused.
const pngBandRows = 64;

/// One band: Sub-filtered rows, raw deflate ending in a sync flush (not
/// final), with the Adler-32 and length of its uncompressed bytes.
class PngBand {
  const PngBand(this.deflate, this.adler, this.length);
  final Uint8List deflate;
  final int adler, length;
}

/// Encodes [rowCount] rows of straight RGBA ([rows] starts at a band edge)
/// at zlib [level].
List<PngBand> encodePngBands(
  Uint8List rows,
  int width,
  int rowCount, {
  int level = 6,
}) {
  if (rows.length != width * rowCount * 4) {
    throw ArgumentError('Incorrect RGBA byte count');
  }
  final stride = width * 4;
  final bands = <PngBand>[];
  for (var start = 0; start < rowCount; start += pngBandRows) {
    final count = (rowCount - start).clamp(0, pngBandRows);
    final filtered = Uint8List((stride + 1) * count);
    for (var y = 0; y < count; y++) {
      final row = (start + y) * stride, out = y * (stride + 1);
      filtered[out] = 1;
      for (var x = 0; x < stride; x++) {
        filtered[out + 1 + x] =
            (rows[row + x] - (x < 4 ? 0 : rows[row + x - 4])) & 0xff;
      }
    }
    final filter = RawZLibFilter.deflateFilter(level: level, raw: true)
      ..process(filtered, 0, filtered.length);
    final out = BytesBuilder(copy: false);
    // flush: true is a sync flush: byte-aligned, not final, no shared window.
    for (List<int>? part; (part = filter.processed()) != null;) {
      out.add(part!);
    }
    bands.add(PngBand(out.takeBytes(), getAdler32(filtered), filtered.length));
  }
  return bands;
}

int _adler32Combine(int a1, int a2, int length2) {
  const base = 65521;
  final rem = length2 % base;
  var sum1 = a1 & 0xffff;
  var sum2 = (rem * sum1) % base;
  sum1 += (a2 & 0xffff) + base - 1;
  sum2 += ((a1 >> 16) & 0xffff) + ((a2 >> 16) & 0xffff) + base - rem;
  if (sum1 >= base) sum1 -= base;
  if (sum1 >= base) sum1 -= base;
  if (sum2 >= base << 1) sum2 -= base << 1;
  if (sum2 >= base) sum2 -= base;
  return (sum2 << 16) | sum1;
}

/// An 8-bit straight RGBA PNG whose single zlib stream joins [bands].
Uint8List assemblePng(List<PngBand> bands, int width, int height) {
  var adler = 1;
  final idat = BytesBuilder(copy: false)..add(const [0x78, 0x9c]);
  for (final band in bands) {
    idat.add(band.deflate);
    adler = _adler32Combine(adler, band.adler, band.length);
  }
  // Empty final fixed-Huffman block, then the stream checksum.
  idat
    ..add(const [0x03, 0x00])
    ..add((ByteData(4)..setUint32(0, adler)).buffer.asUint8List());
  final bytes = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final header = ByteData(8)
      ..setUint32(0, data.length)
      ..setUint8(4, type.codeUnitAt(0))
      ..setUint8(5, type.codeUnitAt(1))
      ..setUint8(6, type.codeUnitAt(2))
      ..setUint8(7, type.codeUnitAt(3));
    bytes
      ..add(header.buffer.asUint8List(0, 8))
      ..add(data);
    final crc = getCrc32(data, getCrc32(header.buffer.asUint8List(4, 4)));
    bytes.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  }

  chunk(
    'IHDR',
    (ByteData(13)
          ..setUint32(0, width)
          ..setUint32(4, height)
          ..setUint8(8, 8)
          ..setUint8(9, 6))
        .buffer
        .asUint8List(),
  );
  chunk('IDAT', idat.takeBytes());
  chunk('IEND', const []);
  return bytes.takeBytes();
}

/// 8-bit straight RGBA PNG, Sub-filtered rows, platform zlib at [level].
Uint8List encodeRgbaPng(
  Uint8List rgba,
  int width,
  int height, {
  int level = 6,
}) => assemblePng(
  encodePngBands(rgba, width, height, level: level),
  width,
  height,
);

/// Exact straight RGBA of an 8-bit RGBA, non-interlaced PNG of the given size
/// (any filter), or null for other formats. Unlike a GPU round trip, this
/// keeps low-alpha colors byte for byte.
Uint8List? decodeRgbaPng(Uint8List png, int width, int height) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (png.length < 33) return null;
  for (var i = 0; i < 8; i++) {
    if (png[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(png);
  final idat = BytesBuilder(copy: false);
  var offset = 8;
  var header = false;
  while (offset + 12 <= png.length) {
    final length = data.getUint32(offset);
    if (offset + 12 + length > png.length) return null;
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = offset + 8;
    if (type == 'IHDR') {
      if (length != 13 ||
          data.getUint32(body) != width ||
          data.getUint32(body + 4) != height ||
          png[body + 8] != 8 ||
          png[body + 9] != 6 ||
          png[body + 12] != 0) {
        return null;
      }
      header = true;
    } else if (type == 'IDAT') {
      idat.add(Uint8List.sublistView(png, body, body + length));
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  if (!header) return null;
  final List<int> inflated;
  try {
    inflated = ZLibDecoder().convert(idat.takeBytes());
  } on FormatException {
    return null;
  }
  final stride = width * 4;
  if (inflated.length != (stride + 1) * height) return null;
  final out = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    final filter = inflated[y * (stride + 1)];
    final source = y * (stride + 1) + 1, row = y * stride;
    for (var x = 0; x < stride; x++) {
      final a = x < 4 ? 0 : out[row + x - 4];
      final b = y == 0 ? 0 : out[row - stride + x];
      final c = x < 4 || y == 0 ? 0 : out[row - stride + x - 4];
      final value = inflated[source + x];
      out[row + x] =
          switch (filter) {
            0 => value,
            1 => value + a,
            2 => value + b,
            3 => value + ((a + b) >> 1),
            4 => value + _paeth(a, b, c),
            _ => -1,
          } &
          0xff;
      if (filter > 4) return null;
    }
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
