import 'dart:ui';

import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

List<int> rgbAt(RgbaPixels p, int x, int y) =>
    p.bytes.sublist((y * p.width + x) * 4, (y * p.width + x) * 4 + 3);

/// Two red squares apart, a darker red inside the first (its shading).
Future<StudioController> drawing() async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  await c.replaceDocument(
    ArtDocument.empty(name: 'R', dimensions: const CanvasSize(128, 64)),
  );
  for (final (rect, color) in [
    (const Rect.fromLTWH(4, 4, 40, 40), 0xffd02020),
    (const Rect.fromLTWH(14, 14, 10, 10), 0xffb01818),
    (const Rect.fromLTWH(80, 4, 40, 40), 0xffd02020),
  ]) {
    c.selectColor(color);
    c.setSelection(SelectionRegion.rectangle(rect));
    await c.fillActiveLayer();
  }
  c.setSelection(null);
  return c;
}

Future<RgbaPixels> recolored(StudioController c, {required bool global}) async {
  c.selectColor(0xff20c040);
  expect(await c.startAdjustment(AdjustmentKind.recolor), isTrue);
  c.moveAdjustmentCentre(const Offset(30, 30));
  c.setAdjustmentValue('global', global ? 1 : 0);
  for (var i = 0; i < 100 && !c.adjustment!.floodReady; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(c.adjustment!.floodReady, isTrue);
  await c.applyAdjustment();
  return Exporter(c).layerPixels(c.document.activeLayer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recolor takes the current colour and remembers it per adjustment', () {
    final a = Adjustment.initial(AdjustmentKind.recolor).withColor(0xff123456);
    expect(a.withValue('threshold', .5).color, 0xff123456);
    expect(a == a.withColor(0xff000001), isFalse);
    expect(a.centred, isTrue);
  });

  test('flood recolors the connected area only, keeping its shading; '
      'global recolors every match', () async {
    final c = await drawing();
    addTearDown(c.dispose);
    final flood = await recolored(c, global: false);
    final light = rgbAt(flood, 30, 30), dark = rgbAt(flood, 18, 18);
    expect(light, [0x20, 0xc0, 0x40], reason: 'the colour under it, exactly');
    expect(dark[1], greaterThan(dark[0]), reason: 'the shade turned green');
    expect(dark[1], lessThan(light[1]), reason: 'and stayed darker');
    expect(rgbAt(flood, 100, 20), [0xd0, 0x20, 0x20], reason: 'not connected');
    expect(flood.bytes[(60 * 128 + 60) * 4 + 3], 0, reason: 'empty stays');

    c.undo();
    final global = await recolored(c, global: true);
    expect(rgbAt(global, 100, 20), [0x20, 0xc0, 0x40]);
  });

  test('a colour picked while recoloring changes the new colour', () async {
    final c = await drawing();
    addTearDown(c.dispose);
    await c.startAdjustment(AdjustmentKind.recolor);
    c.selectColor(0xff0000ff);
    expect(c.adjustment!.adjustment.color, 0xff0000ff);
    c.cancelAdjustment();
  });
}
