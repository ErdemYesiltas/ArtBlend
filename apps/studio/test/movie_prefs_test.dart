import 'dart:io';

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_prefs.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

ArtDocument painted() {
  const n = TiledRaster.size;
  final layer = ArtLayer(
    id: 'ink',
    name: 'Ink',
    raster: TiledRaster(TileGrid(const CanvasSize(100, 100)), {
      0: RasterAsset(
        id: newId(),
        png: encodeRgbaPng(Uint8List(n * n * 4)..fillRange(0, 400, 7), n, n),
        width: n,
        height: n,
      ),
    }),
  );
  return ArtDocument(
    id: 'd',
    name: 'D',
    dimensions: const CanvasSize(100, 100),
    layers: [layer],
    activeLayerId: 'ink',
  );
}

MovieDocument film([String name = 'Film']) => MovieDocument(
  id: 'm',
  name: name,
  width: 400,
  height: 200,
  fps: 10,
  frames: 20,
  tracks: [
    MovieTrack(
      id: 't',
      name: 'Ink',
      kind: TrackKind.drawing,
      contents: [
        MovieContent(
          id: 'c',
          name: 'Ink',
          kind: TrackKind.drawing,
          start: 0,
          length: 20,
          width: 100,
          height: 50,
        ),
      ],
    ),
  ],
);

void main() {
  test('recovery points: one at most every five minutes, restorable, their '
      'tiles kept by compaction, gone with the movie', () async {
    final dir = await Directory.systemTemp.createTemp('points');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStudioStorage(dir);
    await storage.saveMovie(film(), drawings: {'c': painted()});
    await storage.saveMovie(film('Renamed'), drawings: {});
    final points = await storage.moviePoints('m');
    expect(points, hasLength(1), reason: 'the second came too soon');
    await storage.compact();
    expect(await storage.restoreMoviePoint('m', points.single), isTrue);
    final fresh = LocalStudioStorage(dir);
    expect((await fresh.listMovies()).movies.single.name, 'Film');
    final back = (await fresh.loadMovieDrawings('m'))['c']!;
    expect(
      back.layers.single.raster!.tiles[0]!.png,
      painted().layers.single.raster!.tiles[0]!.png,
      reason: 'its tile survived compaction',
    );
    expect(await fresh.restoreMoviePoint('m', DateTime(2000)), isFalse);
    await fresh.deleteMovie('m');
    expect(await LocalStudioStorage(dir).moviePoints('m'), isEmpty);
  });

  test('preferences are kept, shortcuts too', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    final prefs = MoviePrefs(store);
    expect((prefs.undoButtons, prefs.undoDepth), (true, 100));
    prefs.update((p) {
      p.undoDepth = 9999;
      p.undoButtons = false;
      p.shortcuts[MovieAction.play] = const SingleActivator(
        LogicalKeyboardKey.keyP,
        shift: true,
      );
    });
    final again = MoviePrefs(store);
    expect((again.undoButtons, again.undoDepth), (false, MoviePrefs.maxDepth));
    expect(again.shortcuts[MovieAction.play]!.trigger, LogicalKeyboardKey.keyP);
    expect(again.shortcuts[MovieAction.play]!.shift, isTrue);
    expect(
      MoviePrefs.describe(again.shortcuts[MovieAction.play]!),
      contains('P'),
    );
  });

  testWidgets('a two-finger tap undoes, a remapped key plays, the stage '
      'buttons follow the preference', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    MoviePrefs(store).update(
      (p) => p.shortcuts[MovieAction.play] = const SingleActivator(
        LogicalKeyboardKey.keyP,
      ),
    );
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
          preferences: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-mode-pingPong')));
    await tester.tap(find.byKey(const ValueKey('content-c')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compose-flip-h')));
    await tester.pumpAndSettle();
    expect(
      storage.movies['m']!.tracks.single.contents.single.transform.flipX,
      isTrue,
    );

    final stage = tester.getCenter(find.byKey(const ValueKey('movie-stage')));
    final a = await tester.createGesture(pointer: 1);
    final b = await tester.createGesture(pointer: 2);
    await a.down(stage + const Offset(-200, 120));
    await b.down(stage + const Offset(-160, 120));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(
      storage.movies['m']!.tracks.single.contents.single.transform.flipX,
      isFalse,
      reason: 'undone',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0:00:02 / 0:02:00'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();

    expect(find.byKey(const ValueKey('stage-undo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('movie-prefs-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prefs-undo-buttons')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stage-undo')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
