import 'dart:typed_data';

import 'package:artblend_brush_engine/brush_worker.dart';
import 'package:test/test.dart';

void main() {
  test('worker preserves ordered input, returns pixels, recovers after a rejected preset', () async {
    final worker = await BrushWorker.create(width: 128, height: 128);
    addTearDown(worker.close);
    await expectLater(worker.loadPreset('{}'), throwsStateError);
    await worker.configure(diameter: 16, hue: 0.5, saturation: 1, value: 1);
    await worker.beginStroke();
    await worker.points([(16, 64, 0, 0, 0, 0.05)]);
    final samples = [
      for (int x = 16; x < 112; x++) (x.toDouble(), 64.0, 1.0, 0.0, 0.0, 0.01),
    ];
    final painting = worker.points(samples);
    final reading = worker.readRgba();
    await painting;
    final pixels = await reading;
    final center = (64 * 128 + 64) * 4;
    expect(pixels[center], lessThan(10));
    expect(pixels[center + 1], greaterThan(240));
    expect(pixels[center + 2], greaterThan(240));
    expect(pixels[center + 3], greaterThan(200));
    expect(await worker.allocatedTiles, greaterThan(0));
    final translucent = Uint8List(128 * 128 * 4);
    translucent.setAll(0, [200, 100, 50, 128]);
    await worker.loadRgba(translucent);
    final straight = await worker.readRgba();
    final premultiplied = await worker.readRgbaPremultiplied();
    expect(premultiplied[3], straight[3]);
    for (var c = 0; c < 3; c++) {
      expect(premultiplied[c], (straight[c] * straight[3] + 127) ~/ 255);
    }
    final dirty = await worker.takeDirtyChunks(chunk: 64);
    expect(dirty.indices, containsAll([2, 3]));
    expect(dirty.pixels!.length, dirty.indices.length * 64 * 64 * 4);
    expect((await worker.takeDirtyChunks(chunk: 64)).indices, isEmpty);
    final corner = await worker.readRgbaRect(64, 64, 16, 16);
    expect(corner.length, 16 * 16 * 4);
    await worker.loadRgbaRect(
      0,
      0,
      2,
      1,
      Uint8List.fromList(List.filled(8, 9)),
    );
    expect(await worker.readRgbaRect(0, 0, 2, 1), List.filled(8, 9));
    await worker.loadRgba(Uint8List(128 * 128 * 4));
    expect((await worker.readRgba()).every((b) => b == 0), isTrue);
    await Future.wait([worker.close(), worker.close()]);
    await expectLater(worker.readRgba(), throwsStateError);
  });
  test('failed worker startup releases ports', () async {
    await expectLater(
      BrushWorker.create(width: -1, height: 128),
      throwsStateError,
    );
  });
}
