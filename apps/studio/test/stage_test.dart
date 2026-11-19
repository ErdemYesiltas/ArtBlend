import 'dart:math' as math;

import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

const stage = Size(400, 200);

Matcher near(Offset o) =>
    isA<Offset>().having((p) => (p - o).distance, 'distance', lessThan(1e-6));

MovieDocument film() => MovieDocument(
  id: 'm',
  name: 'Film',
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
  test('a content frame maps its pixels to the stage and back, flipped and '
      'turned about its anchor; moving the anchor moves nothing', () {
    const t = ContentTransform(
      x: .25,
      y: .5,
      scaleX: 2,
      rotation: math.pi / 2,
      flipX: true,
      anchorX: 0,
      anchorY: 0,
    );
    final f = ContentFrame(t, const Size(100, 50), stage);
    expect(f.toStage(Offset.zero), near(const Offset(100, 100)));
    // x flipped and doubled: (10, 0) → (-20, 0), turned 90° → (0, -20).
    expect(f.toStage(const Offset(10, 0)), near(const Offset(100, 80)));
    expect(
      f.toLocal(f.toStage(const Offset(37, 21))),
      near(const Offset(37, 21)),
    );
    expect(f.contains(f.toStage(const Offset(50, 25))), isTrue);
    expect(f.contains(f.toStage(const Offset(150, 25))), isFalse);
    final moved = ContentFrame(
      f.withAnchor(const Offset(50, 25)),
      f.size,
      stage,
    );
    for (final p in [Offset.zero, const Offset(100, 50)]) {
      expect(moved.toStage(p), near(f.toStage(p)));
    }
    expect((moved.transform.anchorX, moved.transform.anchorY), (.5, .5));
  });

  test('dragging moves, turns, sizes, stretches and re-anchors; snapping '
      'keeps to the grid, 15° and 5% steps', () {
    final f = ContentFrame(
      ContentTransform.identity,
      const Size(100, 50),
      stage,
    );
    final moved = dragTransform(
      f,
      StageHandle.body,
      const Offset(200, 100),
      const Offset(219, 100),
      snap: true,
    );
    expect(moved.x, closeTo(.5 + 1 / 24, 1e-9), reason: '19 px → 16.7 px');
    final turned = dragTransform(
      f,
      StageHandle.rotate,
      const Offset(200, 50),
      const Offset(260, 90),
      snap: true,
    );
    final steps = turned.rotation / (math.pi / 12);
    expect(steps, closeTo(steps.roundToDouble(), 1e-9));
    expect(turned.rotation, isNot(0));
    final bigger = dragTransform(
      f,
      StageHandle.bottomRight,
      const Offset(250, 125),
      const Offset(300, 150),
    );
    expect((bigger.scaleX, bigger.scaleY), (2, 2));
    final wider = dragTransform(
      f,
      StageHandle.right,
      const Offset(250, 100),
      const Offset(300, 140),
    );
    expect((wider.scaleX, wider.scaleY), (2, 1));
    final anchored = dragTransform(
      f,
      StageHandle.anchor,
      const Offset(200, 100),
      const Offset(152, 77),
      snap: true,
    );
    expect((anchored.anchorX, anchored.anchorY), (0, 0));
    expect((anchored.x, anchored.y), (.375, .375), reason: 'nothing moves');
  });

  testWidgets('a drag on the stage is one undo step; choose, flip, reset, '
      'fullscreen', (tester) async {
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
    final box = tester.getRect(find.byKey(const ValueKey('movie-stage')));
    final fit = stageFit(box.size, stage);
    Offset screen(Offset p) => box.topLeft + fit.origin + p * fit.scale;

    final gesture = await tester.startGesture(screen(const Offset(200, 100)));
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(screen(Offset(200 + i * 10, 100)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    MovieContent saved() => storage.movies['m']!.tracks.single.contents.single;
    expect(saved().transform.x, closeTo(.625, 1e-6));
    expect(find.byKey(const ValueKey('compose-done')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compose-flip-h')));
    await tester.pump();
    expect(saved().transform.flipX, isTrue);
    await tester.tap(find.byKey(const ValueKey('stage-undo')));
    await tester.pump();
    expect(saved().transform.flipX, isFalse);
    await tester.tap(find.byKey(const ValueKey('stage-undo')));
    await tester.pump();
    expect(saved().transform.x, .5, reason: 'the whole drag at once');

    await tester.tap(find.byKey(const ValueKey('stage-redo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-reset')));
    await tester.pump();
    expect(saved().transform.x, .5);

    await tester.tap(find.byKey(const ValueKey('compose-done')));
    await tester.pump();
    expect(find.byKey(const ValueKey('compose-done')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stage-fullscreen')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('fullscreen-preview')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(600, 450));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fullscreen-preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('preview edits become one undo step when committed', () {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    for (final x in [.6, .7, .8]) {
      c.preview(
        c.withContent(
          'c',
          (content) =>
              content.copyWith(transform: content.transform.copyWith(x: x)),
        ),
      );
    }
    c.commitPreview();
    expect(c.content('c')!.transform.x, .8);
    c.undo();
    expect(c.content('c')!.transform.x, .5);
    expect(c.canUndo, isFalse);
    expect(c.shownAt(5).single.id, 'c');
    expect(c.shownAt(25), isEmpty);
  });
}
