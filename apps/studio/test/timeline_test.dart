import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

MovieDocument film({int fps = 10, int frames = 20}) => MovieDocument(
  id: 'm',
  name: 'Film',
  width: 640,
  height: 360,
  fps: fps,
  frames: frames,
);

void main() {
  test('contents: where they sit, what source frame shows, trimmed to '
      'their source; tracks keep them in order and never overlapping', () {
    final c = MovieContent(
      id: 'c',
      name: 'C',
      kind: TrackKind.flipbook,
      start: 10,
      length: 50,
      sourceIn: 4,
      sourceLength: 20,
    );
    expect(c.length, 16, reason: 'only 16 source frames after frame 4');
    expect(
      (c.end, c.sourceFrame(10), c.sourceFrame(25), c.sourceFrame(26)),
      (26, 4, 19, null),
    );
    final t = MovieTrack.fromJson({
      'id': 't',
      'kind': 'drawing',
      'contents': [
        {'id': 'b', 'start': 30, 'length': 5},
        {'id': 'a', 'start': 0, 'length': 10},
        {'id': 'x', 'start': 8, 'length': 4},
        'junk',
      ],
    })!;
    expect(
      [for (final c in t.contents) c.id],
      ['a', 'b'],
      reason: 'x overlaps',
    );
    expect(t.at(32)!.id, 'b');
    expect(t.at(20), isNull);
    expect((t.fits(10, 20), t.fits(10, 21)), (true, false));

    final m =
        MovieDocument.create(
          name: 'F',
          width: 320,
          height: 240,
          fps: 12,
          seconds: 3,
        ).copyWith(
          playback: PlaybackMode.pingPong,
          view: const TimelineView().copyWith(framePixels: 999, split: .5),
        );
    final flipbook = m.tracks.single.contents.single;
    expect((flipbook.start, flipbook.length), (0, 36), reason: 'whole movie');
    expect(m.view.framePixels, TimelineView.maxFramePixels);
    final back = MovieDocument.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
    expect(back.playback, PlaybackMode.pingPong);
  });

  test('timecode and ruler marks', () {
    expect(timecode(0, 24), '0:00:00');
    expect(timecode(24 * 61 + 5, 24), '1:01:05');
    expect(timecode(121, 120), '0:01:001');
    expect(rulerSteps(24, 20), (minor: 1, label: 5), reason: 'frames');
    expect(rulerSteps(24, 1), (
      minor: 12,
      label: 120,
    ), reason: '5 s labels, half-second marks');
    final far = rulerSteps(30, .25);
    expect(far.label % 30, 0);
    expect(far.label * .25, greaterThanOrEqualTo(56));
  });

  testWidgets('edits undo and redo and are saved; layout is not an undo '
      'step; playback loops, ping-pongs or stops once', (tester) async {
    final storage = MemoryStorage();
    final c = MovieController(storage: storage, movie: film(frames: 4));
    addTearDown(c.dispose);
    c.seek(2);
    c.addTrack(TrackKind.drawing, 'Ink');
    expect(c.movie.tracks.single.contents.single.start, 2);
    expect(c.movie.tracks.single.contents.single.length, 2, reason: 'to end');
    expect(c.selected, c.movie.tracks.single.contents.single.id);
    expect(storage.movies['m']!.tracks, hasLength(1));
    c.setView(c.movie.view.copyWith(framePixels: 20));
    c.undo();
    expect(c.movie.tracks, isEmpty);
    expect(c.selected, isNull);
    c.redo();
    expect(c.movie.tracks, hasLength(1));
    expect(c.canRedo, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(storage.movies['m']!.view.framePixels, 20, reason: 'saved later');

    c.seek(0);
    c.play();
    final frames = <int>[c.playhead.value];
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      frames.add(c.playhead.value);
    }
    expect(frames, [0, 1, 2, 3, 0, 1, 2, 3, 0, 1]);
    c.stop();
    c.setPlayback(PlaybackMode.pingPong);
    c.seek(0);
    c.play();
    frames.clear();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      frames.add(c.playhead.value);
    }
    expect(frames, [1, 2, 3, 2, 1, 0, 1, 2]);
    c.stop();
    c.setPlayback(PlaybackMode.oneShot);
    c.seek(2);
    c.play();
    await tester.pump(const Duration(milliseconds: 300));
    expect((c.playhead.value, c.playing.value), (3, false));
    c.play();
    expect(c.playhead.value, 0, reason: 'one shot at the end starts over');
    c.stop();
  });

  testWidgets('the timeline: ruler moves the playhead, tracks are added '
      'and undone, zoom and the divider change the layout, space plays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MovieScreen(
          storage: storage,
          movie: film(fps: 24, frames: 240),
          askName: (name) async => 'Renamed',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ruler = find.byKey(const ValueKey('timeline-ruler'));
    final left = tester.getTopLeft(ruler);
    // 6 px a frame: frame 20 is at 120 px.
    await tester.tapAt(left + const Offset(123, 10));
    await tester.pump();
    expect(find.text('0:00:20 / 0:10:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timeline-add-track')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drawing').last);
    await tester.pumpAndSettle();
    final track = storage.movies['m']!.tracks.single;
    expect(track.contents.single.start, 20);
    expect(
      find.byKey(ValueKey('content-${track.contents.single.id}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('track-menu-${track.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(storage.movies['m']!.tracks.single.name, 'Renamed');
    await tester.tap(find.byKey(const ValueKey('movie-undo')));
    await tester.tap(find.byKey(const ValueKey('movie-undo')));
    await tester.pumpAndSettle();
    expect(storage.movies['m']!.tracks, isEmpty);

    await tester.tap(find.byKey(const ValueKey('timeline-zoom-in')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(storage.movies['m']!.view.framePixels, 9);
    final split = storage.movies['m']!.view.split;
    await tester.drag(
      find.byKey(const ValueKey('timeline-divider')),
      const Offset(0, -100),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(storage.movies['m']!.view.split, greaterThan(split));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 210));
    expect(find.text('0:01:01 / 0:10:00'), findsOneWidget, reason: 'frame 25');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpWidget(const SizedBox());
  });
}
