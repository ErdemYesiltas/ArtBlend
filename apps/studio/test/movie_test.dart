import 'dart:io';

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/gallery.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

void main() {
  test('a movie keeps its stage, timing and tracks; Flipbook starts with a '
      'Flipbook track, Blank with none', () {
    final m = MovieDocument.create(
      name: 'Walk',
      width: 1920,
      height: 1080,
      fps: 24,
      seconds: 2.5,
      background: 0xff102030,
      flipbookName: 'Flipbook',
    );
    expect(m.frames, 60);
    expect(m.tracks.single.kind, TrackKind.flipbook);
    expect(
      MovieDocument.create(
        name: 'B',
        width: 100,
        height: 100,
        start: MovieStart.blank,
      ).tracks,
      isEmpty,
    );
    final faster = m.copyWith(fps: 48);
    expect((faster.frames, faster.seconds), (120, 2.5), reason: 'same length');
    expect(m.copyWith(fps: 500).fps, MovieDocument.maxFps);
    expect(m.copyWith(offstage: 3).offstage, 1);

    final back = MovieDocument.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
    final damaged = MovieDocument.fromJson({
      ...m.toJson(),
      'fps': 'x',
      'tracks': [
        'junk',
        {'id': 't', 'kind': 'nope'},
      ],
    });
    expect(damaged.fps, 24);
    expect(damaged.tracks.single.kind, TrackKind.drawing);
    expect(
      () => MovieDocument.fromJson({...m.toJson(), 'width': 2}),
      throwsFormatException,
    );
    expect(() => MovieDocument.fromJson({'id': 'x'}), throwsFormatException);
  });

  test('stage sizes follow the aspect, short side and even numbers', () {
    expect(movieSize(MovieAspect.wide, 1080), (1920, 1080));
    expect(movieSize(MovieAspect.cinema, 1080), (2520, 1080));
    expect(movieSize(MovieAspect.portrait, 1080), (1080, 1920));
    expect(movieSize(MovieAspect.square, 720), (720, 720));
    expect(movieSize(MovieAspect.screen, 1000, screenRatio: 1.6001), (
      1600,
      1000,
    ));
  });

  test('movies are saved, listed newest first and deleted on disk; '
      'compaction keeps tiles a movie\'s drawings use', () async {
    final dir = await Directory.systemTemp.createTemp('movies');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStudioStorage(dir);
    final a = MovieDocument.create(name: 'A', width: 640, height: 360);
    final b = MovieDocument.create(name: 'B', width: 640, height: 360);
    await storage.saveMovie(a);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await storage.saveMovie(b);
    await storage.saveTheater(GalleryLayout(order: [a.id]).toJson());
    final fresh = LocalStudioStorage(dir);
    expect(
      [for (final m in (await fresh.listMovies()).movies) m.name],
      ['B', 'A'],
    );
    expect(GalleryLayout.fromJson(await fresh.loadTheater()).order, [a.id]);

    final tiles = Directory('${dir.path}/tiles')..createSync();
    for (final name in ['kept', 'loose']) {
      File('${tiles.path}/$name.png').writeAsBytesSync([1]);
    }
    await fresh.movieFile(a.id).write({
      ...a.toJson(),
      'contents': [
        {
          'drawing': {
            'layers': [
              {
                'tiles': [
                  {'sha256': 'kept'},
                ],
              },
            ],
          },
        },
      ],
    });
    await fresh.compact();
    expect(File('${tiles.path}/kept.png').existsSync(), isTrue);
    expect(File('${tiles.path}/loose.png').existsSync(), isFalse);

    await fresh.deleteMovie(b.id);
    expect([for (final m in (await fresh.listMovies()).movies) m.id], [a.id]);
    File('${dir.path}/movies/broken.movie').writeAsStringSync('{');
    expect((await fresh.listMovies()).unreadable, ['broken.movie']);
  });

  testWidgets('the Theater makes, opens, files, copies and deletes movies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    final c = StudioController(storage: storage);
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.setPanel(EditorPanel.gallery);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theater-empty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theater-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('movie-name')), 'Run');
    await tester.enterText(find.byKey(const ValueKey('movie-seconds')), '3');
    await tester.tap(find.byKey(const ValueKey('movie-settings-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movie-screen')), findsOneWidget);
    final run = storage.movies.values.single;
    expect((run.name, run.width, run.height), ('Run', 1920, 1080));
    expect((run.fps, run.frames), (24, 72));
    expect(run.tracks.single.kind, TrackKind.flipbook);

    // Settings change the saved movie.
    await tester.tap(find.byKey(const ValueKey('movie-settings-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movie-transparent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movie-settings-done')));
    await tester.pumpAndSettle();
    expect(storage.movies[run.id]!.transparent, isTrue);
    expect(storage.movies[run.id]!.frames, 72);

    await tester.tap(find.byKey(const ValueKey('movie-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('theater-${run.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('theater-menu-${run.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate').last);
    await tester.pumpAndSettle();
    expect(storage.movies, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('theater-select')));
    await tester.pumpAndSettle();
    for (final id in storage.movies.keys) {
      await tester.tap(find.byKey(ValueKey('theater-$id')));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theater-folder')));
    await tester.pumpAndSettle();
    final folder = GalleryLayout.fromJson(storage.theater).stacks.single;
    expect(folder.members.toSet(), storage.movies.keys.toSet());
    await tester.tap(find.byKey(ValueKey('theater-folder-${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('theater-menu-${run.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theater-delete-yes')));
    await tester.pumpAndSettle();
    expect(storage.movies.containsKey(run.id), isFalse);
    expect(
      GalleryLayout.fromJson(storage.theater).stacks.single.members,
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
