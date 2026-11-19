import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/drawing_storage.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/main.dart';
import 'package:atelier_studio/movie/drawing_frames.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

const size = TiledRaster.size;

ArtDocument painted(String id, int shade) {
  final tile = RasterAsset(
    id: newId(),
    png: encodeRgbaPng(
      Uint8List(size * size * 4)..fillRange(0, size * size * 4, shade),
      size,
      size,
    ),
    width: size,
    height: size,
  );
  final layer = ArtLayer(
    id: 'l-$id',
    name: 'Ink',
    raster: TiledRaster(TileGrid(const CanvasSize(256, 256)), {0: tile}),
  );
  return ArtDocument(
    id: id,
    name: 'Ink',
    dimensions: const CanvasSize(256, 256),
    layers: [layer],
    activeLayerId: layer.id,
  );
}

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
      name: 'Flipbook',
      kind: TrackKind.flipbook,
      contents: [
        MovieContent(
          id: 'f',
          name: 'Flipbook',
          kind: TrackKind.flipbook,
          start: 5,
          length: 30,
        ),
      ],
    ),
  ],
);

void main() {
  test('a Flipbook content shows its frames as they play: holds counted, '
      'pinned background left out, looping over its length', () {
    final doc = ArtDocument(
      id: 'd',
      name: 'D',
      dimensions: const CanvasSize(100, 100),
      layers: [for (var i = 0; i < 4; i++) ArtLayer(id: 'p$i', name: 'P$i')],
      activeLayerId: 'p0',
      animation: const AnimationSettings(
        holds: {'p2': 1},
        background: 'p0',
        mode: PlaybackMode.pingPong,
      ),
    );
    final content = film().tracks.single.contents.single;
    int? page(int frame) => drawingAt(content, doc, frame)?.page;
    expect(
      [for (var f = 4; f < 12; f++) page(f)],
      [
        null, // before it starts
        1, 2, 2, 3, // one pass, forward only
        1, 2, 2, // and again
      ],
    );
    final shown = drawingAt(content, doc, 6)!.view;
    expect([for (final l in shown.layers) l.id], ['p0', 'p2']);
    final still = painted('s', 9);
    expect(drawingAt(content, still, 20)!.page, -1, reason: 'whole drawing');
  });

  test('drawings live in the movie file with their tiles; a save without '
      'them keeps them; compaction keeps their tiles', () async {
    final dir = await Directory.systemTemp.createTemp('movie-drawings');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStudioStorage(dir);
    final movie = film();
    await storage.saveMovie(movie, drawings: {'f': painted('d1', 120)});
    await storage.saveMovie(movie.copyWith(name: 'Renamed'));
    final fresh = LocalStudioStorage(dir);
    expect((await fresh.listMovies()).movies.single.name, 'Renamed');
    await fresh.compact();
    final back = (await fresh.loadMovieDrawings('m'))['f']!;
    expect(back.id, 'd1');
    final png = back.layers.single.raster!.tiles[0]!.png;
    expect(png, painted('x', 120).layers.single.raster!.tiles[0]!.png);
    await fresh.deleteMovie('m');
    expect(await LocalStudioStorage(dir).loadMovieDrawings('m'), isEmpty);
  });

  test('the editor on a movie drawing saves only that drawing and shares '
      'the library', () async {
    final base = MemoryStorage()..library = {'version': 1};
    final saved = <ArtDocument>[];
    final drawing = painted('d', 1);
    final storage = DrawingStorage(base, drawing, saved.add);
    expect(await storage.loadDocument(), same(drawing));
    await storage.saveDocument(painted('other', 2));
    await storage.saveDocument(drawing.copyWith(name: 'Edited'));
    expect([for (final d in saved) d.name], ['Edited']);
    expect(await storage.loadLibrary(), {'version': 1});
    await storage.saveLibrary({'version': 2});
    expect(base.library, {'version': 2});
    expect((await storage.listDocuments()).documents, isEmpty);
  });

  testWidgets('a double tap on a content opens a blank Flipbook drawing to '
      'draw in; what is drawn is saved and shows on the stage', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    ArtDocument? opened;
    late void Function(ArtDocument) save;
    void Function(int frame)? scrub;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MovieScreen(
          storage: storage,
          movie: film(),
          askName: (name) async => name,
          editDrawing: (context, drawing, onSave, {onScrub}) async {
            scrub = onScrub;
            opened = drawing;
            save = onSave;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('movie-stage')));
    final fit = stageFit(box.size, const Size(400, 200));
    final middle =
        box.topLeft + fit.origin + const Offset(200, 100) * fit.scale;
    // Frame 10: the content is on screen.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('timeline-ruler'))) +
          const Offset(63, 10),
    );
    await tester.pump();
    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(middle);
    await tester.pumpAndSettle();
    expect(opened, isNotNull);
    expect(opened!.animating, isTrue, reason: 'a Flipbook draws frames');
    expect(opened!.backgroundHidden, isTrue);
    expect((opened!.dimensions.width, opened!.dimensions.height), (400, 200));
    expect(storage.movieDrawings['m']!['f']!.id, opened!.id);

    final drawn = painted(
      opened!.id,
      200,
    ).copyWith(animation: opened!.animation);
    save(drawn);
    await tester.pump();
    expect(storage.movieDrawings['m']!['f'], same(drawn));
    // Showing the Flipbook's frame in its editor brings the movie there.
    final two = drawn.copyWith(
      layers: [
        ...drawn.layers,
        ArtLayer(id: 'second', name: '2'),
      ],
    );
    save(two);
    scrub!(1);
    await tester.pump();
    expect(find.text('0:00:06 / 0:04:00'), findsOneWidget, reason: 'frame 6');
    final content = storage.movies['m']!.tracks.single.contents.single;
    expect((content.width, content.height), (256, 256), reason: 'its canvas');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drawing frames render once and come back as pictures', (
    tester,
  ) async {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    final content = c.movie.tracks.single.contents.single;
    final doc = painted('d', 255);
    ui.Image? image;
    await tester.runAsync(() async {
      expect(c.frames.image(content, doc, 10), isNull, reason: 'rendering');
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        image = c.frames.image(content, doc, 10);
        if (image != null) break;
      }
    });
    expect((image!.width, image!.height), (256, 256));
    expect(c.frames.image(content, doc, 4), isNull, reason: 'not started');
  });

  testWidgets('from the Theater: a movie, its Flipbook opened in the full '
      'editor, back to the movie', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    await storage.saveMovie(film());
    final c = StudioController(storage: storage);
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.setPanel(EditorPanel.gallery);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theater-m')));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('content-f'));
    await tester.tap(content);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compose-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-exit')), findsOneWidget);
    expect(find.byKey(const ValueKey('animation-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('frame-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movie-screen')), findsOneWidget);
    expect(storage.movieDrawings['m']!['f']!.pages, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
