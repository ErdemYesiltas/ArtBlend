import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

RgbaPixels solid(int r, int g, int b, {int a = 255}) => RgbaPixels(
  8,
  8,
  Uint8List.fromList([
    for (var i = 0; i < 64; i++) ...[r, g, b, a],
  ]),
);

bool loops(Uint8List gif) {
  final tag = 'NETSCAPE2.0'.codeUnits;
  for (var i = 0; i + tag.length <= gif.length; i++) {
    var hit = true;
    for (var k = 0; k < tag.length && hit; k++) {
      hit = gif[i + k] == tag[k];
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  final frames = <TimedFrame>[
    (pixels: solid(255, 0, 0), ms: 100),
    (pixels: solid(0, 0, 255), ms: 300),
  ];

  test('a GIF keeps the frames and their times; one shot has no loop '
      'block', () {
    final looping = encodeGif(frames, loop: true);
    final once = encodeGif(frames, loop: false);
    expect(loops(looping), isTrue);
    expect(loops(once), isFalse);
    for (final bytes in [looping, once]) {
      final gif = img.decodeGif(bytes)!;
      expect(gif.numFrames, 2);
      expect([for (final f in gif.frames) f.frameDuration], [100, 300]);
      final p = gif.frames[1].getPixel(4, 4);
      expect([p.r, p.g, p.b], [0, 0, 255]);
    }
  });

  test('an animated PNG keeps transparency, times and the loop count', () {
    final bytes = encodeApng([
      (pixels: solid(255, 0, 0, a: 128), ms: 100),
      frames[1],
    ], loop: false);
    final apng = img.decodePng(bytes)!;
    expect(apng.numFrames, 2);
    expect([for (final f in apng.frames) f.frameDuration], [100, 300]);
    final info = img.PngDecoder().startDecode(bytes)! as img.PngInfo;
    expect(info.repeat, 1, reason: 'plays once');
    expect(apng.frames.first.getPixel(4, 4).a, 128);
  });

  test('animation frames follow playback: holds become time on screen, '
      'ping-pong comes back, frames are drawn as played', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(
      ArtDocument(
        id: 'a',
        name: 'Anim',
        dimensions: const CanvasSize(400, 200),
        layers: [for (var i = 0; i < 3; i++) ArtLayer(id: 'f$i', name: 'F$i')],
        activeLayerId: 'f0',
      ),
    );
    for (final (i, color) in [0xffff0000, 0xff00ff00, 0xff0000ff].indexed) {
      c.selectLayer('f$i');
      c.selectColor(color);
      c.setSelection(
        SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 400, 200)),
      );
      await c.fillActiveLayer();
    }
    c.setSelection(null);
    c.setAnimationAssist(true);
    c.setAnimation(
      c.document.animation!.copyWith(
        fps: 10,
        mode: PlaybackMode.pingPong,
        holds: {'f1': 2},
      ),
    );
    final out = await Exporter(c).animationFrames(longest: 100);
    expect([for (final f in out) f.ms], [100, 300, 100, 300]);
    expect((out.first.pixels.width, out.first.pixels.height), (100, 50));
    int green(TimedFrame f) => f.pixels.bytes[(25 * 100 + 50) * 4 + 1];
    expect([for (final f in out) green(f)], [0, 255, 0, 255]);

    final gif = img.decodeGif(
      await Exporter(c).export(ExportFormat.gif, web: true),
    )!;
    expect(gif.numFrames, 4);
    expect(gif.width, 400, reason: "web caps at 800, never enlarges");
    // No paper and an empty frame: that frame comes out see-through.
    c.toggleBackground();
    c.clearFrames({2});
    final clear = img.decodeGif(
      await Exporter(c).export(ExportFormat.gif, web: true),
    )!;
    expect(clear.frames[2].getPixel(10, 10).a, 0, reason: 'no paper');
    expect(clear.frames[1].getPixel(10, 10).a, 255);
  });
}
