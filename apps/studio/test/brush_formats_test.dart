import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:atelier_studio/data/brush_formats.dart';
import 'package:atelier_studio/data/plist.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [w]×[h] grey tip: a bright square in the middle.
StampImage tip(int w, int h) {
  final pixels = Uint8List(w * h);
  for (var y = h ~/ 4; y < h * 3 ~/ 4; y++) {
    for (var x = w ~/ 4; x < w * 3 ~/ 4; x++) {
      pixels[y * w + x] = 200;
    }
  }
  return StampImage(pixels, w, h);
}

class _W {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v);
  void u16(int v) => b.add([v >> 8 & 0xff, v & 0xff]);
  void u32(int v) =>
      b.add([v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff]);
  void ascii(String s) => b.add(latin1.encode(s));
  void bytes(List<int> v) => b.add(v);
  Uint8List take() => b.takeBytes();
}

/// A sampled brush's pixels, RLE: one literal run per row.
Uint8List rle(StampImage t) {
  final w = _W();
  for (var y = 0; y < t.height; y++) {
    w.u16(t.width + 1);
  }
  for (var y = 0; y < t.height; y++) {
    w.u8(t.width - 1);
    w.bytes(t.pixels.sublist(y * t.width, (y + 1) * t.width));
  }
  return w.take();
}

Uint8List abrV6(
  List<StampImage> tips, {
  int subversion = 2,
  bool packed = true,
}) {
  final samples = _W();
  for (final t in tips) {
    final body = _W()
      ..bytes(Uint8List(subversion == 1 ? 47 : 301))
      ..u32(0)
      ..u32(0)
      ..u32(t.height)
      ..u32(t.width)
      ..u16(8)
      ..u8(packed ? 1 : 0)
      ..bytes(packed ? rle(t) : t.pixels);
    final data = body.take();
    samples.u32(data.length);
    samples.bytes(data);
    for (var pad = (4 - data.length % 4) % 4; pad > 0; pad--) {
      samples.u8(0);
    }
  }
  final s = samples.take();
  return (_W()
        ..u16(6)
        ..u16(subversion)
        ..ascii('8BIMdesc')
        ..u32(4)
        ..u32(0)
        ..ascii('8BIMsamp')
        ..u32(s.length)
        ..bytes(s))
      .take();
}

Uint8List abrV1(StampImage t) {
  final body = _W()
    ..u32(0)
    ..u16(25)
    ..u8(1)
    ..bytes(Uint8List(8))
    ..u32(0)
    ..u32(0)
    ..u32(t.height)
    ..u32(t.width)
    ..u16(8)
    ..u8(0)
    ..bytes(t.pixels);
  final data = body.take();
  return (_W()
        ..u16(1)
        ..u16(2)
        ..u16(1) // a computed brush, skipped
        ..u32(4)
        ..u32(0)
        ..u16(2)
        ..u32(data.length)
        ..bytes(data))
      .take();
}

void main() {
  test('a binary property list reads back what was written', () {
    final value = {
      'name': 'Fırça',
      'ascii': 'plain',
      'count': 42,
      'negative': -7,
      'ratio': .25,
      'on': true,
      'off': false,
      'data': Uint8List.fromList([1, 2, 3]),
      'list': [1, 'two', 3.5, const PlistUid(9)],
      'long': 'x' * 40,
    };
    final back = readBinaryPlist(writeBinaryPlist(value)) as Map;
    expect(back['name'], 'Fırça');
    expect(back['count'], 42);
    expect(back['negative'], -7);
    expect(back['ratio'], .25);
    expect((back['on'], back['off']), (true, false));
    expect(back['data'], [1, 2, 3]);
    expect(back['list'], [1, 'two', 3.5, const PlistUid(9)]);
    expect(back['long'], 'x' * 40);
    expect(() => readBinaryPlist(Uint8List(10)), throwsFormatException);
  });

  test('a keyed archive resolves its references, strings and arrays', () {
    final archive = {
      r'$archiver': 'NSKeyedArchiver',
      r'$top': {'root': const PlistUid(1)},
      r'$objects': [
        r'$null',
        {
          r'$class': const PlistUid(4),
          'name': const PlistUid(2),
          'plotSpacing': .3,
          'tags': const PlistUid(3),
          'missing': const PlistUid(0),
        },
        {'NS.string': 'Kömür'},
        {
          'NS.objects': [const PlistUid(2), 5],
        },
        {r'$classname': 'SilicaBrush'},
      ],
    };
    final root = unarchiveRoot(readBinaryPlist(writeBinaryPlist(archive)));
    expect(root['name'], 'Kömür');
    expect(root['plotSpacing'], .3);
    expect(root['tags'], ['Kömür', 5]);
    expect(root['missing'], isNull);
    expect(
      unarchiveRoot(
        readBinaryPlist(archiveObject('SilicaBrush', {'name': 'A', 'x': 1.0})),
      ),
      {'name': 'A', 'x': 1.0},
    );
  });

  test('a stamp brush goes out as a Procreate .brush and comes back with '
      'its shape, grain and settings; a .brushset keeps its order', () {
    final shape = stampPng(tip(64, 64));
    final grain = stampPng(tip(128, 128));
    const settings = StampSettings(
      spacing: .25,
      scatter: .4,
      sizeJitter: .3,
      opacityJitter: .2,
      followStroke: true,
      rotationJitter: .5,
      pressureSize: .8,
      pressureOpacity: .1,
      flow: .6,
      grainDepth: .7,
      grainScale: 2,
    );
    final brush = BrushPreset(
      id: 'b',
      name: 'Kuru fırça',
      size: 48,
      engine: BrushEngineKind.stamp,
      tip: 'builtin:round-soft',
      stamp: settings,
    );
    final bytes = encodeProcreateBrush((
      brush: brush,
      shape: shape,
      grain: grain,
    ));
    final names = [
      for (final f in ZipDecoder().decodeBytes(bytes).files) f.name,
    ];
    expect(names, containsAll(['Brush.archive', 'Shape.png', 'Grain.png']));
    final back = decodeProcreateBrushes(bytes, 'x.brush').single;
    expect(back.name, 'Kuru fırça');
    expect(back.size, 48);
    expect(back.engine, BrushEngineKind.stamp);
    expect(back.stamp, settings);
    final shapeBack = img.decodePng(base64Decode(back.tip!.substring(4)))!;
    expect(shapeBack.getPixel(32, 32).r, 200);
    expect(back.grain, startsWith('png:'));

    final set = encodeProcreateBrushset('Set', [
      (brush: brush.copyWith(name: 'Bir'), shape: shape, grain: null),
      (brush: brush.copyWith(name: 'İki'), shape: shape, grain: grain),
    ]);
    final both = decodeProcreateBrushes(set, 'Set.brushset');
    expect([for (final b in both) b.name], ['Bir', 'İki']);
    expect(both.first.grain, isNull);
    expect(both.first.stamp!.grainDepth, 0, reason: 'no grain, no depth');
  });

  test('a .brush with unreadable settings keeps its shape; without one, a '
      'round tip; an empty zip is refused', () {
    final zip = Archive()
      ..addFile(ArchiveFile.bytes('Brush.archive', Uint8List(50)))
      ..addFile(ArchiveFile.bytes('Shape.png', stampPng(tip(2000, 1000))));
    final brush = decodeProcreateBrushes(
      Uint8List.fromList(ZipEncoder().encode(zip)),
      'Ink.brush',
    ).single;
    expect(brush.name, 'Ink');
    final fitted = img.decodePng(base64Decode(brush.tip!.substring(4)))!;
    expect((fitted.width, fitted.height), (256, 128), reason: 'fitted');
    final bare = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'Brush.archive',
          archiveObject('SilicaBrush', {'name': 'Bare'}),
        ),
      );
    expect(
      decodeProcreateBrushes(
        Uint8List.fromList(ZipEncoder().encode(bare)),
        'b.brush',
      ).single.tip,
      'builtin:round-soft',
    );
    expect(
      () => decodeProcreateBrushes(
        Uint8List.fromList(ZipEncoder().encode(Archive())),
        'e.brush',
      ),
      throwsFormatException,
    );
  });

  test('Photoshop .abr sampled tips are read: version 6 packed and raw, '
      'version 1; a computed brush is skipped', () {
    final a = tip(40, 20), b = tip(16, 16);
    for (final file in [
      abrV6([a, b]),
      abrV6([a, b], subversion: 1, packed: false),
    ]) {
      final tips = decodeAbrTips(file);
      expect([for (final t in tips) (t.width, t.height)], [(40, 20), (16, 16)]);
      expect(tips.first.pixels, a.pixels);
    }
    final old = decodeAbrTips(abrV1(b)).single;
    expect(old.pixels, b.pixels);
    final brushes = decodeAbrBrushes(abrV6([a, b]), 'Kit.abr');
    expect([for (final x in brushes) x.name], ['Kit 1', 'Kit 2']);
    expect(brushes.first.isStamp, isTrue);
    expect(
      () => decodeAbrTips(Uint8List.fromList([0, 3, 0, 0])),
      throwsFormatException,
    );
  });
}
