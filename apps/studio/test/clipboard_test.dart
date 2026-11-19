import 'dart:typed_data';
import 'dart:ui';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/history_change.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

int alphaAt(Uint8List rgba, int x, int y) => rgba[(y * 1024 + x) * 4 + 3];

Future<Uint8List> pixels(StudioController c, [ArtLayer? layer]) async =>
    (await renderNativeBase(
      layer ?? c.document.activeLayer,
      c.document.grid,
      c.rasters.images,
    )).rgba;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copy keeps where pixels were; cut clears them; paste lands them '
      'there on a new layer, in this or another drawing', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final white = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 255);
    await c.addImageLayer(
      encodeRgbaPng(white, 64, 64),
      'White',
      at: const Rect.fromLTWH(100, 100, 400, 300),
    );
    final source = c.document.activeLayer;
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(200, 150, 100, 100)),
    );
    expect(await c.copy(), isTrue);
    expect(c.clipboard!.area, const Rect.fromLTWH(200, 150, 100, 100));

    await c.cut();
    final cut = await pixels(c);
    expect(alphaAt(cut, 250, 200), 0, reason: 'cut away');
    expect(alphaAt(cut, 150, 200), 255, reason: 'outside kept');

    c.setSelection(null);
    final layers = c.document.layers.length;
    await c.paste('Pasted');
    expect(c.document.layers.length, layers + 1);
    expect(c.document.activeLayer.name, 'Pasted');
    final pasted = await pixels(c);
    expect(alphaAt(pasted, 250, 200), 255, reason: 'back in place');
    expect(alphaAt(pasted, 150, 200), 0);
    expect(c.document.layers.contains(source), isFalse);

    // Copy all: every visible layer flattened, then into a new drawing.
    expect(await c.copy(all: true), isTrue);
    expect(c.clipboard!.area, const Rect.fromLTWH(100, 100, 400, 300));
    final clip = c.clipboard;
    await c.replaceDocument(ArtDocument.empty());
    expect(c.clipboard, same(clip), reason: 'kept across drawings');
    await c.paste('Pasted');
    final other = await pixels(c);
    expect(alphaAt(other, 120, 120), 255);
    expect(alphaAt(other, 60, 60), 0);
  });

  test('undo and redo name what they reverse', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.addLayer('Two');
    c.beginStroke(const InkPoint(10, 10, .5), simulatePressure: true);
    c.appendPoint(const InkPoint(80, 80, .5));
    c.finishStroke();
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(opacity: .5));
    final seen = <(bool, HistoryChange)>[];
    c.historyNotice.addListener(() {
      final n = c.historyNotice.value!;
      seen.add((n.$2, n.$3));
    });
    c.undo();
    c.undo();
    c.undo();
    c.redo();
    expect(seen, [
      (true, HistoryChange.layerSettings),
      (true, HistoryChange.paint),
      (true, HistoryChange.addLayer),
      (false, HistoryChange.addLayer),
    ]);
    expect(StudioController.maxUndoSteps, 250);
  });
}
