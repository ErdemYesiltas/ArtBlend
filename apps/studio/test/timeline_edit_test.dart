import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/domain/movie_edits.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

MovieContent clip(String id, int start, int length) => MovieContent(
  id: id,
  name: id,
  kind: TrackKind.drawing,
  start: start,
  length: length,
);

MovieDocument film() => MovieDocument(
  id: 'm',
  name: 'Film',
  width: 320,
  height: 180,
  fps: 10,
  frames: 120,
  tracks: [
    MovieTrack(
      id: 'a',
      name: 'Top',
      kind: TrackKind.drawing,
      contents: [clip('a1', 0, 20), clip('a2', 30, 20)],
    ),
    MovieTrack(
      id: 'b',
      name: 'Bottom',
      kind: TrackKind.drawing,
      contents: [clip('b1', 10, 20)],
    ),
  ],
);

void main() {
  testWidgets('a drag down one track moves there; halfway between two tracks '
      'it opens a new track; each drag is one undo step', (tester) async {
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
          movie: film(),
          askName: (name) async => name,
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<List<String>> layout() => [
      for (final t in storage.movies['m']!.tracks)
        [for (final c in t.contents) c.id],
    ];
    // a2 (30–50) fits on the bottom track after b1 (10–30).
    final a2 = find.byKey(const ValueKey('content-a2'));
    await tester.tap(a2);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(a2, const Offset(0, 56));
    await tester.pumpAndSettle();
    expect(layout(), [
      ['a1'],
      ['b1', 'a2'],
    ]);
    await tester.tap(find.byKey(const ValueKey('movie-undo')));
    await tester.pumpAndSettle();
    expect(layout(), [
      ['a1', 'a2'],
      ['b1'],
    ]);

    final a1 = find.byKey(const ValueKey('content-a1'));
    await tester.tap(a1);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(a1, const Offset(0, 28));
    await tester.pumpAndSettle();
    expect(layout(), [
      ['a2'],
      ['a1'],
      ['b1'],
    ], reason: 'a new track between the two');
    await tester.tap(find.byKey(const ValueKey('movie-undo')));
    await tester.pumpAndSettle();
    expect(layout(), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  test('copies made by split, duplicate and paste keep their drawings; '
      'hidden contents and tracks leave the stage', () {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    final ink = ArtDocument.empty(name: 'ink');
    c.drawings['a1'] = ink;
    c.seek(5);
    c.splitAtPlayhead('a1');
    final right = c.movie.tracks.first.contents[1];
    expect(right.start, 5);
    expect(c.drawings[right.id], same(ink));
    c.duplicateAfter('a2');
    expect(c.movie.tracks.first.contents.length, 4);
    c.select('a1');
    c.copySelection();
    c.seek(100);
    c.paste();
    final pasted = c.movie.tracks.first.contents.last;
    expect(pasted.start, 100);
    expect(c.drawings[pasted.id], same(ink));

    expect(c.shownAt(15).map((x) => x.id), contains('b1'));
    c.setTrackHidden('b', true);
    expect(c.shownAt(15).map((x) => x.id), isNot(contains('b1')));
    c.setHidden(right.id, true);
    expect(c.shownAt(6), isEmpty);
    c.undo();
    c.undo();
    expect(c.shownAt(15).map((x) => x.id), contains('b1'));
  });

  for (final size in [const Size(1280, 900), const Size(900, 600)]) {
    testWidgets(
      'drag to move, ends to trim (Free Trim pushes), menu to '
      'split, lasso to choose, copy and paste, eye to hide, group and fold '
      '(${size.width.round()}×${size.height.round()}, the timeline '
      'scrolling sideways in the smaller)',
      (tester) => edit(tester, size),
    );
  }
}

Future<void> edit(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
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
        movie: film(),
        askName: (name) async => 'Named',
      ),
    ),
  );
  await tester.pumpAndSettle();
  MovieDocument saved() => storage.movies['m']!;
  (int, int) span(String id) {
    final c = saved().contentById(id)!;
    return (c.start, c.end);
  }

  // 6 px a frame. Choose a2, then drag it 60 px: 10 frames later.
  final a2 = find.byKey(const ValueKey('content-a2'));
  await tester.tap(a2);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.drag(a2, const Offset(60, 0));
  await tester.pumpAndSettle();
  expect(span('a2'), (40, 60));
  await tester.tap(find.byKey(const ValueKey('movie-undo')));
  await tester.pumpAndSettle();
  expect(span('a2'), (30, 50), reason: 'the whole drag, one step');

  // Trim a1's end into a2: stops at it; with Free Trim a2 is pushed.
  await tester.tap(find.byKey(const ValueKey('content-a1')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.drag(
    find.byKey(const ValueKey('trim-end-a1')),
    const Offset(90, 0),
  );
  await tester.pumpAndSettle();
  expect(span('a1'), (0, 30));
  await tester.tap(find.byKey(const ValueKey('movie-undo')));
  await tester.tap(find.byKey(const ValueKey('timeline-free-trim')));
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey('trim-end-a1')),
    const Offset(90, 0),
  );
  await tester.pumpAndSettle();
  expect((span('a1'), span('a2')), ((0, 35), (45, 65)));
  await tester.tap(find.byKey(const ValueKey('movie-undo')));
  await tester.tap(find.byKey(const ValueKey('timeline-free-trim')));
  await tester.pumpAndSettle();

  // Split at the playhead from the right-click menu.
  final ruler = tester.getTopLeft(find.byKey(const ValueKey('timeline-ruler')));
  await tester.tapAt(ruler + const Offset(63, 10));
  await tester.pump();
  await tester.tapAt(
    tester.getCenter(find.byKey(const ValueKey('content-a1'))),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Split at the playhead'));
  await tester.pumpAndSettle();
  expect(saved().tracks.first.contents.length, 3);
  expect(span('a1'), (0, 10));

  // A lasso over everything, copy, paste at frame 80.
  await tester.tap(find.byKey(const ValueKey('timeline-choose')));
  await tester.pumpAndSettle();
  final tracks = tester.getTopLeft(
    find.byKey(const ValueKey('timeline-tracks')),
  );
  await tester.dragFrom(tracks + const Offset(2, 2), const Offset(400, 100));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('timeline-copy')));
  await tester.tapAt(ruler + const Offset(483, 10));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('timeline-paste')));
  await tester.pumpAndSettle();
  expect(saved().tracks.first.contents.length, 6);
  expect(saved().tracks.last.contents.length, 2);
  await tester.tap(find.byKey(const ValueKey('timeline-choose')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('track-eye-b')));
  await tester.pumpAndSettle();
  expect(saved().tracks.last.hidden, isTrue);

  await tester.tap(find.byKey(const ValueKey('track-menu-a')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Group with the track below'));
  await tester.pumpAndSettle();
  final group = saved().groups.single;
  expect(saved().tracks.every((t) => t.group == group.id), isTrue);
  await tester.tap(find.byKey(ValueKey('group-fold-${group.id}')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('track-a')), findsNothing);
  await tester.pumpWidget(const SizedBox());
}
