import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/drawing/adjustments.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/live_filters.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

MovieContent ink({
  List<ContentFilter> filters = const [],
  Map<String, Keys> keys = const {},
}) => MovieContent(
  id: 'c',
  name: 'Ink',
  kind: TrackKind.drawing,
  start: 0,
  length: 40,
  width: 100,
  height: 50,
  filters: filters,
  keys: keys,
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
      contents: [ink()],
    ),
  ],
);

Future<ui.Image> image(int w, int h, void Function(ui.Canvas c) paint) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  return recorder.endRecording().toImage(w, h);
}

Future<List<int>> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return data.sublist(i, i + 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a setting stays constant until keyed; filters and warp grids '
      'survive saving; Distort corners and Warp nodes move the mesh', () {
    var keys = setKeyed(const {}, 'f.amount', 12, .3, keying: false);
    expect(keys['f.amount']!.single.frame, 0, reason: 'constant');
    keys = setKeyed(keys, 'f.amount', 12, .6, keying: false);
    expect(keys['f.amount']!.single.value, .6);
    keys = setKeyed(keys, 'f.amount', 12, .9, keying: true);
    expect(keys['f.amount']!.map((k) => k.frame), [0, 12]);

    const blur = ContentFilter(id: 'f', kind: FilterKind.gaussianBlur);
    final c = ink(
      filters: const [blur],
      keys: keys,
    ).copyWith(warpCols: 3, warpRows: 2);
    expect(c.filterValue(blur, blur.kind.params.single, 6), closeTo(.75, 1e-9));
    final back = MovieContent.fromJson(c.toJson())!;
    expect(back.toJson(), c.toJson());
    expect(
      (back.warpCols, back.filters.single.kind),
      (3, FilterKind.gaussianBlur),
    );

    const size = Size(100, 50);
    final distorted = {
      distortKey(1, 'x'): const [Keyframe(0, .2)],
    };
    expect(meshPoint(distorted, 0, size, 1, 0), const Offset(120, 0));
    expect(meshPoint(distorted, 0, size, .5, 0), const Offset(60, 0));
    expect(meshPoint(distorted, 0, size, 1, 1), const Offset(100, 50));
    final warped = {
      warpKey(1, 0, 'y'): const [Keyframe(0, .2)],
    };
    expect(
      meshPoint(warped, 0, size, .5, 0, cols: 3, rows: 2),
      const Offset(50, 10),
    );
    final quarter = meshPoint(warped, 0, size, .25, .5, cols: 3, rows: 2);
    expect(
      (quarter - const Offset(25, 27.5)).distance,
      lessThan(1e-9),
      reason: 'a quarter of the node\'s move',
    );
  });

  test('live filters run painting\'s shaders: hue turns red green, lens '
      'blur softens an edge, noise drifts over time', () async {
    final shaders = await AdjustmentShaders.load();
    final red = await image(
      32,
      32,
      (c) => c.drawColor(const Color(0xffff0000), BlendMode.src),
    );
    const hsb = ContentFilter(id: 'h', kind: FilterKind.hsb);
    final turned = filterImage(
      red,
      ink(
        filters: const [hsb],
        keys: {
          'h.hue': const [Keyframe(0, .5 + 1 / 3)],
        },
      ),
      0,
      10,
      shaders,
    )!;
    final p = await pixel(turned, 16, 16);
    expect(p[1], greaterThan(200));
    expect(p[0], lessThan(40));

    final edge = await image(64, 8, (c) {
      c.drawColor(const Color(0xff000000), BlendMode.src);
      c.drawRect(
        const Rect.fromLTWH(32, 0, 32, 8),
        Paint()..color = const Color(0xffffffff),
      );
    });
    const lens = ContentFilter(id: 'l', kind: FilterKind.lensBlur);
    final soft = filterImage(
      edge,
      ink(
        filters: const [lens],
        keys: {
          'l.radius': const [Keyframe(0, 1)],
        },
      ),
      0,
      10,
      shaders,
    )!;
    expect((await pixel(soft, 31, 4))[0], greaterThan(30), reason: 'dark side');
    expect((await pixel(soft, 32, 4))[0], lessThan(250), reason: 'light side');

    const noise = ContentFilter(id: 'n', kind: FilterKind.noise);
    final grey = await image(
      32,
      32,
      (c) => c.drawColor(const Color(0xff808080), BlendMode.src),
    );
    final drifting = ink(
      filters: const [noise],
      keys: {
        'n.travelX': const [Keyframe(0, 1)],
      },
    );
    final a = filterImage(grey, drifting, 0, 10, shaders)!;
    final b = filterImage(grey, drifting, 5, 10, shaders)!;
    final pa = (await a.toByteData())!.buffer.asUint8List();
    final pb = (await b.toByteData())!.buffer.asUint8List();
    expect(pa, isNot(pb));

    const opacity = ContentFilter(id: 'o', kind: FilterKind.opacity);
    expect(
      filterOpacity(
        ink(
          filters: const [opacity, opacity],
          keys: {
            'o.amount': const [Keyframe(0, .5)],
          },
        ),
        0,
      ),
      .25,
    );
  });

  test('a distorted content draws past its own box', () async {
    final source = await image(
      8,
      8,
      (c) => c.drawColor(const Color(0xff0000ff), BlendMode.src),
    );
    final content = ink(
      keys: {
        distortKey(1, 'x'): const [Keyframe(0, .5)],
        distortKey(2, 'x'): const [Keyframe(0, .5)],
      },
    );
    expect(content.meshed, isTrue);
    final out = await image(160, 50, (c) {
      drawMesh(c, source, content, 0, const Size(100, 50), Paint());
    });
    expect((await pixel(out, 140, 25))[2], greaterThan(200));
    expect((await pixel(out, 155, 25))[3], 0);
  });

  testWidgets('the stage adds filters, pulls a Distort corner and makes a '
      'Warp grid', (tester) async {
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
    MovieContent saved() => storage.movies['m']!.tracks.single.contents.single;
    await tester.tap(find.byKey(const ValueKey('content-c')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compose-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaussian blur').last);
    await tester.pumpAndSettle();
    expect(saved().filters.single.kind, FilterKind.gaussianBlur);
    await tester.tap(
      find.byKey(ValueKey('filter-remove-${saved().filters.single.id}')),
    );
    await tester.pumpAndSettle();
    expect(saved().filters, isEmpty);

    await tester.tap(find.byKey(const ValueKey('compose-distort')));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('movie-stage')));
    final fit = stageFit(box.size, const Size(400, 200));
    Offset screen(Offset p) => box.topLeft + fit.origin + p * fit.scale;
    // The 100×50 content sits in the middle: top left corner at 150, 75.
    final g = await tester.startGesture(screen(const Offset(150, 75)));
    await g.moveTo(screen(const Offset(140, 70)));
    await g.moveTo(screen(const Offset(130, 65)));
    await g.up();
    await tester.pumpAndSettle();
    final keys = saved().keys;
    expect(keyedValue(keys, distortKey(0, 'x'), 0), closeTo(-.2, .02));
    expect(keyedValue(keys, distortKey(0, 'y'), 0), closeTo(-.2, .02));

    await tester.tap(find.byKey(const ValueKey('compose-warp')));
    await tester.pumpAndSettle();
    expect((saved().warpCols, saved().warpRows), (3, 3));
    await tester.tap(find.byKey(const ValueKey('warp-add-column')));
    await tester.pumpAndSettle();
    expect(saved().warpCols, 4);
    await tester.tap(find.byKey(const ValueKey('mesh-straighten')));
    await tester.pumpAndSettle();
    expect(saved().keys.keys.where((k) => k.startsWith('warp.')), isEmpty);
    expect(
      meshHandles(saved(), const Size(400, 200), 0, ComposeMode.warp, (p) => p),
      hasLength(12),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('the controller removes a filter with its keyframes', () {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    c.addFilter('c', FilterKind.noise);
    final f = c.content('c')!.filters.single;
    c.setKeyedValues('c', {f.key('amount'): .9});
    expect(c.content('c')!.keys.containsKey(f.key('amount')), isTrue);
    c.removeFilter('c', f.id);
    expect(c.content('c')!.keys, isEmpty);
    expect(Uint8List(0), isEmpty);
  });
}
