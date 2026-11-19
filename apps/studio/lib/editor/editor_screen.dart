import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/asset_importer.dart';
import '../data/document_package.dart';
import '../domain/canvas_preset.dart';
import '../domain/document.dart';
import '../drawing/adjustments.dart';
import '../drawing/brush_engine.dart';
import '../drawing/color_pick.dart';
import '../drawing/native_stroke.dart';
import '../drawing/stamp_shapes.dart';
import '../drawing/raster_cache.dart';
import '../l10n/app_localizations.dart';
import 'drawing_surface.dart';
import 'pen_probe.dart';
import 'gallery_panel.dart';
import '../drawing/symmetry.dart';
import 'adjustment_bar.dart';
import 'adjustment_editors.dart';
import 'brush_studio.dart';
import 'canvas_navigation.dart';
import 'clone_bar.dart';
import 'crop_bar.dart';
import 'exporter.dart';
import 'text_bar.dart';
import 'quick_menu.dart';
import 'quick_menu_overlay.dart';
import 'page_bar.dart';
import 'animation_bar.dart';
import 'timelapse_player.dart';
import 'reference_window.dart';
import '../data/font_library.dart';
import '../data/brush_formats.dart';
import '../data/import_formats.dart';
import '../data/palette_formats.dart';
import '../data/timelapse.dart';
import 'guide_bar.dart';
import 'liquify_bar.dart';
import 'overlay_bar.dart';
import 'color_picker.dart';
import 'color_names.dart';
import 'copy_paste_menu.dart';
import 'generative_bar.dart';
import 'history_banner.dart';
import 'hub_panel.dart';
import '../mcp/mcp_service.dart';
import '../mcp/mcp_settings.dart';
import 'layers_panel.dart';
import 'studio_controller.dart';
import 'transform_bar.dart';
import 'value_slider.dart';
import 'selection_bar.dart';
import 'drawing_storage.dart';
import '../data/media.dart';
import 'mini_flipbook.dart';
import '../movie/theater_panel.dart';

/// Android maps picker extensions to MIME types and iOS to UTIs; formats
/// without a registered type (.artdoc, .myb, .gpl, .ase, .aco, .swatches)
/// would be greyed out there. Mobile pickers show every file instead and the
/// extension is checked after picking ([requireExtension]).
final pickAnyFile = Platform.isAndroid || Platform.isIOS;

void requireExtension(String name, List<String> extensions) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || !extensions.contains(name.substring(dot + 1).toLowerCase())) {
    throw UnsupportedFile(name);
  }
}

class UnsupportedFile implements Exception {
  const UnsupportedFile(this.name);
  final String name;
  @override
  String toString() => 'Unsupported file: $name';
}

Future<Uint8List> readLimitedImportedFile(PlatformFile file, int limit) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    if (builder.length + chunk.length > limit) {
      throw const FormatException('File exceeds import size limit');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.mcp,
  });
  final StudioController controller;

  /// The MCP server's setting (the main editor only).
  final McpService? mcp;

  /// Set when it edits a drawing inside a movie: back to the movie in
  /// place of the gallery.
  final VoidCallback? onExit;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _engine = FreehandBrushEngine();

  /// The gallery shows the Theater's movies instead of drawings.
  bool _theater = false;
  final _transformation = TransformationController();
  final _surface = GlobalKey<DrawingSurfaceState>();
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;
  StudioController get c => widget.controller;
  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    PenProbe.instance.watchFrames(() {
      final d = c.document;
      return '${d.dimensions} ${d.layers.length} layers, '
          'active ${d.layers.indexWhere((l) => l.id == d.activeLayerId) + 1}, '
          'flatten ${c.flattenLayers}';
    });
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(c.settleStroke().then((_) => c.save())),
      onExitRequested: () async {
        await c.settleStroke();
        await c.save();
        return c.saveState == SaveState.failed
            ? ui.AppExitResponse.cancel
            : ui.AppExitResponse.exit;
      },
    );
    _strokeFailures = c.strokeFailures.listen((error) {
      if (mounted) _message(l.operationFailed(error.toString()));
    });
    c.textLayerTouched.addListener(_askRasterize);
    c.addListener(_syncQuickMenu);
    c.historyNotice.addListener(_clickSound);
    c.colorPicked.addListener(_clickSound);
    if (widget.onExit == null) unawaited(_openTimelapse());
    unawaited(_loadFonts());
  }

  /// Feedback sounds: a click when an undo, redo or colour pick lands.
  void _clickSound() {
    if (c.feedbackSounds) unawaited(SystemSound.play(SystemSoundType.click));
  }

  final _quickPortal = OverlayPortalController();

  /// The QuickMenu lives in the root overlay, over panels and bars.
  void _syncQuickMenu() {
    final open = c.quickMenuAt != null;
    if (open == _quickPortal.isShowing) return;
    open ? _quickPortal.show() : _quickPortal.hide();
  }

  void _quickAction(QuickAction action) {
    c.closeQuickMenu();
    final layer = c.document.activeLayer;
    switch (action) {
      case QuickAction.newLayer:
        c.addLayer(l.layerName(c.document.layers.length + 1));
      case QuickAction.duplicateLayer:
        c.duplicateLayer(layer.id, l.layerCopy(layer.name));
      case QuickAction.mergeDown:
        _run(() => c.mergeDown(layer.id));
      case QuickAction.clearLayer:
        _run(c.clearActiveLayer);
      case QuickAction.hideLayer:
        c.updateLayer(layer.id, (l) => l.copyWith(visible: !l.visible));
      case QuickAction.alphaLock:
        c.toggleAlphaLock(layer.id);
      case QuickAction.clippingMask:
        c.toggleClipping(layer.id);
      case QuickAction.fillLayer:
        _run(c.fillActiveLayer);
      case QuickAction.invertLayer:
        _run(c.invertActiveLayer);
      case QuickAction.undo:
        c.undo();
      case QuickAction.redo:
        c.redo();
      case QuickAction.brush:
        c.selectTool(StudioTool.brush);
      case QuickAction.smudge:
        c.selectTool(StudioTool.smudge);
      case QuickAction.eraser:
        c.selectTool(StudioTool.eraser);
      case QuickAction.eyedropper:
        c.selectTool(StudioTool.eyedropper);
      case QuickAction.selection:
        c.selectTool(StudioTool.selection);
      case QuickAction.transform:
        c.selectTool(StudioTool.transform);
      case QuickAction.deselect:
        c.setSelection(null);
      case QuickAction.invertSelection:
        c.invertSelection();
      case QuickAction.cut:
        _run(c.cut);
      case QuickAction.copy:
        _run(() async => c.copy());
      case QuickAction.paste:
        _run(() => c.paste(l.pastedLayer));
      case QuickAction.flipHorizontal:
        _run(() => c.flipCanvas(horizontal: true));
      case QuickAction.flipVertical:
        _run(() => c.flipCanvas(horizontal: false));
      case QuickAction.swapColor:
        c.swapColor();
      case QuickAction.addText:
        c.addText(l.textDefault, fallbackName: l.textDefault);
      case QuickAction.liquify:
        _run(() async => c.startLiquify());
      case QuickAction.fullScreen:
        c.toggleFullScreen();
      case QuickAction.layers:
        c.setPanel(EditorPanel.layers);
      case QuickAction.colors:
        c.setPanel(EditorPanel.colors);
      case QuickAction.brushes:
        c.setPanel(EditorPanel.brushes);
      case QuickAction.adjustments:
        c.setPanel(EditorPanel.adjustments);
      case QuickAction.reference:
        c.toggleReference();
    }
  }

  Future<FontLibrary>? _fonts;

  Future<void> _loadFonts() async {
    try {
      final library = await (_fonts ??= FontLibrary.open());
      for (final (family, bytes) in await library.load()) {
        await c.loadFont(family, bytes);
      }
    } on Object {
      // No fonts folder (tests) or an unreadable font: system fonts only.
    }
  }

  Future<void> _importFont() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: FontLibrary.extensions,
    );
    if (selected.isEmpty) return;
    final file = selected.single;
    final bytes = await readLimitedImportedFile(file, FontLibrary.maxBytes);
    final family = await (await (_fonts ??= FontLibrary.open())).add(
      file.name,
      bytes,
    );
    await c.loadFont(family, bytes);
    c.setText((t) => t.copyWith(font: family));
    if (mounted) _message(l.importSuccess(file.name));
  }

  bool _asking = false;

  /// Painting on a text layer: rasterise it first, if wanted.
  Future<void> _askRasterize() async {
    if (c.feedbackSounds) unawaited(SystemSound.play(SystemSoundType.alert));
    if (_asking || !mounted) return;
    final id = c.document.activeLayerId;
    _asking = true;
    try {
      // The first tap of a double tap, which opens the text instead.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted ||
          c.textEditing != null ||
          c.document.activeLayerId != id ||
          c.document.activeLayer.text == null) {
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.rasterizeAsk),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('rasterize-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.rasterize),
            ),
          ],
        ),
      );
      if (yes == true) await _run(() => c.rasterizeText(id));
    } finally {
      _asking = false;
    }
  }

  late final StreamSubscription<Object> _strokeFailures;

  @override
  void dispose() {
    c.textLayerTouched.removeListener(_askRasterize);
    c.removeListener(_syncQuickMenu);
    c.historyNotice.removeListener(_clickSound);
    c.colorPicked.removeListener(_clickSound);
    unawaited(_strokeFailures.cancel());
    _lifecycle.dispose();
    _transformation.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on UnsupportedFile catch (error) {
      if (mounted) _message(l.unsupportedFile(error.name));
    } catch (error) {
      if (mounted) _message(l.operationFailed(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _escape() {
    if (c.quickMenuAt != null) {
      c.closeQuickMenu();
      return;
    }
    if (c.textEditing != null) {
      c.finishText();
      return;
    }
    if (c.shapeEdit != null) {
      c.finishShapeEdit(keep: false);
      return;
    }
    if (c.adjustment != null) {
      c.cancelAdjustment();
      return;
    }
    if (c.liquify != null) {
      c.cancelLiquify();
      return;
    }
    if (c.clone != null) {
      c.cancelClone();
      return;
    }
    if (c.canvasCrop != null) {
      c.cancelCanvasCrop();
      return;
    }
    if (c.guideEditing) {
      c.setGuideEditing(false);
      return;
    }
    if (c.fillSession != null) {
      c.endFill();
      return;
    }
    if (c.fullScreen) {
      c.toggleFullScreen();
      return;
    }
    if (c.panel != null || c.transformDraft != null) {
      _closePanel();
      return;
    }
    if (c.tool == StudioTool.selection || c.selection != null) {
      c.setSelection(null);
      c.selectTool(StudioTool.brush);
    }
  }

  Future<void> _exportSelectionMask() async {
    final region = c.selection;
    if (region == null) return;
    final bytes = await renderSelectionMaskPng(region, c.document.dimensions);
    final path = await FilePicker.saveFile(
      fileName: '$_filename-mask.png',
      bytes: bytes,
      mimeType: 'image/png',
    );
    if (path != null && mounted) _message(l.exportSuccess);
  }

  void _closePanel() {
    if (c.transformDraft != null) c.cancelTransform();
    if (c.panel != null) c.setPanel(null);
  }

  /// A built-in brush's name in the app's language, unless renamed.
  String _brushName(BrushPreset b) =>
      initialBrushes.any((o) => o.id == b.id && o.name == b.name)
      ? _builtinName(b)
      : b.name;

  String _builtinName(BrushPreset b) => switch (b.id) {
    'ink' => l.ink,
    'pencil' => l.pencil,
    'marker' => l.marker,
    'mypaint-charcoal' => l.charcoal,
    'mypaint-modelling' => l.modelling,
    'stamp-graphite' => l.graphiteBrush,
    'stamp-pastel' => l.pastelBrush,
    'stamp-dry-brush' => l.dryBrush,
    'stamp-gouache' => l.gouacheBrush,
    'stamp-splatter' => l.splatterBrush,
    _ => b.name,
  };

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: c, builder: (context, _) => _editor());

  /// Procreate's keyboard shortcuts (⌘ on macOS, Ctrl elsewhere).
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final mac = Platform.isMacOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: mac, control: !mac, shift: shift);
    void size(double step) => c.setSize(c.size + step * 127);
    void nudge(double dx, double dy) {
      final draft = c.transformDraft;
      if (draft != null) {
        c.previewTransform(draft.translated(Offset(dx, dy)));
      }
    }

    return {
      cmd(LogicalKeyboardKey.keyZ): c.undo,
      cmd(LogicalKeyboardKey.keyZ, shift: true): c.redo,
      cmd(LogicalKeyboardKey.keyS): () => _run(c.save),
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
      const SingleActivator(LogicalKeyboardKey.enter): () {
        if (c.adjustment != null) _run(c.applyAdjustment);
        if (c.liquify != null) _run(c.applyLiquify);
        if (c.clone != null) _run(c.applyClone);
        if (c.canvasCrop != null) _run(c.applyCanvasCrop);
        if (c.transformDraft != null) _run(c.applyTransform);
      },
      // Tools: a second press opens the brush library.
      const SingleActivator(LogicalKeyboardKey.keyB): () =>
          c.tool == StudioTool.brush
          ? c.setPanel(EditorPanel.brushes)
          : c.selectTool(StudioTool.brush),
      const SingleActivator(LogicalKeyboardKey.keyE): () =>
          c.tool == StudioTool.eraser
          ? c.setPanel(EditorPanel.brushes)
          : c.selectTool(StudioTool.eraser),
      const SingleActivator(LogicalKeyboardKey.keyS): () =>
          c.selectTool(StudioTool.selection),
      const SingleActivator(LogicalKeyboardKey.keyV): () =>
          c.selectTool(StudioTool.transform),
      const SingleActivator(LogicalKeyboardKey.keyL): () =>
          c.setPanel(EditorPanel.layers),
      const SingleActivator(LogicalKeyboardKey.keyC): () =>
          c.setPanel(EditorPanel.colors),
      const SingleActivator(LogicalKeyboardKey.keyX): c.swapColor,
      // Brush size: ±5 %, with ⌘ ±1 %, with ⇧ ±10 % of the slider.
      const SingleActivator(LogicalKeyboardKey.bracketLeft): () => size(-.05),
      const SingleActivator(LogicalKeyboardKey.bracketRight): () => size(.05),
      cmd(LogicalKeyboardKey.bracketLeft): () => size(-.01),
      cmd(LogicalKeyboardKey.bracketRight): () => size(.01),
      const SingleActivator(LogicalKeyboardKey.bracketLeft, shift: true): () =>
          size(-.1),
      const SingleActivator(LogicalKeyboardKey.bracketRight, shift: true): () =>
          size(.1),
      cmd(LogicalKeyboardKey.keyJ): () => c.duplicateLayer(
        c.document.activeLayerId,
        l.layerCopy(c.document.activeLayer.name),
      ),
      cmd(LogicalKeyboardKey.keyD): () => c.setSelection(null),
      cmd(LogicalKeyboardKey.keyC): () => _run(() async => c.copy()),
      cmd(LogicalKeyboardKey.keyX): () => _run(c.cut),
      cmd(LogicalKeyboardKey.keyV): () => _run(() => c.paste(l.pastedLayer)),
      cmd(LogicalKeyboardKey.keyA): () => _run(() async => c.copy(all: true)),
      cmd(LogicalKeyboardKey.backspace): c.clearActiveLayer,
      cmd(LogicalKeyboardKey.digit0): c.toggleFullScreen,
      // Transform: arrows move the content one canvas pixel.
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => nudge(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => nudge(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => nudge(0, -1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => nudge(0, 1),
    };
  }

  /// Shortcuts step aside while a text field has focus: letters and ⌘Z
  /// belong to the text then.
  Widget _editor() => Shortcuts(
    shortcuts: {
      for (final MapEntry(:key, :value) in _shortcuts.entries)
        key: VoidCallbackIntent(value),
    },
    child: Actions(
      actions: {VoidCallbackIntent: _CanvasShortcutAction()},
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop:
              c.panel == null &&
              c.transformDraft == null &&
              c.tool != StudioTool.selection,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _escape();
          },
          child: OverlayPortal(
            controller: _quickPortal,
            overlayLocation: OverlayChildLocation.rootOverlay,
            overlayChildBuilder: (_) => QuickMenuOverlay(
              controller: c,
              onAction: _quickAction,
              askName: _askName,
            ),
            child: Scaffold(
              body: SafeArea(
                // Stretch: the workspace takes the full width whatever its
                // overlays (in full screen nothing else sizes it).
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!c.fullScreen) _fading(_toolbar()),
                    Expanded(
                      child: c.initialized
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  // A colour dropped on the canvas fills there.
                                  child: DragTarget<int>(
                                    onAcceptWithDetails: (drop) {
                                      final point = _surface.currentState
                                          ?.documentPoint(drop.offset);
                                      if (point != null) {
                                        _run(
                                          () => c.colorDrop(
                                            point,
                                            color: drop.data,
                                          ),
                                        );
                                      }
                                    },
                                    builder: (context, _, _) => DrawingSurface(
                                      key: _surface,
                                      controller: c,
                                      engine: _engine,
                                      transformation: _transformation,
                                      onQuickAction: _quickAction,
                                    ),
                                  ),
                                ),
                                if (c.lastQuickShape != null ||
                                    c.shapeEdit != null)
                                  _shapeBar(),
                                if (c.fillSession != null) _fillBar(),
                                if (c.panel != null)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _closePanel,
                                      child: const ColoredBox(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                if (c.copyPasteMenu)
                                  Positioned.fill(
                                    child: CopyPasteMenu(
                                      controller: c,
                                      run: _run,
                                    ),
                                  ),
                                Positioned(
                                  top: 10,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: HistoryBanner(
                                      notice: c.historyNotice,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 48,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: _ColorNameBanner(controller: c),
                                  ),
                                ),
                                if (c.singleTouch && !c.fullScreen)
                                  Positioned(
                                    right: c.rightSidebar ? 60 : 8,
                                    bottom: 16,
                                    child: _SingleTouchPad(
                                      controller: c,
                                      onFit: () => _transformation.value =
                                          Matrix4.identity(),
                                    ),
                                  ),
                                if (c.fullScreen)
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: IconButton.filledTonal(
                                      key: const ValueKey('exit-full-screen'),
                                      tooltip: l.exitFullScreen,
                                      onPressed: c.toggleFullScreen,
                                      icon: const Icon(Icons.fullscreen_exit),
                                    ),
                                  ),
                                if (!c.fullScreen &&
                                    c.transformDraft == null &&
                                    c.tool != StudioTool.selection)
                                  LayoutBuilder(
                                    builder: (context, box) => Align(
                                      alignment: Alignment(
                                        c.rightSidebar ? 1 : -1,
                                        c.sidebarPosition * 2 - 1,
                                      ),
                                      child: _fading(
                                        _sidebar(travel: box.maxHeight - 440),
                                      ),
                                    ),
                                  ),
                                if (c.document.animating &&
                                    c.miniFlipbook &&
                                    c.panel == null)
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (context, box) => Stack(
                                        children: [
                                          MiniFlipbook(
                                            controller: c,
                                            workspace: box.biggest,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (c.referenceOpen)
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (context, box) => Stack(
                                        children: [
                                          ReferenceWindow(
                                            controller: c,
                                            workspace: box.biggest,
                                            onImport: () =>
                                                _run(_importReference),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (c.panel != null) _panel(),
                                if (c.canvasCrop != null)
                                  CropBar(controller: c, run: _run),
                                if (c.editedText != null)
                                  TextBar(
                                    key: ValueKey('text-${c.textEditing}'),
                                    controller: c,
                                    run: _run,
                                    onImportFont: () => _run(_importFont),
                                  ),
                                if (c.guideEditing) GuideBar(controller: c),
                                if (c.clone != null)
                                  CloneBar(
                                    controller: c,
                                    onApply: () => _run(c.applyClone),
                                  ),
                                if (c.liquify != null)
                                  LiquifyBar(
                                    controller: c,
                                    onApply: () => _run(c.applyLiquify),
                                  ),
                                if (c.adjustment != null)
                                  AdjustmentBar(
                                    controller: c,
                                    onApply: () => _run(c.applyAdjustment),
                                  ),
                                if (c.panel == null &&
                                    c.transformDraft == null &&
                                    c.adjustment == null &&
                                    c.liquify == null &&
                                    c.clone == null &&
                                    c.canvasCrop == null &&
                                    !c.guideEditing)
                                  ListenableBuilder(
                                    listenable: c.hubJob,
                                    builder: (context, _) {
                                      final job = c.hubJob;
                                      if (c.hub.paired &&
                                          (job.open ||
                                              job.busy ||
                                              job.pending)) {
                                        return GenerativeBar(controller: c);
                                      }
                                      if (c.tool != StudioTool.selection) {
                                        if (c.textEditing != null) {
                                          return const SizedBox.shrink();
                                        }
                                        if (c.document.animating) {
                                          return c.miniFlipbook
                                              ? const SizedBox.shrink()
                                              : AnimationBar(controller: c);
                                        }
                                        return c.document.pageAssist
                                            ? PageBar(controller: c)
                                            : const SizedBox.shrink();
                                      }
                                      return SelectionBar(
                                        controller: c,
                                        onDelete: () =>
                                            _run(c.deleteSelectedPixels),
                                        onMask: () => _run(() async {
                                          c.maskLayerFromSelection();
                                        }),
                                        onExport: () =>
                                            _run(_exportSelectionMask),
                                        onDuplicate: () => _run(
                                          () => c.duplicateContent(
                                            l.fromSelection,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                if (c.transformDraft != null)
                                  TransformBar(
                                    controller: c,
                                    onApply: () => _run(c.applyTransform),
                                  ),
                                if (_busy || c.documentTransition)
                                  const Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                              ],
                            )
                          : _restoreError(),
                    ),
                    if (!c.fullScreen) _footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toolbar() {
    final left = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.onExit case final exit?)
          TextButton.icon(
            key: const ValueKey('editor-exit'),
            onPressed: () async {
              await c.settleStroke();
              await c.save();
              exit();
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l.backToMovie),
          )
        else
          TextButton(
            onPressed: () => c.setPanel(EditorPanel.gallery),
            child: Text(l.gallery),
          ),
        _button(
          l.actions,
          Icons.tune_outlined,
          () => c.setPanel(EditorPanel.actions),
          selected: c.panel == EditorPanel.actions,
        ),
        _button(
          l.adjustments,
          Icons.auto_fix_high_outlined,
          () => c.setPanel(EditorPanel.adjustments),
          selected:
              c.panel == EditorPanel.adjustments ||
              c.adjustment != null ||
              c.liquify != null ||
              c.clone != null,
        ),
        _button(l.undo, Icons.undo_rounded, c.canUndo ? c.undo : null),
        _button(l.redo, Icons.redo_rounded, c.canRedo ? c.redo : null),
        _button(l.selection, Icons.gesture_outlined, () {
          if (c.tool == StudioTool.selection) {
            c.selectTool(StudioTool.brush);
          } else {
            _closePanel();
            c.selectTool(StudioTool.selection);
          }
        }, selected: c.selection != null || c.tool == StudioTool.selection),
        _button(
          c.selection != null ? l.transformSelection : l.transformLayer,
          Icons.open_with_rounded,
          () {
            if (c.transformDraft != null) {
              c.cancelTransform();
            } else if (!c.beginTransform()) {
              _message(l.transformUnavailable);
            }
          },
          selected: c.transformDraft != null,
        ),
      ],
    );
    final right = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(l.brush, Icons.brush_outlined, () {
          c.selectTool(StudioTool.brush);
          c.setPanel(EditorPanel.brushes);
        }, selected: c.tool == StudioTool.brush),
        _button(l.smudge, Icons.touch_app_outlined, () {
          _closePanel();
          c.selectTool(StudioTool.smudge);
        }, selected: c.tool == StudioTool.smudge),
        // Two fingers pan in every tool; the hand stays for mouse users
        // where there is room.
        if (MediaQuery.sizeOf(context).width >= 480)
          _button(l.pan, Icons.pan_tool_outlined, () {
            _closePanel();
            c.selectTool(StudioTool.pan);
          }, selected: c.tool == StudioTool.pan),
        _button(l.eraser, Icons.cleaning_services_outlined, () {
          _closePanel();
          c.selectTool(StudioTool.eraser);
        }, selected: c.tool == StudioTool.eraser),
        _button(
          l.layers,
          Icons.layers_outlined,
          () => c.setPanel(EditorPanel.layers),
          selected: c.panel == EditorPanel.layers,
        ),
        Tooltip(
          message: l.colors,
          // Drag the colour onto the canvas to fill (ColorDrop); press and
          // hold swaps to the previous colour, as in Procreate.
          child: Draggable<int>(
            data: c.color,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _dropFeedback(c.color),
            child: GestureDetector(
              key: const ValueKey('color-button'),
              onLongPress: c.swapColor,
              child: IconButton(
                onPressed: () => c.setPanel(EditorPanel.colors),
                icon: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(c.color),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
              ),
            ),
          ),
        ),
        _button(
          l.connections,
          Icons.auto_awesome_outlined,
          () => c.setPanel(EditorPanel.connections),
          selected: c.panel == EditorPanel.connections,
        ),
      ],
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: LayoutBuilder(
          builder: (context, size) => size.maxWidth < 700
              ? Column(
                  children: [
                    Align(alignment: Alignment.centerLeft, child: left),
                    Align(alignment: Alignment.centerRight, child: right),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [left, right],
                ),
        ),
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    color: selected ? Theme.of(context).colorScheme.primary : null,
    icon: Icon(icon, size: 21),
  );

  /// A sidebar slider's value: tapping types one.
  Widget _sidebarValue({
    required String key,
    required String label,
    required String text,
    required double value,
    required String unit,
    required ValueChanged<double> onTyped,
  }) => Tooltip(
    message: label,
    child: InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final typed = await askNumber(
          context,
          title: label,
          value: value,
          unit: unit,
        );
        if (typed != null) onTyped(typed);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      ),
    ),
  );

  /// With "fade while drawing" on: [child] all but goes while the canvas
  /// is touched.
  Widget _fading(Widget child) => !c.autoHideInterface
      ? child
      : ValueListenableBuilder<bool>(
          valueListenable: c.canvasEngaged,
          builder: (context, busy, child) => AnimatedOpacity(
            opacity: busy ? .08 : 1,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(ignoring: busy, child: child),
          ),
          child: child,
        );

  /// The sidebar; its grip drags it up and down over [travel] pixels.
  Widget _sidebar({double travel = 400}) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(c.rightSidebar ? 8 : 0),
        right: Radius.circular(c.rightSidebar ? 0 : 8),
      ),
    ),
    child: SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: l.moveSidebar,
            child: GestureDetector(
              key: const ValueKey('sidebar-grip'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => c.setSidebarPosition(
                c.sidebarPosition + d.delta.dy / math.max(travel, 40),
              ),
              child: SizedBox(
                width: 48,
                height: 20,
                child: Icon(
                  Icons.drag_handle,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Tooltip(
            message: '${l.size}: ${c.size.round()} px',
            child: SizedBox(
              height: 116,
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: c.size,
                  min: 1,
                  max: 128,
                  semanticFormatterCallback: (v) => '${l.size} ${v.round()}',
                  onChanged: c.setSize,
                ),
              ),
            ),
          ),
          _sidebarValue(
            key: 'sidebar-size',
            label: l.size,
            text: '${c.size.round()}',
            value: c.size,
            unit: ' px',
            onTyped: (n) => c.setSize(n.clamp(1, 128)),
          ),
          Tooltip(
            message: '${l.opacity}: ${(c.opacity * 100).round()}%',
            child: SizedBox(
              height: 116,
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: c.opacity,
                  min: .01,
                  max: 1,
                  semanticFormatterCallback: (v) =>
                      '${l.opacity} ${(v * 100).round()}%',
                  onChanged: c.setOpacity,
                ),
              ),
            ),
          ),
          _sidebarValue(
            key: 'sidebar-opacity',
            label: l.opacity,
            text: '${(c.opacity * 100).round()}%',
            value: c.opacity * 100,
            unit: '%',
            onTyped: (n) => c.setOpacity((n / 100).clamp(.01, 1)),
          ),
          _button(l.eyedropper, Icons.colorize_outlined, () {
            _closePanel();
            c.selectTool(
              c.tool == StudioTool.eyedropper
                  ? StudioTool.brush
                  : StudioTool.eyedropper,
            );
          }, selected: c.tool == StudioTool.eyedropper),
          if (c.hub.paired)
            _button(l.generativeFill, Icons.auto_awesome, () {
              _closePanel();
              c.hubJob.show();
            }),
          _button(
            l.zoomReset,
            Icons.fit_screen_outlined,
            () => _transformation.value = Matrix4.identity(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  Widget _footer() {
    final status = switch (c.saveState) {
      SaveState.saved => l.saved,
      SaveState.pending => l.unsaved,
      SaveState.saving => l.saving,
      SaveState.failed => l.saveFailed,
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _run(c.save),
                  child: Row(
                    children: [
                      Icon(
                        c.saveState == SaveState.failed
                            ? Icons.error_outline
                            : Icons.circle,
                        size: 8,
                        color: c.saveState == SaveState.failed
                            ? Theme.of(context).colorScheme.error
                            : Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          status,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.document.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (constraints.maxWidth > 480) ...[
                const SizedBox(width: 12),
                Text(
                  '${c.document.dimensions} \u00b7 sRGB',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final title = switch (c.panel!) {
      EditorPanel.gallery => l.gallery,
      EditorPanel.actions => l.actions,
      EditorPanel.adjustments => l.adjustments,
      EditorPanel.brushes => l.brushLibrary,
      EditorPanel.layers => l.layers,
      EditorPanel.colors => l.colors,
      EditorPanel.settings => l.settings,
      EditorPanel.connections => l.connections,
    };
    final content = switch (c.panel!) {
      EditorPanel.gallery => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            key: const ValueKey('gallery-kind'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(l.galleryDrawings),
                icon: const Icon(Icons.brush_outlined, size: 18),
              ),
              ButtonSegment(
                value: true,
                label: Text(l.theater),
                icon: const Icon(Icons.movie_outlined, size: 18),
              ),
            ],
            selected: {_theater},
            onSelectionChanged: (v) => setState(() => _theater = v.single),
          ),
          const SizedBox(height: 12),
          if (_theater)
            TheaterPanel(
              storage: c.storage,
              askName: _askName,
              run: _run,
              recent: c.recentColors,
              editDrawing: _editMovieDrawing,
              preferences: c.preferences,
            )
          else
            GalleryPanel(
              controller: c,
              onOpen: (doc) => _run(() async {
                await c.replaceDocument(doc);
                _closePanel();
              }),
              onNew: _newDocument,
              askName: _askName,
              run: _run,
            ),
        ],
      ),
      EditorPanel.actions => _actions(),
      EditorPanel.adjustments => _adjustments(),
      EditorPanel.brushes => _brushes(),
      EditorPanel.layers => _layers(),
      EditorPanel.colors => _colors(),
      EditorPanel.settings => _settings(),
      EditorPanel.connections => HubPanel(controller: c),
    };
    final alignLeft =
        c.panel == EditorPanel.gallery ||
        c.panel == EditorPanel.actions ||
        c.panel == EditorPanel.adjustments ||
        c.panel == EditorPanel.settings;
    return Positioned(
      top: 10,
      bottom: 12,
      left: alignLeft ? 12 : null,
      right: alignLeft ? null : 12,
      width: math.min(350, MediaQuery.sizeOf(context).width - 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          key: _panelKey,
          elevation: 12,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.close,
                      onPressed: _closePanel,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _adjustments() {
    Widget item(AdjustmentKind kind, IconData icon) => _action(
      adjustmentName(l, kind),
      icon,
      () => _run(() async {
        if (!await c.startAdjustment(kind)) _message(l.adjustUnavailable);
      }),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(l.adjustColor),
        item(AdjustmentKind.hueSaturationBrightness, Icons.palette_outlined),
        item(AdjustmentKind.colorBalance, Icons.balance_outlined),
        item(AdjustmentKind.curves, Icons.show_chart),
        item(AdjustmentKind.gradientMap, Icons.gradient),
        item(AdjustmentKind.recolor, Icons.format_color_reset_outlined),
        const Divider(),
        heading(l.adjustBlur),
        item(AdjustmentKind.gaussianBlur, Icons.blur_on),
        item(AdjustmentKind.motionBlur, Icons.air),
        item(AdjustmentKind.perspectiveBlur, Icons.filter_center_focus),
        const Divider(),
        heading(l.adjustFilters),
        item(AdjustmentKind.sharpen, Icons.details),
        item(AdjustmentKind.noise, Icons.grain),
        item(AdjustmentKind.bloom, Icons.flare),
        item(AdjustmentKind.glitch, Icons.broken_image_outlined),
        item(AdjustmentKind.halftone, Icons.blur_circular),
        item(AdjustmentKind.chromaticAberration, Icons.camera_outlined),
        const Divider(),
        _action(
          l.liquify,
          Icons.water_drop_outlined,
          () => _run(() async {
            if (!await c.startLiquify()) _message(l.adjustUnavailable);
          }),
        ),
        _action(
          l.clone,
          Icons.copy_all_outlined,
          () => _run(() async {
            if (!await c.startClone()) _message(l.adjustUnavailable);
          }),
        ),
      ],
    );
  }

  /// Procreate's Canvas Information.
  void _canvasInfo() {
    final doc = c.document;
    final dims = doc.dimensions;
    final rasters = documentRasters(doc);
    final bytes = rasters.fold<int>(0, (n, r) => n + r.png.length);
    String cm(int px) => (px / doc.dpi * 2.54).toStringAsFixed(1);
    final rows = [
      (l.infoSize, '${dims.width} × ${dims.height} px'),
      (l.colorProfile, profileName(l, doc.colorProfile)),
      ('DPI', '${doc.dpi}'),
      (l.infoPrint, '${cm(dims.width)} × ${cm(dims.height)} cm'),
      (l.infoLayers, '${doc.layers.length} / ${StudioController.maxLayers}'),
      (l.infoGroups, '${doc.groups.length}'),
      (
        l.infoStrokes,
        '${doc.layers.fold<int>(0, (n, layer) => n + layer.strokes.length)}',
      ),
      (l.infoSaved, '${doc.savedSelections.length}'),
      (l.infoMemory, '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
      (l.infoEdits, '${doc.revision}'),
    ];
    _closePanel();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.canvasInfo),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(label)),
                        Text(value, key: ValueKey('info-$label')),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ColorProfile>(
                  key: const ValueKey('info-profile'),
                  initialValue: doc.colorProfile,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.colorProfile,
                    isDense: true,
                  ),
                  items: [
                    for (final p in ColorProfile.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(profileName(l, p)),
                      ),
                  ],
                  onChanged: (p) {
                    if (p != null) c.setColorProfile(p);
                  },
                ),
                const SizedBox(height: 6),
                Text(l.profileHint, style: const TextStyle(fontSize: 11)),
              ],
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
    );
  }

  Widget _actions() => Column(
    children: [
      _action(l.newDocument, Icons.add, _newDocument),
      _action(
        l.openDocument,
        Icons.folder_open_outlined,
        () => _run(_openDocument),
      ),
      _action(
        l.importImage,
        Icons.add_photo_alternate_outlined,
        () => _run(_importImage),
      ),
      _action(
        l.insertPrivatePhoto,
        Icons.shield_outlined,
        () => _run(() => _importImage(private: true)),
      ),
      _action(
        l.addText,
        Icons.title,
        () => c.addText(l.textDefault, fallbackName: l.textDefault),
      ),
      _action(l.saveDocument, Icons.save_outlined, () => _run(c.save)),
      _action(
        l.rename,
        Icons.edit_outlined,
        () => _run(() async {
          final name = await _askName(c.document.name);
          if (name != null) c.renameDocument(name);
        }),
      ),
      const Divider(),
      _action(
        l.exportDocument,
        Icons.file_upload_outlined,
        () => _run(_exportDocument),
      ),
      _action(l.exportImage, Icons.image_outlined, _exportImage),
      const Divider(),
      SwitchListTile.adaptive(
        key: const ValueKey('timelapse-on'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.videocam_outlined, size: 20),
        title: Text(l.timelapseRecording, style: const TextStyle(fontSize: 13)),
        value: c.timelapseOn,
        onChanged: c.setTimelapseOn,
      ),
      _action(l.timelapseReplay, Icons.slow_motion_video, _replayTimelapse),
      _action(l.timelapseExport, Icons.movie_outlined, _exportTimelapse),
      _action(l.timelapseClear, Icons.delete_sweep_outlined, _clearTimelapse),
      const Divider(),
      _action(l.cropResize, Icons.crop, c.startCanvasCrop),
      SwitchListTile.adaptive(
        key: const ValueKey('animation-assist'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.animation, size: 20),
        title: Text(l.animationAssist, style: const TextStyle(fontSize: 13)),
        value: c.document.animating,
        onChanged: c.setAnimationAssist,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('page-assist'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.auto_stories_outlined, size: 20),
        title: Text(l.pageAssist, style: const TextStyle(fontSize: 13)),
        value: c.document.pageAssist,
        onChanged: c.setPageAssist,
      ),
      _action(l.reference, Icons.picture_in_picture_alt_outlined, () {
        c.toggleReference(true);
        _closePanel();
      }),
      _action(l.canvasInfo, Icons.info_outline, _canvasInfo),
      const Divider(),
      _drawingGuide(),
      const Divider(),
      _action(
        l.settings,
        Icons.settings_outlined,
        () => c.setPanel(EditorPanel.settings),
      ),
      _action(
        l.connections,
        Icons.auto_awesome_outlined,
        () => c.setPanel(EditorPanel.connections),
      ),
    ],
  );

  /// The colour being dragged to the canvas, under the finger.
  Widget _dropFeedback(int color) => IgnorePointer(
    child: Transform.translate(
      offset: const Offset(-18, -18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
        ),
      ),
    ),
  );

  /// ColorDrop goes on: the threshold for the last fill, and Done.
  /// QuickShape's Edit Shape, then Done / Cancel while editing.
  Widget _shapeBar() => OverlayBar(
    key: const ValueKey('shape-bar'),
    engaged: c.canvasEngaged,
    top: true,
    maxWidth: 220,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (c.shapeEdit == null)
            IconButton(
              key: const ValueKey('edit-shape'),
              tooltip: l.editShape,
              visualDensity: VisualDensity.compact,
              onPressed: () => _run(() async {
                await c.editQuickShape();
              }),
              icon: const Icon(Icons.polyline_outlined, size: 20),
            ),
          IconButton(
            key: const ValueKey('perfect-shape'),
            tooltip: l.perfectShape,
            visualDensity: VisualDensity.compact,
            onPressed: () => _run(c.perfectQuickShape),
            icon: const Icon(Icons.auto_fix_normal_outlined, size: 20),
          ),
          if (c.shapeEdit != null) ...[
            IconButton(
              tooltip: l.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: () => c.finishShapeEdit(keep: false),
              icon: const Icon(Icons.close, size: 20),
            ),
            IconButton.filled(
              key: const ValueKey('shape-done'),
              tooltip: l.done,
              visualDensity: VisualDensity.compact,
              onPressed: c.finishShapeEdit,
              icon: const Icon(Icons.check, size: 20),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _fillBar() {
    final session = c.fillSession!;
    return OverlayBar(
      key: const ValueKey('fill-bar'),
      engaged: c.canvasEngaged,
      top: true,
      maxWidth: 420,
      children: [
        Row(
          children: [
            const SizedBox(width: 6),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color(session.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueSlider(
                id: 'fill-threshold',
                label: l.fillThreshold,
                icon: Icons.tune,
                value: c.fillThreshold,
                max: StudioController.maxFillThreshold,
                onChanged: c.setFillThreshold,
              ),
            ),
            barHint(l.fillHint),
            IconButton.filled(
              key: const ValueKey('fill-done'),
              tooltip: l.done,
              visualDensity: VisualDensity.compact,
              onPressed: c.endFill,
              icon: const Icon(Icons.check, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  /// Symmetry, grid and turning the view, as in Procreate's Canvas menu.
  Widget _drawingGuide() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.drawingGuide, style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 4),
      _action(l.editGuide, Icons.architecture, () => c.setGuideEditing(true)),
      const SizedBox(height: 4),
      Text(l.symmetry, style: _hintStyle),
      const SizedBox(height: 4),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final kind in SymmetryKind.values)
            ChoiceChip(
              key: ValueKey('symmetry-${kind.name}'),
              visualDensity: VisualDensity.compact,
              label: Text(switch (kind) {
                SymmetryKind.off => l.symmetryOff,
                SymmetryKind.vertical => l.symmetryVertical,
                SymmetryKind.horizontal => l.symmetryHorizontal,
                SymmetryKind.quadrant => l.symmetryQuadrant,
                SymmetryKind.radial => l.symmetryRadial,
              }, style: const TextStyle(fontSize: 12)),
              selected: c.symmetry == kind,
              onSelected: (_) => c.setSymmetry(kind),
            ),
        ],
      ),
      SwitchListTile(
        key: const ValueKey('grid-guide'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(l.gridGuide, style: const TextStyle(fontSize: 13)),
        value: c.gridGuide,
        onChanged: (value) => c.setGrid(visible: value),
      ),
      if (c.gridGuide)
        ValueSlider(
          id: 'grid-size',
          label: l.gridGuide,
          value: c.gridSize,
          min: 8,
          max: 512,
          toNumber: (v) => v,
          fromNumber: (n) => n,
          unit: ' px',
          onChanged: (value) => c.setGrid(size: value),
        ),
      Row(
        children: [
          Expanded(
            child: Text(l.turnView, style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            tooltip: l.turnLeft,
            onPressed: () => _turnView(-math.pi / 2),
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            tooltip: l.turnRight,
            onPressed: () => _turnView(math.pi / 2),
            icon: const Icon(Icons.rotate_right),
          ),
        ],
      ),
    ],
  );

  void _turnView(double angle) =>
      _transformation.value = CanvasNavigation.around(
        _transformation.value,
        MediaQuery.sizeOf(context).center(Offset.zero),
        rotation: angle,
      );

  Widget _action(String title, IconData icon, VoidCallback action) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    onTap: _busy ? null : action,
  );

  Widget _brushes() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _percentSlider(
        '${l.streamLine} · ${_brushName(c.brush)}',
        c.streamLine,
        c.setStreamLine,
        key: 'streamline',
      ),
      Text(l.streamLineHint, style: _hintStyle),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('brush-search'),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: l.brushSearch,
        ),
        onChanged: (v) => setState(() => _brushQuery = v.trim().toLowerCase()),
      ),
      Row(
        children: [
          if (_brushChoice == null) ...[
            TextButton.icon(
              key: const ValueKey('brush-select'),
              onPressed: c.libraryLocked
                  ? null
                  : () => setState(() => _brushChoice = {}),
              icon: const Icon(Icons.check_box_outlined, size: 18),
              label: Text(l.gallerySelect),
            ),
          ] else ...[
            Expanded(
              child: Text(
                l.gallerySelected(_brushChoice!.length),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              key: const ValueKey('brush-select-all'),
              onPressed: () => setState(
                () => _brushChoice = {
                  for (final b in c.brushes)
                    if (_brushQuery.isEmpty ||
                        _brushName(b).toLowerCase().contains(_brushQuery))
                      b.id,
                },
              ),
              child: Text(l.selectAll),
            ),
            IconButton(
              key: const ValueKey('brush-delete-chosen'),
              tooltip: l.galleryDelete,
              onPressed: _brushChoice!.isEmpty ? null : _deleteChosenBrushes,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            IconButton(
              key: const ValueKey('brush-select-done'),
              tooltip: l.cancel,
              onPressed: () => setState(() => _brushChoice = null),
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ],
      ),
      const SizedBox(height: 4),
      if (_brushQuery.isEmpty && c.recentBrushes.length > 1) ...[
        Text(l.recentBrushes, style: _hintStyle),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in c.recentBrushes)
              if (c.brushes.where((b) => b.id == id).firstOrNull
                  case final brush?)
                ActionChip(
                  key: ValueKey('recent-brush-$id'),
                  label: Text(_brushName(brush)),
                  onPressed: () {
                    c.selectBrush(brush);
                    _closePanel();
                  },
                ),
          ],
        ),
        const SizedBox(height: 10),
      ],
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: _brushQuery.isEmpty && !c.libraryLocked
            ? c.moveBrush
            : (_, _) {},
        children: [
          for (final (i, brush) in c.brushes.indexed)
            if (_brushQuery.isEmpty ||
                _brushName(brush).toLowerCase().contains(_brushQuery))
              ReorderableDelayedDragStartListener(
                key: ValueKey('brush-${brush.id}'),
                index: i,
                enabled: _brushQuery.isEmpty && _brushChoice == null,
                child: _brushRow(brush),
              ),
        ],
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy || c.libraryLocked ? null : () => _run(_importBrush),
        icon: const Icon(Icons.download_outlined, size: 17),
        label: Text(l.importBrush),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: const ValueKey('export-brushset'),
        onPressed: _busy || !c.brushes.any((b) => b.isStamp)
            ? null
            : () => _run(
                () => _exportBrushes([
                  for (final b in c.brushes)
                    if (b.isStamp) b,
                ]),
              ),
        icon: const Icon(Icons.upload_outlined, size: 17),
        label: Text(l.exportBrushset),
      ),
      const SizedBox(height: 10),
      Text(l.brushImportHint, style: _hintStyle),
      Text(l.brushImportFormats, style: _hintStyle),
      ..._libraryWarning(),
    ],
  );

  /// What the brush library is narrowed to.
  String _brushQuery = '';

  /// Brush selection mode: the brushes chosen to delete together.
  Set<String>? _brushChoice;

  Future<void> _deleteChosenBrushes() async {
    final ids = {...?_brushChoice};
    if (ids.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.brushDeleteAsk(ids.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('brush-delete-yes'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.galleryDelete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    c.deleteBrushes(ids);
    setState(() => _brushChoice = null);
    await _run(c.save);
  }

  Widget _brushRow(BrushPreset brush) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: c.brush.id == brush.id
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 0),
        leading: _brushChoice == null
            ? null
            : Icon(
                _brushChoice!.contains(brush.id)
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: _brushChoice!.contains(brush.id)
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
        title: Text(_brushName(brush), style: const TextStyle(fontSize: 13)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: brush.isNative
              ? NativeBrushPreview(
                  brush,
                  Theme.of(context).colorScheme.onSurface,
                )
              : CustomPaint(
                  size: const Size(200, 25),
                  painter: BrushPreviewPainter(
                    brush,
                    _engine,
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
        ),
        trailing: _brushChoice != null
            ? null
            : PopupMenuButton<int>(
                key: ValueKey('brush-menu-${brush.id}'),
                tooltip: l.actions,
                enabled: !c.libraryLocked,
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) => action == 0
                    // Brush Studio is its own window, not a task to wait on.
                    ? () {
                        _closePanel();
                        unawaited(showBrushStudio(context, c, brush));
                      }()
                    : _run(() async {
                        switch (action) {
                          case 1:
                            c.duplicateBrush(
                              brush.id,
                              l.brushCopy(_brushName(brush)),
                            );
                          case 2:
                            final name = await _askName(_brushName(brush));
                            if (name != null && name.trim().isNotEmpty) {
                              c.renameBrush(brush.id, name.trim());
                            }
                          case 3:
                            c.resetBrush(brush.id);
                          case 4:
                            c.deleteBrush(brush.id);
                          case 5:
                            await _exportBrushes([brush]);
                        }
                      }),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 0, child: Text(l.brushEdit)),
                  PopupMenuItem(value: 1, child: Text(l.duplicateLayer)),
                  PopupMenuItem(value: 2, child: Text(l.rename)),
                  if (c.isEdited(brush))
                    PopupMenuItem(value: 3, child: Text(l.brushReset)),
                  if (brush.isStamp)
                    PopupMenuItem(
                      value: 5,
                      child: Text(l.exportProcreateBrush),
                    ),
                  PopupMenuItem(
                    value: 4,
                    enabled: c.brushes.length > 1,
                    child: Text(l.deleteChosen),
                  ),
                ],
              ),
        onTap: () {
          final chosen = _brushChoice;
          if (chosen != null) {
            setState(
              () => chosen.contains(brush.id)
                  ? chosen.remove(brush.id)
                  : chosen.add(brush.id),
            );
            return;
          }
          c.selectBrush(brush);
          _closePanel();
        },
      ),
    ),
  );

  Widget _percentSlider(
    String label,
    double value,
    ValueChanged<double>? onChanged, {
    required String key,
  }) => ValueSlider(
    id: key,
    label: label,
    value: value,
    onChanged: onChanged,
    labelWidth: 130,
  );

  List<Widget> _libraryWarning() => [
    if (c.libraryLocked) ...[
      const SizedBox(height: 10),
      Text(
        l.libraryUnreadable,
        key: const ValueKey('library-unreadable'),
        style: _hintStyle.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

  TextStyle get _hintStyle => TextStyle(
    fontSize: 11,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    height: 1.6,
  );

  Widget _layers() => LayersPanel(
    controller: c,
    run: _run,
    askName: _askName,
    exportLayer: _exportLayer,
  );

  Widget _colors() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ColorPicker(
        color: c.color,
        onColor: c.selectColor,
        recent: c.recentColors,
        hexField: ColorHexInput(color: c.color, onColor: c.selectColor),
        onEyedropper: () {
          _closePanel();
          c.selectTool(StudioTool.eyedropper);
        },
      ),
      const Divider(height: 28),
      Row(
        children: [
          Expanded(
            child: Text(l.palettes, style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            key: const ValueKey('palette-cards'),
            tooltip: l.paletteCards,
            isSelected: c.paletteCards,
            onPressed: () => c.setPaletteCards(!c.paletteCards),
            icon: const Icon(Icons.view_agenda_outlined, size: 20),
          ),
          IconButton(
            key: const ValueKey('palette-new'),
            tooltip: l.newPalette,
            onPressed: c.libraryLocked
                ? null
                : () => c.createPalette(
                    '${l.paletteName} ${c.palettes.length + 1}',
                  ),
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
      for (final palette in c.orderedPalettes) _palette(palette),
      OutlinedButton.icon(
        onPressed: _busy || c.libraryLocked ? null : () => _run(_importPalette),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: Text(l.importPalette),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: const ValueKey('palette-from-image'),
        onPressed: _busy || c.libraryLocked ? null : _paletteFromImage,
        icon: const Icon(Icons.colorize_outlined, size: 18),
        label: Text(l.paletteFromImage),
      ),
      const SizedBox(height: 10),
      Text(l.paletteImportHint, style: _hintStyle),
      ..._libraryWarning(),
    ],
  );

  /// Where a swatch drag began: palette id and index.
  (String, int)? _swatchDrag;
  final _panelKey = GlobalKey();

  /// One palette: its name and menu, its swatches (tap to use, hold for
  /// replace/delete, drag to reorder or onto the canvas), and +.
  Widget _palette(ColorPalette palette) {
    final cards = c.paletteCards;
    final isDefault = palette.id == c.defaultPaletteId;
    final name = palette.id == 'coast' ? l.coast : palette.name;
    Widget swatch(int index, int color) {
      final size = cards ? const Size(64, 46) : const Size(43, 37);
      final tile = Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(5),
          border: color == c.color
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 2,
                )
              : null,
        ),
      );
      return DragTarget<int>(
        key: ValueKey('swatch-${palette.id}-$index'),
        onAcceptWithDetails: (drop) {
          final from = _swatchDrag;
          if (from != null && from.$1 == palette.id) {
            c.moveSwatch(palette.id, from.$2, index);
          } else {
            c.addSwatch(palette.id, drop.data, index: index);
          }
          _swatchDrag = null;
        },
        builder: (context, hovering, _) => Semantics(
          label: '#${color.toRadixString(16).padLeft(8, '0')}',
          selected: color == c.color,
          // SwatchDrop: dragged out of the panel onto the canvas, it fills.
          child: Draggable<int>(
            data: color,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _dropFeedback(color),
            onDragStarted: () => _swatchDrag = (palette.id, index),
            onDragUpdate: (d) {
              final box =
                  _panelKey.currentContext?.findRenderObject() as RenderBox?;
              if (box != null &&
                  !(box.localToGlobal(Offset.zero) & box.size).contains(
                    d.globalPosition,
                  )) {
                _closePanel();
              }
            },
            onDragEnd: (_) => _swatchDrag = null,
            child: GestureDetector(
              onLongPressStart: (d) => _swatchMenu(palette, index, d),
              child: InkWell(
                onTap: () => c.pickedColor(color),
                borderRadius: BorderRadius.circular(5),
                child: Opacity(
                  opacity: hovering.isNotEmpty ? .5 : 1,
                  child: cards
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tile,
                            const SizedBox(height: 2),
                            Text(
                              '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}',
                              style: const TextStyle(fontSize: 9),
                            ),
                            // Colour cards name their colour.
                            SizedBox(
                              width: 64,
                              child: Text(
                                colorName(l, color),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          ],
                        )
                      : tile,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      key: ValueKey('palette-${palette.id}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isDefault)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star, size: 14),
                ),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
              PopupMenuButton<int>(
                key: ValueKey('palette-menu-${palette.id}'),
                tooltip: l.actions,
                enabled: !c.libraryLocked,
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) => _run(() async {
                  switch (action) {
                    case 0:
                      final next = await _askName(name);
                      if (next != null && next.trim().isNotEmpty) {
                        c.renamePalette(palette.id, next.trim());
                      }
                    case 1:
                      c.duplicatePalette(palette.id, l.paletteCopy(name));
                    case 2:
                      c.setDefaultPalette(isDefault ? null : palette.id);
                    case 3:
                      c.deletePalette(palette.id);
                    case >= 10:
                      final format = PaletteFormat.values[action - 10];
                      final bytes = encodePalette(name, palette.colors, format);
                      final result = await FilePicker.saveFile(
                        fileName:
                            '${name.replaceAll(RegExp(r'[^\w\- ]'), '_')}'
                            '.${format.extension}',
                        bytes: bytes,
                      );
                      if (result != null && mounted) {
                        _message(l.exportSuccess);
                      }
                  }
                }),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 0, child: Text(l.rename)),
                  PopupMenuItem(value: 1, child: Text(l.duplicateLayer)),
                  PopupMenuItem(
                    value: 2,
                    child: Text(
                      isDefault ? l.unsetDefaultPalette : l.setDefaultPalette,
                    ),
                  ),
                  PopupMenuItem(value: 3, child: Text(l.deleteChosen)),
                  if (palette.colors.isNotEmpty) ...[
                    const PopupMenuDivider(),
                    for (final (i, f) in PaletteFormat.values.indexed)
                      PopupMenuItem(
                        value: 10 + i,
                        child: Text(l.exportPalette(f.extension)),
                      ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, color) in palette.colors.indexed) swatch(i, color),
              // An empty square: the current colour goes in.
              DragTarget<int>(
                onAcceptWithDetails: (drop) {
                  final from = _swatchDrag;
                  if (from != null && from.$1 == palette.id) {
                    c.moveSwatch(palette.id, from.$2, palette.colors.length);
                  } else {
                    c.addSwatch(palette.id, drop.data);
                  }
                  _swatchDrag = null;
                },
                builder: (context, _, _) => Tooltip(
                  message: l.addCurrentColor,
                  child: InkWell(
                    key: ValueKey('swatch-add-${palette.id}'),
                    onTap: c.libraryLocked
                        ? null
                        : () => c.addSwatch(palette.id, c.color),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      width: cards ? 64 : 43,
                      height: cards ? 46 : 37,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: const Icon(Icons.add, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _swatchMenu(
    ColorPalette palette,
    int index,
    LongPressStartDetails at,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        at.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 0, child: Text(l.replaceSwatch)),
        PopupMenuItem(value: 1, child: Text(l.deleteChosen)),
      ],
    );
    if (!mounted || action == null) return;
    await _run(() async {
      if (action == 0) {
        c.replaceSwatch(palette.id, index, c.color);
      } else {
        c.removeSwatch(palette.id, index);
      }
    });
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Field profiling builds only (--dart-define=ARTBLEND_PEN_LOG=true).
      if (penLogging) ...[
        OutlinedButton(
          onPressed: _busy ? null : () => _run(c.createStressDocument),
          child: const Text('Stress drawing 4096² × 16 layers'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Flatten layers', style: TextStyle(fontSize: 13)),
          value: c.flattenLayers,
          onChanged: c.setFlattenLayers,
        ),
        const SizedBox(height: 18),
      ],
      DropdownButtonFormField<String>(
        key: ValueKey('language-${c.locale}'),
        initialValue: c.locale?.languageCode ?? 'system',
        decoration: InputDecoration(labelText: l.language),
        items: [
          DropdownMenuItem(value: 'system', child: Text(l.system)),
          const DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
          const DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (value) {
          if (value != null) c.setLanguage(value);
        },
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<ThemeMode>(
        key: ValueKey('theme-${c.themeMode}'),
        initialValue: c.themeMode,
        decoration: InputDecoration(labelText: l.theme),
        items: [
          DropdownMenuItem(value: ThemeMode.system, child: Text(l.system)),
          DropdownMenuItem(value: ThemeMode.light, child: Text(l.light)),
          DropdownMenuItem(value: ThemeMode.dark, child: Text(l.dark)),
        ],
        onChanged: (value) {
          if (value != null) c.setTheme(value);
        },
      ),
      const SizedBox(height: 12),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(l.rightSidebar, style: const TextStyle(fontSize: 13)),
        value: c.rightSidebar,
        onChanged: c.setSidebar,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(l.fingerDrawing, style: const TextStyle(fontSize: 13)),
        value: c.fingerDrawing,
        onChanged: c.setFingerDrawing,
      ),
      const SizedBox(height: 18),
      Text(
        l.pressureAndSmoothing,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      _percentSlider(
        l.stabilization,
        c.stabilization,
        (v) => c.setSmoothing(stabilization: v),
        key: 'stabilization',
      ),
      _percentSlider(
        l.motionFiltering,
        c.motionFilter,
        (v) => c.setSmoothing(motionFilter: v),
        key: 'motion-filter',
      ),
      _percentSlider(
        l.motionExpression,
        c.motionExpression,
        c.motionFilter > 0 ? (v) => c.setSmoothing(expression: v) : null,
        key: 'motion-expression',
      ),
      Text(l.smoothingHint, style: _hintStyle),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Text(l.pressureCurve, style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            key: const ValueKey('pressure-curve-reset'),
            tooltip: l.resetCurve,
            onPressed:
                c.pressureCurve.length == 2 &&
                    c.pressureCurve.first == Offset.zero &&
                    c.pressureCurve.last == const Offset(1, 1)
                ? null
                : () => c.setPressureCurve(Adjustment.straight),
            icon: const Icon(Icons.restart_alt, size: 20),
          ),
        ],
      ),
      Center(
        child: SizedBox(
          width: 200,
          child: CurveEditor(
            key: const ValueKey('pressure-curve'),
            points: c.pressureCurve,
            color: Theme.of(context).colorScheme.primary,
            onChangeStart: () {},
            onChanged: c.setPressureCurve,
          ),
        ),
      ),
      Text(l.pressureCurveHint, style: _hintStyle),
      const SizedBox(height: 8),
      DropdownButtonFormField<QuickMenuTrigger>(
        key: ValueKey('quick-trigger-${c.quickMenuTrigger.name}'),
        initialValue: c.quickMenuTrigger,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.quickMenuTrigger),
        items: [
          DropdownMenuItem(
            value: QuickMenuTrigger.touchHold,
            child: Text(l.quickMenuTriggerHold),
          ),
          DropdownMenuItem(
            value: QuickMenuTrigger.fourFingerTap,
            child: Text(l.quickMenuTriggerFour),
          ),
          DropdownMenuItem(
            value: QuickMenuTrigger.none,
            child: Text(l.quickMenuTriggerNone),
          ),
        ],
        onChanged: (value) {
          if (value != null) c.setQuickMenuTrigger(value);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('quick-profiles'),
          onPressed: () => showQuickMenuProfiles(context, c, _askName),
          icon: const Icon(Icons.radio_button_checked, size: 18),
          label: Text(l.quickMenuProfiles),
        ),
      ),
      Text(l.quickMenuHint, style: _hintStyle),
      const SizedBox(height: 18),
      Text(
        l.gestureControls,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      if (c.fingerDrawing)
        DropdownButtonFormField<FingerTool>(
          key: ValueKey('finger-tool-${c.fingerTool.name}'),
          initialValue: c.fingerTool,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.fingerTool),
          items: [
            DropdownMenuItem(
              value: FingerTool.same,
              child: Text(l.fingerToolSame),
            ),
            DropdownMenuItem(
              value: FingerTool.smudge,
              child: Text(l.fingerToolSmudge),
            ),
            DropdownMenuItem(
              value: FingerTool.eraser,
              child: Text(l.fingerToolEraser),
            ),
          ],
          onChanged: (value) {
            if (value != null) c.setFingerTool(value);
          },
        ),
      SwitchListTile.adaptive(
        key: const ValueKey('eyedropper-hold'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.eyedropperHold, style: const TextStyle(fontSize: 13)),
        value: c.eyedropperHold,
        onChanged: c.setEyedropperHold,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('touch-gestures'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.touchGestures, style: const TextStyle(fontSize: 13)),
        value: c.touchGestures,
        onChanged: c.setTouchGestures,
      ),
      ValueSlider(
        id: 'quickshape-delay',
        label: l.quickShapeDelay,
        labelWidth: 120,
        value: c.quickShapeDelay,
        max: 1.5,
        toNumber: (v) => v * 1000,
        fromNumber: (n) => n / 1000,
        unit: ' ms',
        onChanged: c.setQuickShapeDelay,
      ),
      if (c.quickShapeDelay == 0)
        Text('QuickShape: ${l.quickShapeOff}', style: _hintStyle),
      ValueSlider(
        id: 'undo-delay',
        label: l.undoDelay,
        labelWidth: 120,
        value: c.undoDelay,
        min: .2,
        max: 1.5,
        toNumber: (v) => v * 1000,
        fromNumber: (n) => n / 1000,
        unit: ' ms',
        onChanged: c.setUndoDelay,
      ),
      ValueSlider(
        id: 'selection-mask',
        label: l.selectionMaskVisibility,
        labelWidth: 120,
        value: c.selectionMask,
        max: .8,
        onChanged: c.setSelectionMask,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('auto-hide'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.autoHideInterface, style: const TextStyle(fontSize: 13)),
        value: c.autoHideInterface,
        onChanged: c.setAutoHideInterface,
      ),
      Text(l.gestureHint, style: _hintStyle),
      const SizedBox(height: 18),
      if (widget.mcp case final mcp?) ...[
        McpSettings(service: mcp),
        const SizedBox(height: 18),
      ],
      Text(
        l.accessibility,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      ValueSlider(
        id: 'text-scale',
        label: l.largeText,
        labelWidth: 120,
        value: c.textScale,
        min: 1,
        max: 1.6,
        onChanged: c.setTextScale,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('color-names'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.colorNames, style: const TextStyle(fontSize: 13)),
        value: c.colorNames,
        onChanged: c.setColorNames,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('feedback-sounds'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.feedbackSounds, style: const TextStyle(fontSize: 13)),
        value: c.feedbackSounds,
        onChanged: c.setFeedbackSounds,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('single-touch'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.singleTouch, style: const TextStyle(fontSize: 13)),
        value: c.singleTouch,
        onChanged: c.setSingleTouch,
      ),
      Text(l.singleTouchHint, style: _hintStyle),
      SwitchListTile.adaptive(
        key: const ValueKey('brush-cursor'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.brushCursor, style: const TextStyle(fontSize: 13)),
        value: c.brushCursor,
        onChanged: c.setBrushCursor,
      ),
      const SizedBox(height: 10),
      Text(l.themeHint, style: _hintStyle),
      const SizedBox(height: 10),
      Text(l.palmHint, style: _hintStyle),
      const Divider(height: 32),
      Text(l.prototype, style: _hintStyle),
    ],
  );

  Widget _restoreError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_outlined, size: 36),
            const SizedBox(height: 18),
            Text(l.startupError),
            const SizedBox(height: 12),
            SelectableText(c.error ?? '', style: _hintStyle),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => _run(c.initialize),
              child: Text(l.retry),
            ),
          ],
        ),
      ),
    ),
  );

  Future<String?> _askName(String initial) async {
    final field = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.rename),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: l.name),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
    // Dialog dismissal animation may still reference its controller briefly.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    return value;
  }

  Future<void> _newDocument() async {
    final physical = View.of(context).physicalSize;
    final picked = await showDialog<(CanvasSize, int, ColorProfile)>(
      context: context,
      builder: (context) => NewDocumentDialog(screen: physical, controller: c),
    );
    if (picked == null || !mounted) return;
    final (dimensions, dpi, profile) = picked;
    // The dialog is not part of the work: no progress while it is open.
    await _run(() async {
      await c.replaceDocument(
        ArtDocument.empty(
          name: l.untitled,
          dimensions: dimensions,
        ).copyWith(dpi: dpi, colorProfile: profile),
      );
      _transformation.value = Matrix4.identity();
      _closePanel();
    });
  }

  Future<void> _openDocument() async {
    const extensions = ['artdoc', 'json', ...importExtensions];
    final file = await FilePicker.pickFile(
      type: pickAnyFile ? FileType.any : FileType.custom,
      allowedExtensions: pickAnyFile ? null : extensions,
    );
    if (file == null || !mounted) return;
    requireExtension(file.name, extensions);
    final dot = file.name.lastIndexOf('.');
    final extension = file.name.substring(dot + 1).toLowerCase();
    if (importExtensions.contains(extension)) {
      // Another app's file: up to 256 MB, decoded off the UI thread.
      final bytes = await readLimitedImportedFile(file, 256 * 1024 * 1024);
      final drawing =
          await _pdfDrawing(bytes, extension) ??
          await Isolate.run<ImportedDrawing>(
            () => decodeDrawing(bytes, extension),
          );
      final all = await c.openImported(drawing, file.name.substring(0, dot));
      _transformation.value = Matrix4.identity();
      _closePanel();
      if (!mounted) return;
      if (drawing.partial) _message(l.importPartial);
      if (drawing.scaled) _message(l.importScaled(CanvasSize.maxSide));
      if (!all) _message(l.importTooManyLayers(StudioController.maxLayers));
      return;
    }
    final bytes = await readLimitedImportedFile(file, maxDocumentFileBytes);
    final doc = await compute(decodeDocumentFile, bytes);
    await c.replaceDocument(doc);
    _transformation.value = Matrix4.identity();
    _closePanel();
  }

  Future<void> _importBrush() async {
    const extensions = ['json', 'myb', 'png', 'brush', 'brushset', 'abr'];
    final file = await FilePicker.pickFile(
      type: pickAnyFile ? FileType.any : FileType.custom,
      allowedExtensions: pickAnyFile ? null : extensions,
    );
    if (file == null) return;
    requireExtension(file.name, extensions);
    final lower = file.name.toLowerCase();
    // Brush sets carry big shape and grain images.
    final large = RegExp(r'\.(brush|brushset|abr)$').hasMatch(lower);
    final bytes = await readLimitedImportedFile(
      file,
      large ? 128 * 1024 * 1024 : maxImportBytes,
    );
    final name = file.name;
    final brushes = lower.endsWith('.png')
        ? [await pngTipBrush(bytes, file.name)]
        : lower.endsWith('.brush') || lower.endsWith('.brushset')
        ? await Isolate.run(() => decodeProcreateBrushes(bytes, name))
        : lower.endsWith('.abr')
        ? await Isolate.run(() => decodeAbrBrushes(bytes, name))
        : lower.endsWith('.myb')
        ? await compute(decodeMypaintImport, (bytes, file.name))
        : await compute(decodeBrushImport, bytes);
    c.addBrushes(brushes);
    await c.save();
    if (mounted) _message(l.importSuccess(file.name));
  }

  /// One stamp brush as a `.brush`, several as a `.brushset`.
  Future<void> _exportBrushes(List<BrushPreset> brushes) async {
    final images = <BrushImages>[];
    for (final brush in brushes) {
      final (tip, grain) = await resolveStampShapes(brush);
      images.add((
        brush: brush.copyWith(name: _brushName(brush)),
        shape: stampPng(tip),
        grain: grain == null ? null : stampPng(grain),
      ));
    }
    final single = images.length == 1;
    final bytes = single
        ? await Isolate.run(() => encodeProcreateBrush(images.single))
        : await Isolate.run(() => encodeProcreateBrushset('ArtBlend', images));
    final stem = single
        ? images.single.brush.name.replaceAll(RegExp(r'[^\w\- ]'), '_')
        : 'ArtBlend';
    final result = await FilePicker.saveFile(
      fileName: single ? '$stem.brush' : '$stem.brushset',
      bytes: bytes,
      mimeType: 'application/zip',
    );
    if (result != null && mounted) _message(l.exportSuccess);
  }

  /// A palette of a picture's main colours: from a file or the canvas,
  /// previewed with how many to keep.
  Future<void> _paletteFromImage() async {
    final source = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.paletteFromImage),
        children: [
          SimpleDialogOption(
            key: const ValueKey('palette-source-file'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.paletteFromFile),
          ),
          SimpleDialogOption(
            key: const ValueKey('palette-source-canvas'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.paletteFromCanvas),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    Uint8List? pixels;
    String name = l.paletteFromCanvas;
    await _run(() async {
      if (source) {
        final selected = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
        );
        if (selected.isEmpty) return;
        final file = selected.single;
        name = file.name.replaceFirst(RegExp(r'\.\w+$'), '');
        final codec = await ui.instantiateImageCodec(
          await readLimitedImportedFile(file, 32 * 1024 * 1024),
          targetWidth: 256,
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        pixels = data?.buffer.asUint8List();
      } else {
        await c.settleStroke();
        pixels = await renderDocumentRgba(c.document, c.rasters.images);
      }
    });
    final rgba = pixels;
    if (rgba == null || !mounted) return;
    final colors = await showDialog<List<int>>(
      context: context,
      builder: (context) => _PaletteFromPixels(pixels: rgba),
    );
    if (colors == null || colors.isEmpty || !mounted) return;
    c.addPalettes([ColorPalette(id: newId(), name: name, colors: colors)]);
    await _run(c.save);
  }

  Future<void> _importPalette() async {
    const extensions = ['hex', 'gpl', 'ase', 'aco', 'swatches', 'json'];
    final file = await FilePicker.pickFile(
      type: pickAnyFile ? FileType.any : FileType.custom,
      allowedExtensions: pickAnyFile ? null : extensions,
    );
    if (file == null) return;
    requireExtension(file.name, extensions);
    final palettes = await compute(decodePaletteImport, (
      await file.readAsBytes(),
      file.name,
    ));
    if (palettes.isEmpty) throw const FormatException('No palette found');
    c.addPalettes(palettes);
    await c.save();
    if (mounted) _message(l.importSuccess(file.name));
  }

  String get _filename => c.document.name.replaceAll(RegExp(r'[^\w\- ]'), '_');

  /// A [private] photo stays out of the time-lapse.
  Future<void> _importImage({bool private = false}) async {
    final id = c.document.id;
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'bmp',
        'tif',
        'tiff',
        'psd',
      ],
    );
    if (selected.isEmpty) return;
    final file = selected.single;
    final extension = file.name.split('.').last.toLowerCase();
    final flat = const ['psd', 'tif', 'tiff'].contains(extension);
    final read = await readLimitedImportedFile(
      file,
      (flat ? 128 : 16) * 1024 * 1024,
    );
    // PSD and TIFF: their flattened picture, as PNG.
    final bytes = flat
        ? await Isolate.run(() => flatImagePng(read, extension))
        : read;
    await c.addImageLayer(
      bytes,
      file.name,
      expectedDocumentId: id,
      private: private,
    );
    if (mounted) _message(l.importSuccess(file.name));
  }

  Future<void> _importReference() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    if (selected.isEmpty) return;
    await c.setReferenceImage(
      await readLimitedImportedFile(selected.single, 32 * 1024 * 1024),
    );
  }

  /// The editor on a movie's [drawing], as its own screen: same brushes,
  /// palettes and preferences; every save goes to [onSave].
  Future<void> _editMovieDrawing(
    BuildContext context,
    ArtDocument drawing,
    void Function(ArtDocument drawing) onSave, {
    void Function(int frame)? onScrub,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => _DrawingEditor(
          base: c,
          drawing: drawing,
          onSave: onSave,
          onScrub: onScrub,
          onExit: () => Navigator.pop(route),
        ),
      ),
    );
  }

  /// A PDF drawn page by page by the platform (vector pages included);
  /// null for other files, or where the platform cannot (its pictures are
  /// read instead).
  Future<ImportedDrawing?> _pdfDrawing(
    Uint8List bytes,
    String extension,
  ) async {
    if (extension != 'pdf') return null;
    final dir = await Directory.systemTemp.createTemp('artblend-pdf');
    try {
      final file = File('${dir.path}/in.pdf');
      await file.writeAsBytes(bytes);
      final pages = await const MediaTools().pdfPages(
        file.path,
        '${dir.path}/pages',
        CanvasSize.maxSide,
      );
      if (pages.isEmpty) return null;
      final pngs = [for (final p in pages) await File(p).readAsBytes()];
      return await compute(pdfPagesDrawing, pngs);
    } catch (_) {
      return null;
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _openTimelapse() async {
    try {
      c.timelapse = await TimelapseStore.open();
    } on Object {
      // No app folder (tests): nothing is recorded.
    }
  }

  Future<void> _replayTimelapse() async {
    final frames = await c.timelapse?.frames(c.document.id) ?? const <File>[];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => TimelapsePlayer(frames: frames),
    );
  }

  Future<void> _exportTimelapse() async {
    final store = c.timelapse;
    if (store == null) return;
    final all = await store.frames(c.document.id);
    if (!mounted) return;
    if (all.isEmpty) {
      _message(l.timelapseEmpty);
      return;
    }
    final seconds = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.timelapseExport),
        children: [
          SimpleDialogOption(
            key: const ValueKey('timelapse-full'),
            onPressed: () => Navigator.pop(context, 0),
            child: Text(
              '${l.timelapseFull} · ${l.timelapseFrames(all.length)}',
            ),
          ),
          SimpleDialogOption(
            key: const ValueKey('timelapse-30'),
            onPressed: () => Navigator.pop(context, 30),
            child: Text(l.timelapse30),
          ),
        ],
      ),
    );
    if (seconds == null || !mounted) return;
    await _run(() async {
      final (width, height) =
          await store.size(c.document.id) ??
          timelapseSize(
            c.document.dimensions.width,
            c.document.dimensions.height,
          );
      final frames = framesFor(all, seconds: seconds == 0 ? null : seconds);
      final output = File(
        '${(await getTemporaryDirectory()).path}/timelapse-${newId()}.mp4',
      );
      try {
        final ok = await const VideoEncoder().encode(
          frames: [for (final f in frames) f.path],
          output: output.path,
          width: width,
          height: height,
        );
        if (!ok) throw StateError('The video could not be made');
        final result = await FilePicker.saveFile(
          fileName: '$_filename.mp4',
          bytes: await output.readAsBytes(),
          mimeType: 'video/mp4',
        );
        if (result != null && mounted) _message(l.exportSuccess);
      } on MissingPluginException {
        if (mounted) _message(l.timelapseUnsupported);
      } finally {
        if (await output.exists()) await output.delete();
      }
    });
  }

  Future<void> _clearTimelapse() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.timelapseClearAsk),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('timelapse-clear-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.galleryDelete),
          ),
        ],
      ),
    );
    if (yes == true) await _run(c.clearTimelapse);
  }

  Future<void> _exportDocument() async {
    await c.settleStroke();
    final document = c.document;
    await RasterAsset.hashAll([
      for (final layer in document.layers) ...?layer.raster?.tiles.values,
    ]);
    final blobs = <String, Uint8List>{};
    final manifest = document.toJson(blobs: blobs);
    final bytes = await compute(encodeDocumentPackage, (manifest, blobs));
    final result = await FilePicker.saveFile(
      fileName: '$_filename.artdoc',
      bytes: bytes,
    );
    if (result != null && mounted) _message(l.exportSuccess);
  }

  Future<void> _exportImage() async {
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.exportImage),
        children: [
          for (final (format, label, icon) in [
            (ExportFormat.psd, l.exportFormatPsd, Icons.layers_outlined),
            (ExportFormat.png, l.exportFormatPng, Icons.image_outlined),
            (ExportFormat.jpeg, l.exportFormatJpeg, Icons.photo_outlined),
            (
              ExportFormat.tiff,
              l.exportFormatTiff,
              Icons.photo_library_outlined,
            ),
            (
              ExportFormat.pdf,
              l.exportFormatPdf,
              Icons.picture_as_pdf_outlined,
            ),
            (
              ExportFormat.layersPng,
              l.exportLayersPng,
              Icons.folder_zip_outlined,
            ),
            (
              ExportFormat.layersPdf,
              l.exportLayersPdf,
              Icons.auto_stories_outlined,
            ),
            if (c.document.pageAssist)
              (
                ExportFormat.pagesPdf,
                l.exportPagesPdf,
                Icons.menu_book_outlined,
              ),
            if (c.document.animating) ...[
              (ExportFormat.gif, l.exportFormatGif, Icons.gif_box_outlined),
              (ExportFormat.apng, l.exportFormatApng, Icons.animation_outlined),
              (ExportFormat.mp4, l.exportFormatMp4, Icons.movie_outlined),
              if (Platform.isMacOS)
                (
                  ExportFormat.hevc,
                  l.exportFormatHevc,
                  Icons.video_file_outlined,
                ),
            ],
          ])
            SimpleDialogOption(
              key: ValueKey('export-${format.name}'),
              onPressed: () => Navigator.pop(context, format),
              child: Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    var web = false;
    if (format.animated) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.exportAnimationSize),
          children: [
            SimpleDialogOption(
              key: const ValueKey('export-size-full'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                l.exportSizeFull(Exporter.longestSide(format, web: false)),
              ),
            ),
            SimpleDialogOption(
              key: const ValueKey('export-size-web'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.exportSizeWeb),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      web = choice;
    }
    await _run(() async {
      final Uint8List bytes;
      try {
        bytes = await Exporter(c).export(format, web: web);
      } on MissingPluginException {
        if (mounted) _message(l.timelapseUnsupported);
        return;
      }
      final result = await FilePicker.saveFile(
        fileName: '$_filename.${format.extension}',
        bytes: bytes,
        mimeType: format.mimeType,
      );
      if (result != null && mounted) _message(l.exportSuccess);
    });
  }

  Future<void> _exportLayer(ArtLayer layer) async {
    await c.settleStroke();
    final bytes = await Exporter(c).layerPng(layer);
    final name = layer.name.replaceAll(RegExp(r'[^\w\- ]'), '_');
    final result = await FilePicker.saveFile(
      fileName: '$_filename - $name.png',
      bytes: bytes,
      mimeType: 'image/png',
    );
    if (result != null && mounted) _message(l.exportSuccess);
  }
}

/// The real MyPaint dabs of a preset, rendered once per brush and tinted.
class NativeBrushPreview extends StatelessWidget {
  const NativeBrushPreview(this.brush, this.color, {super.key});
  final BrushPreset brush;
  final Color color;

  /// Per brush as it is: an edited brush (same id) draws afresh.
  static final _cache = Expando<Future<ui.Image>>();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 28,
    child: FutureBuilder<ui.Image>(
      future: _cache[brush] ??= renderNativePreview(brush)
          .catchError((Object error) {
            _cache[brush] = null;
            throw error;
          }),
      builder: (context, snapshot) => snapshot.hasData
          ? RawImage(
              image: snapshot.data,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              color: color,
              colorBlendMode: BlendMode.srcIn,
            )
          : const SizedBox.shrink(),
    ),
  );
}

class BrushPreviewPainter extends CustomPainter {
  BrushPreviewPainter(this.brush, this.engine, this.color);
  final BrushPreset brush;
  final BrushEngine engine;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = InkStroke(
      id: 'preview',
      size: math.min(brush.size, 12),
      color: color.toARGB32(),
      opacity: 1,
      thinning: brush.thinning,
      smoothing: brush.smoothing,
      points: List.generate(
        40,
        (i) => InkPoint(
          i * size.width / 40,
          12 + math.sin(i / 6) * 4,
          .3 + i / 80,
        ),
      ),
    );
    canvas.drawPath(engine.outline(stroke), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant BrushPreviewPainter oldDelegate) =>
      oldDelegate.brush != brush || oldDelegate.color != color;
}

class ColorHexInput extends StatefulWidget {
  const ColorHexInput({super.key, required this.color, required this.onColor});
  final int color;
  final ValueChanged<int> onColor;
  @override
  State<ColorHexInput> createState() => _ColorHexInputState();
}

class _ColorHexInputState extends State<ColorHexInput> {
  late final TextEditingController field = TextEditingController(
    text: _hex(widget.color),
  );
  String? error;
  String _hex(int color) =>
      '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}${(color >> 24) == 255 ? '' : (color >> 24).toRadixString(16).padLeft(2, '0')}';
  @override
  void didUpdateWidget(covariant ColorHexInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) field.text = _hex(widget.color);
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void submit() {
    try {
      final color = parseHex(field.text.trim());
      setState(() => error = null);
      widget.onColor(color);
    } catch (_) {
      setState(() => error = AppLocalizations.of(context).invalidHex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: field,
            maxLength: 9,
            decoration: InputDecoration(
              labelText: l.colorHex,
              errorText: error,
              counterText: '',
            ),
            onSubmitted: (_) => submit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l.apply,
          onPressed: submit,
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }
}

/// Picks a new drawing's canvas: a preset (built-in, the screen or the
/// user's own) or a size in pixels, millimetres, centimetres or inches at
/// a DPI. Pops `(size, dpi)`, or null when cancelled.
class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({super.key, required this.screen, this.controller});

  /// The display in physical pixels; landscape and fitted to the largest
  /// canvas side, so it can become a canvas.
  final Size screen;

  /// Keeps the user's presets; without it there are none.
  final StudioController? controller;

  CanvasSize get screenCanvas {
    final long = math.max(screen.width, screen.height);
    final short = math.min(screen.width, screen.height);
    final fit = math.min(1.0, CanvasSize.maxSide / long);
    return CanvasSize(
      math.max(CanvasSize.minSide, (long * fit).round()),
      math.max(CanvasSize.minSide, (short * fit).round()),
    );
  }

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  /// The preset the fields came from; null once they are typed in.
  String? chosen = 'square';

  /// The user's preset being edited ("Update preset" saves it).
  String? editing;
  CanvasUnit unit = CanvasUnit.px;
  ColorProfile profile = ColorProfile.srgb;
  final width = TextEditingController(text: '2048');
  final height = TextEditingController(text: '2048');
  final dpi = TextEditingController(text: '132');

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    dpi.dispose();
    super.dispose();
  }

  static String _number(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  double? _read(TextEditingController field) {
    final v = double.tryParse(field.text.trim().replaceAll(',', '.'));
    return v != null && v.isFinite && v > 0 ? v : null;
  }

  /// The fields as a preset; null while one is not a number.
  CanvasPreset? get typed {
    final w = _read(width), h = _read(height), d = _read(dpi);
    if (w == null || h == null || d == null) return null;
    return CanvasPreset(
      id: editing ?? newId(),
      name: '',
      width: w,
      height: h,
      unit: unit,
      dpi: d.round().clamp(CanvasPreset.minDpi, CanvasPreset.maxDpi),
    );
  }

  void _fill(CanvasPreset preset, {String? id}) => setState(() {
    chosen = id ?? preset.id;
    editing = null;
    unit = preset.unit;
    width.text = _number(preset.width);
    height.text = _number(preset.height);
    dpi.text = '${preset.dpi}';
  });

  void _setUnit(CanvasUnit next) {
    final now = typed;
    setState(() {
      if (now != null) {
        final converted = now.inUnit(next);
        width.text = _number(converted.width);
        height.text = _number(converted.height);
      }
      unit = next;
    });
  }

  Future<void> _savePreset(AppLocalizations l) async {
    final c = widget.controller, preset = typed;
    if (c == null || preset == null) return;
    final current = c.canvasPresets.where((p) => p.id == editing).firstOrNull;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _PresetNameDialog(initial: current?.name ?? ''),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final saved = preset.copyWith(name: name.trim());
    c.saveCanvasPreset(saved);
    setState(() {
      chosen = saved.id;
      editing = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final screen = widget.screenCanvas;
    final mine = widget.controller?.canvasPresets ?? const <CanvasPreset>[];
    final preset = typed;
    final size = preset?.size;
    final valid = size != null && size.isValid;
    String builtInName(String id) => switch (id) {
      'square' => l.presetSquare,
      '4k' => l.preset4k,
      'a4' => l.presetA4,
      'photo' => l.presetPhoto,
      _ => l.presetLetter,
    };
    String describe(CanvasPreset p) {
      final px = p.size;
      return p.unit == CanvasUnit.px
          ? '${px.width} × ${px.height} px'
          : '${_number(p.width)} × ${_number(p.height)} ${p.unit.symbol} · '
                '${p.dpi} DPI · ${px.width} × ${px.height} px';
    }

    Widget row(
      String id,
      String name,
      String detail,
      VoidCallback onTap, {
      List<Widget> trailing = const [],
    }) => ListTile(
      key: ValueKey('preset-$id'),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      selected: chosen == id,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: .4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 11)),
      trailing: trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
      onTap: onTap,
    );

    Widget field(String key, TextEditingController c, String label) => Expanded(
      child: TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => setState(() => chosen = null),
      ),
    );

    final wide = MediaQuery.sizeOf(context).width >= 760;
    final presetList = <Widget>[
      Text(l.canvasSize, style: const TextStyle(fontWeight: FontWeight.w600)),
      row(
        'screen',
        l.presetScreen,
        '${screen.width} × ${screen.height} px',
        () => _fill(
          CanvasPreset(
            id: 'screen',
            name: '',
            width: screen.width.toDouble(),
            height: screen.height.toDouble(),
          ),
        ),
      ),
      for (final p in CanvasPreset.builtIn)
        row(p.id, builtInName(p.id), describe(p), () => _fill(p)),
      if (mine.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(l.myPresets, style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final p in mine)
          row(
            p.id,
            p.name,
            describe(p),
            () => _fill(p),
            trailing: [
              IconButton(
                key: ValueKey('preset-edit-${p.id}'),
                tooltip: l.editPreset,
                iconSize: 18,
                onPressed: () {
                  _fill(p);
                  setState(() => editing = p.id);
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: ValueKey('preset-delete-${p.id}'),
                tooltip: l.deletePreset,
                iconSize: 18,
                onPressed: () {
                  widget.controller!.deleteCanvasPreset(p.id);
                  setState(() {
                    if (chosen == p.id) chosen = null;
                    if (editing == p.id) editing = null;
                  });
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
      ],
      row(
        'custom',
        l.customCanvas,
        l.canvasSizeHint(CanvasSize.minSide, CanvasSize.maxSide),
        () => setState(() => chosen = null),
      ),
    ];
    final form = <Widget>[
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          field('canvas-width', width, l.canvasWidth),
          IconButton(
            key: const ValueKey('canvas-swap'),
            tooltip: l.swapSides,
            onPressed: () => setState(() {
              final w = width.text;
              width.text = height.text;
              height.text = w;
              chosen = null;
            }),
            icon: const Icon(Icons.swap_horiz),
          ),
          field('canvas-height', height, l.canvasHeight),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: DropdownButtonFormField<CanvasUnit>(
              key: const ValueKey('canvas-unit'),
              initialValue: unit,
              decoration: InputDecoration(
                labelText: l.canvasUnit,
                isDense: true,
              ),
              items: [
                for (final u in CanvasUnit.values)
                  DropdownMenuItem(value: u, child: Text(u.symbol)),
              ],
              onChanged: (u) {
                if (u != null) _setUnit(u);
              },
            ),
          ),
          const SizedBox(width: 12),
          field('canvas-dpi', dpi, l.canvasDpi),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        size == null
            ? ''
            : valid
            ? l.canvasPixels(size.width, size.height)
            : l.canvasTooLarge(
                size.width,
                size.height,
                CanvasSize.minSide,
                CanvasSize.maxSide,
              ),
        key: const ValueKey('canvas-pixels'),
        style: TextStyle(fontSize: 12, color: valid ? null : scheme.error),
      ),
      if (widget.controller != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('preset-save'),
            onPressed: preset == null ? null : () => _savePreset(l),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(editing == null ? l.savePreset : l.updatePreset),
          ),
        ),
      const SizedBox(height: 8),
      DropdownButtonFormField<ColorProfile>(
        key: const ValueKey('canvas-profile'),
        initialValue: profile,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.colorProfile, isDense: true),
        items: [
          for (final p in ColorProfile.values)
            DropdownMenuItem(value: p, child: Text(profileName(l, p))),
        ],
        onChanged: (p) {
          if (p != null) setState(() => profile = p);
        },
      ),
      const SizedBox(height: 8),
      Text(l.newDocumentMessage, style: const TextStyle(fontSize: 12)),
    ];
    return AlertDialog(
      title: Text(l.newDocument),
      content: SizedBox(
        width: wide ? 700 : 440,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: presetList,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: form,
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...presetList, ...form],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('canvas-create'),
          onPressed: !valid
              ? null
              : () => Navigator.pop(context, (size, preset!.dpi, profile)),
          child: Text(l.confirm),
        ),
      ],
    );
  }
}

/// The colours found in [pixels], as many as chosen.
class _PaletteFromPixels extends StatefulWidget {
  const _PaletteFromPixels({required this.pixels});
  final Uint8List pixels;

  @override
  State<_PaletteFromPixels> createState() => _PaletteFromPixelsState();
}

class _PaletteFromPixelsState extends State<_PaletteFromPixels> {
  double count = 12;
  late Future<List<int>> colors = _find();

  Future<List<int>> _find() {
    final pixels = widget.pixels, n = count.round();
    return Isolate.run(() => paletteFromPixels(pixels, count: n));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.paletteFromImage),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueSlider(
              id: 'palette-count',
              label: l.paletteColors,
              value: count,
              min: 3,
              max: 30,
              toNumber: (v) => v,
              fromNumber: (n) => n,
              unit: '',
              onChanged: (v) => setState(() => count = v.roundToDouble()),
              onChangeEnd: (_) => setState(() => colors = _find()),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<int>>(
              future: colors,
              builder: (context, snapshot) {
                final found = snapshot.data;
                if (found == null) {
                  return const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Wrap(
                  key: const ValueKey('palette-preview'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in found)
                      Container(
                        width: 36,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('palette-create'),
          onPressed: () async {
            final found = await colors;
            if (context.mounted) Navigator.pop(context, found);
          },
          child: Text(l.paletteCreate),
        ),
      ],
    );
  }
}

String profileName(AppLocalizations l, ColorProfile p) => switch (p) {
  ColorProfile.srgb => l.profileSrgb,
  ColorProfile.displayP3 => l.profileP3,
  ColorProfile.cmyk => l.profileCmyk,
};

/// The picked colour's name for a moment at the top, and said aloud by the
/// screen reader (when colour names are on).
class _ColorNameBanner extends StatefulWidget {
  const _ColorNameBanner({required this.controller});
  final StudioController controller;

  @override
  State<_ColorNameBanner> createState() => _ColorNameBannerState();
}

class _ColorNameBannerState extends State<_ColorNameBanner> {
  String? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.controller.colorPicked.addListener(_picked);
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.controller.colorPicked.removeListener(_picked);
    super.dispose();
  }

  void _picked() {
    final c = widget.controller, picked = c.colorPicked.value;
    if (!c.colorNames || picked == null || !mounted) return;
    final name = colorName(AppLocalizations.of(context), picked.$2);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        name,
        Directionality.of(context),
      ),
    );
    _hide?.cancel();
    setState(() => _shown = name);
    _hide = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _shown = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('color-name-banner'),
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(shown, style: TextStyle(color: scheme.onInverseSurface)),
      ),
    );
  }
}

/// Single-touch gestures: undo, redo, fit, and the canvas moved, zoomed or
/// turned by one finger while a mode is on.
class _SingleTouchPad extends StatelessWidget {
  const _SingleTouchPad({required this.controller, required this.onFit});
  final StudioController controller;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget mode(SingleTouchMode m, String tip, IconData icon) => IconButton(
      key: ValueKey('single-${m.name}'),
      tooltip: tip,
      isSelected: c.singleTouchMode == m,
      style: IconButton.styleFrom(
        backgroundColor: c.singleTouchMode == m
            ? scheme.primaryContainer
            : null,
      ),
      onPressed: () => c.setSingleTouchMode(m),
      icon: Icon(icon),
    );
    return Material(
      key: const ValueKey('single-touch-pad'),
      elevation: 6,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('single-undo'),
              tooltip: l.undo,
              onPressed: c.undo,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              key: const ValueKey('single-redo'),
              tooltip: l.redo,
              onPressed: c.redo,
              icon: const Icon(Icons.redo),
            ),
            mode(SingleTouchMode.move, l.touchMove, Icons.open_with),
            mode(SingleTouchMode.zoom, l.touchZoom, Icons.zoom_in),
            mode(SingleTouchMode.rotate, l.touchRotate, Icons.rotate_right),
            IconButton(
              key: const ValueKey('single-fit'),
              tooltip: l.fitCanvas,
              onPressed: onFit,
              icon: const Icon(Icons.fit_screen_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks a preset's name; the field outlives the closing animation.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.initial});
  final String initial;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.presetName),
      content: TextField(
        key: const ValueKey('preset-name'),
        controller: _field,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: Text(l.confirm),
        ),
      ],
    );
  }
}

/// Runs editor shortcuts unless a text field is being typed in.
class _CanvasShortcutAction extends VoidCallbackAction {
  @override
  bool isEnabled(VoidCallbackIntent intent) =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() ==
      null;
}

/// A movie drawing's editor: its own controller, saved and closed once
/// the screen is gone (its exit animation included), then the main
/// editor picks up library changes.
class _DrawingEditor extends StatefulWidget {
  const _DrawingEditor({
    required this.base,
    required this.drawing,
    required this.onSave,
    required this.onExit,
    this.onScrub,
  });
  final StudioController base;
  final ArtDocument drawing;
  final void Function(ArtDocument drawing) onSave;
  final void Function(int frame)? onScrub;
  final VoidCallback onExit;

  @override
  State<_DrawingEditor> createState() => _DrawingEditorState();
}

class _DrawingEditorState extends State<_DrawingEditor> {
  late final inner = StudioController(
    storage: DrawingStorage(widget.base.storage, widget.drawing, widget.onSave),
    preferences: widget.base.preferences,
  )..onFrameShown = widget.onScrub;
  late final Future<void> ready = inner.initialize();

  @override
  void dispose() {
    final base = widget.base;
    unawaited(
      inner.settleStroke().then((_) => inner.save()).whenComplete(() {
        inner.dispose();
        return base.reloadLibrary();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) =>
        snapshot.connectionState == ConnectionState.done
        ? EditorScreen(controller: inner, onExit: widget.onExit)
        : const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}
