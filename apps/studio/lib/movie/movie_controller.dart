import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import '../data/studio_storage.dart';
import '../domain/document.dart';
import '../domain/movie.dart';
import '../domain/movie_edits.dart';
import '../data/import_formats.dart';
import '../data/media.dart';
import '../drawing/adjustments.dart';
import '../drawing/imported_document.dart';
import 'drawing_frames.dart';
import 'media_cache.dart';

Uint8List _mixWav((List<MixPart>, int, int) job) =>
    encodeWav(mixAudio(job.$1, job.$2, job.$3));

/// "m:ss:ff": minutes, seconds and the frame within the second.
String timecode(int frame, int fps) {
  final seconds = frame ~/ fps;
  return '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}:'
      '${'${frame % fps}'.padLeft(fps > 99 ? 3 : 2, '0')}';
}

/// The ruler's marks at [framePixels] a frame: a short mark every [minor]
/// frames, a labelled one every [label] frames (whole seconds once frames
/// are too small to tell apart).
({int minor, int label}) rulerSteps(int fps, double framePixels) {
  final labels = {
    1, 2, 5, 10, //
    for (final s in [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]) s * fps,
  }.toList()..sort();
  final label = labels.firstWhere(
    (step) => step * framePixels >= 56,
    orElse: () => labels.last,
  );
  final minor =
      (label < fps
              ? [1, 2, 5, 10]
              : [
                  math.max(1, fps ~/ 4),
                  math.max(1, fps ~/ 2),
                  fps,
                  fps * 5,
                  fps * 10,
                ])
          .where((step) => label % step == 0 && step * framePixels >= 8)
          .fold<int?>(
            null,
            (best, step) => best == null ? step : math.min(best, step),
          );
  return (minor: minor ?? label, label: label);
}

/// An open movie: its edits (undo and redo), where the playhead is and
/// playback. Every edit is saved at once; the timeline's layout shortly
/// after it settles.
class MovieController extends ChangeNotifier {
  MovieController({
    required this.storage,
    required this._movie,
    this.undoDepth = 100,
  });

  final StudioStorage storage;

  /// The movie open on screen, for tools that act on it (MCP).
  static final ValueNotifier<MovieController?> active = ValueNotifier(null);

  /// How many steps back undo reaches (a preference).
  int undoDepth;
  MovieDocument _movie;
  MovieDocument get movie => _movie;

  final _undo = <MovieDocument>[], _redo = <MovieDocument>[];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The frame on the stage.
  final ValueNotifier<int> playhead = ValueNotifier(0);
  final ValueNotifier<bool> playing = ValueNotifier(false);

  /// The content chosen on the timeline.
  String? selected;

  /// Every content chosen (several in selection mode); [selected] is the
  /// last one picked.
  Set<String> selection = {};

  /// Selection mode: taps add and remove contents.
  bool choosing = false;

  /// Free Trim: trimming a content's end moves what follows on its track.
  bool freeTrim = false;

  /// Keyframe mode: the timeline shows keyframes and stage changes key the
  /// content at the playhead.
  bool keyframing = false;

  /// The easing new keyframes take (the last one chosen).
  KeyEasing lastEasing = KeyEasing.linear;

  /// Keyframes copied (from frame 0).
  Map<String, Keys>? keyClipboard;

  /// Contents cut or copied, with their drawings.
  ({MovieClip clip, Map<String, ArtDocument> drawings})? clipboard;

  /// The last save's failure, if it failed.
  Object? saveError;

  Timer? _timer, _viewSave;
  int _timerFps = 0, _direction = 1;
  bool _disposed = false;

  /// Drawings and Flipbook frames rendered for the stage.
  final frames = DrawingFrames();

  /// Videos' pictures and sounds made ready.
  late MediaCache media = MediaCache(storage);
  AudioOut audio = const AudioOut();

  /// Every media file the movie uses, made ready in the background.
  void prepareMedia() {
    for (final t in _movie.tracks) {
      for (final c in t.contents) {
        if (c.mediaId case final id?) media.prepare(id);
      }
    }
  }

  static const pictureTypes = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'];
  static const videoTypes = ['mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'];
  static const soundTypes = [
    'mp3',
    'wav',
    'aac',
    'm4a',
    'flac',
    'ogg',
    'aif',
    'aiff',
    'caf',
    'opus',
  ];

  /// [content] on a new track named [name] on top, from the playhead.
  void _addOnNewTrack(MovieContent content, String name) {
    edit(
      _movie.copyWith(
        tracks: [
          MovieTrack(
            id: newId(),
            name: name,
            kind: content.kind,
            contents: [content],
          ),
          ..._movie.tracks,
        ],
      ),
    );
    select(content.id);
  }

  /// A picture ([bytes], a file of type [ext]) as a drawing on a new track;
  /// an animated GIF as a Flipbook, each frame held as long as it lasts.
  Future<bool> importPicture(Uint8List bytes, String name) async {
    final ImportedDrawing picture;
    try {
      picture = await compute(decodePicture, bytes);
    } catch (_) {
      return false;
    }
    var doc = await documentFromImport(picture, name, maxLayers: 600);
    final frames = picture.layers.length;
    if (frames > 1) {
      final durations = await compute(gifDurations, bytes);
      doc = doc.copyWith(
        animation: AnimationSettings(
          holds: {
            for (final (i, l) in doc.layers.indexed)
              if (i < durations.length)
                l.id: math.max(
                  0,
                  (durations[i] * _movie.fps / 1000).round() - 1,
                ),
          },
        ),
      );
    }
    final order = doc.animating
        ? doc.animation!.playOrder([
            for (final p in doc.pages) ArtDocument.frameId(p),
          ])
        : const <int>[];
    final start = playhead.value;
    final content = MovieContent(
      id: newId(),
      name: name,
      kind: doc.animating ? TrackKind.flipbook : TrackKind.drawing,
      start: start,
      length: math.max(
        1,
        math.min(
          _movie.frames - start,
          doc.animating ? order.length : _movie.fps * 2,
        ),
      ),
      width: doc.dimensions.width,
      height: doc.dimensions.height,
    );
    drawings[content.id] = doc;
    _drawingsDirty = true;
    _addOnNewTrack(content, name);
    return true;
  }

  /// A video or sound file at [path] brought into the movie on a new
  /// track, as long as it lasts (to the movie's end); its pictures and
  /// sound are made ready in the background.
  Future<bool> importMedia(String path, String name) async {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    final video = videoTypes.contains(ext);
    if (!video && !soundTypes.contains(ext)) return false;
    final id = await storage.importMedia(path);
    final info = await media.info(id);
    if (info == null || (!info.hasVideo && !info.hasAudio)) return false;
    final source = math.max(1, (info.durationMs * _movie.fps / 1000).round());
    final start = playhead.value;
    final content = MovieContent(
      id: newId(),
      name: name,
      kind: info.hasVideo ? TrackKind.video : TrackKind.audio,
      start: start,
      length: math.max(1, math.min(source, _movie.frames - start)),
      sourceLength: source,
      width: info.hasVideo ? info.width : null,
      height: info.hasVideo ? info.height : null,
      mediaId: id,
    );
    _addOnNewTrack(content, name);
    media.prepare(id);
    return true;
  }

  /// Video [id]'s sound onto a track of its own above it (Separate audio
  /// and video); the video goes quiet.
  void separateAudio(String id, String name) {
    final v = content(id);
    if (v == null ||
        v.kind != TrackKind.video ||
        v.muted ||
        v.mediaId == null) {
      return;
    }
    final sound = MovieContent(
      id: newId(),
      name: name,
      kind: TrackKind.audio,
      start: v.start,
      length: v.length,
      sourceIn: v.sourceIn,
      sourceLength: v.sourceLength,
      mediaId: v.mediaId,
      keys: {'volume': ?v.keys['volume']},
    );
    final at = _movie.trackIndexOf(id);
    edit(
      _movie
          .updateContents({id}, (c) => c.copyWith(muted: true))
          .copyWith(
            tracks: [
              ..._movie.tracks.take(at),
              MovieTrack(
                id: newId(),
                name: name,
                kind: TrackKind.audio,
                contents: [sound],
              ),
              ..._movie
                  .updateContents({id}, (c) => c.copyWith(muted: true))
                  .tracks
                  .skip(at),
            ],
          ),
    );
  }

  MovieDocument? _mixFor;
  String? _mixPath;
  Future<String?>? _mixing;
  int _mixes = 0;

  /// The movie's sound as one WAV: every sound heard, at its volume;
  /// null when there is none (yet).
  Future<String?> soundMix() {
    if (identical(_mixFor, _movie) && _mixing != null) return _mixing!;
    final movie = _movie;
    final parts = <MixPart>[
      for (final t in movie.tracks)
        if (movie.trackShows(t))
          for (final c in t.contents)
            if (c.sounds && !c.hidden)
              if (media.sounds[c.mediaId] case final samples?)
                (
                  samples: samples,
                  start: c.start,
                  length: c.length,
                  sourceIn: c.sourceIn,
                  volume: c.keys['volume'] ?? const <Keyframe>[],
                ),
    ];
    _mixFor = movie;
    return _mixing = () async {
      if (parts.isEmpty) return null;
      final frames = movie.frames, fps = movie.fps;
      final wav = await compute(_mixWav, (parts, frames, fps));
      final dir = await media.folder();
      final file = File('${dir.path}/artblend-mix-${movie.id}-${_mixes++}.wav');
      await file.writeAsBytes(wav);
      final old = _mixPath;
      _mixPath = file.path;
      if (old != null) {
        unawaited(File(old).delete().then((_) {}, onError: (_) {}));
      }
      return file.path;
    }();
  }

  Duration _at(int frame) =>
      Duration(microseconds: frame * 1000000 ~/ _movie.fps);

  /// The frame the sound started from, while it plays (the playhead
  /// follows the sound's clock).
  int? _soundFrom;

  /// The sound clock's last reading: followed only while it moves on.
  Duration _heard = Duration.zero;

  /// Sound from frame [from] while playing.
  Future<void> _sound(int from) async {
    try {
      final path = await soundMix();
      if (path == null || !playing.value) return;
      await audio.play(path, _at(from));
      _soundFrom = from;
      _heard = Duration.zero;
    } catch (_) {
      // No sound out here (tests, an unsupported platform).
    }
  }

  void _quiet() {
    _soundFrom = null;
    audio.stop().catchError((_) {});
  }

  /// The playhead pulled to where the sound is, when it has drifted more
  /// than a frame: the timer's ticks are not as steady as the sound card.
  void _follow() {
    final from = _soundFrom;
    if (from == null) return;
    audio.position().then((at) {
      if (at == null || _soundFrom != from || !playing.value) return;
      // A clock standing still (some players report 0 for a while) is not
      // followed: the timer goes on alone.
      if (at <= _heard) return;
      _heard = at;
      final want = from + at.inMicroseconds * _movie.fps ~/ 1000000;
      if (want < _movie.frames && (want - playhead.value).abs() > 1) {
        playhead.value = want;
      }
    }, onError: (_) {});
  }

  /// A sliver of sound at the playhead while it is dragged.
  Future<void> scrub() async {
    if (playing.value) return;
    try {
      final path = await soundMix();
      if (path == null || playing.value) return;
      await audio.play(
        path,
        _at(playhead.value),
        length: Duration(milliseconds: math.max(60, 1000 ~/ _movie.fps)),
      );
    } catch (_) {}
  }

  /// What each drawing or Flipbook content holds, by content id. Kept
  /// apart from the movie's undo steps: undoing a move never undoes ink.
  final Map<String, ArtDocument> drawings = {};
  bool _drawingsDirty = false;

  /// The drawings as saved; call once on opening.
  Future<void> loadDrawings() async {
    drawings.addAll(await storage.loadMovieDrawings(_movie.id));
    notifyListeners();
  }

  /// Words to start a text content with: the stage's width, in the middle.
  LayerText newText(String words) {
    final w = _movie.width.toDouble(), h = _movie.height.toDouble();
    final box = w * .8;
    final size = (h / 8).clamp(12.0, 600.0);
    return LayerText(
      text: words,
      origin: Offset((w - box) / 2, (h - size * 1.2) / 2),
      width: box,
      size: size,
      color: 0xffffffff,
      alignment: TextAlignment.center,
      weight: 700,
    );
  }

  /// [text] as a text content on a new track on top, from the playhead for
  /// two seconds: a see-through stage-sized drawing holding one text layer
  /// (still words, editable).
  void addText(LayerText text, String trackName) {
    final layer = ArtLayer(id: newId(), name: _textName(text), text: text);
    final doc = ArtDocument(
      id: newId(),
      name: layer.name,
      dimensions: CanvasSize(_movie.width, _movie.height),
      layers: [layer],
      activeLayerId: layer.id,
      backgroundHidden: true,
    );
    final start = playhead.value;
    final content = MovieContent(
      id: newId(),
      name: layer.name,
      kind: TrackKind.text,
      start: start,
      length: math.max(1, math.min(_movie.fps * 2, _movie.frames - start)),
      width: _movie.width,
      height: _movie.height,
    );
    drawings[content.id] = doc;
    _drawingsDirty = true;
    edit(
      _movie.copyWith(
        tracks: [
          MovieTrack(
            id: newId(),
            name: trackName,
            kind: TrackKind.text,
            contents: [content],
          ),
          ..._movie.tracks,
        ],
      ),
    );
    select(content.id);
  }

  static String _textName(LayerText text) {
    final line = text.text.trim().split('\n').first;
    return line.length > 24 ? '${line.substring(0, 24)}…' : line;
  }

  /// The words of text content [id], if it still holds them as text.
  LayerText? textOf(String id) =>
      drawings[id]?.layers.where((l) => l.text != null).firstOrNull?.text;

  /// Text content [id]'s words and style: one undo step (its name follows
  /// the words).
  void setText(String id, LayerText text) {
    final doc = drawings[id];
    if (doc == null) return;
    final name = _textName(text);
    final before = _movie;
    drawings[id] = doc.copyWith(
      layers: [
        for (final l in doc.layers) l.text != null ? l.copyWith(text: text) : l,
      ],
    );
    _drawingsDirty = true;
    edit(before.updateContents({id}, (c) => c.copyWith(name: name)));
  }

  /// A blank drawing for [content]: its own size (the stage's unless set),
  /// see-through, and for a Flipbook with Animation Assist on (its frames,
  /// holds and onion skins).
  ArtDocument newDrawingFor(MovieContent content) {
    final size = content.sizeOn(
      Size(_movie.width.toDouble(), _movie.height.toDouble()),
    );
    final blank = ArtDocument.empty(
      name: content.name,
      dimensions: CanvasSize(size.width.round(), size.height.round()),
    );
    return blank.copyWith(
      backgroundHidden: true,
      animation: content.kind == TrackKind.flipbook
          ? const AnimationSettings()
          : null,
    );
  }

  /// [contentId]'s drawing as edited: saved, not an undo step.
  /// The content takes the drawing's canvas size (it may differ from the
  /// stage's), so nothing is stretched.
  void setDrawing(String contentId, ArtDocument drawing) {
    drawings[contentId] = drawing;
    final content = this.content(contentId);
    final size = drawing.dimensions;
    if (content != null &&
        (content.width != size.width || content.height != size.height)) {
      _movie = withContent(
        contentId,
        (c) => c.copyWith(width: size.width, height: size.height),
      );
    }
    _drawingsDirty = true;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final withDrawings = _drawingsDirty;
      _drawingsDirty = false;
      final used = {
        for (final t in _movie.tracks)
          for (final c in t.contents) c.id,
      };
      await storage.saveMovie(
        _movie,
        drawings: withDrawings
            ? {
                for (final MapEntry(:key, :value) in drawings.entries)
                  if (used.contains(key)) key: value,
              }
            : null,
      );
      saveError = null;
    } catch (error) {
      saveError = error;
      if (!_disposed) notifyListeners();
    }
  }

  void _set(MovieDocument next) {
    _movie = next;
    final alive = {
      for (final t in next.tracks)
        for (final c in t.contents) c.id,
    };
    selection = {...selection.where(alive.contains)};
    if (selected != null && !alive.contains(selected)) {
      selected = selection.lastOrNull;
    }
    seek(playhead.value);
    if (playing.value && _timerFps != next.fps) _startTimer();
    notifyListeners();
    unawaited(_save());
  }

  /// [next] as one undo step.
  void edit(MovieDocument next) {
    if (identical(next, _movie)) return;
    _undo.add(_movie);
    if (_undo.length > undoDepth) _undo.removeAt(0);
    _redo.clear();
    _set(next.copyWith(revision: _movie.revision + 1));
  }

  MovieDocument? _previewBase;

  /// A drag's in-between state: shown, not saved, not an undo step.
  void preview(MovieDocument next) {
    _previewBase ??= _movie;
    _movie = next;
    notifyListeners();
  }

  /// The drag is over: everything since it began is one undo step.
  void commitPreview() {
    final base = _previewBase;
    if (base == null) return;
    _previewBase = null;
    final end = _movie;
    _movie = base;
    if (!identical(base, end)) edit(end);
  }

  /// [id] changed by [change].
  MovieDocument withContent(
    String id,
    MovieContent Function(MovieContent content) change,
  ) => _movie.copyWith(
    tracks: [
      for (final t in _movie.tracks)
        t.contents.any((c) => c.id == id)
            ? t.copyWith(
                contents: [
                  for (final c in t.contents) c.id == id ? change(c) : c,
                ],
              )
            : t,
    ],
  );

  MovieContent? content(String? id) => id == null
      ? null
      : _movie.tracks
            .expand((t) => t.contents)
            .where((c) => c.id == id)
            .firstOrNull;

  /// What the stage shows at [frame], bottom track first.
  List<MovieContent> shownAt(int frame) => [
    for (final t in _movie.tracks.reversed)
      if (_movie.trackShows(t))
        if (t.at(frame) case final c?
            when !c.hidden && c.kind != TrackKind.audio)
          c,
  ];

  void undo() {
    if (!canUndo || _previewBase != null) return;
    _redo.add(_movie);
    _set(_undo.removeLast());
  }

  void redo() {
    if (!canRedo || _previewBase != null) return;
    _undo.add(_movie);
    _set(_redo.removeLast());
  }

  /// The timeline's layout: not an undo step, saved once it settles.
  void setView(TimelineView view) {
    _movie = _movie.copyWith(view: view);
    notifyListeners();
    _viewSave?.cancel();
    _viewSave = Timer(const Duration(milliseconds: 400), () {
      _viewSave = null;
      unawaited(_save());
    });
  }

  /// A preference of the movie, not an undo step.
  void setPlayback(PlaybackMode mode) {
    if (mode == _movie.playback) return;
    _direction = 1;
    _movie = _movie.copyWith(playback: mode);
    notifyListeners();
    unawaited(_save());
  }

  /// [contentId] alone chosen (none when null); in selection mode a tap
  /// adds or removes it instead.
  void select(String? contentId) {
    if (choosing && contentId != null) {
      selection.contains(contentId)
          ? selection.remove(contentId)
          : selection.add(contentId);
      selected = selection.contains(contentId)
          ? contentId
          : selection.lastOrNull;
    } else {
      if (selected == contentId && selection.length <= 1) return;
      selected = contentId;
      selection = {?contentId};
    }
    notifyListeners();
  }

  /// [ids] chosen (a lasso in selection mode adds to the selection).
  void selectAll(Iterable<String> ids, {bool add = false}) {
    selection = {if (add) ...selection, ...ids};
    selected = selection.lastOrNull;
    notifyListeners();
  }

  void setChoosing(bool on) {
    choosing = on;
    if (!on && selection.length > 1) {
      selection = {?selected};
    }
    notifyListeners();
  }

  /// Painting's filter shaders, for live filters (null until loaded).
  AdjustmentShaders? shaders;

  Future<void> loadShaders() async {
    try {
      shaders = await AdjustmentShaders.load();
      notifyListeners();
    } catch (_) {
      // Without shaders the contents show unfiltered.
    }
  }

  void addFilter(String id, FilterKind kind) => edit(
    withContent(
      id,
      (c) => c.copyWith(
        filters: [
          ...c.filters,
          ContentFilter(id: newId(), kind: kind),
        ],
      ),
    ),
  );

  /// Filter [filterId] off [id], its keyframes with it.
  void removeFilter(String id, String filterId) => edit(
    withContent(
      id,
      (c) => c.copyWith(
        filters: [...c.filters.where((f) => f.id != filterId)],
        keys: {
          for (final MapEntry(:key, :value) in c.keys.entries)
            if (!key.startsWith('$filterId.')) key: value,
        },
      ),
    ),
  );

  /// Keyed parameters of [id] set at the playhead (see [setKeyed]: keyed
  /// there in keyframe mode or when already keyed, otherwise constant);
  /// [live] shows it without an undo step, [commitPreview] ends it.
  void setKeyedValues(
    String id,
    Map<String, double> values, {
    bool live = false,
  }) {
    final c = content(id);
    if (c == null) return;
    final local = (playhead.value - c.start).clamp(0, c.length - 1);
    final next = withContent(id, (c) {
      var keys = c.keys;
      for (final MapEntry(:key, :value) in values.entries) {
        keys = setKeyed(
          keys,
          key,
          local,
          value,
          keying: keyframing,
          easing: lastEasing,
        );
      }
      return c.copyWith(keys: keys);
    });
    live ? preview(next) : edit(next);
  }

  /// Warp's grid for [id] ([cols] × [rows] nodes); its Warp keyframes
  /// start over.
  void setWarpGrid(String id, int cols, int rows) => edit(
    withContent(
      id,
      (c) => c.copyWith(
        warpCols: cols.clamp(2, 12),
        warpRows: rows.clamp(2, 12),
        keys: {
          for (final MapEntry(:key, :value) in c.keys.entries)
            if (!key.startsWith('warp.')) key: value,
        },
      ),
    ),
  );

  /// [id]'s Distort corners or Warp nodes back in place, keyframes gone.
  void straighten(String id, {required bool warp}) => edit(
    withContent(
      id,
      (c) => c.copyWith(
        keys: {
          for (final MapEntry(:key, :value) in c.keys.entries)
            if (!key.startsWith(warp ? 'warp.' : 'distort.')) key: value,
        },
      ),
    ),
  );

  /// Perform mode: dragging records keyframes at the movie's frame rate
  /// while the movie plays (Dreams' Perform).
  bool performing = false;

  /// How much a performance is smoothed (0: every wobble kept).
  double motionFilter = .3;

  ({String id, Map<String, double> target, Map<String, double> smooth})? _take;
  Timer? _takeTimer;

  bool get recording => _take != null;

  void setPerforming(bool on) {
    endTake();
    performing = on;
    notifyListeners();
  }

  void setMotionFilter(double value) {
    motionFilter = value.clamp(0, 1);
    notifyListeners();
  }

  /// A performance of [id]'s parameters [values] begins at the playhead:
  /// keyed there at once, then every frame while the movie plays, until
  /// [endTake]. The whole take is one undo step.
  void beginTake(String id, Map<String, double> values) {
    if (content(id) == null) return;
    stop();
    _take = (id: id, target: {...values}, smooth: {...values});
    _record();
    _takeTimer = Timer.periodic(
      Duration(microseconds: 1000000 ~/ _movie.fps),
      (_) => _advanceTake(),
    );
    playing.value = true;
  }

  /// Where the finger (or slider) is now.
  void updateTake(Map<String, double> values) => _take?.target.addAll(values);

  void endTake() {
    _takeTimer?.cancel();
    _takeTimer = null;
    if (_take == null) return;
    _take = null;
    playing.value = false;
    commitPreview();
  }

  void _advanceTake() {
    final take = _take;
    if (take == null) return;
    final next = playhead.value + 1;
    final c = content(take.id);
    if (c == null || next >= _movie.frames) return endTake();
    if (next >= c.end) {
      // Recording past its end makes it longer, where there is room.
      final track = _movie.tracks[_movie.trackIndexOf(c.id)];
      final room = track.contents
          .where((o) => o.start >= c.end)
          .map((o) => o.start)
          .fold(_movie.frames, math.min);
      if (next >= room ||
          (c.sourceLength != null &&
              next >= c.start + c.sourceLength! - c.sourceIn)) {
        return endTake();
      }
      preview(withContent(c.id, (c) => c.copyWith(length: next + 1 - c.start)));
    }
    playhead.value = next;
    final ease = 1 - motionFilter * .9;
    for (final MapEntry(:key, :value) in take.target.entries) {
      final was = take.smooth[key] ?? value;
      take.smooth[key] = was + (value - was) * ease;
    }
    _record();
  }

  void _record() {
    final take = _take;
    if (take == null) return;
    final c = content(take.id);
    if (c == null) return;
    final local = playhead.value - c.start;
    var keys = c.keys;
    for (final MapEntry(:key, :value) in take.smooth.entries) {
      keys = setKeyed(
        keys,
        key,
        local,
        value,
        keying: true,
        easing: lastEasing,
      );
    }
    preview(withContent(take.id, (c) => c.copyWith(keys: keys)));
  }

  /// The chosen contents' (or [id]'s) opacity, blend mode and mask.
  void setLook(
    String? id, {
    double? opacity,
    LayerBlend? blend,
    ContentMask? mask,
    bool? maskInvert,
  }) => edit(
    _movie.updateContents(
      _targets(id),
      (c) => c.copyWith(
        opacity: opacity,
        blend: blend,
        mask: mask,
        maskInvert: maskInvert,
      ),
    ),
  );

  /// Flipbook [id] back into drawings on its track: one a run of the same
  /// frame, as long as it showed, each keeping the Flipbook's place, motion
  /// and look. [name] names the n-th (from 1).
  void flipbookToDrawings(String id, String Function(int n) name) {
    final f = content(id), doc = drawings[id];
    if (f == null || doc == null || !doc.animating) return;
    final pieces = <MovieContent>[];
    final made = <String, ArtDocument>{};
    var from = f.start;
    int? page;
    for (var frame = f.start; frame <= f.end; frame++) {
      final p = frame < f.end ? drawingAt(f, doc, frame)?.page : null;
      if (frame == f.start) {
        page = p;
        continue;
      }
      if (p == page) continue;
      if (page != null) {
        final piece = MovieContent(
          id: newId(),
          name: name(pieces.length + 1),
          kind: TrackKind.drawing,
          start: from,
          length: frame - from,
          width: f.width,
          height: f.height,
          transform: f.transform,
          keys: f.shiftedKeys(f.start - from),
          filters: f.filters,
          warpCols: f.warpCols,
          warpRows: f.warpRows,
          opacity: f.opacity,
          blend: f.blend,
          mask: f.mask,
          maskInvert: f.maskInvert,
          color: f.color,
        );
        pieces.add(piece);
        final view = page < 0 ? doc : doc.animationFrame(page);
        made[piece.id] = view.copyWith(
          id: newId(),
          name: piece.name,
          animation: doc.animation!.copyWith(enabled: false),
        );
      }
      from = frame;
      page = p;
    }
    if (pieces.isEmpty) return;
    drawings.addAll(made);
    _drawingsDirty = true;
    final track = _movie.tracks[_movie.trackIndexOf(id)];
    edit(
      _movie.updateTrack(
        track.id,
        (t) => t.copyWith(
          contents: [...t.contents.where((c) => c.id != id), ...pieces],
        ),
      ),
    );
    selectAll(made.keys);
  }

  /// Drawings [ids] (in time order, not overlapping) made into one
  /// Flipbook [name] where the first was: each drawing a frame held as
  /// long as it showed, gaps as blank frames. False when they cannot be.
  bool drawingsToFlipbook(Set<String> ids, String name) {
    final chosen = [
      for (final t in _movie.tracks)
        for (final c in t.contents)
          if (ids.contains(c.id) &&
              c.kind == TrackKind.drawing &&
              drawings[c.id] != null)
            c,
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (chosen.length < 2) return false;
    for (var i = 1; i < chosen.length; i++) {
      if (chosen[i].start < chosen[i - 1].end) return false;
    }
    final layers = <ArtLayer>[];
    final groups = <LayerGroup>[];
    final holds = <String, int>{};
    var at = chosen.first.start;
    for (final x in chosen) {
      if (x.start > at) {
        final blank = ArtLayer(id: newId(), name: '${layers.length + 1}');
        layers.add(blank);
        holds[blank.id] = x.start - at - 1;
      }
      final d = drawings[x.id]!;
      final String frame;
      if (d.layers.length == 1) {
        final only = d.layers.single.copyWith(clearGroup: true);
        layers.add(only);
        frame = only.id;
      } else {
        final group = LayerGroup(id: newId(), name: x.name);
        groups.add(group);
        layers.addAll([for (final l in d.layers) l.copyWith(group: group.id)]);
        frame = group.id;
      }
      if (x.length > 1) holds[frame] = x.length - 1;
      at = x.end;
    }
    final first = chosen.first, base = drawings[first.id]!;
    final doc = ArtDocument(
      id: newId(),
      name: name,
      dimensions: base.dimensions,
      layers: layers,
      groups: groups,
      activeLayerId: layers.first.id,
      backgroundHidden: true,
      animation: AnimationSettings(holds: holds),
    );
    final flipbook = MovieContent(
      id: newId(),
      name: name,
      kind: TrackKind.flipbook,
      start: first.start,
      length: at - first.start,
      width: base.dimensions.width,
      height: base.dimensions.height,
      transform: first.transform,
    );
    final track = _movie.tracks[_movie.trackIndexOf(first.id)];
    final gone = {for (final c in chosen) c.id};
    drawings[flipbook.id] = doc;
    _drawingsDirty = true;
    edit(
      _movie
          .deleteContents(gone)
          .updateTrack(
            track.id,
            (t) => t.copyWith(contents: [...t.contents, flipbook]),
          ),
    );
    select(flipbook.id);
    return true;
  }

  void setKeyframing(bool on) {
    keyframing = on;
    notifyListeners();
  }

  /// [content] placed at [placed]: keyed at the playhead when it moves by
  /// keyframes or in keyframe mode, otherwise its own placement changes.
  MovieContent place(MovieContent content, ContentTransform placed) =>
      keyframing || content.moving
      ? content.withMoveKey(
          playhead.value - content.start,
          placed,
          easing: lastEasing,
        )
      : content.copyWith(transform: placed);

  void _keys(String id, Map<String, Keys> Function(MovieContent c) change) =>
      edit(withContent(id, (c) => c.copyWith(keys: change(c))));

  /// A Move & Scale keyframe at the playhead, from where [id] is now.
  void addMoveKey(String id) {
    final c = content(id);
    if (c == null) return;
    final at = playhead.value.clamp(c.start, c.end - 1);
    edit(
      withContent(
        id,
        (c) =>
            c.withMoveKey(at - c.start, c.transformAt(at), easing: lastEasing),
      ),
    );
  }

  /// A Move & Scale keyframe at [id]'s first frame, from where it is there.
  void addKeyAtStart(String id) {
    final c = content(id);
    if (c == null) return;
    edit(
      withContent(
        id,
        (c) => c.withMoveKey(0, c.transformAt(c.start), easing: lastEasing),
      ),
    );
  }

  /// [id]'s keyframes at [frame] (from its start): every parameter's, or
  /// [param]'s alone.
  void deleteKeys(String id, int frame, {String? param}) => _keys(
    id,
    (c) => {
      for (final MapEntry(:key, :value) in c.keys.entries)
        key: param == null || param == key
            ? [...value.where((k) => k.frame != frame)]
            : value,
    },
  );

  /// [id]'s keyframes at [from] moved to [to] (kept inside it), shown live
  /// while dragging; [commitPreview] ends the drag.
  void dragKeys(
    MovieDocument base,
    String id,
    int from,
    int to, {
    String? param,
  }) {
    final c = base.contentById(id);
    if (c == null) return;
    final at = to.clamp(0, c.length - 1);
    preview(
      base.updateContents(
        {id},
        (c) => c.copyWith(
          keys: {
            for (final MapEntry(:key, :value) in c.keys.entries)
              key: param == null || param == key
                  ? moveKey(value, from, at)
                  : value,
          },
        ),
      ),
    );
  }

  /// The easing from [id]'s keyframe at [frame] to the next; it becomes
  /// the one new keyframes take.
  void setEasing(String id, int frame, KeyEasing easing, {String? param}) {
    lastEasing = easing;
    _keys(
      id,
      (c) => {
        for (final MapEntry(:key, :value) in c.keys.entries)
          key: param == null || param == key
              ? [
                  for (final k in value)
                    k.frame == frame ? k.copyWith(easing: easing) : k,
                ]
              : value,
      },
    );
  }

  /// Every easing of [id] at once (Set all easings).
  void setAllEasings(String id, KeyEasing easing) {
    lastEasing = easing;
    _keys(
      id,
      (c) => {
        for (final MapEntry(:key, :value) in c.keys.entries)
          key: [for (final k in value) k.copyWith(easing: easing)],
      },
    );
  }

  /// [id]'s motion played backwards (mirrored over its length).
  void reverseMotion(String id) => _keys(
    id,
    (c) => {
      for (final MapEntry(:key, :value) in c.keys.entries)
        key: reverseKeys(value, 0, c.length - 1),
    },
  );

  void clearKeys(String id) => _keys(id, (_) => const {});

  void copyKeys(String id) {
    final c = content(id);
    if (c == null || !c.animated) return;
    final first = c.keyFrames.first;
    keyClipboard = c.shiftedKeys(-first);
    notifyListeners();
  }

  /// The copied keyframes on [id], the first at the playhead.
  void pasteKeys(String id) {
    final board = keyClipboard, c = content(id);
    if (board == null || c == null) return;
    final at = playhead.value - c.start;
    _keys(id, (c) {
      final next = {...c.keys};
      for (final MapEntry(:key, :value) in board.entries) {
        var keys = next[key] ?? const <Keyframe>[];
        for (final k in value) {
          keys = withKey(keys, k.copyWith(frame: k.frame + at));
        }
        next[key] = keys;
      }
      return next;
    });
  }

  void setFreeTrim(bool on) {
    freeTrim = on;
    notifyListeners();
  }

  /// The chosen contents, or [id] alone when it is not among them.
  Set<String> _targets(String? id) =>
      id == null || selection.contains(id) ? {...selection} : {id};

  /// [next] as one undo step, its new contents ([copies]: new id → the
  /// content it copies) given their originals' drawings.
  void _editCopies(MovieDocument next, Map<String, String> copies) {
    var copied = false;
    for (final MapEntry(key: copy, value: original) in copies.entries) {
      if (drawings[original] case final d?) {
        drawings[copy] = d;
        copied = true;
      }
    }
    if (copied) _drawingsDirty = true;
    edit(next);
  }

  void splitAtPlayhead(String id) {
    final copy = newId();
    _editCopies(_movie.split(id, playhead.value, copy), {copy: id});
  }

  void fillDuration(String id) => edit(_movie.fill(id));

  void duplicateAfter(String id) {
    final copy = newId();
    _editCopies(_movie.duplicateAfter(id, copy), {copy: id});
    select(copy);
  }

  void closeGaps(String trackId) => edit(_movie.closeGaps(trackId));

  void setHidden(String? id, bool hidden) => edit(
    _movie.updateContents(_targets(id), (c) => c.copyWith(hidden: hidden)),
  );

  /// The chosen contents' accent ([color] null: their kind's).
  void recolor(String? id, int? color) => edit(
    _movie.updateContents(
      _targets(id),
      (c) => c.copyWith(color: color, clearColor: color == null),
    ),
  );

  void renameContent(String id, String name) =>
      edit(_movie.updateContents({id}, (c) => c.copyWith(name: name)));

  void deleteContents(String? id) {
    final ids = _targets(id);
    if (ids.isEmpty) return;
    edit(_movie.deleteContents(ids));
  }

  void reverseSelection() => edit(_movie.reverseContents(selection));

  /// The chosen contents all longer (or shorter) by [delta] frames.
  void retimeSelection(int delta) => edit(_movie.retime(selection, delta));

  void copySelection({String? id}) {
    final ids = _targets(id);
    if (ids.isEmpty) return;
    clipboard = (
      clip: _movie.clip(ids),
      drawings: {for (final i in ids) i: ?drawings[i]},
    );
    notifyListeners();
  }

  void cutSelection({String? id}) {
    copySelection(id: id);
    deleteContents(id);
  }

  /// The clipboard at the playhead, on the tracks it came from.
  void paste() {
    final board = clipboard;
    if (board == null) return;
    final (next, copies) = _movie.paste(board.clip, playhead.value, newId);
    for (final MapEntry(key: copy, value: original) in copies.entries) {
      if (board.drawings[original] case final d?) {
        drawings[copy] = d;
        _drawingsDirty = true;
      }
    }
    edit(next);
    selectAll(copies.keys);
  }

  void duplicateTrack(String trackId, String name) {
    final (next, copies) = _movie.duplicateTrack(trackId, name, newId);
    _editCopies(next, copies);
  }

  void moveTrack(String trackId, {required bool up}) =>
      edit(_movie.moveTrack(trackId, up: up));

  void setTrackHidden(String trackId, bool hidden) =>
      edit(_movie.updateTrack(trackId, (t) => t.copyWith(hidden: hidden)));

  /// Track [trackId] grouped with the one below it (or that track's
  /// group, when it has one).
  void groupWithBelow(String trackId, String name) {
    final i = _movie.tracks.indexWhere((t) => t.id == trackId);
    if (i < 0 || i + 1 >= _movie.tracks.length) return;
    final below = _movie.tracks[i + 1];
    if (below.group case final existing?) {
      edit(_movie.updateTrack(trackId, (t) => t.copyWith(group: existing)));
      return;
    }
    edit(
      _movie.groupTracks({
        trackId,
        below.id,
      }, TrackGroup(id: newId(), name: name)),
    );
  }

  void ungroup(String groupId) => edit(_movie.ungroup(groupId));

  void updateGroup(
    String groupId,
    TrackGroup Function(TrackGroup group) change, {
    bool undoable = true,
  }) {
    final next = _movie.updateGroup(groupId, change);
    if (undoable) return edit(next);
    _movie = next;
    notifyListeners();
    unawaited(_save());
  }

  void seek(int frame) =>
      playhead.value = frame.clamp(0, math.max(0, _movie.frames - 1));

  void play() {
    if (playing.value) return;
    if (_movie.playback == PlaybackMode.oneShot &&
        playhead.value >= _movie.frames - 1) {
      seek(0);
    }
    _direction = 1;
    playing.value = true;
    _startTimer();
    _sound(playhead.value);
  }

  /// The playhead flung back: from the first frame.
  void playFromStart() {
    stop();
    seek(0);
    play();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (playing.value) _quiet();
    playing.value = false;
  }

  void togglePlay() => playing.value ? stop() : play();

  void _startTimer() {
    _timer?.cancel();
    _timerFps = _movie.fps;
    _timer = Timer.periodic(
      Duration(microseconds: 1000000 ~/ _movie.fps),
      (_) => _tick(),
    );
  }

  void _tick() {
    final last = _movie.frames - 1;
    var next = playhead.value + _direction;
    switch (_movie.playback) {
      case PlaybackMode.loop:
        if (next > last) {
          next = 0;
          _sound(0);
        }
      case PlaybackMode.pingPong:
        // Sound plays forward only: quiet on the way back.
        if (next > last) {
          _direction = -1;
          next = math.max(0, last - 1);
          _quiet();
        } else if (next < 0) {
          _direction = 1;
          next = math.min(1, last);
          _sound(next);
        }
      case PlaybackMode.oneShot:
        if (next > last) {
          stop();
          return;
        }
    }
    playhead.value = next;
    if (_direction == 1) _follow();
  }

  /// A new track on top, holding one [kind] content [name] from the
  /// playhead for two seconds (or to the end of the movie).
  void addTrack(TrackKind kind, String name) {
    final start = playhead.value;
    final content = MovieContent(
      id: newId(),
      name: name,
      kind: kind,
      start: start,
      length: math.max(1, math.min(_movie.fps * 2, _movie.frames - start)),
    );
    edit(
      _movie.copyWith(
        tracks: [
          MovieTrack(id: newId(), name: name, kind: kind, contents: [content]),
          ..._movie.tracks,
        ],
      ),
    );
    select(content.id);
  }

  void renameTrack(String id, String name) => edit(
    _movie.copyWith(
      tracks: [
        for (final t in _movie.tracks) t.id == id ? t.copyWith(name: name) : t,
      ],
    ),
  );

  void deleteTrack(String id) => edit(
    _movie.copyWith(tracks: [..._movie.tracks.where((t) => t.id != id)]),
  );

  /// Settings from the settings dialog, as one undo step.
  void applySettings(MovieDocument next) => edit(
    next.copyWith(
      tracks: _movie.tracks,
      playback: _movie.playback,
      view: _movie.view,
    ),
  );

  /// Writes a layout change that has not been saved yet.
  Future<void> flush() async {
    if (_viewSave == null) return;
    _viewSave!.cancel();
    _viewSave = null;
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _takeTimer?.cancel();
    if (_viewSave != null) {
      _viewSave!.cancel();
      unawaited(storage.saveMovie(_movie));
    }
    playhead.dispose();
    playing.dispose();
    frames.dispose();
    media.dispose();
    audio.release().catchError((_) {});
    super.dispose();
  }
}
