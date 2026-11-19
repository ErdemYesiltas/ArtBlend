import 'dart:math' as math;

import 'movie.dart';

/// Contents copied from the timeline: each with the track it was on and
/// its start, to land the same way elsewhere.
typedef MovieClip = List<({int row, MovieContent content})>;

/// Dreams' content and track editing on a movie. Every edit returns a new
/// movie (or the same one when nothing could change) and never lets two
/// contents on a track overlap.
extension MovieEdits on MovieDocument {
  int trackIndexOf(String contentId) =>
      tracks.indexWhere((t) => t.contents.any((c) => c.id == contentId));

  MovieContent? contentById(String id) =>
      tracks.expand((t) => t.contents).where((c) => c.id == id).firstOrNull;

  MovieDocument _withTrack(int index, MovieTrack track) =>
      copyWith(tracks: [...tracks]..[index] = track);

  MovieDocument _withContent(MovieContent next) {
    final i = trackIndexOf(next.id);
    if (i < 0) return this;
    return _withTrack(
      i,
      tracks[i].copyWith(
        contents: [
          for (final c in tracks[i].contents) c.id == next.id ? next : c,
        ],
      ),
    );
  }

  static bool _clear(List<MovieContent> contents) {
    final sorted = [...contents]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].start < sorted[i - 1].end) return false;
    }
    return true;
  }

  /// [ids] moved [delta] frames later (earlier when negative) and [rows]
  /// tracks down; null when they would overlap something, start before
  /// the movie or leave the tracks.
  MovieDocument? moveContents(Set<String> ids, int delta, {int rows = 0}) {
    final moving = <(int, MovieContent)>[
      for (final (i, t) in tracks.indexed)
        for (final c in t.contents)
          if (ids.contains(c.id)) (i, c),
    ];
    if (moving.isEmpty) return this;
    final next = [
      for (final t in tracks) [...t.contents.where((c) => !ids.contains(c.id))],
    ];
    for (final (i, c) in moving) {
      final to = i + rows, start = c.start + delta;
      if (to < 0 || to >= tracks.length || start < 0) return null;
      next[to].add(c.copyWith(start: start));
    }
    if (!next.every(_clear)) return null;
    return copyWith(
      tracks: [
        for (final (i, t) in tracks.indexed) t.copyWith(contents: next[i]),
      ],
    );
  }

  /// [ids] moved [delta] frames and onto a new [track] put at [index]
  /// in the track list (dropped between two tracks); null when they would
  /// start before the movie.
  MovieDocument? moveToNewTrack(
    Set<String> ids,
    int delta,
    int index,
    MovieTrack track,
  ) {
    final moving = [
      for (final t in tracks)
        for (final c in t.contents)
          if (ids.contains(c.id)) c,
    ];
    if (moving.isEmpty || moving.any((c) => c.start + delta < 0)) return null;
    final placed = [for (final c in moving) c.copyWith(start: c.start + delta)];
    if (!_clear(placed)) return null;
    final rest = [
      for (final t in tracks)
        t.copyWith(contents: [...t.contents.where((c) => !ids.contains(c.id))]),
    ];
    return copyWith(
      tracks: [...rest]
        ..insert(index.clamp(0, rest.length), track.copyWith(contents: placed)),
    );
  }

  ({MovieContent? before, MovieContent? after}) _neighbours(String id) {
    final track = tracks[trackIndexOf(id)];
    final at = track.contents.indexWhere((c) => c.id == id);
    return (
      before: at > 0 ? track.contents[at - 1] : null,
      after: at + 1 < track.contents.length ? track.contents[at + 1] : null,
    );
  }

  /// Content [id] starts at [start], its end staying: more or less of its
  /// source shows. It stops at the content before it, the movie's start and
  /// its source's first frame.
  MovieDocument trimStart(String id, int start) {
    final c = contentById(id);
    if (c == null) return this;
    final floor = math.max(
      _neighbours(id).before?.end ?? 0,
      c.start - c.sourceIn,
    );
    final s = start.clamp(math.max(0, floor), c.end - 1).toInt();
    final d = s - c.start;
    return _withContent(
      c.copyWith(
        start: s,
        length: c.length - d,
        sourceIn: c.sourceIn + d,
        keys: c.shiftedKeys(-d),
      ),
    );
  }

  /// Content [id] ends at [end]. With [ripple] (Free Trim) the contents
  /// after it on its track move by as much (pushed or pulled); otherwise
  /// it stops at the next one. It never runs past its source.
  MovieDocument trimEnd(String id, int end, {bool ripple = false}) {
    final c = contentById(id);
    if (c == null) return this;
    var e = math.max(end, c.start + 1);
    if (c.sourceLength case final source?) {
      e = math.min(e, c.start + source - c.sourceIn);
    }
    final after = _neighbours(id).after;
    if (!ripple && after != null) e = math.min(e, after.start);
    final d = e - c.end;
    if (d == 0) return this;
    final i = trackIndexOf(id);
    return _withTrack(
      i,
      tracks[i].copyWith(
        contents: [
          for (final other in tracks[i].contents)
            if (other.id == id)
              other.copyWith(length: e - c.start)
            else if (ripple && other.start >= c.end)
              other.copyWith(start: other.start + d)
            else
              other,
        ],
      ),
    );
  }

  /// Content [id] cut in two at movie frame [frame]; the right part is
  /// [newId] and goes on from where the left one stops in the source.
  MovieDocument split(String id, int frame, String newId) {
    final c = contentById(id);
    if (c == null || frame <= c.start || frame >= c.end) return this;
    final i = trackIndexOf(id);
    return _withTrack(
      i,
      tracks[i].copyWith(
        contents: [
          for (final other in tracks[i].contents)
            if (other.id == id) ...[
              c.copyWith(length: frame - c.start),
              c.copyWith(
                id: newId,
                start: frame,
                length: c.end - frame,
                sourceIn: c.sourceIn + frame - c.start,
                keys: c.shiftedKeys(c.start - frame),
              ),
            ] else
              other,
        ],
      ),
    );
  }

  /// Content [id] lengthened to the next content on its track or the end
  /// of the movie (Fill duration).
  MovieDocument fill(String id) {
    final c = contentById(id);
    if (c == null) return this;
    return trimEnd(id, _neighbours(id).after?.start ?? math.max(frames, c.end));
  }

  /// A copy [newId] of content [id] right after it; what follows on its
  /// track moves along to make room.
  MovieDocument duplicateAfter(String id, String newId) {
    final c = contentById(id);
    if (c == null) return this;
    final i = trackIndexOf(id);
    return _withTrack(
      i,
      tracks[i].copyWith(
        contents: [
          for (final other in tracks[i].contents)
            other.start >= c.end
                ? other.copyWith(start: other.start + c.length)
                : other,
          c.copyWith(id: newId, start: c.end),
        ],
      ),
    );
  }

  /// Track [trackId]'s contents slid left until they touch (the first
  /// stays where it is).
  MovieDocument closeGaps(String trackId) {
    final i = tracks.indexWhere((t) => t.id == trackId);
    if (i < 0 || tracks[i].contents.isEmpty) return this;
    var at = tracks[i].contents.first.start;
    final packed = <MovieContent>[];
    for (final c in tracks[i].contents) {
      packed.add(c.copyWith(start: at));
      at += c.length;
    }
    return _withTrack(i, tracks[i].copyWith(contents: packed));
  }

  MovieDocument updateContents(
    Set<String> ids,
    MovieContent Function(MovieContent content) change,
  ) => copyWith(
    tracks: [
      for (final t in tracks)
        t.contents.any((c) => ids.contains(c.id))
            ? t.copyWith(
                contents: [
                  for (final c in t.contents)
                    ids.contains(c.id) ? change(c) : c,
                ],
              )
            : t,
    ],
  );

  MovieDocument deleteContents(Set<String> ids) => copyWith(
    tracks: [
      for (final t in tracks)
        t.copyWith(contents: [...t.contents.where((c) => !ids.contains(c.id))]),
    ],
  );

  /// [ids] in reverse time order on each track, over the time they span
  /// (gaps mirrored too); a track with something else inside that span is
  /// left as it is.
  MovieDocument reverseContents(Set<String> ids) => copyWith(
    tracks: [
      for (final t in tracks)
        () {
          final chosen = [...t.contents.where((c) => ids.contains(c.id))];
          if (chosen.length < 2) return t;
          final from = chosen.first.start, to = chosen.last.end;
          final inside = t.contents.any(
            (c) => !ids.contains(c.id) && c.end > from && c.start < to,
          );
          if (inside) return t;
          return t.copyWith(
            contents: [
              for (final c in t.contents)
                ids.contains(c.id) ? c.copyWith(start: from + to - c.end) : c,
            ],
          );
        }(),
    ],
  );

  /// [ids] each lengthened or shortened by [delta] frames at the end
  /// (retimed together), each stopping where trimming stops.
  MovieDocument retime(Set<String> ids, int delta) {
    var movie = this;
    final ordered = [
      for (final t in tracks)
        for (final c in t.contents.reversed)
          if (ids.contains(c.id)) c,
    ];
    for (final c in ordered) {
      movie = movie.trimEnd(c.id, c.end + delta);
    }
    return movie;
  }

  /// [ids] as a clip to paste.
  MovieClip clip(Set<String> ids) => [
    for (final (row, t) in tracks.indexed)
      for (final c in t.contents)
        if (ids.contains(c.id)) (row: row, content: c),
  ];

  /// [clip] pasted from frame [at] on the tracks it came from, each
  /// content at the first free time from where it should land (further
  /// along its track when that is taken); [newId] names each copy. Also
  /// returns which copy came from which content.
  (MovieDocument, Map<String, String>) paste(
    MovieClip clip,
    int at,
    String Function() newId,
  ) {
    if (clip.isEmpty || tracks.isEmpty) return (this, const {});
    final first = clip.map((e) => e.content.start).reduce(math.min);
    final next = [
      for (final t in tracks) [...t.contents],
    ];
    final copies = <String, String>{};
    for (final (:row, :content) in clip) {
      final track = next[math.min(row, next.length - 1)];
      var start = at + content.start - first;
      for (final other in [
        ...track,
      ]..sort((a, b) => a.start.compareTo(b.start))) {
        if (start < other.end && start + content.length > other.start) {
          start = other.end;
        }
      }
      final id = newId();
      copies[id] = content.id;
      track.add(content.copyWith(id: id, start: start));
    }
    return (
      copyWith(
        tracks: [
          for (final (i, t) in tracks.indexed) t.copyWith(contents: next[i]),
        ],
      ),
      copies,
    );
  }

  /// Track [trackId] copied above itself with its contents; [newId] names
  /// the track and each copied content.
  (MovieDocument, Map<String, String>) duplicateTrack(
    String trackId,
    String name,
    String Function() newId,
  ) {
    final i = tracks.indexWhere((t) => t.id == trackId);
    if (i < 0) return (this, const {});
    final copies = <String, String>{};
    final source = tracks[i];
    final copy = source.copyWith(
      id: newId(),
      name: name,
      contents: [
        for (final c in source.contents)
          () {
            final id = newId();
            copies[id] = c.id;
            return c.copyWith(id: id);
          }(),
      ],
    );
    return (copyWith(tracks: [...tracks]..insert(i, copy)), copies);
  }

  /// Track [trackId] one place up (toward the top, drawn later) or down;
  /// inside its group it stays in the group.
  MovieDocument moveTrack(String trackId, {required bool up}) {
    final i = tracks.indexWhere((t) => t.id == trackId);
    final j = up ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= tracks.length) return this;
    final swapped = [...tracks];
    swapped[i] = tracks[j].copyWith(
      group: tracks[i].group,
      clearGroup: tracks[i].group == null,
    );
    swapped[j] = tracks[i].copyWith(
      group: tracks[j].group,
      clearGroup: tracks[j].group == null,
    );
    return copyWith(tracks: swapped);
  }

  MovieDocument updateTrack(String id, MovieTrack Function(MovieTrack t) f) =>
      copyWith(tracks: [for (final t in tracks) t.id == id ? f(t) : t]);

  /// Tracks [trackIds] put in a new group [group], gathered where the
  /// first of them is.
  MovieDocument groupTracks(Set<String> trackIds, TrackGroup group) {
    final chosen = [...tracks.where((t) => trackIds.contains(t.id))];
    if (chosen.isEmpty) return this;
    final at = tracks.indexWhere((t) => trackIds.contains(t.id));
    final rest = [...tracks.where((t) => !trackIds.contains(t.id))];
    final before = tracks.take(at).where((t) => !trackIds.contains(t.id));
    return copyWith(
      tracks: [
        ...before,
        for (final t in chosen) t.copyWith(group: group.id),
        ...rest.skip(before.length),
      ],
      groups: [...groups, group],
    );
  }

  /// Group [groupId] undone; its tracks stay where they are.
  MovieDocument ungroup(String groupId) => copyWith(
    tracks: [
      for (final t in tracks)
        t.group == groupId ? t.copyWith(clearGroup: true) : t,
    ],
    groups: [...groups.where((g) => g.id != groupId)],
  );

  MovieDocument updateGroup(String id, TrackGroup Function(TrackGroup g) f) =>
      copyWith(groups: [for (final g in groups) g.id == id ? f(g) : g]);

  TrackGroup? groupById(String? id) =>
      id == null ? null : groups.where((g) => g.id == id).firstOrNull;

  /// Whether [track] shows on the stage (it and its group not hidden).
  bool trackShows(MovieTrack track) =>
      !track.hidden && !(groupById(track.group)?.hidden ?? false);
}
