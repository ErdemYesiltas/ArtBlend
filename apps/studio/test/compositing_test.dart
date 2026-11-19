import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/stage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

/// B covers stage x 0–240, A (on the track above) 160–400.
MovieDocument film({
  ContentMask mask = ContentMask.none,
  bool invert = false,
  double groupOpacity = 1,
}) => MovieDocument(
  id: 'm',
  name: 'M',
  width: 400,
  height: 200,
  fps: 10,
  frames: 10,
  groups: [TrackGroup(id: 'g', name: 'G', opacity: groupOpacity)],
  tracks: [
    MovieTrack(
      id: 'a',
      name: 'A',
      kind: TrackKind.drawing,
      group: 'g',
      contents: [
        MovieContent(
          id: 'A',
          name: '',
          kind: TrackKind.flipbook,
          start: 0,
          length: 10,
          width: 240,
          height: 200,
          transform: const ContentTransform(x: .7),
          mask: mask,
          maskInvert: invert,
        ),
      ],
    ),
    MovieTrack(
      id: 'b',
      name: 'B',
      kind: TrackKind.drawing,
      group: 'g',
      contents: [
        MovieContent(
          id: 'B',
          name: '',
          kind: TrackKind.drawing,
          start: 0,
          length: 10,
          width: 240,
          height: 200,
          transform: const ContentTransform(x: .3),
        ),
      ],
    ),
  ],
);

Future<List<int>> shades(WidgetTester tester, MovieDocument movie) async {
  final c = MovieController(storage: MemoryStorage(), movie: movie);
  addTearDown(c.dispose);
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 440,
          height: 240,
          child: StageView(controller: c, interactive: false),
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final data = (await tester.runAsync(image.toByteData))!.buffer.asUint8List();
  final fit = stageFit(const Size(440, 240), const Size(400, 200));
  int green(double x) {
    final p = fit.origin + Offset(x, 100) * fit.scale;
    return data[(p.dy.round() * image.width + p.dx.round()) * 4 + 1];
  }

  // Green drops under the purple and teal tints; white shows 255.
  return [green(100), green(200), green(300)];
}

void main() {
  testWidgets('masks act on the content beneath: clip, alpha, luminance, '
      'inverted; a group\'s opacity', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool tinted(int g) => g < 254;
    final plain = await shades(tester, film());
    expect(plain.map(tinted), [true, true, true]);
    final alpha = await shades(tester, film(mask: ContentMask.alpha));
    expect(alpha.map(tinted), [false, true, false], reason: 'B inside A only');
    final inverted = await shades(
      tester,
      film(mask: ContentMask.alpha, invert: true),
    );
    expect(inverted[0], plain[0], reason: 'B outside A untouched');
    expect(inverted[1], greaterThan(plain[0]), reason: 'B cut back inside A');
    expect(tinted(inverted[2]), isFalse);
    final clip = await shades(tester, film(mask: ContentMask.clip));
    expect(clip.map(tinted), [true, true, false], reason: 'A only over B');
    expect(clip[1], lessThan(plain[0]), reason: 'A over B in the overlap');
    final luma = await shades(tester, film(mask: ContentMask.luma));
    expect(luma[0], 255, reason: 'nothing of B outside A');
    final gone = await shades(tester, film(groupOpacity: 0));
    expect(gone, [255, 255, 255]);
  });

  test('look and group settings are kept', () {
    final m = film(mask: ContentMask.luma, invert: true).copyWith(
      groups: [
        const TrackGroup(
          id: 'g',
          name: 'G',
          blend: LayerBlend.multiply,
          passthrough: true,
          opacity: .5,
        ),
      ],
    );
    final back = MovieDocument.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
    final a = back.tracks.first.contents.single;
    expect((a.mask, a.maskInvert), (ContentMask.luma, true));
    expect(back.groups.single.passthrough, isTrue);
  });

  test('a Flipbook becomes drawings, one a frame as long as it showed, and '
      'drawings become a Flipbook again', () {
    final doc = ArtDocument(
      id: 'd',
      name: 'D',
      dimensions: const CanvasSize(100, 100),
      layers: [for (var i = 0; i < 3; i++) ArtLayer(id: 'p$i', name: 'P$i')],
      activeLayerId: 'p0',
      backgroundHidden: true,
      animation: const AnimationSettings(holds: {'p1': 2}),
    );
    final c = MovieController(
      storage: MemoryStorage(),
      movie: film().copyWith(
        frames: 20,
        tracks: [
          MovieTrack(
            id: 't',
            name: 'T',
            kind: TrackKind.flipbook,
            contents: [
              MovieContent(
                id: 'f',
                name: 'F',
                kind: TrackKind.flipbook,
                start: 2,
                length: 5,
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(c.dispose);
    c.drawings['f'] = doc;
    c.flipbookToDrawings('f', (n) => 'Frame $n');
    final pieces = c.movie.tracks.single.contents;
    expect(
      [for (final p in pieces) (p.start, p.length)],
      [(2, 1), (3, 3), (6, 1)],
    );
    expect(pieces.every((p) => p.kind == TrackKind.drawing), isTrue);
    expect(c.drawings[pieces[1].id]!.layers.single.id, 'p1');

    expect(
      c.drawingsToFlipbook({for (final p in pieces) p.id}, 'Back'),
      isTrue,
    );
    final back = c.movie.tracks.single.contents.single;
    expect((back.kind, back.start, back.length), (TrackKind.flipbook, 2, 5));
    final flip = c.drawings[back.id]!;
    expect(flip.pages, hasLength(3));
    expect(flip.animation!.hold(ArtDocument.frameId(flip.pages[1])), 2);
    c.undo();
    expect(c.movie.tracks.single.contents, hasLength(3));
    expect(ui.Size.zero, ui.Size.zero);
  });
}
