import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/domain/movie_edits.dart';
import 'package:flutter_test/flutter_test.dart';

MovieContent clip(String id, int start, int length, {int? source}) =>
    MovieContent(
      id: id,
      name: id,
      kind: TrackKind.drawing,
      start: start,
      length: length,
      sourceLength: source,
    );

/// Track a: [a1 0–10) [a2 20–30) [a3 40–50); track b: [b1 5–15).
MovieDocument film() => MovieDocument(
  id: 'm',
  name: 'M',
  width: 100,
  height: 100,
  fps: 10,
  frames: 100,
  tracks: [
    MovieTrack(
      id: 'a',
      name: 'A',
      kind: TrackKind.drawing,
      contents: [clip('a1', 0, 10), clip('a2', 20, 10), clip('a3', 40, 10)],
    ),
    MovieTrack(
      id: 'b',
      name: 'B',
      kind: TrackKind.drawing,
      contents: [clip('b1', 5, 10, source: 12)],
    ),
  ],
);

List<(String, int, int)> spans(MovieDocument m, String track) => [
  for (final c in m.tracks.firstWhere((t) => t.id == track).contents)
    (c.id, c.start, c.end),
];

void main() {
  test('moving keeps contents apart, on the movie and on its tracks', () {
    final m = film();
    expect(spans(m.moveContents({'a2'}, 5)!, 'a'), [
      ('a1', 0, 10),
      ('a2', 25, 35),
      ('a3', 40, 50),
    ]);
    expect(m.moveContents({'a2'}, 15), isNull, reason: 'onto a3');
    expect(m.moveContents({'a1'}, -1), isNull, reason: 'before the start');
    final up = m.moveContents({'b1'}, 25, rows: -1)!;
    expect(spans(up, 'a')[2], ('b1', 30, 40), reason: 'fits between a2, a3');
    expect(spans(up, 'b'), isEmpty);
    expect(m.moveContents({'b1'}, 26, rows: -1), isNull, reason: 'onto a3');
    final moved = m.moveContents({'b1'}, -5, rows: -1);
    expect(moved, isNull, reason: 'a1 is at 0–10');
    final both = m.moveContents({'a2', 'a3'}, 10)!;
    expect(spans(both, 'a').last, ('a3', 50, 60));
    expect(m.moveContents({'a1'}, 0, rows: 2), isNull, reason: 'no track');
  });

  test('trimming stops at neighbours and the source; Free Trim pushes and '
      'pulls what follows', () {
    final m = film();
    expect(spans(m.trimEnd('a1', 30), 'a').first, ('a1', 0, 20));
    expect(spans(m.trimEnd('b1', 40), 'b').single, (
      'b1',
      5,
      17,
    ), reason: '12 source frames');
    final pushed = m.trimEnd('a2', 35, ripple: true);
    expect(spans(pushed, 'a'), [('a1', 0, 10), ('a2', 20, 35), ('a3', 45, 55)]);
    final pulled = m.trimEnd('a2', 25, ripple: true);
    expect(spans(pulled, 'a').last, ('a3', 35, 45));
    final front = m.trimStart('a2', 25);
    final a2 = front.contentById('a2')!;
    expect((a2.start, a2.end, a2.sourceIn), (25, 30, 5));
    expect(
      front.trimStart('a2', 0).contentById('a2')!.start,
      20,
      reason: 'not before its first source frame',
    );
  });

  test('split, fill, duplicate after, close gaps, reverse, retime', () {
    final m = film();
    final cut = m.split('a2', 24, 'a2b');
    final right = cut.contentById('a2b')!;
    expect((right.start, right.end, right.sourceIn), (24, 30, 4));
    expect(cut.contentById('a2')!.end, 24);
    expect(m.split('a2', 20, 'x'), same(m), reason: 'not inside');

    expect(spans(m.fill('a2'), 'a')[1], ('a2', 20, 40));
    expect(spans(m.fill('a3'), 'a').last, ('a3', 40, 100));

    expect(spans(m.duplicateAfter('a1', 'a1b'), 'a'), [
      ('a1', 0, 10),
      ('a1b', 10, 20),
      ('a2', 30, 40),
      ('a3', 50, 60),
    ]);
    expect(spans(m.closeGaps('a'), 'a'), [
      ('a1', 0, 10),
      ('a2', 10, 20),
      ('a3', 20, 30),
    ]);
    expect(spans(m.reverseContents({'a1', 'a2', 'a3'}), 'a'), [
      ('a3', 0, 10),
      ('a2', 20, 30),
      ('a1', 40, 50),
    ]);
    expect(spans(m.retime({'a1', 'a2'}, 5), 'a'), [
      ('a1', 0, 15),
      ('a2', 20, 35),
      ('a3', 40, 50),
    ]);
  });

  test('paste lands where asked or further along; tracks copy, move and '
      'group', () {
    final m = film();
    var n = 0;
    final (pasted, from) = m.paste(m.clip({'a1', 'b1'}), 60, () => 'p${n++}');
    expect(spans(pasted, 'a').last, ('p0', 60, 70));
    expect(spans(pasted, 'b').last, ('p1', 65, 75));
    expect(from, {'p0': 'a1', 'p1': 'b1'});
    final (again, _) = m.paste(m.clip({'a1'}), 18, () => 'q');
    expect(spans(again, 'a')[2], ('q', 30, 40), reason: 'a2 was in the way');

    final (twin, copies) = m.duplicateTrack('b', 'B2', () => 'n${n++}');
    expect([for (final t in twin.tracks) t.name], ['A', 'B2', 'B']);
    expect(copies.values, ['b1']);
    expect(
      [for (final t in m.moveTrack('b', up: true).tracks) t.id],
      ['b', 'a'],
    );
    final grouped = m.groupTracks({
      'a',
      'b',
    }, const TrackGroup(id: 'g', name: 'G'));
    expect([for (final t in grouped.tracks) t.group], ['g', 'g']);
    final hidden = grouped.updateGroup('g', (g) => g.copyWith(hidden: true));
    expect(hidden.trackShows(hidden.tracks.first), isFalse);
    expect(
      MovieDocument.fromJson(hidden.toJson()).groups.single.hidden,
      isTrue,
    );
    expect(hidden.ungroup('g').tracks.every((t) => t.group == null), isTrue);
  });
}
