import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

ArtDocument frames(int n) => ArtDocument(
  id: 'p',
  name: 'Play',
  dimensions: const CanvasSize(100, 100),
  layers: [for (var i = 0; i < n; i++) ArtLayer(id: 'f$i', name: 'F$i')],
  activeLayerId: 'f1',
);

const ids = ['f0', 'f1', 'f2', 'f3'];

void main() {
  test('play order: holds repeat a frame, ping-pong turns without '
      'repeating its ends, pinned frames are not played', () {
    const loop = AnimationSettings(holds: {'f1': 2});
    expect(loop.playOrder(ids), [0, 1, 1, 1, 2, 3]);
    const pingPong = AnimationSettings(mode: PlaybackMode.pingPong);
    expect(pingPong.playOrder(ids), [0, 1, 2, 3, 2, 1]);
    const pinned = AnimationSettings(background: 'f0', foreground: 'f3');
    expect(pinned.playOrder(ids), [1, 2]);
    expect(pinned.playOrder(['f0']), [0], reason: 'a lone frame still plays');
  });

  testWidgets('plays from the shown frame at the fps, shows the playing '
      'frame without onions, one shot stops at the end', (tester) async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(frames(4));
    c.setAnimationAssist(true);
    c.setAnimation(c.document.animation!.copyWith(fps: 10));
    expect(c.onionView, isNotNull);

    c.play();
    expect(c.playback.value, 1, reason: 'starts on the shown frame');
    expect(c.onionView, isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.playback.value, 2);
    expect(c.shownDocument.layers.single.id, 'f2');
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.playback.value, 0, reason: 'loops');
    expect(c.stopPlayback(), isTrue);
    expect(c.playing, isFalse);
    expect(c.shownDocument.layers.single.id, 'f1', reason: 'back to editing');
    expect(c.stopPlayback(), isFalse);

    c.setAnimation(c.document.animation!.copyWith(mode: PlaybackMode.oneShot));
    c.play();
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.playback.value, 3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.playing, isFalse);

    c.play();
    c.setAnimationAssist(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.playing, isFalse, reason: 'stops with Animation Assist');
  });
}
