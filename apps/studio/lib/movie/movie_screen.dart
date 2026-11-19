import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/studio_storage.dart';
import '../domain/document.dart';
import '../domain/movie.dart';
import '../l10n/app_localizations.dart';
import 'movie_controller.dart';
import 'movie_settings.dart';
import 'drawing_frames.dart' show drawingAt;
import 'export_dialog.dart';
import 'movie_prefs.dart';
import 'stage.dart';
import 'text_content.dart';
import 'timeline.dart';

/// The stage: the movie's colour, or a checkerboard when transparent.
class StagePainter extends CustomPainter {
  const StagePainter(this.movie);
  final MovieDocument movie;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (!movie.transparent) {
      canvas.drawRect(rect, Paint()..color = Color(movie.background));
      return;
    }
    canvas.drawRect(rect, Paint()..color = const Color(0xffffffff));
    final grey = Paint()..color = const Color(0xffd9d9d9);
    const cell = 10.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (
        var x = (y / cell).round().isEven ? 0.0 : cell;
        x < size.width;
        x += cell * 2
      ) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell).intersect(rect), grey);
      }
    }
  }

  @override
  bool shouldRepaint(StagePainter old) =>
      old.movie.background != movie.background ||
      old.movie.transparent != movie.transparent;
}

IconData trackIcon(TrackKind kind) => switch (kind) {
  TrackKind.flipbook => Icons.auto_stories_outlined,
  TrackKind.drawing => Icons.brush_outlined,
  TrackKind.video => Icons.movie_outlined,
  TrackKind.audio => Icons.graphic_eq_rounded,
  TrackKind.text => Icons.text_fields_rounded,
};

/// An open movie: the stage over the timeline (the bar between them
/// moves), undo and redo, settings. Every edit is saved at once.
/// Opens the editor on a movie's [drawing]; each save goes to [onSave].
typedef EditDrawing = Future<void> Function(
  BuildContext context,
  ArtDocument drawing,
  void Function(ArtDocument drawing) onSave, {
  void Function(int frame)? onScrub,
});

class MovieScreen extends StatefulWidget {
  const MovieScreen({
    super.key,
    required this.storage,
    required this.movie,
    required this.askName,
    this.recent = const [],
    this.editDrawing,
    this.preferences,
  });
  final StudioStorage storage;
  final MovieDocument movie;
  final Future<String?> Function(String current) askName;
  final List<int> recent;
  final EditDrawing? editDrawing;
  final SharedPreferences? preferences;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  late final prefs = MoviePrefs(widget.preferences);
  late final c = MovieController(
    storage: widget.storage,
    movie: widget.movie,
    undoDepth: prefs.undoDepth,
  );

  void _followPrefs() => c.undoDepth = prefs.undoDepth;

  /// What keyboard shortcut [a] does.
  void _act(MovieAction a) => switch (a) {
    MovieAction.play => c.togglePlay(),
    MovieAction.stepBack => (c..stop()).seek(c.playhead.value - 1),
    MovieAction.stepForward => (c..stop()).seek(c.playhead.value + 1),
    MovieAction.undo => c.undo(),
    MovieAction.redo => c.redo(),
    MovieAction.copy => c.copySelection(),
    MovieAction.cut => c.cutSelection(),
    MovieAction.paste => c.paste(),
    MovieAction.duplicate => switch (c.selected) {
      final id? => c.duplicateAfter(id),
      null => null,
    },
    MovieAction.delete => c.deleteContents(null),
    MovieAction.keyframes => c.setKeyframing(!c.keyframing),
    MovieAction.perform => c.setPerforming(!c.performing),
    MovieAction.fullscreen => _fullscreen(),
  };

  void _fullscreen() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => FullscreenPreview(controller: c)),
  );

  /// The movie's recovery points; one picked brings the movie back as it
  /// was then (the screen opens afresh on it).
  Future<void> _recovery() async {
    final l = AppLocalizations.of(context);
    final points = await c.storage.moviePoints(c.movie.id);
    if (!mounted) return;
    final at = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('recovery-dialog'),
        title: Text(l.prefsRecovery),
        content: SizedBox(
          width: 360,
          child: points.isEmpty
              ? Text(l.recoveryNone)
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in points)
                      ListTile(
                        key: ValueKey('recovery-${p.millisecondsSinceEpoch}'),
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          MaterialLocalizations.of(context).formatFullDate(p),
                        ),
                        subtitle: Text(
                          TimeOfDay.fromDateTime(p).format(context),
                        ),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
    if (at == null || !mounted) return;
    await c.flush();
    if (!await c.storage.restoreMoviePoint(c.movie.id, at) || !mounted) return;
    final movie = (await c.storage.listMovies()).movies
        .where((m) => m.id == c.movie.id)
        .firstOrNull;
    if (movie == null || !mounted) return;
    Navigator.of(context)
        .popUntil((r) => r is! PopupRoute && r is! DialogRoute);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MovieScreen(
          storage: widget.storage,
          movie: movie,
          askName: widget.askName,
          recent: widget.recent,
          editDrawing: widget.editDrawing,
          preferences: widget.preferences,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    prefs.addListener(_followPrefs);
    MovieController.active.value = c;
    c.loadDrawings();
    c.loadShaders();
    c.prepareMedia();
  }

  /// Draw in content [id]: its drawing (a blank one the first time) in the
  /// editor; it comes back on every save.
  Future<void> _edit(String id) async {
    final open = widget.editDrawing, content = c.content(id);
    if (content?.kind == TrackKind.text && c.textOf(id) != null) {
      return editTextContent(context, c, id);
    }
    if (open == null || content == null) return;
    c.stop();
    final drawing = c.drawings[id] ?? c.newDrawingFor(content);
    if (!c.drawings.containsKey(id)) c.setDrawing(id, drawing);
    await open(
      context,
      drawing,
      (next) {
        if (c.content(id) != null) c.setDrawing(id, next);
      },
      // A Flipbook frame shown by hand: the movie there, its sound heard.
      onScrub: (page) {
        final x = c.content(id), doc = c.drawings[id];
        if (x == null || doc == null) return;
        for (var f = x.start; f < x.end; f++) {
          if (drawingAt(x, doc, f)?.page == page) {
            c.seek(f);
            c.scrub();
            return;
          }
        }
      },
    );
  }

  @override
  void dispose() {
    prefs.removeListener(_followPrefs);
    prefs.dispose();
    if (MovieController.active.value == c) MovieController.active.value = null;
    c.dispose();
    super.dispose();
  }

  Future<void> _settings() async {
    final l = AppLocalizations.of(context);
    final next = await showDialog<MovieDocument>(
      context: context,
      builder: (_) => MovieSettingsDialog(
        movie: c.movie,
        untitled: l.untitledMovie,
        flipbookName: l.movieStartFlipbook,
        recent: widget.recent,
      ),
    );
    if (next != null) c.applySettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          for (final MapEntry(:key, :value) in prefs.shortcuts.entries)
            value: () => _act(key),
        },
        child: child!,
      ),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const ValueKey('movie-screen'),
          backgroundColor: const Color(0xff26262a),
          body: SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final movie = c.movie;
                return Column(
                  children: [
                    Material(
                      color: scheme.surface,
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('movie-back'),
                            tooltip: l.theaterBack,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  movie.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  movieSummary(movie),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (c.saveError != null)
                            Tooltip(
                              message: l.operationFailed('${c.saveError}'),
                              child: Icon(
                                Icons.error_outline,
                                color: scheme.error,
                              ),
                            ),
                          IconButton(
                            key: const ValueKey('movie-undo'),
                            tooltip: l.undo,
                            onPressed: c.canUndo ? c.undo : null,
                            icon: const Icon(Icons.undo_rounded),
                          ),
                          IconButton(
                            key: const ValueKey('movie-redo'),
                            tooltip: l.redo,
                            onPressed: c.canRedo ? c.redo : null,
                            icon: const Icon(Icons.redo_rounded),
                          ),
                          IconButton(
                            key: const ValueKey('movie-export-open'),
                            tooltip: l.exportMovie,
                            onPressed: () => exportMovie(context, c),
                            icon: const Icon(Icons.ios_share_rounded),
                          ),
                          IconButton(
                            key: const ValueKey('movie-prefs-open'),
                            tooltip: l.moviePrefs,
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => MoviePrefsDialog(
                                prefs: prefs,
                                onRecovery: _recovery,
                              ),
                            ),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                          IconButton(
                            key: const ValueKey('movie-settings-open'),
                            tooltip: l.movieSettings,
                            onPressed: _settings,
                            icon: const Icon(Icons.tune),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          const bar = 14.0;
                          final room = box.maxHeight - bar;
                          final timeline = room * movie.view.split;
                          return Column(
                            children: [
                              SizedBox(
                                height: room - timeline,
                                child: StageView(
                                  controller: c,
                                  prefs: prefs,
                                  onEdit: widget.editDrawing == null
                                      ? null
                                      : _edit,
                                  onFullscreen: () => Navigator.of(context)
                                      .push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              FullscreenPreview(controller: c),
                                        ),
                                      ),
                                ),
                              ),
                              GestureDetector(
                                key: const ValueKey('timeline-divider'),
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (d) => c.setView(
                                  movie.view.copyWith(
                                    split:
                                        c.movie.view.split - d.delta.dy / room,
                                  ),
                                ),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeRow,
                                  child: SizedBox(
                                    height: bar,
                                    child: Center(
                                      child: Container(
                                        width: 48,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white38,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: timeline,
                                child: Material(
                                  color: scheme.surface,
                                  child: Timeline(
                                    controller: c,
                                    onEdit: _edit,
                                    askName: widget.askName,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
