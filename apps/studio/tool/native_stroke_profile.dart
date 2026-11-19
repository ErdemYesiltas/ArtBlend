// Cost of the first native integration (full 1024² surface transfers).
// Run: ./scripts/flutterw test tool/native_stroke_profile.dart
// Numbers come from the flutter_test host (JIT, no GPU raster thread); treat
// them as relative, and repeat on a release build and real tablets.
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native stroke cost profile', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    addTearDown(c.dispose);
    c.selectBrush(initialBrushes.firstWhere((b) => b.id == 'mypaint-charcoal'));
    c.setSize(24);
    final latencies = <int>[];
    for (var stroke = 0; stroke < 6; stroke++) {
      final y = 120.0 + stroke * 140;
      var t = Duration(seconds: stroke * 10);
      c.beginStroke(InkPoint(80, y, .7), simulatePressure: false, time: t);
      // 1.5 s of 120 Hz input, fed in real time.
      for (var i = 1; i <= 180; i++) {
        t += const Duration(microseconds: 8333);
        c.appendPoint(InkPoint(80 + i * 4.6, y, .7), time: t);
        if (i % 4 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 33));
        }
      }
      final lift = Stopwatch()..start();
      c.finishStroke();
      await c.settleStroke();
      latencies.add(lift.elapsedMilliseconds);
      // ignore: avoid_print
      print(
        'stroke $stroke: ${c.lastNativeStats}; pen-up → commit ${lift.elapsedMilliseconds}ms',
      );
    }
    // History memory after many steps: decoded GPU images vs PNG bytes.
    for (var stroke = 0; stroke < 40; stroke++) {
      final y = 60.0 + (stroke % 20) * 45;
      c.beginStroke(InkPoint(80, y, .7), simulatePressure: false);
      for (var i = 1; i <= 60; i++) {
        c.appendPoint(InkPoint(80 + i * 14.0, y + (stroke ~/ 20) * 20, .7));
      }
      c.finishStroke();
      await c.settleStroke();
    }
    final decoded = c.rasters.images.length;
    // ignore: avoid_print
    print(
      'history: ${c.canUndo ? 'undo available' : 'no undo'}, decoded images $decoded '
      '(${decoded * TiledRaster.size * TiledRaster.size * 4 ~/ 1024 ~/ 1024} MiB GPU), '
      'current layer PNG ${c.document.activeLayer.raster!.tiles.values.fold<int>(0, (n, t) => n + t.png.length) ~/ 1024} KiB',
    );
    final undo = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      c.undo();
    }
    await c.settleStroke();
    // ignore: avoid_print
    print('10 undos (7 decoded on demand): ${undo.elapsedMilliseconds}ms');
    latencies.sort();
    // ignore: avoid_print
    print(
      'pen-up → commit median ${latencies[latencies.length ~/ 2]}ms, '
      'max ${latencies.last}ms, PNG ${c.document.activeLayer.raster!.tiles.values.fold<int>(0, (n, t) => n + t.png.length) ~/ 1024} KiB',
    );
  });
}
