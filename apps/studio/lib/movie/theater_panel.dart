import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/studio_storage.dart';
import '../domain/document.dart';
import '../domain/gallery.dart';
import '../domain/movie.dart';
import '../l10n/app_localizations.dart';
import 'movie_export.dart';
import 'movie_screen.dart';
import 'movie_settings.dart';

/// The Theater (Procreate Dreams' gallery): movies and folders in the
/// user's order; new, open, rename, copy, delete, folders; several at once
/// in selection mode.
class TheaterPanel extends StatefulWidget {
  const TheaterPanel({
    super.key,
    required this.storage,
    required this.askName,
    required this.run,
    this.recent = const [],
    this.editDrawing,
    this.preferences,
  });
  final StudioStorage storage;
  final Future<String?> Function(String current) askName;
  final Future<void> Function(Future<void> Function()) run;
  final List<int> recent;
  final EditDrawing? editDrawing;
  final SharedPreferences? preferences;

  @override
  State<TheaterPanel> createState() => _TheaterPanelState();
}

class _TheaterPanelState extends State<TheaterPanel> {
  late Future<MovieListing> movies = _load();
  GalleryLayout layout = GalleryLayout();
  String? openFolder;
  Set<String>? chosen;

  StudioStorage get storage => widget.storage;

  Future<MovieListing> _load() async {
    layout = GalleryLayout.fromJson(await storage.loadTheater());
    return storage.listMovies();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      movies = _load();
    });
  }

  Future<void> _keep(GalleryLayout next) async {
    setState(() => layout = next);
    await storage.saveTheater(next.toJson());
  }

  Future<void> _new() async {
    final l = AppLocalizations.of(context);
    final movie = await showDialog<MovieDocument>(
      context: context,
      builder: (_) => MovieSettingsDialog(
        untitled: l.untitledMovie,
        flipbookName: l.movieStartFlipbook,
        recent: widget.recent,
      ),
    );
    if (movie == null || !mounted) return;
    await widget.run(() async {
      await storage.saveMovie(movie);
      if (openFolder case final folder?) {
        await _keep(layout.addToStack(movie.id, folder));
      }
    });
    await _open(movie);
  }

  /// An `.artmovie` file brought in as a new movie.
  Future<void> _importProject() async {
    final l = AppLocalizations.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['artmovie', 'zip'],
    );
    if (picked.isEmpty || !mounted) return;
    MovieDocument? movie;
    await widget.run(() async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in picked.single.readAsByteStream()) {
        bytes.add(chunk);
      }
      movie = await importProject(
        bytes.takeBytes(),
        storage,
        Directory.systemTemp,
      );
    });
    if (!mounted) return;
    if (movie == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.importFailed)));
    }
    _reload();
  }

  Future<void> _open(MovieDocument movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieScreen(
          storage: storage,
          movie: movie,
          askName: widget.askName,
          recent: widget.recent,
          editDrawing: widget.editDrawing,
          preferences: widget.preferences,
        ),
      ),
    );
    _reload();
  }

  Future<void> _rename(MovieDocument movie) async {
    final name = (await widget.askName(movie.name))?.trim();
    if (name == null || name.isEmpty) return;
    await widget.run(
      () => storage.saveMovie(
        movie.copyWith(name: name, revision: movie.revision + 1),
      ),
    );
    _reload();
  }

  Future<void> _renameFolder(GalleryStack folder) async {
    final name = (await widget.askName(folder.name))?.trim();
    if (name == null || name.isEmpty) return;
    await _keep(layout.renameStack(folder.id, name));
  }

  Future<void> _duplicate(
    List<MovieDocument> picked,
    List<MovieDocument> all,
  ) async {
    final l = AppLocalizations.of(context);
    var next = layout;
    final ids = [for (final m in all) m.id];
    for (final movie in picked) {
      final copy = movie.copyWith(
        id: newId(),
        name: l.layerCopy(movie.name),
        revision: 0,
      );
      await storage.saveMovie(
        copy,
        drawings: await storage.loadMovieDrawings(movie.id),
      );
      ids.insert(0, copy.id);
      next = next.placeCopy(movie.id, copy.id, ids);
    }
    await _keep(next);
    _reload();
  }

  Future<void> _delete(Set<String> ids) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.theaterDeleteAsk(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('theater-delete-yes'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.galleryDelete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.run(() async {
      for (final id in ids) {
        await storage.deleteMovie(id);
      }
      chosen = null;
      await _keep(layout.without(ids));
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<MovieListing>(
      future: movies,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            children: [
              Text(l.operationFailed(snapshot.error.toString())),
              TextButton(onPressed: _reload, child: Text(l.retry)),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final listing = snapshot.data!;
        final all = listing.movies;
        final byId = {for (final m in all) m.id: m};
        final ids = [for (final m in all) m.id];
        final top = layout.entries(ids);
        final folder = openFolder == null
            ? null
            : top
                  .where((e) => e.id == openFolder && e.stack != null)
                  .firstOrNull;
        if (openFolder != null && folder == null) openFolder = null;
        final entries = folder == null
            ? top
            : [
                for (final m in folder.members)
                  (id: m, stack: null, members: const <String>[]),
              ];
        final shown = [
          for (final e in entries)
            if (e.stack == null) byId[e.id]!,
        ];
        final selecting = chosen != null;
        final picked = [
          for (final m in shown)
            if (chosen?.contains(m.id) ?? false) m,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (folder != null)
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('theater-folder-back'),
                    tooltip: l.theaterBack,
                    onPressed: () => setState(() {
                      openFolder = null;
                      chosen = null;
                    }),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      folder.stack!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('theater-new'),
                    onPressed: _new,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.newMovie),
                  ),
                ),
                IconButton(
                  key: const ValueKey('theater-import'),
                  tooltip: l.importProject,
                  onPressed: _importProject,
                  icon: const Icon(Icons.file_download_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!selecting)
                  TextButton.icon(
                    key: const ValueKey('theater-select'),
                    onPressed: shown.isEmpty
                        ? null
                        : () => setState(() => chosen = {}),
                    icon: const Icon(Icons.check_box_outlined, size: 18),
                    label: Text(l.gallerySelect),
                  )
                else ...[
                  Expanded(
                    child: Text(
                      l.gallerySelected(picked.length),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (folder == null)
                    IconButton(
                      key: const ValueKey('theater-folder'),
                      tooltip: l.theaterFolder,
                      onPressed: picked.isEmpty
                          ? null
                          : () => widget.run(() async {
                              await _keep(
                                layout.stackUp(
                                  newId(),
                                  l.theaterDefaultFolder,
                                  [for (final m in picked) m.id],
                                  ids,
                                ),
                              );
                              setState(() => chosen = null);
                            }),
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                  IconButton(
                    key: const ValueKey('theater-duplicate'),
                    tooltip: l.galleryDuplicate,
                    onPressed: picked.isEmpty
                        ? null
                        : () => widget.run(() async {
                            await _duplicate(picked, all);
                            setState(() => chosen = null);
                          }),
                    icon: const Icon(Icons.copy_outlined, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('theater-delete'),
                    tooltip: l.galleryDelete,
                    onPressed: picked.isEmpty
                        ? null
                        : () => _delete({for (final m in picked) m.id}),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                  IconButton(
                    tooltip: l.cancel,
                    onPressed: () => setState(() => chosen = null),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ],
            ),
            if (listing.unreadable.isNotEmpty)
              Text(
                l.theaterUnreadable(listing.unreadable.length),
                style: TextStyle(fontSize: 11, color: scheme.error),
              ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l.theaterEmpty,
                  key: const ValueKey('theater-empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: .95,
                children: [
                  for (final e in entries)
                    if (e.stack case final stack?)
                      _folderTile(stack, [
                        for (final m in e.members) byId[m]!,
                      ], ids)
                    else
                      _movieTile(byId[e.id]!, all, inFolder: folder != null),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _movieTile(
    MovieDocument movie,
    List<MovieDocument> all, {
    required bool inFolder,
  }) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final picked = chosen?.contains(movie.id) ?? false;
    return InkWell(
      key: ValueKey('theater-${movie.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: chosen != null
          ? () => setState(
              () => picked ? chosen!.remove(movie.id) : chosen!.add(movie.id),
            )
          : () => _open(movie),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff26262a),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: movie.width / movie.height,
                        child: CustomPaint(painter: StagePainter(movie)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 4,
                  child: Row(
                    children: [
                      for (final t in movie.tracks.take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            trackIcon(t.kind),
                            size: 14,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                if (chosen != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(
                      picked ? Icons.check_circle : Icons.circle_outlined,
                      color: picked ? scheme.primary : Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      movieSummary(movie),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (chosen == null)
                PopupMenuButton<String>(
                  key: ValueKey('theater-menu-${movie.id}'),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onSelected: (action) => switch (action) {
                    'rename' => _rename(movie),
                    'duplicate' => widget.run(() => _duplicate([movie], all)),
                    'unfolder' => _keep(
                      layout.unstackDocument(movie.id, [
                        for (final m in all) m.id,
                      ]),
                    ),
                    _ => _delete({movie.id}),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'rename', child: Text(l.rename)),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text(l.galleryDuplicate),
                    ),
                    if (inFolder)
                      PopupMenuItem(
                        value: 'unfolder',
                        child: Text(l.theaterRemoveFromFolder),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l.galleryDelete),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _folderTile(
    GalleryStack folder,
    List<MovieDocument> members,
    List<String> ids,
  ) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('theater-folder-${folder.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: chosen != null
          ? null
          : () => setState(() => openFolder = folder.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Badge(
                  label: Text('${members.length}'),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 48,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (chosen == null)
                PopupMenuButton<String>(
                  key: ValueKey('theater-folder-menu-${folder.id}'),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onSelected: (action) => action == 'rename'
                      ? _renameFolder(folder)
                      : _keep(layout.dissolve(folder.id, ids)),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'rename', child: Text(l.rename)),
                    PopupMenuItem(
                      value: 'dissolve',
                      child: Text(l.theaterUnfolder),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
