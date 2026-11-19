import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../data/studio_storage.dart';
import '../domain/document.dart';
import '../domain/gallery.dart';
import '../drawing/brush_engine.dart';
import '../drawing/raster_cache.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';

/// The gallery: drawings and stacks in the user's order; open, rename,
/// copy, delete, stack, preview; several at once in selection mode.
class GalleryPanel extends StatefulWidget {
  const GalleryPanel({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onNew,
    required this.askName,
    required this.run,
  });
  final StudioController controller;
  final Future<void> Function(ArtDocument) onOpen;
  final VoidCallback onNew;
  final Future<String?> Function(String current) askName;
  final Future<void> Function(Future<void> Function()) run;
  @override
  State<GalleryPanel> createState() => _GalleryPanelState();
}

class _GalleryPanelState extends State<GalleryPanel> {
  late Future<GalleryListing> documents = _load();
  GalleryLayout layout = GalleryLayout();

  /// The stack being looked into.
  String? openStack;

  /// Selection mode: the chosen drawings.
  Set<String>? chosen;

  StudioController get c => widget.controller;
  StudioStorage get storage => c.storage;

  Future<GalleryListing> _load() async {
    await c.save();
    if (c.saveState == SaveState.failed) {
      throw StateError(c.error ?? 'Save failed');
    }
    layout = GalleryLayout.fromJson(await storage.loadGallery());
    return storage.listDocuments();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      documents = _load();
    });
  }

  Future<void> _keep(GalleryLayout next) async {
    setState(() => layout = next);
    await storage.saveGallery(next.toJson());
  }

  /// The open drawing as it is now; any other as saved.
  ArtDocument _latest(ArtDocument doc) =>
      doc.id == c.document.id ? c.document : doc;

  Future<void> _rename(ArtDocument doc) async {
    final name = (await widget.askName(doc.name))?.trim();
    if (name == null || name.isEmpty) return;
    await widget.run(() async {
      if (doc.id == c.document.id) {
        c.renameDocument(name);
        await c.save();
      } else {
        await storage.saveToGallery(doc.copyWith(name: name));
      }
    });
    _reload();
  }

  Future<void> _renameStack(GalleryStack stack) async {
    final name = (await widget.askName(stack.name))?.trim();
    if (name == null || name.isEmpty) return;
    await _keep(layout.renameStack(stack.id, name));
  }

  Future<void> _duplicate(List<ArtDocument> docs, List<ArtDocument> all) async {
    final l = AppLocalizations.of(context);
    var next = layout;
    final everything = [...all];
    for (final doc in docs) {
      final copy = _latest(doc)
          .copyWith(id: newId(), name: l.layerCopy(doc.name), revision: 0);
      await storage.saveToGallery(copy);
      everything.insert(0, copy);
      next = next.placeCopy(doc.id, copy.id, [
        for (final d in everything) d.id,
      ]);
    }
    await _keep(next);
    _reload();
  }

  Future<void> _delete(Set<String> ids, List<ArtDocument> all) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.galleryDeleteAsk(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('gallery-delete-yes'),
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
      if (ids.contains(c.document.id)) {
        // The open drawing goes: another one opens (a new one if none is
        // left) before it is deleted, so no save brings it back.
        final rest = all.where((d) => !ids.contains(d.id)).firstOrNull;
        await c.replaceDocument(
          rest ??
              ArtDocument.empty(
                name: l.untitled,
                dimensions: c.document.dimensions,
              ),
        );
      }
      for (final id in ids) {
        await storage.deleteDocument(id);
        await c.timelapse?.delete(id);
      }
      chosen = null;
      await _keep(layout.without(ids));
    });
    _reload();
  }

  Future<void> _preview(List<ArtDocument> docs, int index) => showDialog<void>(
    context: context,
    builder: (context) => _Preview(
      documents: docs,
      initial: index,
      onOpen: (doc) {
        Navigator.pop(context);
        widget.onOpen(doc);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<GalleryListing>(
      future: documents,
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
        final all = listing.documents;
        final top = layout.arrange(all);
        final stack = openStack == null
            ? null
            : top
                  .whereType<GalleryStackItem>()
                  .where((s) => s.id == openStack)
                  .firstOrNull;
        if (openStack != null && stack == null) openStack = null;
        final items = stack == null
            ? top
            : [for (final d in stack.documents) GalleryDrawing(d)];
        final shown = [
          for (final item in items)
            if (item is GalleryDrawing) item.document,
        ];
        final selecting = chosen != null;
        final picked = [
          for (final d in all)
            if (chosen?.contains(d.id) ?? false) d,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stack != null)
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('gallery-back'),
                    tooltip: l.galleryBack,
                    onPressed: () => setState(() {
                      openStack = null;
                      chosen = null;
                    }),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      stack.stack.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: widget.onNew,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.newDocument),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!selecting) ...[
                  TextButton.icon(
                    key: const ValueKey('gallery-select'),
                    onPressed: () => setState(() => chosen = {}),
                    icon: const Icon(Icons.check_box_outlined, size: 18),
                    label: Text(l.gallerySelect),
                  ),
                  const Spacer(),
                  barHint(l.galleryHint),
                ] else ...[
                  Expanded(
                    child: Text(
                      l.gallerySelected(picked.length),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (stack == null)
                    IconButton(
                      key: const ValueKey('gallery-stack'),
                      tooltip: l.galleryStack,
                      onPressed: picked.isEmpty
                          ? null
                          : () => widget.run(() async {
                              await _keep(
                                layout.stackUp(
                                  newId(),
                                  l.galleryDefaultStack,
                                  [
                                    for (final d in shown)
                                      if (chosen!.contains(d.id)) d.id,
                                  ],
                                  [for (final d in all) d.id],
                                ),
                              );
                              setState(() => chosen = null);
                            }),
                      icon: const Icon(Icons.layers_outlined, size: 20),
                    ),
                  IconButton(
                    key: const ValueKey('gallery-duplicate'),
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
                    key: const ValueKey('gallery-delete'),
                    tooltip: l.galleryDelete,
                    onPressed: picked.isEmpty
                        ? null
                        : () => _delete({for (final d in picked) d.id}, all),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('gallery-select-done'),
                    tooltip: l.cancel,
                    onPressed: () => setState(() => chosen = null),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ],
            ),
            if (listing.unreadable.isNotEmpty) ...[
              Text(
                l.galleryUnreadable(listing.unreadable.length),
                key: const ValueKey('gallery-unreadable'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: .8,
              children: [
                for (final item in items)
                  _target(item, all, switch (item) {
                    GalleryDrawing(:final document) => _drawing(
                      document,
                      all,
                      shown,
                      inStack: stack != null,
                    ),
                    GalleryStackItem() => _stack(item, all),
                  }),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Dropping a drawing on [item]: into it (a stack) or just before it.
  Widget _target(GalleryItem item, List<ArtDocument> all, Widget child) =>
      DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != item.id,
        onAcceptWithDetails: (d) => widget.run(
          () => _keep(
            item is GalleryStackItem && layout.stack(d.data) == null
                ? layout.addToStack(d.data, item.id)
                : layout.move(d.data, item.id, [for (final d in all) d.id]),
          ),
        ),
        builder: (context, candidates, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              width: 2,
              color: candidates.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child,
        ),
      );

  Widget _draggable(String id, Widget preview, Widget child) => chosen != null
      ? child
      : LongPressDraggable<String>(
          data: id,
          feedback: Opacity(
            opacity: .8,
            child: SizedBox(width: 120, height: 120, child: preview),
          ),
          childWhenDragging: Opacity(opacity: .3, child: child),
          child: child,
        );

  Widget _drawing(
    ArtDocument doc,
    List<ArtDocument> all,
    List<ArtDocument> shown, {
    required bool inStack,
  }) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final picked = chosen?.contains(doc.id) ?? false;
    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: _Thumbnail(
        key: ValueKey('${doc.id}:${doc.revision}:${doc.name}'),
        document: doc,
      ),
    );
    return _draggable(
      doc.id,
      thumbnail,
      InkWell(
        key: ValueKey('gallery-${doc.id}'),
        onTap: chosen != null
            ? () => setState(
                () => picked ? chosen!.remove(doc.id) : chosen!.add(doc.id),
              )
            : () => widget.onOpen(doc),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: doc.id == c.document.id
                          ? Border.all(color: scheme.primary, width: 2)
                          : null,
                    ),
                    child: thumbnail,
                  ),
                  if (chosen != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        picked ? Icons.check_circle : Icons.circle_outlined,
                        color: picked ? scheme.primary : Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 3, color: Colors.black54),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (chosen == null)
                  _compact(
                    PopupMenuButton<String>(
                      key: ValueKey('gallery-menu-${doc.id}'),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onSelected: (action) => switch (action) {
                        'rename' => _rename(doc),
                        'duplicate' => widget.run(() => _duplicate([doc], all)),
                        'preview' => _preview(shown, shown.indexOf(doc)),
                        'unstack' => _keep(
                          layout.unstackDocument(doc.id, [
                            for (final d in all) d.id,
                          ]),
                        ),
                        _ => _delete({doc.id}, all),
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'preview',
                          child: Text(l.galleryPreview),
                        ),
                        PopupMenuItem(value: 'rename', child: Text(l.rename)),
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text(l.galleryDuplicate),
                        ),
                        if (inStack)
                          PopupMenuItem(
                            value: 'unstack',
                            child: Text(l.galleryRemoveFromStack),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l.galleryDelete),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stack(GalleryStackItem item, List<ArtDocument> all) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final front = item.documents.first;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: _Thumbnail(
        key: ValueKey('${front.id}:${front.revision}:${front.name}'),
        document: front,
      ),
    );
    return _draggable(
      item.id,
      cover,
      InkWell(
        key: ValueKey('gallery-${item.id}'),
        onTap: chosen != null
            ? null
            : () => setState(() => openStack = item.id),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The drawings behind, as a pile.
                  for (final shift in const [8.0, 4.0])
                    Padding(
                      padding: EdgeInsets.only(left: shift, bottom: shift),
                      child: Transform.translate(
                        offset: Offset(shift, -shift) * .5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: cover,
                  ),
                  Positioned(
                    right: 12,
                    bottom: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        child: Text(
                          '${item.documents.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.layers_outlined, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.stack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (chosen == null)
                  _compact(
                    PopupMenuButton<String>(
                      key: ValueKey('gallery-menu-${item.id}'),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onSelected: (action) => action == 'rename'
                          ? _renameStack(item.stack)
                          : _keep(
                              layout.dissolve(item.id, [
                                for (final d in all) d.id,
                              ]),
                            ),
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'rename', child: Text(l.rename)),
                        PopupMenuItem(
                          value: 'dissolve',
                          child: Text(l.galleryUnstack),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tile's ⋯ menu, small enough not to make the tile taller.
Widget _compact(Widget menu) => SizedBox(width: 28, height: 28, child: menu);

/// Full screen: swipe between drawings, pinch to look closer.
class _Preview extends StatefulWidget {
  const _Preview({
    required this.documents,
    required this.initial,
    required this.onOpen,
  });
  final List<ArtDocument> documents;
  final int initial;
  final ValueChanged<ArtDocument> onOpen;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final doc = widget.documents[_page];
    return Dialog.fullscreen(
      key: const ValueKey('gallery-preview'),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView(
            controller: _pages,
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              for (final d in widget.documents)
                InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: d.dimensions.width / d.dimensions.height,
                      child: _Thumbnail(document: d, side: 1600),
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('gallery-preview-close'),
                    tooltip: l.cancel,
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      '${doc.name}  ·  ${_page + 1}/${widget.documents.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('gallery-preview-open'),
                    tooltip: l.openDocument,
                    color: Colors.white,
                    onPressed: () => widget.onOpen(doc),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({super.key, required this.document, this.side = 160});
  final ArtDocument document;

  /// The longest side rendered, in pixels.
  final double side;
  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  // Decode one document at a time to bound native pixel memory in large galleries.
  static Future<void> _tail = Future.value();
  late final Future<Uint8List> preview = _queue();
  Future<Uint8List> _queue() {
    final task = _tail.then((_) => _render());
    _tail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<Uint8List> _render() async {
    final cache = RasterCache();
    ui.Image? image;
    ui.Picture? picture;
    try {
      if (!mounted) return Uint8List(0);
      await cache.prepare(documentRasters(widget.document));
      final dimensions = widget.document.dimensions;
      final scale = widget.side / math.max(dimensions.width, dimensions.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(scale);
      paintDocument(
        canvas,
        widget.document,
        FreehandBrushEngine(),
        rasterImages: cache.images,
      );
      picture = recorder.endRecording();
      image = await picture.toImage(
        math.max(1, (dimensions.width * scale).round()),
        math.max(1, (dimensions.height * scale).round()),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Thumbnail encoding failed');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image?.dispose();
      picture?.dispose();
      cache.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (documentRasters(widget.document).isEmpty) {
      return CustomPaint(painter: _InkThumbnail(widget.document));
    }
    return FutureBuilder<Uint8List>(
      future: preview,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}

class _InkThumbnail extends CustomPainter {
  _InkThumbnail(this.document);
  final ArtDocument document;
  @override
  void paint(Canvas canvas, Size size) {
    final dimensions = document.dimensions;
    canvas.save();
    canvas.scale(
      math.min(size.width / dimensions.width, size.height / dimensions.height),
    );
    paintDocument(canvas, document, FreehandBrushEngine());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InkThumbnail old) => document != old.document;
}
