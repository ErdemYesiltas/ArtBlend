import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

MovieContent clip(String id, int start, int length) => MovieContent(
  id: id,
  name: id,
  kind: TrackKind.drawing,
  start: start,
  length: length,
  width: 100,
  height: 50,
);

MovieDocument film() => MovieDocument(
  id: 'm',
  name: 'Film',
  width: 400,
  height: 200,
  fps: 10,
  frames: 40,
  tracks: [
    MovieTrack(
      id: 't',
      name: 'Ink',
      kind: TrackKind.drawing,
      contents: [clip('c', 0, 5), clip('d', 8, 10)],
    ),
  ],
);

List<double> xs(MovieController c, String param) => [
  for (final k in c.content('c')!.keys[param] ?? const <Keyframe>[]) k.value,
];

void main() {
  testWidgets('a take keys every frame while the movie plays, smoothed by '
      'the motion filter; the same kind is written over, others layer; '
      'it makes its content longer where there is room; one undo step', (
    tester,
  ) async {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    c.setPerforming(true);
    c.setMotionFilter(0);
    c.beginTake('c', {'x': .2});
    expect(c.playing.value, isTrue);
    c.updateTake({'x': .8});
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.playhead.value, 3);
    expect(xs(c, 'x'), [.2, .8, .8, .8]);
    c.endTake();
    expect(c.playing.value, isFalse);

    c.seek(1);
    c.beginTake('c', {'x': .5});
    await tester.pump(const Duration(milliseconds: 100));
    c.endTake();
    expect(xs(c, 'x'), [.2, .5, .5, .8], reason: 'frames 1–2 written over');

    c.seek(0);
    c.setMotionFilter(1);
    c.beginTake('c', {'scale': 1});
    c.updateTake({'scale': 2});
    await tester.pump(const Duration(milliseconds: 200));
    c.endTake();
    final scale = xs(c, 'scale');
    expect(scale.first, 1);
    expect(scale[1], inExclusiveRange(1, 1.5), reason: 'smoothed');
    expect(xs(c, 'x'), [.2, .5, .5, .8], reason: 'layered, x kept');

    c.seek(3);
    c.setMotionFilter(0);
    c.beginTake('c', {'y': .1});
    await tester.pump(const Duration(milliseconds: 1000));
    expect(c.recording, isFalse, reason: 'stopped at d');
    expect(c.content('c')!.end, 8, reason: 'grew to the next content');
    c.undo();
    expect(c.content('c')!.end, 5);
    expect(c.content('c')!.keys['y'], isNull);
  });

  testWidgets('Perform on the stage: drag the content, the movie plays and '
      'records; lifting stops', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
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
    await tester.tap(find.byKey(const ValueKey('timeline-perform')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-indicator')), findsOneWidget);
    final box = tester.getRect(find.byKey(const ValueKey('movie-stage')));
    final fit = stageFit(box.size, const Size(400, 200));
    Offset screen(Offset p) => box.topLeft + fit.origin + p * fit.scale;
    final g = await tester.startGesture(screen(const Offset(200, 100)));
    await tester.pump();
    await g.moveTo(screen(const Offset(220, 100)));
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveTo(screen(const Offset(260, 120)));
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pumpAndSettle();
    final keys = storage.movies['m']!.tracks.single.contents.first.keys;
    expect(keys['x']!.length, greaterThanOrEqualTo(3));
    expect(keys['y'], isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
