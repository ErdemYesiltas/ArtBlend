import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/asset_importer.dart';
import 'package:atelier_studio/data/palette_formats.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

/// Half red, 30% blue, 20% green, then a transparent strip.
Uint8List picture() {
  const w = 100, h = 20;
  final rgba = Uint8List(w * (h + 5) * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = x < 50
          ? [220, 30, 30]
          : x < 80
          ? [30, 60, 220]
          : [40, 200, 70];
      rgba.setAll((y * w + x) * 4, [...c, 255]);
    }
  }
  return rgba;
}

int distance(int a, int b) => [16, 8, 0]
    .map((s) => ((a >> s & 0xff) - (b >> s & 0xff)).abs())
    .reduce((x, y) => x > y ? x : y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a picture\'s main colours, most common first, the same each time; '
      'duplicates merge', () {
    final colors = paletteFromPixels(picture(), count: 3);
    expect(colors, hasLength(3));
    expect(distance(colors[0], 0xffdc1e1e), lessThan(3));
    expect(distance(colors[1], 0xff1e3cdc), lessThan(3));
    expect(distance(colors[2], 0xff28c846), lessThan(3));
    expect(paletteFromPixels(picture(), count: 3), colors);
    expect(paletteFromPixels(picture(), count: 12), hasLength(3));
    expect(paletteFromPixels(Uint8List(400)), isEmpty, reason: 'transparent');
  });

  test('every export format reads back as the same palette', () {
    const colors = [0xffdc1e1e, 0xff1e3cdc, 0xff28c846, 0xff000000, 0xffffffff];
    for (final format in PaletteFormat.values) {
      final bytes = encodePalette('Güneş', colors, format);
      final back = decodePaletteImport((bytes, 'Güneş.${format.extension}'));
      expect(back, hasLength(1), reason: format.name);
      expect(back.single.colors.length, colors.length, reason: format.name);
      for (var i = 0; i < colors.length; i++) {
        expect(
          distance(back.single.colors[i], colors[i]),
          lessThanOrEqualTo(1),
          reason: '${format.name} $i',
        );
      }
      if (format == PaletteFormat.swatches || format == PaletteFormat.gpl) {
        expect(back.single.name, 'Güneş', reason: format.name);
      }
    }
    final names = [
      for (final f
          in ZipDecoder()
              .decodeBytes(encodePalette('x', colors, PaletteFormat.swatches))
              .files)
        f.name,
    ];
    expect(names, ['Swatches.json']);
  });

  test('a Procreate palette with empty slots imports its colours', () {
    final json = utf8.encode(
      jsonEncode([
        {
          'name': 'Boşluklu',
          'swatches': [
            {'hue': 0, 'saturation': 1, 'brightness': 1, 'alpha': 1},
            null,
            {'hue': .5, 'saturation': 1, 'brightness': 1, 'alpha': 1},
          ],
        },
      ]),
    );
    final zip = Archive()..addFile(ArchiveFile.bytes('Swatches.json', json));
    final palette = decodePaletteImport((
      Uint8List.fromList(ZipEncoder().encode(zip)),
      'b.swatches',
    )).single;
    expect(palette.name, 'Boşluklu');
    expect(palette.colors, [0xffff0000, 0xff00ffff]);
  });

  testWidgets('a palette is made from the canvas\'s colours', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.runAsync(() async {
      c.selectColor(0xff2050d0);
      c.setSelection(
        SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 600, 1024)),
      );
      await c.fillActiveLayer();
      c.setSelection(null);
    });
    await tester.pumpWidget(StudioApp(controller: c));
    c.setPanel(EditorPanel.colors);
    await tester.pumpAndSettle();
    final palettes = c.palettes.length;
    await tester.ensureVisible(
      find.byKey(const ValueKey('palette-from-image')),
    );
    await tester.tap(find.byKey(const ValueKey('palette-from-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-source-canvas')));
    for (
      var i = 0;
      i < 100 &&
          find.byKey(const ValueKey('palette-preview')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('palette-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('palette-create')));
    for (var i = 0; i < 50 && c.palettes.length == palettes; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.palettes.length, palettes + 1);
    final made = c.palettes.last.colors;
    expect(made.any((x) => distance(x, 0xff2050d0) < 4), isTrue);
    expect(
      made.any((x) => distance(x, 0xfffffdf8) < 4),
      isTrue,
      reason: 'paper',
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
