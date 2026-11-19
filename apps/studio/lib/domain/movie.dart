import 'dart:math' as math;
import 'dart:ui';

import 'document.dart';
import 'keyframes.dart';
import 'movie_filters.dart';

export 'keyframes.dart';
export 'movie_filters.dart';

/// How a new movie begins (Procreate Dreams): a Flipbook track ready for
/// frames, or nothing.
enum MovieStart { flipbook, blank }

/// The stage's shape; [screen] follows the device's own screen.
enum MovieAspect {
  wide(16 / 9),
  cinema(21 / 9),
  portrait(9 / 16),
  square(1),
  screen(null);

  const MovieAspect(this.ratio);

  /// Width over height; null for [screen].
  final double? ratio;
}

/// A movie's stage size: [short] pixels on its short side, even numbers
/// (video encoders want them), [screenRatio] standing in for
/// [MovieAspect.screen].
(int, int) movieSize(MovieAspect aspect, int short, {double screenRatio = 1}) {
  final ratio = aspect.ratio ?? screenRatio;
  int even(double v) =>
      ((v / 2).round() * 2).clamp(MovieDocument.minSide, MovieDocument.maxSide);
  return ratio >= 1
      ? (even(short * ratio), even(short.toDouble()))
      : (even(short.toDouble()), even(short / ratio));
}

/// What a content is: a Flipbook, a drawing, a video, a sound or text.
enum TrackKind { flipbook, drawing, video, audio, text }

/// Where a content sits on the stage: its anchor point (a share of the
/// content's own width and height) placed at [x], [y] (a share of the
/// stage's), scaled, rotated (radians, clockwise) and flipped about it.
class ContentTransform {
  const ContentTransform({
    this.x = .5,
    this.y = .5,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.flipX = false,
    this.flipY = false,
    this.anchorX = .5,
    this.anchorY = .5,
  });
  final double x, y, scaleX, scaleY, rotation, anchorX, anchorY;
  final bool flipX, flipY;

  static const identity = ContentTransform();
  static const minScale = .01, maxScale = 100.0;

  ContentTransform copyWith({
    double? x,
    double? y,
    double? scaleX,
    double? scaleY,
    double? rotation,
    bool? flipX,
    bool? flipY,
    double? anchorX,
    double? anchorY,
  }) => ContentTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    scaleX: (scaleX ?? this.scaleX).clamp(minScale, maxScale),
    scaleY: (scaleY ?? this.scaleY).clamp(minScale, maxScale),
    rotation: rotation ?? this.rotation,
    flipX: flipX ?? this.flipX,
    flipY: flipY ?? this.flipY,
    anchorX: anchorX ?? this.anchorX,
    anchorY: anchorY ?? this.anchorY,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'scaleX': scaleX,
    'scaleY': scaleY,
    'rotation': rotation,
    'flipX': flipX,
    'flipY': flipY,
    'anchorX': anchorX,
    'anchorY': anchorY,
  };

  factory ContentTransform.fromJson(Object? json) {
    if (json is! Map) return identity;
    double number(String key, double fallback) =>
        json[key] is num ? (json[key] as num).toDouble() : fallback;
    return identity.copyWith(
      x: number('x', .5),
      y: number('y', .5),
      scaleX: number('scaleX', 1),
      scaleY: number('scaleY', 1),
      rotation: number('rotation', 0),
      flipX: json['flipX'] == true,
      flipY: json['flipY'] == true,
      anchorX: number('anchorX', .5),
      anchorY: number('anchorY', .5),
    );
  }
}

/// A content's geometry on a [stage]: from its own pixels (0 to [size])
/// to the stage's and back.
class ContentFrame {
  ContentFrame(this.transform, this.size, this.stage);
  final ContentTransform transform;
  final Size size, stage;

  Offset get anchor =>
      Offset(transform.anchorX * size.width, transform.anchorY * size.height);
  Offset get position =>
      Offset(transform.x * stage.width, transform.y * stage.height);
  double get _sx => transform.scaleX * (transform.flipX ? -1 : 1);
  double get _sy => transform.scaleY * (transform.flipY ? -1 : 1);

  Offset toStage(Offset local) {
    final q = local - anchor;
    final x = q.dx * _sx, y = q.dy * _sy;
    final c = math.cos(transform.rotation), s = math.sin(transform.rotation);
    return position + Offset(x * c - y * s, x * s + y * c);
  }

  Offset toLocal(Offset point) {
    final q = point - position;
    final c = math.cos(-transform.rotation), s = math.sin(-transform.rotation);
    final x = q.dx * c - q.dy * s, y = q.dx * s + q.dy * c;
    return anchor + Offset(x / _sx, y / _sy);
  }

  /// Top left, top right, bottom right, bottom left.
  List<Offset> get corners => [
    toStage(Offset.zero),
    toStage(Offset(size.width, 0)),
    toStage(Offset(size.width, size.height)),
    toStage(Offset(0, size.height)),
  ];

  bool contains(Offset point) => (Offset.zero & size).contains(toLocal(point));

  /// The same placement with the anchor moved to [local] (its own pixels):
  /// nothing moves on the stage.
  ContentTransform withAnchor(Offset local) {
    final at = toStage(local);
    return transform.copyWith(
      anchorX: local.dx / size.width,
      anchorY: local.dy / size.height,
      x: at.dx / stage.width,
      y: at.dy / stage.height,
    );
  }
}

/// How a content masks the content on the track right beneath it
/// (Dreams): [clip] shows itself only where that one has pixels; [alpha]
/// and [luma] are not drawn but let that one show where they are opaque
/// or bright.
enum ContentMask { none, clip, alpha, luma }

/// Something on a track for a while: it starts at frame [start] of the
/// movie and lasts [length] frames, showing its source from frame
/// [sourceIn] on. [sourceLength] is how long the source is (null: as long
/// as needed, like a drawing), so it can be trimmed back out later.
class MovieContent {
  MovieContent({
    required this.id,
    required this.name,
    required this.kind,
    required int start,
    required int length,
    int sourceIn = 0,
    int? sourceLength,
    this.width,
    this.height,
    this.transform = ContentTransform.identity,
    this.hidden = false,
    this.color,
    this.keys = const {},
    this.filters = const [],
    this.warpCols = 0,
    this.warpRows = 0,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.mask = ContentMask.none,
    this.maskInvert = false,
    this.mediaId,
    this.muted = false,
  }) : sourceLength = sourceLength == null ? null : math.max(1, sourceLength),
       sourceIn = math.max(0, sourceIn),
       start = math.max(0, start),
       length = math.max(
         1,
         sourceLength == null
             ? length
             : math.min(
                 length,
                 math.max(1, sourceLength) - math.max(0, sourceIn),
               ),
       );

  final String id, name;
  final TrackKind kind;
  final int start, length, sourceIn;
  final int? sourceLength;

  /// Its own canvas size; null: the stage's.
  final int? width, height;
  final ContentTransform transform;

  /// Left off the stage (still on the timeline).
  final bool hidden;

  /// Its accent on the timeline (ARGB); null: its kind's colour.
  final int? color;

  /// Keyframes by parameter id (Move & Scale's [MoveParam] names, filter
  /// and mesh parameters), frames counted from its start (they travel with
  /// it).
  final Map<String, Keys> keys;

  /// Live filters, applied in order.
  final List<ContentFilter> filters;

  /// Warp's grid of nodes (0: no warp).
  final int warpCols, warpRows;

  /// Its own opacity, scaling any keyed or performed one.
  final double opacity;

  /// How it mixes with what lies beneath it (inside its group only, unless
  /// the group passes through).
  final LayerBlend blend;
  final ContentMask mask;

  /// An alpha or luminance mask the other way round.
  final bool maskInvert;

  /// The video or sound file it shows or plays (the movies' media).
  final String? mediaId;

  /// A video whose sound was taken out to its own track.
  final bool muted;

  /// Whether it is heard: a sound, or a video still holding its sound.
  bool get sounds =>
      mediaId != null &&
      (kind == TrackKind.audio || (kind == TrackKind.video && !muted));

  /// Whether its picture is drawn through a mesh (Distort or Warp keyed).
  bool get meshed =>
      warpCols > 0 ||
      keys.entries.any(
        (e) => e.key.startsWith('distort.') && e.value.isNotEmpty,
      );

  /// Filter [filter]'s [param] at movie [frame].
  double filterValue(ContentFilter filter, FilterParam param, int frame) =>
      keyedValue(keys, filter.key(param.id), frame - start, param.initial);

  bool get animated => keys.values.any((k) => k.isNotEmpty);

  /// Whether Move & Scale is keyed.
  bool get moving =>
      MoveParam.values.any((p) => keys[p.name]?.isNotEmpty ?? false);

  /// Every frame (from its start) holding a keyframe of any parameter.
  List<int> get keyFrames =>
      {for (final k in keys.values) ...k.map((key) => key.frame)}.toList()
        ..sort();

  /// Where it sits at movie [frame]: its transform with the keyframed
  /// parameters taken from their keyframes.
  ContentTransform transformAt(int frame) {
    if (!moving) return transform;
    final local = frame - start;
    final t = transform;
    double value(MoveParam p, double fallback) =>
        keyValue(keys[p.name] ?? const [], local) ?? fallback;
    final scale = value(MoveParam.scale, t.scaleX);
    return t.copyWith(
      x: value(MoveParam.x, t.x),
      y: value(MoveParam.y, t.y),
      scaleX: scale,
      scaleY: scale * t.scaleY / t.scaleX,
      rotation: value(MoveParam.rotation, t.rotation),
    );
  }

  /// [placed] set as a Move & Scale keyframe at frame [local] (from its
  /// start): position, size and turn keyed; flips, anchor and the
  /// width-to-height stretch go to its own transform. A new keyframe eases
  /// with [easing]; one already there keeps its easing.
  MovieContent withMoveKey(
    int local,
    ContentTransform placed, {
    KeyEasing easing = KeyEasing.linear,
  }) {
    final values = {
      MoveParam.x.name: placed.x,
      MoveParam.y.name: placed.y,
      MoveParam.scale.name: placed.scaleX,
      MoveParam.rotation.name: placed.rotation,
    };
    return copyWith(
      transform: transform.copyWith(
        flipX: placed.flipX,
        flipY: placed.flipY,
        anchorX: placed.anchorX,
        anchorY: placed.anchorY,
        scaleY: transform.scaleX * placed.scaleY / placed.scaleX,
      ),
      keys: {
        ...keys,
        for (final p in MoveParam.values)
          p.name: withKey(
            keys[p.name] ?? const [],
            Keyframe(
              local,
              values[p.name]!,
              easing:
                  (keys[p.name] ?? const [])
                      .where((k) => k.frame == local)
                      .firstOrNull
                      ?.easing ??
                  easing,
            ),
          ),
      },
    );
  }

  /// Every keyframe [by] frames later (earlier when negative): kept where
  /// they are in the movie when its start moves by -[by].
  Map<String, Keys> shiftedKeys(int by) => {
    for (final MapEntry(:key, :value) in keys.entries)
      key: [for (final k in value) k.copyWith(frame: k.frame + by)],
  };

  Size sizeOn(Size stage) => Size(
    (width ?? stage.width).toDouble(),
    (height ?? stage.height).toDouble(),
  );

  /// Its geometry on [stage] at movie [frame] (keyframes applied), or as
  /// set when no frame is given.
  ContentFrame frameOn(Size stage, [int? frame]) => ContentFrame(
    frame == null ? transform : transformAt(frame),
    sizeOn(stage),
    stage,
  );

  /// The first frame after it.
  int get end => start + length;

  /// The source frame showing at movie frame [frame], or null when it is
  /// not on screen then.
  int? sourceFrame(int frame) =>
      frame < start || frame >= end ? null : sourceIn + frame - start;

  MovieContent copyWith({
    String? id,
    String? name,
    int? start,
    int? length,
    int? sourceIn,
    ContentTransform? transform,
    int? width,
    int? height,
    bool? hidden,
    int? color,
    bool clearColor = false,
    Map<String, Keys>? keys,
    List<ContentFilter>? filters,
    int? warpCols,
    int? warpRows,
    double? opacity,
    LayerBlend? blend,
    ContentMask? mask,
    bool? maskInvert,
    bool? muted,
  }) => MovieContent(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind,
    start: start ?? this.start,
    length: length ?? this.length,
    sourceIn: sourceIn ?? this.sourceIn,
    sourceLength: sourceLength,
    width: width ?? this.width,
    height: height ?? this.height,
    transform: transform ?? this.transform,
    hidden: hidden ?? this.hidden,
    color: clearColor ? null : color ?? this.color,
    keys: keys ?? this.keys,
    filters: filters ?? this.filters,
    warpCols: warpCols ?? this.warpCols,
    warpRows: warpRows ?? this.warpRows,
    opacity: (opacity ?? this.opacity).clamp(0, 1),
    blend: blend ?? this.blend,
    mask: mask ?? this.mask,
    maskInvert: maskInvert ?? this.maskInvert,
    mediaId: mediaId,
    muted: muted ?? this.muted,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'start': start,
    'length': length,
    'sourceIn': sourceIn,
    'sourceLength': ?sourceLength,
    'width': ?width,
    'height': ?height,
    'transform': transform.toJson(),
    if (hidden) 'hidden': true,
    'color': ?color,
    if (animated)
      'keys': {
        for (final MapEntry(:key, :value) in keys.entries)
          if (value.isNotEmpty) key: [for (final k in value) k.toJson()],
      },
    if (filters.isNotEmpty) 'filters': [for (final f in filters) f.toJson()],
    if (warpCols > 0) 'warp': [warpCols, warpRows],
    if (opacity < 1) 'opacity': opacity,
    if (blend != LayerBlend.normal) 'blend': blend.name,
    if (mask != ContentMask.none) 'mask': mask.name,
    if (maskInvert) 'maskInvert': true,
    'mediaId': ?mediaId,
    if (muted) 'muted': true,
  };

  static MovieContent? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    int? number(String key) =>
        json[key] is num ? (json[key] as num).round() : null;
    final start = number('start'), length = number('length');
    if (start == null || length == null) return null;
    return MovieContent(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      kind: TrackKind.values.asNameMap()[json['kind']] ?? TrackKind.drawing,
      start: start,
      length: length,
      sourceIn: number('sourceIn') ?? 0,
      sourceLength: number('sourceLength'),
      width: switch (number('width')) {
        final w? when w > 0 => w,
        _ => null,
      },
      height: switch (number('height')) {
        final h? when h > 0 => h,
        _ => null,
      },
      transform: ContentTransform.fromJson(json['transform']),
      hidden: json['hidden'] == true,
      color: number('color'),
      keys: {
        if (json['keys'] case final Map keys)
          for (final MapEntry(:key, :value) in keys.entries)
            if (key is String && value is List)
              key: () {
                final parsed = [for (final k in value) ?Keyframe.fromJson(k)];
                var list = <Keyframe>[];
                for (final k in parsed) {
                  list = withKey(list, k);
                }
                return list;
              }(),
      },
      filters: [
        if (json['filters'] case final List filters)
          for (final f in filters) ?ContentFilter.fromJson(f),
      ],
      warpCols: switch (json['warp']) {
        [final int c, final int _] when c >= 2 && c <= 12 => c,
        _ => 0,
      },
      warpRows: switch (json['warp']) {
        [final int _, final int r] when r >= 2 && r <= 12 => r,
        _ => 0,
      },
      opacity: json['opacity'] is num
          ? (json['opacity'] as num).toDouble().clamp(0, 1)
          : 1,
      blend: LayerBlend.values.asNameMap()[json['blend']] ?? LayerBlend.normal,
      mask: ContentMask.values.asNameMap()[json['mask']] ?? ContentMask.none,
      maskInvert: json['maskInvert'] == true,
      mediaId: json['mediaId'] as String?,
      muted: json['muted'] == true,
    );
  }
}

/// One row of the timeline: its contents, in time order, never
/// overlapping.
class MovieTrack {
  MovieTrack({
    required this.id,
    required this.name,
    required this.kind,
    List<MovieContent> contents = const [],
    this.hidden = false,
    this.group,
  }) : contents = List.unmodifiable(
         [...contents]..sort((a, b) => a.start.compareTo(b.start)),
       );
  final String id, name;
  final TrackKind kind;
  final List<MovieContent> contents;

  /// Left off the stage.
  final bool hidden;

  /// The [TrackGroup] it belongs to.
  final String? group;

  /// The content on screen at [frame].
  MovieContent? at(int frame) =>
      contents.where((c) => c.sourceFrame(frame) != null).firstOrNull;

  /// Frame [frame] is free for [length] frames.
  bool fits(int frame, int length) =>
      contents.every((c) => frame + length <= c.start || frame >= c.end);

  MovieTrack copyWith({
    String? id,
    String? name,
    List<MovieContent>? contents,
    bool? hidden,
    String? group,
    bool clearGroup = false,
  }) => MovieTrack(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind,
    contents: contents ?? this.contents,
    hidden: hidden ?? this.hidden,
    group: clearGroup ? null : group ?? this.group,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'contents': [for (final c in contents) c.toJson()],
    if (hidden) 'hidden': true,
    'group': ?group,
  };

  /// Overlapping contents (damage) keep the earlier one.
  static MovieTrack? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final contents = <MovieContent>[];
    if (json['contents'] case final List list) {
      final parsed = [for (final c in list) ?MovieContent.fromJson(c)]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final c in parsed) {
        if (contents.isEmpty || c.start >= contents.last.end) contents.add(c);
      }
    }
    return MovieTrack(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      kind: TrackKind.values.asNameMap()[json['kind']] ?? TrackKind.drawing,
      contents: contents,
      hidden: json['hidden'] == true,
      group: json['group'] as String?,
    );
  }
}

/// Tracks kept together on the timeline (Dreams' groups): folded away or
/// left off the stage at once.
class TrackGroup {
  const TrackGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
    this.hidden = false,
    this.blend = LayerBlend.normal,
    this.passthrough = false,
    this.opacity = 1,
  });
  final String id, name;
  final bool collapsed, hidden;

  /// How the group, made into one picture, mixes beneath it; with
  /// [passthrough] its tracks mix with what is outside it one by one.
  final LayerBlend blend;
  final bool passthrough;
  final double opacity;

  TrackGroup copyWith({
    String? name,
    bool? collapsed,
    bool? hidden,
    LayerBlend? blend,
    bool? passthrough,
    double? opacity,
  }) => TrackGroup(
    id: id,
    name: name ?? this.name,
    collapsed: collapsed ?? this.collapsed,
    hidden: hidden ?? this.hidden,
    blend: blend ?? this.blend,
    passthrough: passthrough ?? this.passthrough,
    opacity: (opacity ?? this.opacity).clamp(0, 1),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (collapsed) 'collapsed': true,
    if (hidden) 'hidden': true,
    if (blend != LayerBlend.normal) 'blend': blend.name,
    if (passthrough) 'passthrough': true,
    if (opacity < 1) 'opacity': opacity,
  };

  static TrackGroup? fromJson(Object? json) =>
      json is Map && json['id'] is String
      ? TrackGroup(
          id: json['id'] as String,
          name: json['name'] as String? ?? '',
          collapsed: json['collapsed'] == true,
          hidden: json['hidden'] == true,
          blend:
              LayerBlend.values.asNameMap()[json['blend']] ?? LayerBlend.normal,
          passthrough: json['passthrough'] == true,
          opacity: json['opacity'] is num
              ? (json['opacity'] as num).toDouble().clamp(0, 1)
              : 1,
        )
      : null;
}

/// How the timeline is laid out: pixels a frame, a track's height, the
/// share of the screen it takes under the stage. Kept with the movie, not
/// an undo step.
class TimelineView {
  const TimelineView({
    this.framePixels = 6,
    this.trackHeight = 56,
    this.split = .38,
  });
  final double framePixels, trackHeight, split;

  static const minFramePixels = .25, maxFramePixels = 64.0;
  static const minTrackHeight = 32.0, maxTrackHeight = 160.0;
  static const minSplit = .18, maxSplit = .8;

  TimelineView copyWith({
    double? framePixels,
    double? trackHeight,
    double? split,
  }) => TimelineView(
    framePixels: (framePixels ?? this.framePixels).clamp(
      minFramePixels,
      maxFramePixels,
    ),
    trackHeight: (trackHeight ?? this.trackHeight).clamp(
      minTrackHeight,
      maxTrackHeight,
    ),
    split: (split ?? this.split).clamp(minSplit, maxSplit),
  );

  Map<String, dynamic> toJson() => {
    'framePixels': framePixels,
    'trackHeight': trackHeight,
    'split': split,
  };

  factory TimelineView.fromJson(Object? json) {
    const d = TimelineView();
    if (json is! Map) return d;
    double? number(String key) =>
        json[key] is num ? (json[key] as num).toDouble() : null;
    return d.copyWith(
      framePixels: number('framePixels'),
      trackHeight: number('trackHeight'),
      split: number('split'),
    );
  }
}

/// A Procreate Dreams movie: its stage (size, background, how much of the
/// offstage area shows), its timing and its tracks.
class MovieDocument {
  MovieDocument({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.fps = 24,
    int? frames,
    this.background = 0xffffffff,
    this.transparent = false,
    this.offstage = .5,
    this.tracks = const [],
    this.groups = const [],
    this.playback = PlaybackMode.loop,
    this.view = const TimelineView(),
    this.revision = 0,
  }) : frames = frames ?? fps * 10;

  final String id, name;
  final int width, height;

  /// Frames a second; [frames] long.
  final int fps, frames;

  /// The stage's colour, unless [transparent] (exports keep the alpha).
  final int background;
  final bool transparent;

  /// How much of what lies off the stage shows while working (0–1).
  final double offstage;

  final List<MovieTrack> tracks;
  final List<TrackGroup> groups;

  /// How playback goes over the movie.
  final PlaybackMode playback;
  final TimelineView view;
  final int revision;

  static const minFps = 1, maxFps = 120, minSide = 16, maxSide = 7680;
  static const fpsPresets = [12, 15, 24, 25, 30, 48, 50, 60, 120];
  static const maxSeconds = 60 * 60;

  double get seconds => frames / fps;

  /// A new movie of [seconds] at [fps].
  factory MovieDocument.create({
    required String name,
    required int width,
    required int height,
    int fps = 24,
    double seconds = 10,
    int background = 0xffffffff,
    bool transparent = false,
    MovieStart start = MovieStart.flipbook,
    String flipbookName = 'Flipbook',
  }) {
    final rate = fps.clamp(minFps, maxFps);
    return MovieDocument(
      id: newId(),
      name: name,
      width: width.clamp(minSide, maxSide),
      height: height.clamp(minSide, maxSide),
      fps: rate,
      frames: math.max(1, (seconds.clamp(0, maxSeconds) * rate).round()),
      background: background,
      transparent: transparent,
      tracks: [
        if (start == MovieStart.flipbook)
          MovieTrack(
            id: newId(),
            name: flipbookName,
            kind: TrackKind.flipbook,
            contents: [
              MovieContent(
                id: newId(),
                name: flipbookName,
                kind: TrackKind.flipbook,
                start: 0,
                length: math.max(
                  1,
                  (seconds.clamp(0, maxSeconds) * rate).round(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// A changed [fps] keeps the length in seconds.
  MovieDocument copyWith({
    String? id,
    String? name,
    int? width,
    int? height,
    int? fps,
    int? frames,
    int? background,
    bool? transparent,
    double? offstage,
    List<MovieTrack>? tracks,
    List<TrackGroup>? groups,
    PlaybackMode? playback,
    TimelineView? view,
    int? revision,
  }) {
    final rate = (fps ?? this.fps).clamp(minFps, maxFps);
    return MovieDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      width: (width ?? this.width).clamp(minSide, maxSide),
      height: (height ?? this.height).clamp(minSide, maxSide),
      fps: rate,
      frames: math.max(
        1,
        frames ?? (rate == this.fps ? this.frames : (seconds * rate).round()),
      ),
      background: background ?? this.background,
      transparent: transparent ?? this.transparent,
      offstage: (offstage ?? this.offstage).clamp(0, 1),
      tracks: tracks ?? this.tracks,
      groups: groups ?? this.groups,
      playback: playback ?? this.playback,
      view: view ?? this.view,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': 'artblend.movie',
    'version': 1,
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'fps': fps,
    'frames': frames,
    'background': background,
    'transparent': transparent,
    'offstage': offstage,
    'tracks': [for (final t in tracks) t.toJson()],
    if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
    'playback': playback.name,
    'view': view.toJson(),
    'revision': revision,
  };

  /// Damaged fields take their defaults; no id or size is not a movie.
  static MovieDocument fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'artblend.movie' || json['id'] is! String) {
      throw const FormatException('Not a movie');
    }
    int number(String key, int fallback) =>
        json[key] is num ? (json[key] as num).round() : fallback;
    final width = number('width', 0), height = number('height', 0);
    if (width < minSide || height < minSide) {
      throw const FormatException('Invalid stage size');
    }
    final fps = number('fps', 24).clamp(minFps, maxFps);
    return MovieDocument(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      width: math.min(width, maxSide),
      height: math.min(height, maxSide),
      fps: fps,
      frames: math.max(1, number('frames', fps * 10)),
      background: number('background', 0xffffffff),
      transparent: json['transparent'] == true,
      offstage: json['offstage'] is num
          ? (json['offstage'] as num).toDouble().clamp(0, 1)
          : .5,
      tracks: [
        if (json['tracks'] case final List tracks)
          for (final t in tracks) ?MovieTrack.fromJson(t),
      ],
      groups: [
        if (json['groups'] case final List groups)
          for (final g in groups) ?TrackGroup.fromJson(g),
      ],
      playback:
          PlaybackMode.values.asNameMap()[json['playback']] ??
          PlaybackMode.loop,
      view: TimelineView.fromJson(json['view']),
      revision: number('revision', 0),
    );
  }
}

/// Every raster tile a movie file refers to, in whatever drawings it
/// holds (any map with layers), so storage compaction keeps them.
Set<String> movieReferencedBlobs(Object? json) => {
  if (json is Map) ...[
    if (json['layers'] is List)
      ...referencedBlobs(json.cast<String, dynamic>()),
    for (final value in json.values) ...movieReferencedBlobs(value),
  ] else if (json is List)
    for (final value in json) ...movieReferencedBlobs(value),
};
