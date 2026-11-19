import 'dart:convert';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

ArtDocument film() => ArtDocument(
  id: 'f',
  name: 'Film',
  dimensions: const CanvasSize(120, 80),
  layers: [
    ArtLayer(id: 'bg', name: 'Fon'),
    ArtLayer(id: 'a', name: 'A'),
    ArtLayer(id: 'b1', name: 'B line', group: 'g'),
    ArtLayer(id: 'b2', name: 'B colour', group: 'g'),
    ArtLayer(id: 'fg', name: 'Ön'),
  ],
  groups: const [LayerGroup(id: 'g', name: 'B')],
  activeLayerId: 'a',
);

List<String> ids(ArtDocument d) => [for (final l in d.layers) l.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('animation settings are kept with the drawing; damaged ones take '
      'their defaults', () {
    const settings = AnimationSettings(
      fps: 24,
      mode: PlaybackMode.pingPong,
      onionFrames: 4,
      holds: {'a': 3},
      background: 'bg',
    );
    final doc = film().copyWith(animation: settings);
    final back = ArtDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())));
    expect(back.animating, isTrue);
    expect(back.animation!.fps, 24);
    expect(back.animation!.mode, PlaybackMode.pingPong);
    expect(back.animation!.hold('a'), 3);
    expect(back.animation!.background, 'bg');
    final odd = AnimationSettings.fromJson({
      'fps': 500,
      'mode': 'sideways',
      'holds': {'x': 999},
    });
    expect((odd.fps, odd.mode, odd.hold('x')), (60, PlaybackMode.loop, 120));
    expect(ArtDocument.frameId(film().pages[2]), 'g');
  });

  test('a frame is shown alone, over the background frame and under the '
      'foreground frame; frames are added, copied and deleted', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(film());
    c.setPageAssist(true);
    c.setAnimationAssist(true);
    expect(c.document.pageAssist, isFalse, reason: 'one assist at a time');
    expect(ids(c.shownDocument), ['a']);
    final settings = c.document.animation!;
    c.setFrameOptions(settings.copyWith(background: 'bg', foreground: 'fg'));
    expect(ids(c.shownDocument), ['bg', 'a', 'fg']);
    c.goToPage(0);
    expect(ids(c.shownDocument), ['bg', 'fg']);
    c.goToPage(3);
    expect(ids(c.shownDocument), ['bg', 'fg']);
    c.undo();
    expect(c.document.animation!.background, isNull, reason: 'an undo step');

    c.goToPage(2);
    c.addFrame('New');
    expect(c.document.pages.length, 5);
    expect(c.document.currentPage, 3, reason: 'right after the group');
    expect(c.document.activeLayer.group, isNull);

    c.duplicateFrame(2, 'Copy');
    final pages = c.document.pages;
    expect(pages.length, 6);
    expect([for (final l in pages[3]) l.name], ['B line', 'B colour']);
    expect(pages[3].first.group, isNot('g'));
    c.deleteFrame(3);
    expect(c.document.pages.length, 5);
    c.setAnimation(c.document.animation!.copyWith(fps: 30));
    c.setAnimationAssist(false);
    expect(c.shownDocument.layers.length, c.document.layers.length);
    expect(c.document.animation!.fps, 30, reason: 'kept when off');
  });

  testWidgets('the timeline jumps between frames, adds one, and the shown '
      'frame\'s options set its hold and make it the background', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.runAsync(() => c.replaceDocument(film()));
    await tester.pumpWidget(StudioApp(controller: c));
    c.setAnimationAssist(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('animation-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('frame-0')));
    await tester.pumpAndSettle();
    expect(c.document.currentPage, 0);
    await tester.tap(find.byKey(const ValueKey('frame-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('frame-options')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('frame-hold-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('number-field')), '4');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frame-background')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(c.document.animation!.hold('bg'), 4);
    expect(c.document.animation!.background, 'bg');
    expect(find.text('1 +4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('frame-add')));
    await tester.pumpAndSettle();
    expect(c.document.pages.length, 5);
    expect(c.document.currentPage, 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
