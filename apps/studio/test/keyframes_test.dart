import 'dart:math' as math;

import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/domain/movie_edits.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

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
      contents: [
        MovieContent(
          id: 'c',
          name: 'Ink',
          kind: TrackKind.drawing,
          start: 5,
          length: 30,
          width: 100,
          height: 50,
        ),
      ],
    ),
  ],
);

void main() {
  test('values hold outside the keyframes and ease between them', () {
    const keys = [
      Keyframe(10, 0),
      Keyframe(20, 100, easing: KeyEasing.easeIn),
      Keyframe(30, 0),
    ];
    expect(
      [keyValue(keys, 0), keyValue(keys, 15), keyValue(keys, 40)],
      [0, 50, 0],
    );
    final eased = keyValue(keys, 25)!;
    expect(eased, greaterThan(50), reason: 'easing in leaves 100 slowly');
    expect(KeyEasing.easeInOut.apply(.5), closeTo(.5, 1e-9));
    expect(KeyEasing.easeOut.apply(.5), greaterThan(.5));
    expect(keyValue(const [], 3), isNull);

    final back = reverseKeys(keys, 0, 40);
    expect([for (final k in back) k.frame], [10, 20, 30]);
    expect(
      [for (final k in back) k.easing],
      [KeyEasing.easeOut, KeyEasing.linear, KeyEasing.linear],
    );
    expect(moveKey(keys, 20, 30).map((k) => k.frame), [10, 30]);
  });

  test('Move & Scale keyframes travel with their content: trimmed or '
      'split, it moves the same in the movie', () {
    final c = film().tracks.single.contents.single
        .withMoveKey(0, ContentTransform.identity.copyWith(x: .2))
        .withMoveKey(
          20,
          ContentTransform.identity.copyWith(
            x: .8,
            scaleX: 2,
            scaleY: 2,
            rotation: math.pi,
          ),
        );
    expect(c.transformAt(15).x, closeTo(.5, 1e-9), reason: 'halfway');
    expect(c.transformAt(0).x, .2, reason: 'held before');
    expect(c.transformAt(30).scaleY, 2, reason: 'scale keeps its ratio');
    expect(MovieContent.fromJson(c.toJson())!.toJson(), c.toJson());

    var m = film().updateContents({'c'}, (_) => c);
    final before = m.contentById('c')!.transformAt(17).x;
    m = m.trimStart('c', 10);
    expect(m.contentById('c')!.transformAt(17).x, closeTo(before, 1e-9));
    m = m.split('c', 20, 'd');
    expect(
      m.contentById('d')!.transformAt(22).x,
      closeTo(c.transformAt(22).x, 1e-9),
    );
  });

  testWidgets('controller: keyed placing, easing remembered, copy and paste, '
      'reverse, a keyframe drag is one undo step', (tester) async {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    MovieContent ink() => c.content('c')!;
    c.seek(10);
    c.edit(c.withContent('c', (x) => c.place(x, x.transform.copyWith(x: .3))));
    expect(ink().animated, isFalse, reason: 'not in keyframe mode');
    c.setKeyframing(true);
    c.edit(c.withContent('c', (x) => c.place(x, x.transform.copyWith(x: .9))));
    expect(ink().keyFrames, [5]);
    c.addKeyAtStart('c');
    expect(ink().keyFrames, [0, 5]);
    c.setEasing('c', 0, KeyEasing.easeOut);
    expect(c.lastEasing, KeyEasing.easeOut);
    c.seek(25);
    c.addMoveKey('c');
    expect(ink().keys['x']!.last.easing, KeyEasing.easeOut);

    final base = c.movie;
    c.dragKeys(base, 'c', 20, 22);
    c.dragKeys(base, 'c', 20, 25);
    c.commitPreview();
    expect(ink().keyFrames, [0, 5, 25]);
    c.undo();
    expect(ink().keyFrames, [0, 5, 20]);

    c.copyKeys('c');
    c.clearKeys('c');
    expect(ink().animated, isFalse);
    c.seek(15);
    c.pasteKeys('c');
    expect(ink().keyFrames, [10, 15, 30]);
    c.reverseMotion('c');
    expect(ink().keyFrames, [-1, 14, 19], reason: 'mirrored over 0–29');
  });

  testWidgets('keyframe mode: stage drags key the content at the playhead, '
      'diamonds show them, easing and lanes from a diamond', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('timeline-keyframes')));
    await tester.pumpAndSettle();
    final ruler = tester.getTopLeft(
      find.byKey(const ValueKey('timeline-ruler')),
    );
    final box = tester.getRect(find.byKey(const ValueKey('movie-stage')));
    final fit = stageFit(box.size, const Size(400, 200));
    Offset screen(Offset p) => box.topLeft + fit.origin + p * fit.scale;

    for (final (frame, x) in [(5, 0.0), (25, 100.0)]) {
      await tester.tapAt(ruler + Offset(frame * 6 + 3, 10));
      await tester.pump();
      final g = await tester.startGesture(screen(const Offset(200, 100)));
      await g.moveTo(screen(Offset(200 + x / 2, 100)));
      await g.moveTo(screen(Offset(200 + x, 100)));
      await g.up();
      await tester.pumpAndSettle();
    }
    final keys = storage.movies['m']!.contentById('c')!.keyFrames;
    expect(keys, [0, 20]);
    expect(find.byKey(const ValueKey('key-c-20')), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('key-c-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ease in and out'));
    await tester.pumpAndSettle();
    expect(
      storage.movies['m']!.contentById('c')!.keys['y']!.first.easing,
      KeyEasing.easeInOut,
    );
    await tester.longPress(find.byKey(const ValueKey('key-c-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show each parameter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lane-t-rotation')), findsOneWidget);
    expect(find.byKey(const ValueKey('key-c-20-scale')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
