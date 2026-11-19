import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

Future<Uint8List> shown(StudioController c, {bool hidden = true}) async {
  final recorder = ui.PictureRecorder();
  final doc = c.document.copyWith(backgroundHidden: hidden);
  paintDocument(
    ui.Canvas(recorder),
    doc,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final image = await recorder.endRecording().toImage(
    doc.dimensions.width,
    doc.dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

List<int> pixel(Uint8List p) => p.sublist(0, 4);

/// Grey 128 under [top], which is blended by [blend].
Future<StudioController> pair(int top, LayerBlend blend) async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  c.selectColor(0xff808080);
  await c.fillActiveLayer();
  c.addLayer('top');
  c.selectColor(top);
  await c.fillActiveLayer();
  c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(blend: blend));
  return c;
}

void expectNear(List<int> actual, List<int> expected, [int tolerance = 3]) {
  for (var i = 0; i < expected.length; i++) {
    expect(
      (actual[i] - expected[i]).abs() <= tolerance,
      isTrue,
      reason: '$actual vs $expected',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(BlendShader.load);

  test('modes the blend shader paints follow their formulas', () async {
    int grey(double v) => 0xff000000 | (((v * 255).round()) * 0x010101);
    final cases = <(LayerBlend, int, List<int>)>[
      (LayerBlend.linearBurn, grey(.75), [64, 64, 64]),
      (LayerBlend.subtract, grey(.25), [64, 64, 64]),
      (LayerBlend.divide, grey(.75), [171, 171, 171]),
      (LayerBlend.linearLight, grey(.75), [255, 255, 255]),
      (LayerBlend.linearLight, grey(.25), [0, 0, 0]),
      (LayerBlend.pinLight, grey(.9), [204, 204, 204]),
      (LayerBlend.pinLight, grey(.1), [51, 51, 51]),
      (LayerBlend.hardMix, grey(.6), [255, 255, 255]),
      (LayerBlend.hardMix, grey(.4), [0, 0, 0]),
      (LayerBlend.vividLight, grey(.75), [255, 255, 255]),
      (LayerBlend.vividLight, grey(.5), [128, 128, 128]),
      (LayerBlend.darkerColor, 0xffff0000, [255, 0, 0]),
      (LayerBlend.lighterColor, 0xff0000ff, [128, 128, 128]),
      (LayerBlend.exclusion, 0xffffffff, [127, 127, 127]),
    ];
    for (final (blend, top, expected) in cases) {
      final c = await pair(top, blend);
      expectNear(pixel(await shown(c)).sublist(0, 3), expected);
      c.dispose();
    }
  });

  test('opacity mixes the blend in; colour modes keep the backdrop\'s '
      'lightness', () async {
    final c = await pair(0xffbfbfbf, LayerBlend.linearBurn);
    addTearDown(c.dispose);
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(opacity: .5));
    expectNear(pixel(await shown(c)), [96, 96, 96, 255]);
    // Red in Color mode over grey: red's hue at grey's lightness.
    final red = await pair(0xffff0000, LayerBlend.color);
    addTearDown(red.dispose);
    expectNear(pixel(await shown(red)), [255, 74, 74, 255], 6);
  });

  test('a group blended by the shader matches its layer blended alone; '
      'the paper is part of the backdrop', () async {
    final c = await pair(0xffbfbfbf, LayerBlend.linearBurn);
    addTearDown(c.dispose);
    final alone = pixel(await shown(c));
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(blend: LayerBlend.normal),
    );
    c.groupLayers('G', ids: [c.document.activeLayerId]);
    c.updateGroup(
      c.document.groups.single.id,
      (g) => g.copyWith(blend: LayerBlend.linearBurn),
    );
    expectNear(pixel(await shown(c)), alone);

    final p = StudioController(storage: MemoryStorage());
    addTearDown(p.dispose);
    await p.initialize();
    p.selectColor(0xff404040);
    await p.fillActiveLayer();
    p.updateLayer(
      p.document.activeLayerId,
      (l) => l.copyWith(blend: LayerBlend.subtract),
    );
    // Paper 0xfffffdf8 minus 0x40 in each channel.
    expectNear(pixel(await shown(p, hidden: false)), [191, 189, 184, 255]);
  });
}
