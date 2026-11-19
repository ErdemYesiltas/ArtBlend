import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/movie.dart';
import '../domain/movie_edits.dart';
import '../editor/overlay_bar.dart';
import '../l10n/app_localizations.dart';
import '../editor/value_slider.dart';
import '../drawing/brush_engine.dart' show layerBlendMode;
import 'drawing_frames.dart';
import 'live_filters.dart';
import 'movie_prefs.dart';
import 'movie_controller.dart';
import 'timeline.dart' show contentColor;

/// Which part of the chosen content a drag takes.
enum StageHandle {
  body,
  anchor,
  rotate,
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  left,
  right,
  top,
  bottom,
}

const _handleRadius = 9.0, _rotateReach = 34.0;

/// Where the stage sits in a [box]: its top left and screen pixels per
/// stage pixel, a margin left around it for what lies offstage.
({Offset origin, double scale}) stageFit(Size box, Size stage) {
  final margin = math.min(36.0, math.min(box.width, box.height) * .06);
  final scale = math.max(
    .001,
    math.min(
      (box.width - margin * 2) / stage.width,
      (box.height - margin * 2) / stage.height,
    ),
  );
  return (
    origin: Offset(
      (box.width - stage.width * scale) / 2,
      (box.height - stage.height * scale) / 2,
    ),
    scale: scale,
  );
}

/// The handles of [frame] on screen ([toScreen] maps stage pixels).
Map<StageHandle, Offset> stageHandles(
  ContentFrame frame,
  Offset Function(Offset) toScreen,
) {
  final w = frame.size.width, h = frame.size.height;
  final top = toScreen(frame.toStage(Offset(w / 2, 0)));
  final middle = toScreen(frame.toStage(Offset(w / 2, h / 2)));
  final up = top - middle;
  final reach = up.distance < 1 ? const Offset(0, -1) : up / up.distance;
  return {
    StageHandle.anchor: toScreen(frame.position),
    StageHandle.rotate: top + reach * _rotateReach,
    StageHandle.topLeft: toScreen(frame.toStage(Offset.zero)),
    StageHandle.topRight: toScreen(frame.toStage(Offset(w, 0))),
    StageHandle.bottomRight: toScreen(frame.toStage(Offset(w, h))),
    StageHandle.bottomLeft: toScreen(frame.toStage(Offset(0, h))),
    StageHandle.left: toScreen(frame.toStage(Offset(0, h / 2))),
    StageHandle.right: toScreen(frame.toStage(Offset(w, h / 2))),
    StageHandle.top: top,
    StageHandle.bottom: toScreen(frame.toStage(Offset(w / 2, h))),
  };
}

/// [start] dragged by [handle] from stage point [from] to [to]; [snap]
/// keeps moves on a 24-part grid, turns to 15°, sizes to 5% steps and the
/// anchor to the content's corners, edges and middle.
ContentTransform dragTransform(
  ContentFrame start,
  StageHandle handle,
  Offset from,
  Offset to, {
  bool snap = false,
}) {
  final t = start.transform, stage = start.stage;
  double grid(double v, double step) => snap ? (v / step).round() * step : v;
  switch (handle) {
    case StageHandle.body:
      final d = to - from;
      return t.copyWith(
        x: grid(t.x + d.dx / stage.width, 1 / 24),
        y: grid(t.y + d.dy / stage.height, 1 / 24),
      );
    case StageHandle.anchor:
      final local = start.toLocal(to);
      final size = start.size;
      final ax = grid((local.dx / size.width).clamp(-.5, 1.5), .5);
      final ay = grid((local.dy / size.height).clamp(-.5, 1.5), .5);
      return start.withAnchor(Offset(ax * size.width, ay * size.height));
    case StageHandle.rotate:
      final a = start.position;
      final turn = (to - a).direction - (from - a).direction + t.rotation;
      return t.copyWith(rotation: grid(turn, math.pi / 12));
    case StageHandle.topLeft ||
        StageHandle.topRight ||
        StageHandle.bottomRight ||
        StageHandle.bottomLeft:
      final a = start.position;
      final was = (from - a).distance;
      if (was < 1) return t;
      final sx = grid(t.scaleX * (to - a).distance / was, .05);
      return t.copyWith(scaleX: sx, scaleY: t.scaleY * sx / t.scaleX);
    case StageHandle.left || StageHandle.right:
      final a = start.anchor.dx;
      final was = start.toLocal(from).dx - a;
      if (was.abs() < 1) return t;
      final ratio = (start.toLocal(to).dx - a) / was;
      return t.copyWith(scaleX: grid(t.scaleX * math.max(0, ratio), .05));
    case StageHandle.top || StageHandle.bottom:
      final a = start.anchor.dy;
      final was = start.toLocal(from).dy - a;
      if (was.abs() < 1) return t;
      final ratio = (start.toLocal(to).dy - a) / was;
      return t.copyWith(scaleY: grid(t.scaleY * math.max(0, ratio), .05));
  }
}

/// What dragging on the chosen content changes.
enum ComposeMode { move, distort, warp }

/// The chosen content's Distort corners or Warp nodes at movie frame
/// [frame]: their keyed parameters, grid position and place on screen.
List<({String kx, String ky, double u, double v, Offset screen})> meshHandles(
  MovieContent content,
  Size stage,
  int frame,
  ComposeMode mode,
  Offset Function(Offset) toScreen,
) {
  if (mode == ComposeMode.move) return const [];
  final shape = content.frameOn(stage, frame);
  final local = frame - content.start;
  ({String kx, String ky, double u, double v, Offset screen}) at(
    String kx,
    String ky,
    double u,
    double v,
  ) => (
    kx: kx,
    ky: ky,
    u: u,
    v: v,
    screen: toScreen(
      shape.toStage(
        meshPoint(
          content.keys,
          local,
          shape.size,
          u,
          v,
          cols: content.warpCols,
          rows: content.warpRows,
        ),
      ),
    ),
  );
  if (mode == ComposeMode.distort) {
    const corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
    return [
      for (final (i, (u, v)) in corners.indexed)
        at(distortKey(i, 'x'), distortKey(i, 'y'), u, v),
    ];
  }
  final cols = content.warpCols, rows = content.warpRows;
  if (cols < 2 || rows < 2) return const [];
  return [
    for (var r = 0; r < rows; r++)
      for (var col = 0; col < cols; col++)
        at(
          warpKey(col, r, 'x'),
          warpKey(col, r, 'y'),
          col / (cols - 1),
          r / (rows - 1),
        ),
  ];
}

/// The stage at the playhead: its colour, what is on it (faintly beyond
/// its edges, as much as the offstage setting says), the timecode; with
/// [interactive], tap to choose a content and drag it, its handles or its
/// anchor (a second finger or Shift snaps).
class StageView extends StatefulWidget {
  const StageView({
    super.key,
    required this.controller,
    this.interactive = true,
    this.onFullscreen,
    this.onEdit,
    this.prefs,
  });
  final MovieController controller;
  final bool interactive;
  final VoidCallback? onFullscreen;

  /// Draw in content [id] (a double tap on it, or the pencil).
  final void Function(String id)? onEdit;

  /// On-stage undo buttons, a held undo repeating, tap gestures.
  final MoviePrefs? prefs;

  @override
  State<StageView> createState() => _StageViewState();
}

class _StageViewState extends State<StageView> {
  final _pointers = <int>{};
  int? _primary;
  ({StageHandle handle, ContentFrame frame, Offset from, String id})? _drag;
  bool _snapping = false;
  Duration? _lastDown;
  ComposeMode _mode = ComposeMode.move;
  bool _filters = false;

  // A tap with two or three fingers: undo, redo.
  int _tapFingers = 0;
  Duration? _tapStart;
  bool _tapMoved = false;
  Timer? _repeat;
  ({String id, String kx, String ky, double u, double v})? _meshDrag;

  MovieController get c => widget.controller;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  Size get _stage => Size(c.movie.width.toDouble(), c.movie.height.toDouble());

  void _down(PointerDownEvent e, Size box) {
    _pointers.add(e.pointer);
    if (_pointers.length == 1) {
      _tapFingers = 0;
      _tapMoved = false;
      _tapStart = e.timeStamp;
    }
    _tapFingers = math.max(_tapFingers, _pointers.length);
    if (_primary != null) {
      setState(() => _snapping = true);
      return;
    }
    _primary = e.pointer;
    c.stop();
    final now = e.timeStamp;
    final last = _lastDown;
    _lastDown = now;
    final fit = stageFit(box, _stage);
    Offset toScreen(Offset p) => fit.origin + p * fit.scale;
    final at = (e.localPosition - fit.origin) / fit.scale;
    final chosen = c.content(c.selected);
    if (chosen != null &&
        widget.onEdit != null &&
        last != null &&
        now - last < const Duration(milliseconds: 350) &&
        chosen.frameOn(_stage, c.playhead.value).contains(at)) {
      _primary = null;
      _lastDown = null;
      widget.onEdit?.call(chosen.id);
      return;
    }
    if (chosen != null && _mode != ComposeMode.move) {
      for (final h in meshHandles(
        chosen,
        _stage,
        c.playhead.value,
        _mode,
        toScreen,
      )) {
        if ((h.screen - e.localPosition).distance <= _handleRadius + 6) {
          _meshDrag = (id: chosen.id, kx: h.kx, ky: h.ky, u: h.u, v: h.v);
          return;
        }
      }
    }
    if (chosen != null && _mode == ComposeMode.move) {
      final frame = chosen.frameOn(_stage, c.playhead.value);
      final handles = stageHandles(frame, toScreen);
      for (final handle in StageHandle.values.skip(1)) {
        if ((handles[handle]! - e.localPosition).distance <=
            _handleRadius + 6) {
          _drag = (handle: handle, frame: frame, from: at, id: chosen.id);
          return;
        }
      }
    }
    final hit = c
        .shownAt(c.playhead.value)
        .reversed
        .where(
          (content) => content.frameOn(_stage, c.playhead.value).contains(at),
        )
        .firstOrNull;
    c.select(hit?.id);
    if (hit != null) {
      _drag = (
        handle: StageHandle.body,
        frame: hit.frameOn(_stage, c.playhead.value),
        from: at,
        id: hit.id,
      );
    }
  }

  void _move(PointerMoveEvent e, Size box) {
    if (e.delta.distance > 0) _tapMoved = _tapMoved || e.delta.distance > 2;
    if (e.pointer != _primary) return;
    final fit = stageFit(box, _stage);
    final at = (e.localPosition - fit.origin) / fit.scale;
    if (_meshDrag case final mesh?) {
      final content = c.content(mesh.id);
      if (content == null) return;
      final now = c.playhead.value;
      final shape = content.frameOn(_stage, now);
      final local = now - content.start;
      final here = meshPoint(
        content.keys,
        local,
        shape.size,
        mesh.u,
        mesh.v,
        cols: content.warpCols,
        rows: content.warpRows,
      );
      final want = shape.toLocal(at);
      final by = Offset(
        (want.dx - here.dx) / shape.size.width,
        (want.dy - here.dy) / shape.size.height,
      );
      final values = {
        mesh.kx: keyedValue(content.keys, mesh.kx, local) + by.dx,
        mesh.ky: keyedValue(content.keys, mesh.ky, local) + by.dy,
      };
      if (!c.performing) {
        c.setKeyedValues(mesh.id, values, live: true);
      } else if (c.recording) {
        c.updateTake(values);
      } else {
        c.beginTake(mesh.id, values);
      }
      return;
    }
    final drag = _drag;
    if (drag == null) return;
    final snap = _snapping || HardwareKeyboard.instance.isShiftPressed;
    final next = dragTransform(
      drag.frame,
      drag.handle,
      drag.from,
      at,
      snap: snap,
    );
    if (c.performing) {
      final values = switch (drag.handle) {
        StageHandle.body => {'x': next.x, 'y': next.y},
        StageHandle.rotate => {'rotation': next.rotation},
        StageHandle.topLeft ||
        StageHandle.topRight ||
        StageHandle.bottomRight ||
        StageHandle.bottomLeft => {'scale': next.scaleX},
        _ => <String, double>{},
      };
      if (values.isEmpty) return;
      c.recording ? c.updateTake(values) : c.beginTake(drag.id, values);
      return;
    }
    c.preview(c.withContent(drag.id, (content) => c.place(content, next)));
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    final start = _tapStart;
    if (_pointers.isEmpty &&
        !_tapMoved &&
        _tapFingers >= 2 &&
        start != null &&
        e.timeStamp - start < const Duration(milliseconds: 350)) {
      final prefs = widget.prefs;
      if (_tapFingers == 2 && (prefs?.twoFingerUndo ?? true)) c.undo();
      if (_tapFingers == 3 && (prefs?.threeFingerRedo ?? true)) c.redo();
    }
    if (e.pointer != _primary) return;
    _primary = null;
    _drag = null;
    _meshDrag = null;
    c.recording ? c.endTake() : c.commitPreview();
    if (_snapping) setState(() => _snapping = false);
  }

  void _edit(ContentTransform Function(ContentTransform t) change) {
    final id = c.selected;
    if (id == null) return;
    c.edit(
      c.withContent(
        id,
        (content) => content.copyWith(transform: change(content.transform)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final stage = CustomPaint(
          key: const ValueKey('movie-stage'),
          size: size,
          painter: _LiveStagePainter(
            c,
            scheme.primary,
            handles: widget.interactive,
            mode: _mode,
          ),
        );
        if (!widget.interactive) return stage;
        final l = AppLocalizations.of(context);
        return ListenableBuilder(
          listenable: Listenable.merge([c, ?widget.prefs]),
          builder: (context, _) {
            final chosen = c.content(c.selected);
            return Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _down(e, size),
                  onPointerMove: (e) => _move(e, size),
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: stage,
                ),
                if (c.performing)
                  Positioned(
                    top: 8,
                    right: 12,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.fiber_manual_record,
                        key: const ValueKey('perform-indicator'),
                        size: c.recording ? 18 : 14,
                        color: c.recording ? Colors.red : Colors.red.shade200,
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: ValueListenableBuilder(
                        valueListenable: c.playhead,
                        builder: (context, frame, _) => Text(
                          timecode(frame, c.movie.fps),
                          key: const ValueKey('stage-timecode'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (chosen != null)
                  Positioned(
                    top: 0,
                    left: 4,
                    right: 4,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Material(
                          color: scheme.surface.withValues(alpha: .9),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: const ValueKey('compose-flip-h'),
                                tooltip: l.flipHorizontal,
                                onPressed: () =>
                                    _edit((t) => t.copyWith(flipX: !t.flipX)),
                                icon: const Icon(Icons.flip_rounded),
                              ),
                              IconButton(
                                key: const ValueKey('compose-flip-v'),
                                tooltip: l.flipVertical,
                                onPressed: () =>
                                    _edit((t) => t.copyWith(flipY: !t.flipY)),
                                icon: const RotatedBox(
                                  quarterTurns: 1,
                                  child: Icon(Icons.flip_rounded),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('compose-reset'),
                                tooltip: l.composeReset,
                                onPressed: () {
                                  final id = c.selected;
                                  if (id == null) return;
                                  c.edit(
                                    c.withContent(
                                      id,
                                      (content) => content.copyWith(
                                        transform: ContentTransform.identity,
                                        keys: const {},
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                              for (final (mode, icon, tip) in [
                                (
                                  ComposeMode.move,
                                  Icons.open_with_rounded,
                                  l.composeMove,
                                ),
                                (
                                  ComposeMode.distort,
                                  Icons.crop_rotate_rounded,
                                  l.distort,
                                ),
                                (
                                  ComposeMode.warp,
                                  Icons.grid_4x4_rounded,
                                  l.warp,
                                ),
                              ])
                                IconButton(
                                  key: ValueKey('compose-${mode.name}'),
                                  tooltip: tip,
                                  isSelected: _mode == mode,
                                  onPressed: () {
                                    if (mode == ComposeMode.warp &&
                                        chosen.warpCols < 2) {
                                      c.setWarpGrid(chosen.id, 3, 3);
                                    }
                                    setState(() => _mode = mode);
                                  },
                                  icon: Icon(icon),
                                ),
                              if (_mode == ComposeMode.warp) ...[
                                IconButton(
                                  key: const ValueKey('warp-add-column'),
                                  tooltip: l.warpAddColumn,
                                  onPressed: () => c.setWarpGrid(
                                    chosen.id,
                                    chosen.warpCols + 1,
                                    chosen.warpRows,
                                  ),
                                  icon: const Icon(Icons.view_column_outlined),
                                ),
                                IconButton(
                                  key: const ValueKey('warp-add-row'),
                                  tooltip: l.warpAddRow,
                                  onPressed: () => c.setWarpGrid(
                                    chosen.id,
                                    chosen.warpCols,
                                    chosen.warpRows + 1,
                                  ),
                                  icon: const Icon(Icons.table_rows_outlined),
                                ),
                              ],
                              if (_mode != ComposeMode.move)
                                IconButton(
                                  key: const ValueKey('mesh-straighten'),
                                  tooltip: l.meshReset,
                                  onPressed: () => c.straighten(
                                    chosen.id,
                                    warp: _mode == ComposeMode.warp,
                                  ),
                                  icon: const Icon(Icons.crop_free_rounded),
                                ),
                              IconButton(
                                key: const ValueKey('compose-filters'),
                                tooltip: l.liveFilters,
                                isSelected: _filters,
                                onPressed: () =>
                                    setState(() => _filters = !_filters),
                                icon: const Icon(Icons.auto_awesome_rounded),
                              ),
                              if (widget.onEdit != null)
                                IconButton(
                                  key: const ValueKey('compose-edit'),
                                  tooltip: l.contentDraw,
                                  onPressed: () => widget.onEdit!(chosen.id),
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                              IconButton(
                                key: const ValueKey('compose-done'),
                                tooltip: l.done,
                                onPressed: () => c.select(null),
                                icon: const Icon(Icons.check_rounded),
                              ),
                              barHint(l.composeHint),
                              if (_snapping)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.grid_on_rounded,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (chosen != null && _filters)
                  Positioned(
                    right: 8,
                    top: 52,
                    bottom: 64,
                    width: 300,
                    child: FilterPanel(controller: c, content: chosen),
                  ),
                if (widget.prefs?.undoButtons ?? true)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        GestureDetector(
                          onLongPressStart: (_) {
                            final delay = widget.prefs?.quickUndoMs ?? 400;
                            if (delay <= 0) return;
                            _repeat?.cancel();
                            _repeat = Timer(Duration(milliseconds: delay), () {
                              _repeat = Timer.periodic(
                                const Duration(milliseconds: 90),
                                (_) => c.canUndo ? c.undo() : _repeat?.cancel(),
                              );
                            });
                          },
                          onLongPressEnd: (_) => _repeat?.cancel(),
                          onLongPressCancel: () => _repeat?.cancel(),
                          child: _round(
                            'stage-undo',
                            l.undo,
                            Icons.undo_rounded,
                            c.canUndo ? c.undo : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _round(
                          'stage-redo',
                          l.redo,
                          Icons.redo_rounded,
                          c.canRedo ? c.redo : null,
                        ),
                      ],
                    ),
                  ),
                if (widget.onFullscreen != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _round(
                      'stage-fullscreen',
                      l.fullscreenPreview,
                      Icons.fullscreen_rounded,
                      widget.onFullscreen,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _round(String key, String tip, IconData icon, VoidCallback? on) =>
      IconButton.filledTonal(
        key: ValueKey(key),
        tooltip: tip,
        onPressed: on,
        icon: Icon(icon),
      );
}

class _LiveStagePainter extends CustomPainter {
  _LiveStagePainter(
    this.c,
    this.accent, {
    required this.handles,
    this.mode = ComposeMode.move,
    this.frame,
    DrawingFrames? cache,
    String? Function(String id, double seconds)? proxy,
    this.export = false,
  }) : pictures = cache ?? c.frames,
       proxy = proxy ?? c.media.framePath,
       super(
         repaint: export
             ? null
             : Listenable.merge([c, c.playhead, c.frames, c.media]),
       );
  final MovieController c;
  final Color accent;
  final bool handles;
  final ComposeMode mode;

  /// The frame drawn (the playhead's when null).
  final int? frame;

  /// Where pictures come from: drawings rendered, video frames loaded.
  final DrawingFrames pictures;
  final String? Function(String id, double seconds) proxy;

  /// For a file: the stage alone filling the canvas, no margin, nothing
  /// offstage, a transparent stage left see-through.
  final bool export;

  @override
  void paint(Canvas canvas, Size size) {
    final movie = c.movie;
    final stage = Size(movie.width.toDouble(), movie.height.toDouble());
    final fit = export
        ? (origin: Offset.zero, scale: size.width / stage.width)
        : stageFit(size, stage);
    final rect = fit.origin & stage * fit.scale;
    if (export) {
      if (!movie.transparent) {
        canvas.drawRect(rect, Paint()..color = Color(movie.background));
      }
    } else if (movie.transparent) {
      canvas.drawRect(rect, Paint()..color = const Color(0xffffffff));
      final grey = Paint()..color = const Color(0xffd9d9d9);
      const cell = 10.0;
      canvas.save();
      canvas.clipRect(rect);
      for (var y = rect.top; y < rect.bottom; y += cell) {
        final odd = ((y - rect.top) / cell).round().isOdd;
        for (
          var x = rect.left + (odd ? cell : 0);
          x < rect.right;
          x += cell * 2
        ) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), grey);
        }
      }
      canvas.restore();
    } else {
      canvas.drawRect(rect, Paint()..color = Color(movie.background));
    }
    final now = this.frame ?? c.playhead.value;
    final shown = c.shownAt(now);
    void contents() {
      canvas.save();
      canvas.translate(fit.origin.dx, fit.origin.dy);
      canvas.scale(fit.scale);
      _composite(canvas, stage, now);
      canvas.restore();
    }

    // The next frames get ready while this one shows.
    if (c.playing.value) {
      for (final content in shown) {
        if (content.mediaId case final id?
            when content.kind == TrackKind.video) {
          for (var ahead = 1; ahead <= 3; ahead++) {
            final s = content.sourceFrame(now + ahead);
            if (s == null) break;
            final path = proxy(id, s / c.movie.fps);
            if (path != null) pictures.fileImage(path);
          }
        }
        final drawing = c.drawings[content.id];
        if (drawing == null || !drawing.animating) continue;
        for (var ahead = 1; ahead <= 3; ahead++) {
          pictures.image(content, drawing, now + ahead);
        }
      }
    }

    if (movie.offstage > 0 && !export) {
      canvas.save();
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(rect),
        ),
      );
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, movie.offstage),
      );
      contents();
      canvas.restore();
      canvas.restore();
    }
    canvas.save();
    canvas.clipRect(rect);
    contents();
    canvas.restore();
    if (export) return;
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x66ffffff),
    );

    final chosen = c.content(c.selected);
    if (!handles || chosen == null || !shown.contains(chosen)) return;
    final frame = chosen.frameOn(stage, now);
    Offset toScreen(Offset p) => fit.origin + p * fit.scale;
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (mode != ComposeMode.move) {
      final nodes = meshHandles(chosen, stage, now, mode, toScreen);
      if (mode == ComposeMode.warp && chosen.warpCols >= 2) {
        final cols = chosen.warpCols;
        for (var i = 0; i < nodes.length; i++) {
          if ((i + 1) % cols != 0) {
            canvas.drawLine(nodes[i].screen, nodes[i + 1].screen, line);
          }
          if (i + cols < nodes.length) {
            canvas.drawLine(nodes[i].screen, nodes[i + cols].screen, line);
          }
        }
      } else if (nodes.length == 4) {
        canvas.drawPath(
          Path()..addPolygon([for (final n in nodes) n.screen], true),
          line,
        );
      }
      for (final n in nodes) {
        canvas.drawCircle(
          n.screen,
          7,
          Paint()..color = const Color(0xffffffff),
        );
        canvas.drawCircle(n.screen, 7, line);
      }
      return;
    }
    final points = stageHandles(frame, toScreen);
    canvas.drawPath(
      Path()..addPolygon([for (final p in frame.corners) toScreen(p)], true),
      line,
    );
    canvas.drawLine(
      points[StageHandle.top]!,
      points[StageHandle.rotate]!,
      line,
    );
    final fill = Paint()..color = const Color(0xffffffff);
    for (final MapEntry(key: handle, value: p) in points.entries) {
      switch (handle) {
        case StageHandle.anchor:
          canvas.drawCircle(p, 6, line);
          canvas.drawLine(p - const Offset(9, 0), p + const Offset(9, 0), line);
          canvas.drawLine(p - const Offset(0, 9), p + const Offset(0, 9), line);
        case StageHandle.rotate:
          canvas.drawCircle(p, 7, fill);
          canvas.drawCircle(p, 7, line);
        case StageHandle.left ||
            StageHandle.right ||
            StageHandle.top ||
            StageHandle.bottom:
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 10, height: 10),
            fill,
          );
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 10, height: 10),
            line,
          );
        case _:
          canvas.drawCircle(p, 7, fill..color = accent);
          fill.color = const Color(0xffffffff);
      }
    }
  }

  static const _lumaToAlpha = ColorFilter.matrix([
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    .299, .587, .114, 0, 0,
  ]);

  /// Everything on the stage at [at], bottom track first: each content
  /// mixed by its blend mode; a clipping mask shown only over the content
  /// beneath it; an alpha or luminance mask not drawn but letting the
  /// content beneath show; a group made into one picture (its blend mode
  /// and opacity) unless it passes through.
  void _composite(Canvas canvas, Size stage, int at) {
    final movie = c.movie, tracks = movie.tracks;
    MovieContent? on(int i, String? group) {
      if (i < 0 || i >= tracks.length || tracks[i].group != group) return null;
      final t = tracks[i];
      if (!movie.trackShows(t)) return null;
      final x = t.at(at);
      return x == null || x.hidden || x.kind == TrackKind.audio ? null : x;
    }

    String? group;
    var layered = false;
    for (var i = tracks.length - 1; i >= 0; i--) {
      final t = tracks[i];
      if (i == tracks.length - 1 || t.group != group) {
        if (layered) canvas.restore();
        group = t.group;
        final g = movie.groupById(group);
        layered = g != null && !g.passthrough;
        if (layered) {
          canvas.saveLayer(
            null,
            Paint()
              ..blendMode = layerBlendMode(g.blend)
              ..color = Color.fromRGBO(0, 0, 0, g.opacity),
          );
        }
      }
      final x = on(i, group);
      if (x == null ||
          x.mask == ContentMask.alpha ||
          x.mask == ContentMask.luma) {
        continue;
      }
      final above = on(i - 1, group);
      final masked =
          above != null &&
          (above.mask == ContentMask.alpha || above.mask == ContentMask.luma);
      final under = x.mask == ContentMask.clip ? on(i + 1, group) : null;
      if (!masked && under == null) {
        _content(canvas, x, stage, at, blend: layerBlendMode(x.blend));
        continue;
      }
      // A mask is a layer of its own, so what lies outside it goes too.
      void maskWith(MovieContent m, BlendMode mode, {bool luma = false}) {
        canvas.saveLayer(
          null,
          Paint()
            ..blendMode = mode
            ..colorFilter = luma ? _lumaToAlpha : null,
        );
        _content(canvas, m, stage, at);
        canvas.restore();
      }

      canvas.saveLayer(null, Paint()..blendMode = layerBlendMode(x.blend));
      _content(canvas, x, stage, at);
      if (under != null) maskWith(under, BlendMode.dstIn);
      if (masked) {
        maskWith(
          above,
          above.maskInvert ? BlendMode.dstOut : BlendMode.dstIn,
          luma: above.mask == ContentMask.luma,
        );
      }
      canvas.restore();
    }
    if (layered) canvas.restore();
  }

  /// A content: its drawing's picture, or (empty, or not rendered yet) its
  /// frame and name, mixed by [blend].
  void _content(
    Canvas canvas,
    MovieContent content,
    Size stage,
    int at, {
    BlendMode blend = BlendMode.srcOver,
  }) {
    final frame = content.frameOn(stage, at);
    final t = frame.transform, size = frame.size;
    canvas.save();
    canvas.translate(frame.position.dx, frame.position.dy);
    canvas.rotate(t.rotation);
    canvas.scale(t.scaleX * (t.flipX ? -1 : 1), t.scaleY * (t.flipY ? -1 : 1));
    canvas.translate(-frame.anchor.dx, -frame.anchor.dy);
    final color = contentColor(content.kind);
    final box = Offset.zero & size;
    final drawing = c.drawings[content.id];
    final image = switch ((content.kind, content.mediaId)) {
      (TrackKind.video, final id?) => switch (proxy(
        id,
        (content.sourceFrame(at) ?? 0) / c.movie.fps,
      )) {
        final path? => pictures.fileImage(path),
        null => null,
      },
      _ => drawing == null ? null : pictures.image(content, drawing, at),
    };
    if (image != null) {
      final shaders = c.shaders;
      final filtered = shaders == null || content.filters.isEmpty
          ? null
          : filterImage(image, content, at, c.movie.fps, shaders);
      final shown = filtered ?? image;
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = blend
        ..color = Color.fromRGBO(
          0,
          0,
          0,
          content.opacity * filterOpacity(content, at),
        );
      if (content.meshed) {
        drawMesh(canvas, shown, content, at - content.start, size, paint);
      } else {
        canvas.drawImageRect(
          shown,
          Offset.zero & Size(shown.width.toDouble(), shown.height.toDouble()),
          box,
          paint,
        );
      }
      filtered?.dispose();
      canvas.restore();
      return;
    }
    if (drawing != null) {
      canvas.restore();
      return;
    }
    final alpha = content.opacity * filterOpacity(content, at);
    canvas.drawRect(
      box,
      Paint()
        ..blendMode = blend
        ..color = color.withValues(alpha: .28 * alpha),
    );
    canvas.drawRect(
      box,
      Paint()
        ..blendMode = blend
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size.shortestSide / 200)
        ..color = color.withValues(alpha: alpha),
    );
    if (blend != BlendMode.srcOver) {
      canvas.restore();
      return;
    }
    final text = TextPainter(
      text: TextSpan(
        text: content.name,
        style: TextStyle(
          color: color,
          fontSize: size.shortestSide * .08,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * .9);
    text.paint(canvas, box.center - Offset(text.width / 2, text.height / 2));
    text.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiveStagePainter old) =>
      old.c != c ||
      old.accent != accent ||
      old.handles != handles ||
      old.mode != mode;
}

/// The movie playing on its own over the whole screen; a tap (or Escape)
/// ends it.
class FullscreenPreview extends StatefulWidget {
  const FullscreenPreview({super.key, required this.controller});
  final MovieController controller;

  @override
  State<FullscreenPreview> createState() => _FullscreenPreviewState();
}

class _FullscreenPreviewState extends State<FullscreenPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.play();
    });
  }

  void _close() {
    widget.controller.stop();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: Focus(
      autofocus: true,
      child: Scaffold(
        key: const ValueKey('fullscreen-preview'),
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: StageView(controller: widget.controller, interactive: false),
        ),
      ),
    ),
  );
}

/// The chosen content's live filters, in order: each one's settings at the
/// playhead (keyed there in keyframe mode), removable; more to add.
class FilterPanel extends StatelessWidget {
  const FilterPanel({
    super.key,
    required this.controller,
    required this.content,
  });
  final MovieController controller;
  final MovieContent content;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;
    return Material(
      key: const ValueKey('filter-panel'),
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder(
        valueListenable: c.playhead,
        builder: (context, frame, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.liveFilters,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                barHint(l.filtersHint),
                PopupMenuButton<FilterKind>(
                  key: const ValueKey('filter-add'),
                  tooltip: l.addFilter,
                  icon: const Icon(Icons.add_rounded),
                  onSelected: (kind) => c.addFilter(content.id, kind),
                  itemBuilder: (context) => [
                    for (final kind in FilterKind.values)
                      PopupMenuItem(
                        value: kind,
                        child: Text(filterName(l, kind)),
                      ),
                  ],
                ),
              ],
            ),
            if (content.sounds)
              ValueSlider(
                id: 'content-volume',
                label: l.volume,
                labelWidth: 110,
                value: keyedValue(
                  content.keys,
                  'volume',
                  frame - content.start,
                  1,
                ),
                onChangeStart: (v) {
                  if (c.performing) c.beginTake(content.id, {'volume': v});
                },
                onChanged: (v) => c.performing
                    ? c.updateTake({'volume': v})
                    : c.setKeyedValues(content.id, {'volume': v}, live: true),
                onChangeEnd: (_) =>
                    c.performing ? c.endTake() : c.commitPreview(),
              ),
            for (final f in content.filters) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      filterName(l, f.kind),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('filter-remove-${f.id}'),
                    tooltip: l.removeFilter,
                    iconSize: 18,
                    onPressed: () => c.removeFilter(content.id, f.id),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              for (final p in f.kind.params)
                ValueSlider(
                  id: 'filter-${f.kind.name}-${p.id}',
                  label: filterParamName(l, p.id),
                  labelWidth: 110,
                  value: content.filterValue(f, p, frame),
                  onChangeStart: (v) {
                    if (c.performing) c.beginTake(content.id, {f.key(p.id): v});
                  },
                  onChanged: (v) => c.performing
                      ? c.updateTake({f.key(p.id): v})
                      : c.setKeyedValues(content.id, {
                          f.key(p.id): v,
                        }, live: true),
                  onChangeEnd: (_) =>
                      c.performing ? c.endTake() : c.commitPreview(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Movie frame [frame] painted onto [canvas] sized [size] (the stage's
/// shape) as it will be in a file, pictures from [cache] and video frames
/// from [proxy]. Pictures not ready yet are asked for; [cache] says when
/// nothing is pending any more.
void paintMovieFrame(
  Canvas canvas,
  Size size,
  MovieController c,
  int frame, {
  required DrawingFrames cache,
  required String? Function(String id, double seconds) proxy,
}) => _LiveStagePainter(
  c,
  const Color(0x00000000),
  handles: false,
  frame: frame,
  cache: cache,
  proxy: proxy,
  export: true,
).paint(canvas, size);
