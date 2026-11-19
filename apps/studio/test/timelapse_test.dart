import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:atelier_studio/data/timelapse.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

Future<Directory> temp() async {
  final dir = await Directory.systemTemp.createTemp('artblend-timelapse-');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

Future<void> settle(
  StudioController c,
  TimelapseStore store,
  int frames,
) async {
  for (var i = 0; i < 200; i++) {
    if ((await store.frames(c.document.id)).length >= frames) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the video keeps the drawing\'s shape in even sides; 30 seconds '
      'spread the frames evenly', () {
    expect(timelapseSize(4096, 2048), (1080, 540));
    expect(timelapseSize(2480, 3508), (764, 1080));
    expect(timelapseSize(101, 51), (102, 52));
    final frames = List.generate(2000, (i) => i);
    final short = framesFor(frames, seconds: 30);
    expect(short.length, 900);
    expect((short.first, short.last), (0, 1999));
    expect(framesFor(frames.sublist(0, 10), seconds: 30), hasLength(10));
    expect(framesFor(frames), same(frames));
  });

  test('frames are kept in order with the video size; a drawing\'s '
      'time-lapse can be deleted', () async {
    final store = TimelapseStore(await temp());
    expect(await store.size('d'), isNull);
    await store.setSize('d', 640, 480);
    for (final i in [2, 0, 1]) {
      await store.add('d', i, Uint8List.fromList([i]));
    }
    expect(await store.size('d'), (640, 480));
    expect(
      [for (final f in await store.frames('d')) f.readAsBytesSync().single],
      [0, 1, 2],
    );
    await store.delete('d');
    expect(await store.frames('d'), isEmpty);
  });

  test('each change records one frame, without private layers; a change of '
      'selection records none; recording can be turned off', () async {
    final store = TimelapseStore(await temp());
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(
      ArtDocument.empty(name: 'T', dimensions: const CanvasSize(200, 100)),
    );
    c.timelapse = store;
    c.selectColor(0xff2040c0);
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 200, 100)),
    );
    await c.fillActiveLayer();
    await settle(c, store, 1);
    expect(await store.frames(c.document.id), hasLength(1));
    expect(await store.size(c.document.id), (200, 100));

    // A private layer filled red over everything: not in the next frame.
    c.addLayer('Ref');
    c.togglePrivateLayer(c.document.activeLayerId);
    c.selectColor(0xffff0000);
    await c.fillActiveLayer();
    await settle(c, store, 2);
    final frames = await store.frames(c.document.id);
    final last = img.decodeJpg(await frames.last.readAsBytes())!;
    final p = last.getPixel(100, 50);
    expect(p.b, greaterThan(150), reason: 'the blue under it');
    expect(p.r, lessThan(80), reason: 'not the private red');

    final count = frames.length;
    c.selectLayer(c.document.layers.first.id);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await store.frames(c.document.id), hasLength(count));

    c.setTimelapseOn(false);
    await c.fillActiveLayer();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await store.frames(c.document.id), hasLength(count));
    await c.clearTimelapse();
    expect(await store.frames(c.document.id), isEmpty);
  });
}
