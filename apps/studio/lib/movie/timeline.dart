import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../domain/movie.dart';
import '../domain/movie_edits.dart';
import '../editor/overlay_bar.dart';
import '../l10n/app_localizations.dart';
import '../editor/value_slider.dart';
import '../editor/layers_panel.dart' show layerBlendName;
import 'live_filters.dart';
import 'media_cache.dart';
import 'text_content.dart';
import 'movie_controller.dart';
import 'movie_screen.dart' show trackIcon;

const _rulerHeight = 28.0, _headerWidth = 132.0, _tail = 96.0;

Color contentColor(TrackKind kind) => switch (kind) {
  TrackKind.flipbook => const Color(0xff2f8f83),
  TrackKind.drawing => const Color(0xff7457c9),
  TrackKind.video => const Color(0xff3b6fb6),
  TrackKind.audio => const Color(0xffb7742c),
  TrackKind.text => const Color(0xff4b8a3c),
};

/// The movie's timeline: transport and zoom on top; the ruler and the
/// tracks (top track first) with their contents; the playhead across
/// them.
class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.controller,
    required this.askName,
    this.onEdit,
  });
  final MovieController controller;
  final Future<String?> Function(String current) askName;
  final void Function(String id)? onEdit;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  final _h = ScrollController(), _body = ScrollController();
  final _headers = ScrollController();
  final _pointers = <int, Offset>{};
  ({Offset a, Offset b, TimelineView view, double frame})? _pinch;
  ({String id, Duration at})? _lastTap;

  /// A key a content block, so it keeps its drag when it changes rows.
  final _blockKeys = <String, GlobalKey>{};
  final _clock = Stopwatch()..start();

  MovieController get c => widget.controller;
  TimelineView get view => c.movie.view;

  @override
  void initState() {
    super.initState();
    _body.addListener(() {
      if (_headers.hasClients) _headers.jumpTo(_body.offset);
    });
  }

  @override
  void dispose() {
    _h.dispose();
    _body.dispose();
    _headers.dispose();
    super.dispose();
  }

  double get _offset => _h.hasClients ? _h.offset : 0;

  int _frameAt(double x) => ((_offset + x) / view.framePixels).floor();

  /// The time zoom at [framePixels], frame [anchor] kept under [x].
  void _zoomTime(double framePixels, {double? x, double? anchor}) {
    final at = x ?? 0;
    final frame = anchor ?? (_offset + at) / view.framePixels;
    c.setView(view.copyWith(framePixels: framePixels));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_h.hasClients) return;
      _h.jumpTo(
        (frame * view.framePixels - at).clamp(0, _h.position.maxScrollExtent),
      );
    });
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final [a, b] = _pointers.values.toList();
      setState(
        () => _pinch = (
          a: a,
          b: b,
          view: view,
          frame: (_offset + (a.dx + b.dx) / 2) / view.framePixels,
        ),
      );
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final pinch = _pinch;
    if (pinch == null || _pointers.length != 2) return;
    final [a, b] = _pointers.values.toList();
    double scale(double from, double to) => from < 24 ? 1 : to / from;
    final sx = scale((pinch.a.dx - pinch.b.dx).abs(), (a.dx - b.dx).abs());
    final sy = scale((pinch.a.dy - pinch.b.dy).abs(), (a.dy - b.dy).abs());
    final focus = (a.dx + b.dx) / 2;
    c.setView(view.copyWith(trackHeight: pinch.view.trackHeight * sy));
    _zoomTime(pinch.view.framePixels * sx, x: focus, anchor: pinch.frame);
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinch != null) setState(() => _pinch = null);
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _zoomTime(
        view.framePixels * math.exp(-e.scrollDelta.dy / 240),
        x: e.localPosition.dx,
      );
    });
  }

  static const _groupHeight = 28.0, _handle = 12.0, _lane = 22.0;

  /// Contents whose keyframes show one parameter a lane.
  final _expanded = <String>{};
  ({MovieDocument base, String id, int from, String? param})? _keyDrag;

  /// The parameter lanes under track [t] (keyframe mode, contents of it
  /// expanded): Move & Scale first, then the rest as they come.
  List<String> _laneParams(MovieTrack t) {
    if (!c.keyframing) return const [];
    final ids = <String>{
      for (final x in t.contents)
        if (_expanded.contains(x.id))
          for (final MapEntry(:key, :value) in x.keys.entries)
            if (value.isNotEmpty) key,
    };
    return [
      for (final p in MoveParam.values)
        if (ids.contains(p.name)) p.name,
      ...ids.where((id) => !MoveParam.values.any((p) => p.name == id)),
    ];
  }

  bool _lanes(MovieTrack t) => _laneParams(t).isNotEmpty;

  /// The rows top to bottom: group headers and the tracks not folded away.
  List<({MovieTrack? track, TrackGroup? group, double height})> _rows(
    MovieDocument movie,
  ) {
    final rows = <({MovieTrack? track, TrackGroup? group, double height})>[];
    final seen = <String>{};
    for (final t in movie.tracks) {
      final group = movie.groupById(t.group);
      if (group != null && seen.add(group.id)) {
        rows.add((track: null, group: group, height: _groupHeight));
      }
      if (group?.collapsed ?? false) continue;
      rows.add((
        track: t,
        group: null,
        height: view.trackHeight + _laneParams(t).length * _lane,
      ));
    }
    return rows;
  }

  ({MovieDocument base, Set<String> ids, Offset total, String grabbed})?
  _moving;
  ({MovieDocument base, String id, bool end, double total})? _trimming;

  /// Where the finger came down: drags count from there, not from where
  /// the gesture was recognised.
  Offset? _downAt;
  ({Offset from, Offset to, Set<String> base})? _lasso;

  void _beginMove(MovieContent content) {
    c.stop();
    _moving = (
      base: c.movie,
      ids: c.selection.contains(content.id) ? {...c.selection} : {content.id},
      total: Offset.zero,
      grabbed: content.id,
    );
  }

  void _updateMove(DragUpdateDetails d) {
    final m = _moving;
    if (m == null) return;
    final total = d.globalPosition - (_downAt ?? d.globalPosition);
    _moving = (base: m.base, ids: m.ids, total: total, grabbed: m.grabbed);
    final delta = (total.dx / view.framePixels).round();
    final rows = total.dy / view.trackHeight;
    // Halfway between two tracks: onto a new track there.
    final between = (rows - rows.floorToDouble() - .5).abs() < .2;
    final MovieDocument? next;
    if (between) {
      final from = m.base.trackIndexOf(m.grabbed);
      final origin = m.base.tracks[from];
      next = m.base.moveToNewTrack(
        m.ids,
        delta,
        from + rows.floor() + 1,
        MovieTrack(id: newId(), name: origin.name, kind: origin.kind),
      );
    } else {
      next = m.base.moveContents(m.ids, delta, rows: rows.round());
    }
    if (next != null) c.preview(next);
  }

  void _beginTrim(MovieContent content, {required bool end}) {
    c.stop();
    _trimming = (base: c.movie, id: content.id, end: end, total: 0);
  }

  void _updateTrim(DragUpdateDetails d) {
    final t = _trimming;
    if (t == null) return;
    final total = (d.globalPosition - (_downAt ?? d.globalPosition)).dx;
    _trimming = (base: t.base, id: t.id, end: t.end, total: total);
    final frames = (total / view.framePixels).round();
    final was = t.base.contentById(t.id)!;
    c.preview(
      !t.end
          ? t.base.trimStart(t.id, was.start + frames)
          : c.selection.length > 1 && c.selection.contains(t.id)
          ? t.base.retime(c.selection, frames)
          : t.base.trimEnd(t.id, was.end + frames, ripple: c.freeTrim),
    );
  }

  void _endDrag() {
    _moving = null;
    _trimming = null;
    c.commitPreview();
  }

  void _lassoTo(Offset to, MovieDocument movie) {
    final lasso = _lasso;
    if (lasso == null) return;
    setState(() => _lasso = (from: lasso.from, to: to, base: lasso.base));
    final box = Rect.fromPoints(lasso.from, to);
    final fp = view.framePixels;
    final hits = <String>{};
    var top = 0.0;
    for (final row in _rows(movie)) {
      if (row.track case final t?) {
        for (final content in t.contents) {
          final rect = Rect.fromLTWH(
            content.start * fp,
            top + 4,
            content.length * fp,
            row.height - 8,
          );
          if (rect.overlaps(box)) hits.add(content.id);
        }
      }
      top += row.height;
    }
    c.selectAll({...lasso.base, ...hits});
  }

  Future<void> _contentMenu(
    MovieContent content,
    MovieTrack track,
    Offset at,
  ) async {
    final l = AppLocalizations.of(context);
    if (!c.selection.contains(content.id)) c.select(content.id);
    final inside =
        content.sourceFrame(c.playhead.value) != null &&
        c.playhead.value > content.start;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (content.kind == TrackKind.text && c.textOf(content.id) != null)
          PopupMenuItem(value: 'text', child: Text(l.textEdit)),
        if (widget.onEdit != null)
          PopupMenuItem(value: 'edit', child: Text(l.contentDraw)),
        PopupMenuItem(
          value: 'split',
          enabled: inside,
          child: Text(l.contentSplit),
        ),
        PopupMenuItem(value: 'fill', child: Text(l.contentFill)),
        PopupMenuItem(value: 'duplicate', child: Text(l.contentDuplicateAfter)),
        PopupMenuItem(
          value: 'hide',
          child: Text(content.hidden ? l.contentShow : l.contentHide),
        ),
        PopupMenuItem(value: 'rename', child: Text(l.contentRename)),
        PopupMenuItem(value: 'look', child: Text(l.contentLook)),
        if (content.kind == TrackKind.video && !content.muted)
          PopupMenuItem(value: 'separate', child: Text(l.separateAudio)),
        if (content.kind == TrackKind.flipbook &&
            (c.drawings[content.id]?.animating ?? false))
          PopupMenuItem(value: 'toDrawings', child: Text(l.toDrawings)),
        if (c.selection.length > 1)
          PopupMenuItem(value: 'toFlipbook', child: Text(l.toFlipbook)),
        PopupMenuItem(value: 'color', child: Text(l.contentColor)),
        PopupMenuItem(value: 'copy', child: Text(l.copy)),
        PopupMenuItem(value: 'cut', child: Text(l.cut)),
        if (c.selection.length > 1)
          PopupMenuItem(value: 'reverse', child: Text(l.contentReverse)),
        PopupMenuItem(value: 'gaps', child: Text(l.trackCloseGaps)),
        PopupMenuItem(value: 'delete', child: Text(l.galleryDelete)),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'text':
        await editTextContent(context, c, content.id);
      case 'edit':
        widget.onEdit?.call(content.id);
      case 'split':
        c.splitAtPlayhead(content.id);
      case 'fill':
        c.fillDuration(content.id);
      case 'duplicate':
        c.duplicateAfter(content.id);
      case 'hide':
        c.setHidden(content.id, !content.hidden);
      case 'rename':
        final name = (await widget.askName(content.name))?.trim();
        if (name != null && name.isNotEmpty) {
          c.renameContent(content.id, name);
        }
      case 'look':
        await _lookDialog(content);
      case 'separate':
        c.separateAudio(content.id, l.trackSound);
      case 'toDrawings':
        c.flipbookToDrawings(content.id, (n) => l.frameName(n));
      case 'toFlipbook':
        if (!c.drawingsToFlipbook({...c.selection}, l.movieStartFlipbook) &&
            mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.cannotFlipbook)));
        }
      case 'color':
        await _pickColor(content.id);
      case 'copy':
        c.copySelection(id: content.id);
      case 'cut':
        c.cutSelection(id: content.id);
      case 'reverse':
        c.reverseSelection();
      case 'gaps':
        c.closeGaps(track.id);
      case 'delete':
        c.deleteContents(content.id);
    }
  }

  /// [content]'s (and the other chosen ones') opacity, blend mode and
  /// mask, set at once.
  Future<void> _lookDialog(MovieContent content) async {
    final l = AppLocalizations.of(context);
    var opacity = content.opacity;
    var blend = content.blend;
    var mask = content.mask;
    var invert = content.maskInvert;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          key: const ValueKey('look-dialog'),
          title: Text(l.contentLook),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueSlider(
                  id: 'look-opacity',
                  label: l.opacity,
                  value: opacity,
                  onChanged: (v) => setInner(() => opacity = v),
                ),
                DropdownButtonFormField<LayerBlend>(
                  key: const ValueKey('look-blend'),
                  initialValue: blend,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.blendMode),
                  items: [
                    for (final b in LayerBlend.values)
                      DropdownMenuItem(
                        value: b,
                        child: Text(layerBlendName(l, b)),
                      ),
                  ],
                  onChanged: (b) => setInner(() => blend = b!),
                ),
                const SizedBox(height: 12),
                Text(l.maskOver, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                SegmentedButton<ContentMask>(
                  key: const ValueKey('look-mask'),
                  showSelectedIcon: false,
                  segments: [
                    for (final (m, name) in [
                      (ContentMask.none, l.maskNone),
                      (ContentMask.clip, l.maskClip),
                      (ContentMask.alpha, l.maskAlpha),
                      (ContentMask.luma, l.maskLuma),
                    ])
                      ButtonSegment(value: m, label: Text(name)),
                  ],
                  selected: {mask},
                  onSelectionChanged: (m) => setInner(() => mask = m.single),
                ),
                if (mask == ContentMask.alpha || mask == ContentMask.luma)
                  SwitchListTile.adaptive(
                    key: const ValueKey('look-invert'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.maskInvert),
                    value: invert,
                    onChanged: (v) => setInner(() => invert = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('look-done'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.done),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    c.setLook(
      content.id,
      opacity: opacity,
      blend: blend,
      mask: mask,
      maskInvert: invert,
    );
  }

  /// Group [g]'s blend mode (or Passthrough) and opacity.
  Future<void> _groupLook(TrackGroup g) async {
    final l = AppLocalizations.of(context);
    var opacity = g.opacity;
    var blend = g.blend;
    var through = g.passthrough;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(g.name),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('group-passthrough'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.passthrough),
                  value: through,
                  onChanged: (v) => setInner(() => through = v),
                ),
                if (!through) ...[
                  ValueSlider(
                    id: 'group-opacity',
                    label: l.opacity,
                    value: opacity,
                    onChanged: (v) => setInner(() => opacity = v),
                  ),
                  DropdownButtonFormField<LayerBlend>(
                    initialValue: blend,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.blendMode),
                    items: [
                      for (final b in LayerBlend.values)
                        DropdownMenuItem(
                          value: b,
                          child: Text(layerBlendName(l, b)),
                        ),
                    ],
                    onChanged: (b) => setInner(() => blend = b!),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('group-look-done'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.done),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    c.updateGroup(
      g.id,
      (g) => g.copyWith(opacity: opacity, blend: blend, passthrough: through),
    );
  }

  static const _accents = [
    0xffd94848, 0xffe08a2e, 0xffd7b532, 0xff4caf6a, 0xff2f8f83, //
    0xff3b82c4, 0xff7457c9, 0xffc457a8, 0xff7a7a7a,
  ];

  Future<void> _pickColor(String? id) async {
    final l = AppLocalizations.of(context);
    final color = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.contentColor),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final accent in _accents)
              InkWell(
                key: ValueKey('accent-$accent'),
                onTap: () => Navigator.pop(context, accent),
                child: CircleAvatar(backgroundColor: Color(accent), radius: 16),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: Text(l.contentColorDefault),
          ),
        ],
      ),
    );
    if (color == null) return;
    c.recolor(id, color == 0 ? null : color);
  }

  /// A picture, video or sound file onto a new track at the playhead.
  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...MovieController.pictureTypes,
        ...MovieController.videoTypes,
        ...MovieController.soundTypes,
      ],
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    final ext = (file.extension ?? '').toLowerCase();
    final dot = file.name.lastIndexOf('.');
    final name = dot > 0 ? file.name.substring(0, dot) : file.name;
    var ok = false;
    try {
      if (MovieController.pictureTypes.contains(ext)) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in file.readAsByteStream()) {
          bytes.add(chunk);
          if (bytes.length > 64 * 1024 * 1024) {
            throw const FileSystemException();
          }
        }
        ok = await c.importPicture(bytes.takeBytes(), name);
      } else {
        var path = file.path;
        File? copy;
        if (path == null) {
          // Not a local file (an Android content address): copied first.
          copy = File(
            '${Directory.systemTemp.path}/artblend-import-${DateTime.now().microsecondsSinceEpoch}.$ext',
          );
          final sink = copy.openWrite();
          await sink.addStream(file.readAsByteStream());
          await sink.close();
          path = copy.path;
        }
        ok = await c.importMedia(path, name);
        await copy?.delete();
      }
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.importFailed)));
    }
  }

  Future<void> _trackMenu(MovieTrack track, String action) async {
    final l = AppLocalizations.of(context);
    switch (action) {
      case 'delete':
        c.deleteTrack(track.id);
      case 'duplicate':
        c.duplicateTrack(track.id, l.layerCopy(track.name));
      case 'up':
        c.moveTrack(track.id, up: true);
      case 'down':
        c.moveTrack(track.id, up: false);
      case 'group':
        c.groupWithBelow(track.id, l.groupDefault);
      case 'gaps':
        c.closeGaps(track.id);
      case 'rename':
        final name = (await widget.askName(track.name))?.trim();
        if (name != null && name.isNotEmpty) c.renameTrack(track.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final movie = c.movie;
        final fp = view.framePixels;
        final width = movie.frames * fp + _tail;
        final rows = _rows(movie);
        final lasso = _lasso;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(l, movie),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _headerWidth,
                    child: Column(
                      children: [
                        const SizedBox(height: _rulerHeight),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _headers,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                for (final row in rows)
                                  if (row.group case final g?)
                                    _groupHeader(l, scheme, g)
                                  else
                                    _header(l, scheme, row.track!, movie),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Stack(
                        children: [
                          Column(
                            children: [
                              _ruler(movie, scheme, box.maxWidth),
                              Expanded(
                                child: Listener(
                                  onPointerDown: _down,
                                  onPointerMove: _move,
                                  onPointerUp: _up,
                                  onPointerCancel: _up,
                                  onPointerSignal: _signal,
                                  child: SingleChildScrollView(
                                    key: const ValueKey('timeline-tracks'),
                                    controller: _h,
                                    scrollDirection: Axis.horizontal,
                                    physics: _pinch != null || c.choosing
                                        ? const NeverScrollableScrollPhysics()
                                        : null,
                                    child: SizedBox(
                                      width: math.max(width, box.maxWidth),
                                      child: SingleChildScrollView(
                                        controller: _body,
                                        physics: _pinch != null || c.choosing
                                            ? const NeverScrollableScrollPhysics()
                                            : null,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onPanStart: c.choosing
                                              ? (d) => setState(
                                                  () => _lasso = (
                                                    from: d.localPosition,
                                                    to: d.localPosition,
                                                    base: {...c.selection},
                                                  ),
                                                )
                                              : null,
                                          onPanUpdate: c.choosing
                                              ? (d) => _lassoTo(
                                                  d.localPosition,
                                                  movie,
                                                )
                                              : null,
                                          onPanEnd: c.choosing
                                              ? (_) => setState(
                                                  () => _lasso = null,
                                                )
                                              : null,
                                          child: Stack(
                                            children: [
                                              Column(
                                                children: [
                                                  for (final row in rows)
                                                    if (row.track case final t?)
                                                      _row(t, movie, scheme)
                                                    else
                                                      Container(
                                                        height: _groupHeight,
                                                        color: scheme
                                                            .surfaceContainerHighest,
                                                      ),
                                                  SizedBox(
                                                    height: view.trackHeight,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTapUp: (d) {
                                                        c.select(null);
                                                        c.seek(
                                                          (d.localPosition.dx /
                                                                  fp)
                                                              .floor(),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (lasso != null)
                                                Positioned.fromRect(
                                                  rect: Rect.fromPoints(
                                                    lasso.from,
                                                    lasso.to,
                                                  ),
                                                  child: IgnorePointer(
                                                    child: DecoratedBox(
                                                      key: const ValueKey(
                                                        'timeline-lasso',
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: scheme.primary
                                                            .withValues(
                                                              alpha: .12,
                                                            ),
                                                        border: Border.all(
                                                          color: scheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _PlayheadPainter(
                                  c.playhead,
                                  _h,
                                  fp,
                                  scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(AppLocalizations l, MovieDocument movie) {
    final chosen = c.selection.isNotEmpty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: c.playing,
            builder: (context, playing, _) => IconButton(
              key: const ValueKey('timeline-play'),
              tooltip: playing ? l.stop : l.timelapsePlay,
              onPressed: c.togglePlay,
              icon: Icon(
                playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('timeline-from-start'),
            tooltip: l.timelinePlayFromStart,
            onPressed: c.playFromStart,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          ValueListenableBuilder(
            valueListenable: c.playhead,
            builder: (context, frame, _) => Text(
              '${timecode(frame, movie.fps)} / '
              '${timecode(movie.frames, movie.fps)}',
              key: const ValueKey('timeline-timecode'),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (final (mode, icon, label) in [
            (PlaybackMode.loop, Icons.repeat_rounded, l.playbackLoop),
            (PlaybackMode.pingPong, Icons.sync_alt_rounded, l.playbackPingPong),
            (
              PlaybackMode.oneShot,
              Icons.arrow_right_alt_rounded,
              l.playbackOneShot,
            ),
          ])
            IconButton(
              key: ValueKey('timeline-mode-${mode.name}'),
              tooltip: label,
              isSelected: movie.playback == mode,
              onPressed: () => c.setPlayback(mode),
              icon: Icon(icon, size: 20),
            ),
          const SizedBox(width: 16),
          IconButton(
            key: const ValueKey('timeline-choose'),
            tooltip: l.timelineChoose,
            isSelected: c.choosing,
            onPressed: () => c.setChoosing(!c.choosing),
            icon: const Icon(Icons.checklist_rounded),
          ),
          IconButton(
            key: const ValueKey('timeline-keyframes'),
            tooltip: '${l.keyframeMode}\n\n${l.keyframeHint}',
            isSelected: c.keyframing,
            onPressed: () => c.setKeyframing(!c.keyframing),
            icon: const Icon(Icons.key_rounded),
          ),
          if (c.keyframing)
            IconButton(
              key: const ValueKey('timeline-actions'),
              tooltip: l.keyframeActions,
              onPressed: c.selected == null ? null : _actions,
              icon: const Icon(Icons.bolt_rounded),
            ),
          IconButton(
            key: const ValueKey('timeline-perform'),
            tooltip: '${l.performMode}\n\n${l.performHint}',
            isSelected: c.performing,
            color: c.performing ? Colors.red : null,
            onPressed: () => c.setPerforming(!c.performing),
            icon: const Icon(Icons.fiber_manual_record_outlined),
          ),
          if (c.performing)
            IconButton(
              key: const ValueKey('perform-filter'),
              tooltip: l.motionFilter,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l.motionFilter),
                  content: SizedBox(
                    width: 320,
                    child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => ValueSlider(
                        id: 'motion-filter',
                        label: l.motionFilter,
                        value: c.motionFilter,
                        onChanged: c.setMotionFilter,
                      ),
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.done),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.blur_linear_rounded),
            ),
          IconButton(
            key: const ValueKey('timeline-free-trim'),
            tooltip: l.timelineFreeTrim,
            isSelected: c.freeTrim,
            onPressed: () => c.setFreeTrim(!c.freeTrim),
            icon: const Icon(Icons.compare_arrows_rounded),
          ),
          if (chosen) ...[
            IconButton(
              key: const ValueKey('timeline-copy'),
              tooltip: l.copy,
              onPressed: c.copySelection,
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              key: const ValueKey('timeline-cut'),
              tooltip: l.cut,
              onPressed: c.cutSelection,
              icon: const Icon(Icons.content_cut_rounded),
            ),
          ],
          IconButton(
            key: const ValueKey('timeline-paste'),
            tooltip: l.timelinePaste,
            onPressed: c.clipboard == null ? null : c.paste,
            icon: const Icon(Icons.content_paste_rounded),
          ),
          if (chosen) ...[
            if (c.selection.length > 1)
              IconButton(
                key: const ValueKey('timeline-reverse'),
                tooltip: l.contentReverse,
                onPressed: c.reverseSelection,
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
            IconButton(
              key: const ValueKey('timeline-color'),
              tooltip: l.contentColor,
              onPressed: () => _pickColor(null),
              icon: const Icon(Icons.palette_outlined),
            ),
            IconButton(
              key: const ValueKey('timeline-delete'),
              tooltip: l.galleryDelete,
              onPressed: () => c.deleteContents(null),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
          const SizedBox(width: 16),
          IconButton(
            key: const ValueKey('timeline-import'),
            tooltip: l.timelineImport,
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined),
          ),
          PopupMenuButton<TrackKind>(
            key: const ValueKey('timeline-add-track'),
            tooltip: l.timelineAddTrack,
            icon: const Icon(Icons.playlist_add_rounded),
            onSelected: (kind) async {
              if (kind != TrackKind.text) {
                return c.addTrack(
                  kind,
                  kind == TrackKind.flipbook
                      ? l.movieStartFlipbook
                      : l.trackDrawing,
                );
              }
              final text = await showDialog<LayerText>(
                context: context,
                builder: (_) => TextContentDialog(
                  text: c.newText(l.textPlaceholder),
                  recent: const [],
                ),
              );
              if (text != null) c.addText(text, l.trackText);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: TrackKind.drawing,
                child: Text(l.trackDrawing),
              ),
              PopupMenuItem(
                value: TrackKind.flipbook,
                child: Text(l.movieStartFlipbook),
              ),
              PopupMenuItem(value: TrackKind.text, child: Text(l.trackText)),
            ],
          ),
          IconButton(
            key: const ValueKey('timeline-zoom-out'),
            tooltip: l.timelineZoomOut,
            onPressed: () => _zoomTime(view.framePixels / 1.5),
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          IconButton(
            key: const ValueKey('timeline-zoom-in'),
            tooltip: l.timelineZoomIn,
            onPressed: () => _zoomTime(view.framePixels * 1.5),
            icon: const Icon(Icons.zoom_in_rounded),
          ),
          barHint('${l.timelineHint}\n\n${l.contentHint}'),
        ],
      ),
    );
  }

  Widget _ruler(MovieDocument movie, ColorScheme scheme, double width) =>
      GestureDetector(
        key: const ValueKey('timeline-ruler'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => c.seek(_frameAt(d.localPosition.dx)),
        onHorizontalDragStart: (d) {
          c.stop();
          c.seek(_frameAt(d.localPosition.dx));
        },
        onHorizontalDragUpdate: (d) {
          c.seek(_frameAt(d.localPosition.dx));
          c.scrub();
        },
        onHorizontalDragEnd: (d) {
          if (d.velocity.pixelsPerSecond.dx < -1200) c.playFromStart();
        },
        child: SizedBox(
          height: _rulerHeight,
          width: width,
          child: CustomPaint(
            painter: _RulerPainter(
              _h,
              movie.fps,
              movie.frames,
              view.framePixels,
              scheme.onSurfaceVariant,
            ),
          ),
        ),
      );

  Widget _groupHeader(AppLocalizations l, ColorScheme scheme, TrackGroup g) =>
      Container(
        key: ValueKey('group-${g.id}'),
        height: _groupHeight,
        color: scheme.surfaceContainerHighest,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 28,
              child: IconButton(
                key: ValueKey('group-fold-${g.id}'),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: l.groupFold,
                padding: EdgeInsets.zero,
                iconSize: 18,
                onPressed: () => c.updateGroup(
                  g.id,
                  (g) => g.copyWith(collapsed: !g.collapsed),
                  undoable: false,
                ),
                icon: Icon(
                  g.collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                ),
              ),
            ),
            Expanded(
              child: Text(
                g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              height: 28,
              child: IconButton(
                key: ValueKey('group-eye-${g.id}'),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: l.trackVisibility,
                padding: EdgeInsets.zero,
                iconSize: 16,
                onPressed: () =>
                    c.updateGroup(g.id, (g) => g.copyWith(hidden: !g.hidden)),
                icon: Icon(
                  g.hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            SizedBox(
              width: 32,
              height: 28,
              child: PopupMenuButton<String>(
                key: ValueKey('group-menu-${g.id}'),
                iconSize: 16,
                padding: EdgeInsets.zero,
                onSelected: (action) async {
                  if (action == 'ungroup') return c.ungroup(g.id);
                  if (action == 'look') return _groupLook(g);
                  final name = (await widget.askName(g.name))?.trim();
                  if (name != null && name.isNotEmpty) {
                    c.updateGroup(g.id, (g) => g.copyWith(name: name));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text(l.rename)),
                  PopupMenuItem(value: 'look', child: Text(l.contentLook)),
                  PopupMenuItem(value: 'ungroup', child: Text(l.ungroup)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _header(
    AppLocalizations l,
    ColorScheme scheme,
    MovieTrack t,
    MovieDocument movie,
  ) {
    final index = movie.tracks.indexOf(t);
    final header = SizedBox(
      key: ValueKey('track-${t.id}'),
      height: view.trackHeight,
      child: Opacity(
        opacity: movie.trackShows(t) ? 1 : .5,
        child: Row(
          children: [
            SizedBox(width: t.group == null ? 6 : 16),
            Icon(trackIcon(t.kind), size: 16, color: contentColor(t.kind)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              key: ValueKey('track-eye-${t.id}'),
              tooltip: l.trackVisibility,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              iconSize: 16,
              onPressed: () => c.setTrackHidden(t.id, !t.hidden),
              icon: Icon(
                t.hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('track-menu-${t.id}'),
              iconSize: 18,
              padding: EdgeInsets.zero,
              onSelected: (action) => _trackMenu(t, action),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l.rename)),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(l.trackDuplicate),
                ),
                PopupMenuItem(
                  value: 'up',
                  enabled: index > 0,
                  child: Text(l.trackUp),
                ),
                PopupMenuItem(
                  value: 'down',
                  enabled: index < movie.tracks.length - 1,
                  child: Text(l.trackDown),
                ),
                PopupMenuItem(
                  value: 'group',
                  enabled: index < movie.tracks.length - 1,
                  child: Text(l.trackGroup),
                ),
                PopupMenuItem(value: 'gaps', child: Text(l.trackCloseGaps)),
                PopupMenuItem(value: 'delete', child: Text(l.trackDelete)),
              ],
            ),
          ],
        ),
      ),
    );
    if (!_lanes(t)) return header;
    return Column(
      children: [
        header,
        for (final p in _laneParams(t))
          Container(
            height: _lane,
            padding: const EdgeInsets.only(left: 28),
            alignment: Alignment.centerLeft,
            color: scheme.surfaceContainerLow,
            child: Text(
              _paramName(l, p, t),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// A lane's name: Move & Scale's own, a filter's setting, a mesh point.
  static String _paramName(AppLocalizations l, String id, MovieTrack t) =>
      switch (MoveParam.values.asNameMap()[id]) {
        MoveParam.x => l.paramX,
        MoveParam.y => l.paramY,
        MoveParam.scale => l.paramScale,
        MoveParam.rotation => l.paramRotation,
        null => keyLabel(
          l,
          t.contents.where((x) => x.keys.containsKey(id)).firstOrNull,
          id,
        ),
      };

  static String _easingName(AppLocalizations l, KeyEasing e) => switch (e) {
    KeyEasing.linear => l.easingLinear,
    KeyEasing.easeIn => l.easingIn,
    KeyEasing.easeOut => l.easingOut,
    KeyEasing.easeInOut => l.easingInOut,
  };

  Widget _row(MovieTrack t, MovieDocument movie, ColorScheme scheme) {
    if (!_lanes(t)) return _track(t, movie, scheme);
    final fp = view.framePixels;
    return Column(
      children: [
        _track(t, movie, scheme),
        for (final p in _laneParams(t))
          Container(
            key: ValueKey('lane-${t.id}-$p'),
            height: _lane,
            color: scheme.surfaceContainerLow,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final content in t.contents)
                  if (_expanded.contains(content.id))
                    for (final k in content.keys[p] ?? const <Keyframe>[])
                      Positioned(
                        left: (content.start + k.frame) * fp - 7,
                        top: 4,
                        child: _diamond(content, k.frame, p),
                      ),
              ],
            ),
          ),
      ],
    );
  }

  /// A keyframe of [content] at [frame] (from its start), of [param] or of
  /// all its parameters: tap to go there, drag to retime, hold for more.
  Widget _diamond(MovieContent content, int frame, String? param) {
    final scheme = Theme.of(context).colorScheme;
    final on = c.playhead.value == content.start + frame;
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 3)),
      child: GestureDetector(
        key: ValueKey(
          'key-${content.id}-$frame${param == null ? '' : '-$param'}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          c.stop();
          c.select(content.id);
          c.seek(content.start + frame);
        },
        onSecondaryTapUp: (d) =>
            _keyMenu(content, frame, param, d.globalPosition),
        onLongPressStart: (d) =>
            _keyMenu(content, frame, param, d.globalPosition),
        onHorizontalDragDown: (d) => _downAt = d.globalPosition,
        onHorizontalDragStart: (_) => _keyDrag = (
          base: c.movie,
          id: content.id,
          from: frame,
          param: param,
        ),
        onHorizontalDragUpdate: (d) {
          final drag = _keyDrag;
          if (drag == null) return;
          final by =
              ((d.globalPosition - (_downAt ?? d.globalPosition)).dx /
                      view.framePixels)
                  .round();
          c.dragKeys(
            drag.base,
            drag.id,
            drag.from,
            drag.from + by,
            param: drag.param,
          );
        },
        onHorizontalDragEnd: (_) {
          _keyDrag = null;
          c.commitPreview();
        },
        child: SizedBox(
          width: 14,
          height: 14,
          child: Center(
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: on ? scheme.primary : Colors.white,
                  border: Border.all(color: Colors.black54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _keyMenu(
    MovieContent content,
    int frame,
    String? param,
    Offset at,
  ) async {
    final l = AppLocalizations.of(context);
    final current =
        (param == null
                ? content.keys.values.expand((k) => k)
                : content.keys[param] ?? const <Keyframe>[])
            .where((k) => k.frame == frame)
            .firstOrNull
            ?.easing;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'delete', child: Text(l.keyDelete)),
        PopupMenuItem(enabled: false, child: Text(l.keyEasing)),
        for (final e in KeyEasing.values)
          CheckedPopupMenuItem(
            value: e,
            checked: e == current,
            child: Text(_easingName(l, e)),
          ),
        PopupMenuItem(
          value: 'expand',
          child: Text(
            _expanded.contains(content.id) ? l.keyCollapse : l.keyExpand,
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'delete':
        c.deleteKeys(content.id, frame, param: param);
      case final KeyEasing e:
        c.setEasing(content.id, frame, e, param: param);
      case 'expand':
        setState(
          () => _expanded.contains(content.id)
              ? _expanded.remove(content.id)
              : _expanded.add(content.id),
        );
    }
  }

  Future<void> _actions() async {
    final l = AppLocalizations.of(context);
    final id = c.selected;
    if (id == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero);
    final action = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx + 200, at.dy + 40, at.dx, 0),
      items: [
        PopupMenuItem(value: 'add', child: Text(l.keyAddMove)),
        PopupMenuItem(value: 'start', child: Text(l.keyAddStart)),
        PopupMenuItem(enabled: false, child: Text(l.keyAllEasings)),
        for (final e in KeyEasing.values)
          PopupMenuItem(value: e, child: Text('   ${_easingName(l, e)}')),
        PopupMenuItem(value: 'reverse', child: Text(l.keyReverse)),
        PopupMenuItem(value: 'copy', child: Text(l.keyCopy)),
        PopupMenuItem(
          value: 'paste',
          enabled: c.keyClipboard != null,
          child: Text(l.keyPaste),
        ),
        PopupMenuItem(value: 'clear', child: Text(l.keyClear)),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'add':
        c.addMoveKey(id);
      case 'start':
        c.addKeyAtStart(id);
      case final KeyEasing e:
        c.setAllEasings(id, e);
      case 'reverse':
        c.reverseMotion(id);
      case 'copy':
        c.copyKeys(id);
      case 'paste':
        c.pasteKeys(id);
      case 'clear':
        c.clearKeys(id);
    }
  }

  Widget _track(MovieTrack t, MovieDocument movie, ColorScheme scheme) {
    final fp = view.framePixels;
    return Container(
      height: view.trackHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                c.select(null);
                c.seek((d.localPosition.dx / fp).floor());
              },
            ),
          ),
          Positioned(
            left: movie.frames * fp,
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              child: ColoredBox(color: scheme.onSurface.withValues(alpha: .06)),
            ),
          ),
          for (final content in t.contents) _content(content, t, movie, scheme),
        ],
      ),
    );
  }

  Widget _content(
    MovieContent content,
    MovieTrack track,
    MovieDocument movie,
    ColorScheme scheme,
  ) {
    final fp = view.framePixels;
    final chosen = c.selection.contains(content.id);
    final color = content.color == null
        ? contentColor(content.kind)
        : Color(content.color!);
    final faded = content.hidden || !movie.trackShows(track);
    Widget handle({required bool end}) => Positioned(
      left: end ? null : 0,
      right: end ? 0 : null,
      top: 0,
      bottom: 0,
      width: _handle,
      child: GestureDetector(
        key: ValueKey('trim-${end ? 'end' : 'start'}-${content.id}'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragDown: (d) => _downAt = d.globalPosition,
        onHorizontalDragStart: (_) => _beginTrim(content, end: end),
        onHorizontalDragUpdate: _updateTrim,
        onHorizontalDragEnd: (_) => _endDrag(),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Center(
            child: Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      key: ValueKey('content-${content.id}'),
      left: content.start * fp,
      width: math.max(3, content.length * fp),
      top: 4,
      bottom: 4,
      // A chosen content's drag must win over the timeline's scrolling,
      // which takes a sideways drag at the touch slop: its pan (twice the
      // slop by default) gets a smaller one. Its global key keeps the drag
      // alive when it moves to another track's row.
      child: MediaQuery(
        key: _blockKeys.putIfAbsent(content.id, GlobalKey.new),
        data: MediaQuery.of(
          context,
        ).copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 6)),
        child: GestureDetector(
          onTapDown: (_) {
            final last = _lastTap, now = _clock.elapsed;
            _lastTap = (id: content.id, at: now);
            if (last != null &&
                last.id == content.id &&
                now - last.at < const Duration(milliseconds: 350)) {
              _lastTap = null;
              widget.onEdit?.call(content.id);
            }
          },
          onTap: () => c.select(content.id),
          onSecondaryTapUp: (d) =>
              _contentMenu(content, track, d.globalPosition),
          onLongPressStart: (d) =>
              _contentMenu(content, track, d.globalPosition),
          onPanDown: chosen ? (d) => _downAt = d.globalPosition : null,
          onPanStart: chosen ? (_) => _beginMove(content) : null,
          onPanUpdate: chosen ? _updateMove : null,
          onPanEnd: chosen ? (_) => _endDrag() : null,
          onPanCancel: chosen ? _endDrag : null,
          child: Opacity(
            opacity: faded ? .4 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
                border: chosen
                    ? Border.all(color: scheme.primary, width: 2.5)
                    : null,
              ),
              child: Stack(
                children: [
                  if (content.mediaId != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: CustomPaint(
                          painter: _MediaStrip(c, content, view.framePixels),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: chosen ? _handle : 6,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          content.name,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            decoration: content.hidden
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (chosen && content.length * fp >= _handle * 3) ...[
                    handle(end: false),
                    handle(end: true),
                  ],
                  if (c.keyframing)
                    for (final f in content.keyFrames)
                      if (f >= 0 && f < content.length)
                        Positioned(
                          left: f * fp - 7,
                          bottom: 2,
                          child: _diamond(content, f, null),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seconds (or frames, zoomed in) along the top, from the scroll offset.
class _RulerPainter extends CustomPainter {
  _RulerPainter(this.scroll, this.fps, this.frames, this.framePixels, this.ink)
    : super(repaint: scroll);
  final ScrollController scroll;
  final int fps, frames;
  final double framePixels;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final steps = rulerSteps(fps, framePixels);
    final paint = Paint()
      ..color = ink
      ..strokeWidth = 1;
    final first = (offset / framePixels / steps.minor).floor() * steps.minor;
    final last = math.min(frames, ((offset + size.width) / framePixels).ceil());
    for (var f = first; f <= last; f += steps.minor) {
      final x = f * framePixels - offset;
      final labelled = f % steps.label == 0;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - (labelled ? 12 : 5)),
        paint,
      );
      if (!labelled) continue;
      final text = steps.label < fps
          ? '$f'
          : steps.label % fps == 0 && f % fps == 0
          ? _seconds(f ~/ fps)
          : '$f';
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 10, color: ink),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x + 3, 2));
      painter.dispose();
    }
    final end = frames * framePixels - offset;
    canvas.drawLine(
      Offset(end, 0),
      Offset(end, size.height),
      paint..strokeWidth = 2,
    );
  }

  static String _seconds(int s) =>
      s < 60 ? '${s}s' : '${s ~/ 60}:${'${s % 60}'.padLeft(2, '0')}';

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.fps != fps ||
      old.frames != frames ||
      old.framePixels != framePixels ||
      old.ink != ink;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.playhead, this.scroll, this.framePixels, this.color)
    : super(repaint: Listenable.merge([playhead, scroll]));
  final ValueNotifier<int> playhead;
  final ScrollController scroll;
  final double framePixels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final x = (playhead.value + .5) * framePixels - offset;
    if (x < 0 || x > size.width) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    canvas.drawPath(
      Path()
        ..moveTo(x - 6, 0)
        ..lineTo(x + 6, 0)
        ..lineTo(x, 9)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.framePixels != framePixels || old.color != color;
}

/// Inside a video or sound content on the timeline: its pictures along
/// it, its waveform under them.
class _MediaStrip extends CustomPainter {
  _MediaStrip(this.c, this.content, this.framePixels)
    : super(repaint: Listenable.merge([c.media, c.frames]));
  final MovieController c;
  final MovieContent content;
  final double framePixels;

  @override
  void paint(Canvas canvas, Size size) {
    final id = content.mediaId!;
    final fps = c.movie.fps;
    double seconds(double x) => (content.sourceIn + x / framePixels) / fps;
    if (content.kind == TrackKind.video && c.media.proxies.containsKey(id)) {
      final tile = math.max(24.0, size.height * 16 / 9);
      for (var x = 0.0; x < size.width; x += tile) {
        final path = c.media.framePath(id, seconds(x));
        final image = path == null ? null : c.frames.fileImage(path);
        if (image == null) continue;
        final w = image.width.toDouble(), h = image.height.toDouble();
        canvas.drawImageRect(
          image,
          Offset.zero & ui.Size(w, h),
          Rect.fromLTWH(x, 0, tile, size.height),
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = const Color(0xb3000000),
        );
      }
    }
    final peaks = c.media.peaks[id];
    if (peaks == null || !content.sounds) return;
    final paint = Paint()
      ..color = const Color(0xccffffff)
      ..strokeWidth = 1;
    final middle = size.height * .6, reach = size.height * .35;
    for (var x = 0.0; x < size.width; x += 2) {
      final i = (seconds(x) * MediaCache.peaksPerSecond).floor();
      if (i < 0 || i >= peaks.length) continue;
      final v = peaks[i] * reach;
      canvas.drawLine(Offset(x, middle - v), Offset(x, middle + v), paint);
    }
  }

  @override
  bool shouldRepaint(_MediaStrip old) =>
      !identical(old.content, content) || old.framePixels != framePixels;
}
