import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/export_formats.dart';
import '../data/import_formats.dart';
import '../data/timelapse.dart';
import '../data/studio_storage.dart';
import '../data/hub_service.dart';
import '../domain/canvas_preset.dart';
import '../domain/document.dart';
import '../domain/selection.dart';
import '../domain/ai_canvas_input.dart';
import '../drawing/adjustments.dart';
import '../drawing/auto_select.dart';
import '../drawing/raster_cache.dart';
import '../drawing/png_bands.dart';
import '../drawing/imported_document.dart';
import '../drawing/raster_tiles.dart';
import '../drawing/brush_engine.dart';
import '../drawing/clone.dart';
import '../drawing/color_pick.dart';
import '../drawing/flood_fill.dart';
import '../drawing/guides.dart';
import '../drawing/layer_compositor.dart';
import '../drawing/layer_transform.dart';
import '../drawing/liquify.dart';
import '../drawing/native_stroke.dart';
import '../drawing/quick_shape.dart';
import '../drawing/stroke_stabilizer.dart';
import '../drawing/symmetry.dart';
import '../drawing/text_layer.dart';
import 'history_change.dart';
import 'hub_jobs.dart';
import 'pen_probe.dart';
import 'quick_menu.dart';

/// Pixels on the clipboard and the canvas area they came from.
class CanvasClipping {
  const CanvasClipping(this.png, this.area);
  final Uint8List png;
  final Rect area;
}

enum StudioTool { brush, smudge, eraser, pan, transform, selection, eyedropper }

enum SelectionShape { rectangle, ellipse, freehand, polygon, automatic }

/// What the canvas draws with onion skins: the background frame, the
/// tinted neighbours (each with its opacity), then the frame drawn on
/// (see-through with [blendPrimary]) and the foreground frame. None of
/// them paints the paper.
class OnionView {
  const OnionView({
    required this.under,
    required this.onions,
    required this.top,
    required this.blendPrimary,
  });
  final ArtDocument? under;
  final List<(ArtDocument, int, double)> onions;
  final ArtDocument top;
  final bool blendPrimary;
}

/// What a one-finger drag does with the single-touch pad.
enum SingleTouchMode { move, zoom, rotate }

/// What a finger paints with while the pen keeps its tool.
enum FingerTool { same, smudge, eraser }

/// What a new selection shape does to the current selection.
enum SelectionMode { replace, add, subtract }

enum EditorPanel {
  gallery,
  actions,
  adjustments,
  brushes,
  layers,
  colors,
  settings,
  connections,
}

enum SaveState { saved, pending, saving, failed }

class StudioController extends ChangeNotifier {
  StudioController({
    required this.storage,
    SharedPreferences? preferences,
    HubService? hub,
  }) : _preferences = preferences,
       hub = hub ?? HubService() {
    final language = preferences?.getString('language');
    locale = language == 'tr' || language == 'en' ? Locale(language!) : null;
    themeMode = switch (preferences?.getString('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    rightSidebar = preferences?.getBool('rightSidebar') ?? false;
    defaultPaletteId = preferences?.getString('palette.default');
    brushCursor = preferences?.getBool('brush.cursor') ?? true;
    _loadAccessibility(preferences);
    timelapseOn = preferences?.getBool('timelapse.on') ?? true;
    miniFlipbook = preferences?.getBool('flipbook.mini') ?? false;
    _loadGesturePrefs(preferences);
    quickMenuTrigger =
        QuickMenuTrigger.values.asNameMap()[preferences?.getString(
          'quickmenu.trigger',
        )] ??
        QuickMenuTrigger.touchHold;
    try {
      final profiles = jsonDecode(
        preferences?.getString('quickmenu.profiles') ?? '[]',
      );
      if (profiles is List) {
        final read = [...profiles.map(QuickMenuProfile.fromJson).nonNulls];
        if (read.isNotEmpty) quickMenuProfiles = List.unmodifiable(read);
      }
      final active = preferences?.getString('quickmenu.active');
      if (quickMenuProfiles.any((p) => p.id == active)) {
        quickMenuActive = active!;
      }
    } on Object {
      // Damaged: the default buttons.
    }
    try {
      final presets = jsonDecode(
        preferences?.getString('canvas.presets') ?? '[]',
      );
      if (presets is List) {
        canvasPresets = List.unmodifiable(
          presets.map(CanvasPreset.fromJson).nonNulls,
        );
      }
    } on Object {
      // Damaged: no saved presets.
    }
    try {
      final curve = jsonDecode(
        preferences?.getString('pressure.curve') ?? 'null',
      );
      if (curve is List && curve.length >= 2) {
        _setCurve([
          for (final p in curve)
            Offset(
              ((p as List)[0] as num).toDouble().clamp(0, 1),
              (p[1] as num).toDouble().clamp(0, 1),
            ),
        ]);
      }
      final memory = jsonDecode(
        preferences?.getString('brushes.memory') ?? '{}',
      );
      if (memory is Map) {
        _brushMemory = {
          for (final MapEntry(:key, :value) in memory.entries)
            if (value is List && value.length == 2)
              key as String: (
                (value[0] as num).toDouble(),
                (value[1] as num).toDouble(),
              ),
        };
      }
    } on Object {
      // A damaged preference: the straight curve, nothing remembered.
    }
    recentBrushes =
        preferences?.getStringList('brushes.recent') ?? const <String>[];
    paletteCards = preferences?.getBool('palette.cards') ?? false;
    fingerDrawing = preferences?.getBool('fingerDrawing') ?? true;
    fillThreshold = (preferences?.getDouble('fill.threshold') ?? .3).clamp(
      0,
      maxFillThreshold,
    );
    autoThreshold = (preferences?.getDouble('selection.threshold') ?? .12)
        .clamp(0, 1);
    transformSnapping = preferences?.getBool('transform.snapping') ?? false;
    transformMagnetics = preferences?.getBool('transform.magnetics') ?? false;
    snapDistance = (preferences?.getDouble('snap.distance') ?? 12).clamp(4, 60);
    snapVelocity = (preferences?.getDouble('snap.velocity') ?? 1500).clamp(
      100,
      5000,
    );
    try {
      final saved = jsonDecode(preferences?.getString('colors.recent') ?? '[]');
      if (saved is List) {
        recentColors = [
          for (final c in saved.take(maxRecentColors))
            if (c is int && c >= 0 && c <= 0xffffffff) c,
        ];
      }
    } on FormatException {
      // A damaged preference only loses the recent colours.
    }
    symmetry =
        SymmetryKind.values.asNameMap()[preferences?.getString(
          'guide.symmetry',
        )] ??
        SymmetryKind.off;
    try {
      final saved = preferences?.getString('guide.settings');
      guide = saved == null
          // Before guide settings: only a grid and its size.
          ? DrawingGuide(
              kind: preferences?.getBool('guide.grid') ?? false
                  ? GuideKind.grid
                  : GuideKind.none,
            ).copyWith(gridSize: preferences?.getDouble('guide.gridSize'))
          : DrawingGuide.fromJson(jsonDecode(saved));
    } on FormatException {
      guide = const DrawingGuide();
    }
    double pref(String key) => (preferences?.getDouble(key) ?? 0).clamp(0, 1);
    stabilization = pref('smoothing.stabilization');
    motionFilter = pref('smoothing.motionFilter');
    motionExpression = pref('smoothing.expression');
    try {
      final saved = jsonDecode(
        preferences?.getString('smoothing.streamLine') ?? '{}',
      );
      if (saved is Map) {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (key is String && value is num && value.isFinite) {
            _streamLine[key] = value.toDouble().clamp(0, 1);
          }
        }
      }
    } on FormatException {
      // A damaged preference only loses StreamLine values.
    }
    hubJob = HubImageJob(
      this.hub,
      place: (image, source, replace) {
        final prompt = hubJob.prompt ?? '';
        return addImageLayer(
          image,
          prompt.isEmpty
              ? 'Generative fill'
              : prompt.length > 32
              ? '${prompt.substring(0, 31)}…'
              : prompt,
          source: source,
          replace: replace,
        );
      },
      remove: deleteLayer,
      save: (job) => job == null
          ? _preferences?.remove('hub.job')
          : _preferences?.setString('hub.job', jsonEncode(job)),
      saved: () {
        try {
          final json = jsonDecode(_preferences?.getString('hub.job') ?? 'null');
          return json is Map ? json.cast<String, Object?>() : null;
        } on FormatException {
          return null;
        }
      },
    );
    this.hub.addListener(_notify);
  }
  final StudioStorage storage;
  final RasterCache rasters = RasterCache();
  bool documentTransition = false;
  LayerTransform? transformDraft;

  /// How handles act: kept between transforms, as in Procreate.
  TransformMode transformMode = TransformMode.uniform;

  /// Snapping: moved content meets the canvas's and other layers' edges
  /// and middles within [snapDistance] screen pixels, unless dragged faster
  /// than [snapVelocity] screen pixels a second.
  bool transformSnapping = false;
  double snapDistance = 12, snapVelocity = 1500;

  /// Magnetics: moves along axes, turns in 15° steps, corners keep shape.
  bool transformMagnetics = false;

  /// The lines content snapped to, shown while dragging.
  List<(Offset, Offset)> snapGuides = const [];
  ({List<double> xs, List<double> ys})? _snapTargets;

  void setTransformSnapping(bool on) {
    transformSnapping = on;
    _preferences?.setBool('transform.snapping', on);
    _notify();
  }

  void setTransformMagnetics(bool on) {
    transformMagnetics = on;
    _preferences?.setBool('transform.magnetics', on);
    _notify();
  }

  void setSnapSettings({double? distance, double? velocity}) {
    snapDistance = (distance ?? snapDistance).clamp(4, 60);
    snapVelocity = (velocity ?? snapVelocity).clamp(100, 5000);
    _preferences?.setDouble('snap.distance', snapDistance);
    _preferences?.setDouble('snap.velocity', snapVelocity);
    _notify();
  }

  /// Lines moved content may snap to: the canvas's edges and middle, and
  /// the edges and middles of the other visible layers' content.
  ({List<double> xs, List<double> ys}) get snapTargets {
    final cached = _snapTargets;
    if (cached != null) return cached;
    final dims = document.dimensions;
    final xs = [0.0, dims.width / 2, dims.width.toDouble()];
    final ys = [0.0, dims.height / 2, dims.height.toDouble()];
    for (final layer in document.layers) {
      if (layer.id == transformLayerId || !layer.visible) continue;
      final r = layerContentBounds(
        layer,
        FreehandBrushEngine(),
        dims,
        pixelBounds: rasters.pixelBounds,
      );
      if (r == null) continue;
      xs.addAll([r.left, r.center.dx, r.right]);
      ys.addAll([r.top, r.center.dy, r.bottom]);
    }
    return _snapTargets = (xs: xs, ys: ys);
  }

  void showSnapGuides(List<(Offset, Offset)> guides) {
    if (guides.isEmpty && snapGuides.isEmpty) return;
    snapGuides = guides;
    inkChanges.notifyListeners();
  }

  /// A transform gesture ended: guides go, targets are found afresh.
  void endSnap() {
    _snapTargets = null;
    showSnapGuides(const []);
  }

  /// The content Distort and Warp draw across their mesh.
  Image? _transformSource;
  SelectionRegion? selection, transformSelection;
  SelectionShape selectionShape = SelectionShape.rectangle;
  SelectionMode selectionMode = SelectionMode.replace;
  final List<Offset> _selectionPoints = [];
  bool get selectionDrawing => _selectionPoints.isNotEmpty;
  List<Offset> get selectionPoints => List.unmodifiable(_selectionPoints);
  String? transformLayerId;
  StudioTool _toolBeforeTransform = StudioTool.brush;
  final HubService hub;
  late final HubImageJob hubJob;
  final SharedPreferences? _preferences;
  ArtDocument document = ArtDocument.empty();
  List<BrushPreset> brushes = [...initialBrushes];
  List<ColorPalette> palettes = [...initialPalettes];
  BrushPreset brush = initialBrushes.first;
  int color = 0xff346b70;
  double size = 10, opacity = 1;
  StudioTool tool = StudioTool.brush;
  EditorPanel? panel;
  ThemeMode themeMode = ThemeMode.system;
  Locale? locale;
  bool rightSidebar = false, fingerDrawing = true;

  /// Procreate's global "pressure and smoothing" controls, 0…1.
  double stabilization = 0, motionFilter = 0, motionExpression = 0;

  /// StreamLine per brush id; brushes not listed have none.
  final Map<String, double> _streamLine = {};
  double get streamLine => _streamLine[brush.id] ?? 0;
  SmoothingSettings get smoothing => SmoothingSettings(
    streamLine: streamLine,
    stabilization: stabilization,
    motionFilter: motionFilter,
    expression: motionExpression,
  );
  StrokeStabilizer? _stabilizer;
  (double, double) _lastTilt = (0, 0);

  /// Eyedropper: where it is held, and the colour under it once sampled.
  Offset? pickPoint;
  int? pickColor;
  Uint8List? _pickPixels;
  int _pickEpoch = 0;
  bool _pickReleased = false;
  StudioTool _toolBeforePick = StudioTool.brush;
  bool initialized = false, disposed = false, libraryDirty = false;
  String? error;
  SaveState saveState = SaveState.saved;
  final List<ArtDocument> _undo = [], _redo = [];
  final List<InkPoint> _points = [];
  InkStroke? _pending;
  String? _pendingLayerId;
  final NativeBrushRuntime _native = NativeBrushRuntime();
  NativeStrokeSession? _drawingNative;

  /// Native strokes on screen but not yet committed, oldest first.
  final List<NativeStrokeSession> _previews = [];

  /// Main queue: commits and document edits, strictly in the user's order.
  Future<void> _queueTail = Future.value();
  int _queued = 0, _edits = 0;
  bool _inQueue = false;

  /// Worker lane: stroke starts and final reads. A stroke can start as soon
  /// as the previous one is read out, while that one merges and commits.
  Future<void> _workerTail = Future.value();
  int _workerQueued = 0;
  bool get _busy => _queued > 0 || _workerQueued > 0;
  final StreamController<Object> _strokeFailures = StreamController.broadcast(
    sync: true,
  );

  /// Native stroke failures; the stroke is dropped, the document is unchanged.
  Stream<Object> get strokeFailures => _strokeFailures.stream;

  /// True while a native stroke is drawn, finalized or document edits wait.
  bool get strokeBusy => _busy || _drawingNative != null;

  /// The newest native stroke's live blocks.
  NativeOverlay? get nativePreview =>
      _previews.isEmpty ? null : _previews.last.preview;
  String? get nativePreviewLayerId =>
      _previews.isEmpty ? null : _previews.last.layerId;

  /// Per layer, the native strokes drawn over its committed content.
  Map<String, LayerContentOverride> get nativeOverrides {
    final grouped = <String, List<NativeOverlay>>{};
    for (final session in _previews) {
      (grouped[session.layerId] ??= []).add(session.preview);
    }
    final overrides = grouped.map(
      (id, list) => MapEntry(id, LayerContentOverride(list)),
    );
    if (adjustment case final session?) {
      overrides[session.layerId] = LayerContentOverride(
        const [],
        replace: session.paint,
      );
    }
    if (clone case final session?) {
      overrides[session.layerId] = LayerContentOverride(
        const [],
        replace: session.paint,
      );
    }
    if (liquify case final session?) {
      overrides[session.layerId] = LayerContentOverride(
        const [],
        replace: (canvas, _) => session.paint(canvas),
      );
    }
    return overrides;
  }

  /// Last native stroke timings, for profiling the full-surface transfer.
  NativeStrokeStats? lastNativeStats;
  Timer? _autosave;
  int _saveGeneration = 0;
  Future<void> _saveTail = Future.value();
  final ChangeNotifier inkChanges = ChangeNotifier();

  /// Whether frames draw [compositor]'s flattened layers; switchable in pen
  /// log builds to compare frame times on a device.
  bool flattenLayers = true;

  void setFlattenLayers(bool value) {
    flattenLayers = value;
    inkChanges.notifyListeners();
    _notify();
  }

  /// Layers below and above the active one, flattened for drawing.
  late final LayerCompositor compositor = LayerCompositor(
    onReady: () {
      if (!disposed) inkChanges.notifyListeners();
    },
  );

  /// Language and theme only, so drawing never rebuilds the app shell.
  final ChangeNotifier appearance = ChangeNotifier();
  InkStroke? get pendingStroke => _pending;

  /// The vector stroke being drawn and its symmetric copies.
  List<InkStroke> get pendingStrokes {
    final pending = _pending;
    if (pending == null) return const [];
    return symmetry == SymmetryKind.off
        ? [pending]
        : symmetricStrokes(
            pending,
            symmetry,
            guide.symmetryCentreOn(document.dimensions.size),
            rotational: guide.rotational,
          );
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> initialize() async {
    // Blend modes Flutter lacks fall back to the nearest one until it is
    // loaded; then the drawing is redrawn with it.
    if (BlendShader.program == null) {
      BlendShader.load().then((_) {
        if (disposed) return;
        compositor.clear();
        inkChanges.notifyListeners();
        _notify();
      }, onError: (_) {});
    }
    // Never overwrite unreadable user data with a fresh blank document.
    try {
      final saved = await storage.loadDocument();
      if (saved != null) {
        await rasters.prepare(documentRasters(saved));
        final tiled = await _tileLegacyRasters(saved);
        if (disposed) return;
        document = tiled;
        _retainRasterHistory();
      }
      await _loadLibrary();
      // Before any save: tiles left by earlier sessions' history go now.
      unawaited(storage.compact().catchError((Object _) {}));
      initialized = true;
      error = null;
      saveState = SaveState.saved;
    } catch (e) {
      error = e.toString();
      saveState = SaveState.failed;
      // UI provides retry; editing is disabled until restoration succeeds.
    }
    _notify();
  }

  /// An unreadable library must neither block drawing nor be overwritten
  /// with defaults: the editor keeps the built-ins and locks the library.
  Future<void> _loadLibrary() async {
    try {
      final library = await storage.loadLibrary();
      if (library == null) return;
      // Parse everything before applying anything.
      final loadedBrushes = (library['brushes'] as List)
          .map((b) => BrushPreset.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList();
      final loadedPalettes = (library['palettes'] as List)
          .map(
            (p) => ColorPalette.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList();
      if (loadedBrushes.isNotEmpty) {
        final ids = loadedBrushes.map((b) => b.id).toSet();
        brushes = [
          ...loadedBrushes,
          ...initialBrushes.where((b) => b.isNative && !ids.contains(b.id)),
        ];
        brush = brushes.first;
        size = brush.size.clamp(1, 128);
      }
      if (loadedPalettes.isNotEmpty) palettes = loadedPalettes;
    } catch (e) {
      libraryError = e.toString();
    }
  }

  /// The library as saved now (another editor, on a movie's drawing, may
  /// have changed it); the chosen brush stays when it is still there.
  Future<void> reloadLibrary() async {
    final chosen = brush.id;
    await _loadLibrary();
    brush = brushes.where((b) => b.id == chosen).firstOrNull ?? brush;
    _notify();
  }

  SharedPreferences? get preferences => _preferences;

  /// Set when the saved library could not be read; it is then never saved.
  String? libraryError;
  bool get libraryLocked => libraryError != null;

  void setPanel(EditorPanel? next) {
    if (documentTransition) return;
    lastQuickShape = null;
    cancelAdjustment();
    cancelLiquify();
    cancelClone();
    cancelTransform();
    cancelSelectionDraft();
    finishStroke();
    panel = panel == next ? null : next;
    if (panel != EditorPanel.colors) _choosingColor = false;
    fillSession = null;
    _notify();
  }

  void selectTool(StudioTool next) {
    if (documentTransition) return;
    if (next == StudioTool.transform) {
      beginTransform();
      return;
    }
    cancelAdjustment();
    cancelLiquify();
    cancelClone();
    cancelTransform();
    cancelSelectionDraft();
    finishStroke();
    cancelPick();
    lastQuickShape = null;
    if (next == StudioTool.eyedropper && tool != StudioTool.eyedropper) {
      _toolBeforePick = tool == StudioTool.eraser || tool == StudioTool.smudge
          ? tool
          : StudioTool.brush;
    }
    fillSession = null;
    tool = next;
    _notify();
  }

  /// The app's pressure curve: pen pressure in (x) to pressure used (y).
  List<Offset> pressureCurve = Adjustment.straight;
  Uint8List _pressureTable = curveTable(Adjustment.straight);

  void _setCurve(List<Offset> points) {
    pressureCurve = List.unmodifiable(points);
    _pressureTable = curveTable(points);
  }

  void setPressureCurve(List<Offset> points) {
    _setCurve(points);
    _preferences?.setString(
      'pressure.curve',
      jsonEncode([
        for (final p in points) [p.dx, p.dy],
      ]),
    );
    _notify();
  }

  /// [pressure] (0–1) through the pressure curve.
  double mapPressure(double pressure) =>
      _pressureTable[(pressure.clamp(0.0, 1.0) * 255).round()] / 255;

  /// QuickMenu: its profiles, the one in use, how it opens and, while it
  /// is open, its middle (in global coordinates).
  List<QuickMenuProfile> quickMenuProfiles = const [QuickMenuProfile.initial];
  String quickMenuActive = QuickMenuProfile.initial.id;
  QuickMenuTrigger quickMenuTrigger = QuickMenuTrigger.touchHold;
  Offset? quickMenuAt;

  /// The button a held finger is over.
  int? quickMenuHover;

  QuickMenuProfile get quickMenu =>
      quickMenuProfiles.where((p) => p.id == quickMenuActive).firstOrNull ??
      quickMenuProfiles.first;

  void openQuickMenu(Offset at) {
    quickMenuAt = at;
    quickMenuHover = null;
    _notify();
  }

  void closeQuickMenu() {
    if (quickMenuAt == null) return;
    quickMenuAt = null;
    quickMenuHover = null;
    _notify();
  }

  void hoverQuickMenu(Offset point) {
    final at = quickMenuAt;
    if (at == null) return;
    final slot = quickMenuSlotAt(at, point);
    if (slot == quickMenuHover) return;
    quickMenuHover = slot;
    _notify();
  }

  void setQuickMenuTrigger(QuickMenuTrigger trigger) {
    quickMenuTrigger = trigger;
    if (trigger == QuickMenuTrigger.touchHold && eyedropperHold) {
      eyedropperHold = false;
      _preferences?.setBool('gesture.eyedropperHold', false);
    }
    _preferences?.setString('quickmenu.trigger', trigger.name);
    _notify();
  }

  void _keepQuickMenus(List<QuickMenuProfile> profiles, String active) {
    quickMenuProfiles = List.unmodifiable(profiles);
    quickMenuActive = active;
    _preferences?.setString(
      'quickmenu.profiles',
      jsonEncode([for (final p in profiles) p.toJson()]),
    );
    _preferences?.setString('quickmenu.active', active);
    _notify();
  }

  /// Button [slot] of profile [profileId] (the one in use by default)
  /// does [action].
  void assignQuickAction(int slot, QuickAction action, {String? profileId}) {
    final id = profileId ?? quickMenu.id;
    _keepQuickMenus([
      for (final p in quickMenuProfiles)
        p.id == id ? p.copyWith(slots: [...p.slots]..[slot] = action) : p,
    ], quickMenuActive);
  }

  void selectQuickMenu(String id) {
    if (!quickMenuProfiles.any((p) => p.id == id)) return;
    _keepQuickMenus(quickMenuProfiles, id);
  }

  /// The next profile, round.
  void nextQuickMenu() {
    final i = quickMenuProfiles.indexWhere((p) => p.id == quickMenu.id);
    selectQuickMenu(quickMenuProfiles[(i + 1) % quickMenuProfiles.length].id);
  }

  /// A copy of the profile in use, named [name], becomes the one in use.
  void addQuickMenu(String name) {
    final copy = QuickMenuProfile(
      id: newId(),
      name: name,
      slots: quickMenu.slots,
    );
    _keepQuickMenus([...quickMenuProfiles, copy], copy.id);
  }

  void renameQuickMenu(String id, String name) => _keepQuickMenus([
    for (final p in quickMenuProfiles) p.id == id ? p.copyWith(name: name) : p,
  ], quickMenuActive);

  /// The last profile stays.
  void deleteQuickMenu(String id) {
    if (quickMenuProfiles.length < 2) return;
    final rest = [...quickMenuProfiles.where((p) => p.id != id)];
    _keepQuickMenus(
      rest,
      quickMenuActive == id ? rest.first.id : quickMenuActive,
    );
  }

  /// The reference window: open or not, its picture (null shows the
  /// canvas itself) and where it sits in the workspace.
  bool referenceOpen = false;
  ui.Image? referenceImage;
  Uint8List? _referencePixels;
  Rect referenceRect = const Rect.fromLTWH(64, 72, 300, 230);

  void toggleReference([bool? open]) {
    referenceOpen = open ?? !referenceOpen;
    _notify();
  }

  void placeReference(Rect rect) {
    referenceRect = rect;
    _notify();
  }

  /// Shows the image [bytes] (PNG, JPEG…) in the reference window, at most
  /// 2048 pixels a side.
  Future<void> setReferenceImage(Uint8List bytes) async {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    probe.dispose();
    final fit = math.min(1.0, 2048 / math.max(first.width, first.height));
    final image = fit < 1
        ? await () async {
            final codec = await ui.instantiateImageCodec(
              bytes,
              targetWidth: (first.width * fit).round(),
              targetHeight: (first.height * fit).round(),
            );
            first.dispose();
            final frame = (await codec.getNextFrame()).image;
            codec.dispose();
            return frame;
          }()
        : first;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (disposed || data == null) {
      image.dispose();
      return;
    }
    referenceImage?.dispose();
    referenceImage = image;
    _referencePixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    referenceOpen = true;
    _notify();
  }

  /// Back to showing the canvas.
  void clearReferenceImage() {
    referenceImage?.dispose();
    referenceImage = null;
    _referencePixels = null;
    _notify();
  }

  /// The eyedropper in the reference window: [point] in the picture's (or
  /// the canvas's) pixels.
  void pickFromReference(Offset point) {
    final image = referenceImage, pixels = _referencePixels;
    if (image != null && pixels != null) {
      selectColor(
        sampleOpaqueColor(pixels, CanvasSize(image.width, image.height), point),
      );
      _choosingColor = false;
      return;
    }
    if (beginPick(point)) finishPick();
  }

  /// Page Assist on or off for this drawing (a canvas setting, not an
  /// undo step).
  void setPageAssist(bool on) {
    if (documentTransition || document.pageAssist == on) return;
    document = document.copyWith(
      pageAssist: on,
      animation: on ? document.animation?.copyWith(enabled: false) : null,
    );
    _changed();
  }

  /// Animation Assist on or off (its settings are kept either way).
  void setAnimationAssist(bool on) {
    if (documentTransition || document.animating == on) return;
    document = document.copyWith(
      animation: (document.animation ?? const AnimationSettings()).copyWith(
        enabled: on,
      ),
      pageAssist: on ? false : null,
    );
    _changed();
  }

  /// Animation Assist playback: the frame on screen while playing.
  final ValueNotifier<int?> playback = ValueNotifier(null);
  Timer? _playTimer;
  int _playTick = 0, _playFps = 0;

  bool get playing => playback.value != null;

  /// Plays from the frame shown, at the drawing's fps and in its mode.
  void play() {
    if (playing) return;
    final doc = document;
    final order =
        doc.animation?.playOrder([
          for (final p in doc.pages) ArtDocument.frameId(p),
        ]) ??
        const <int>[];
    _playTick = math.max(0, order.indexOf(doc.currentPage));
    _playFps = 0;
    _advancePlayback();
  }

  void _advancePlayback() {
    final doc = document, settings = doc.animation;
    final order = doc.animating && settings != null && !documentTransition
        ? settings.playOrder([
            for (final p in doc.pages) ArtDocument.frameId(p),
          ])
        : const <int>[];
    if (order.isEmpty ||
        (settings!.mode == PlaybackMode.oneShot && _playTick >= order.length)) {
      stopPlayback();
      return;
    }
    if (_playFps != settings.fps) {
      _playTimer?.cancel();
      _playFps = settings.fps;
      _playTimer = Timer.periodic(
        Duration(microseconds: 1000000 ~/ settings.fps),
        (_) => _advancePlayback(),
      );
    }
    playback.value = order[_playTick++ % order.length];
  }

  /// Whether anything was playing.
  bool stopPlayback() {
    _playTimer?.cancel();
    _playTimer = null;
    if (playback.value == null) return false;
    playback.value = null;
    return true;
  }

  /// Playback and onion skin settings: preferences of the drawing, not
  /// undo steps.
  void setAnimation(AnimationSettings settings) {
    if (documentTransition) return;
    document = document.copyWith(animation: settings);
    _changed();
  }

  /// A frame's own options (hold, background, foreground): undo steps.
  void setFrameOptions(AnimationSettings settings) {
    if (documentTransition) return;
    _commit(document.copyWith(animation: settings));
  }

  /// A blank frame right after the current one.
  void addFrame(String name) {
    if (_defer(() => addFrame(name))) return;
    if (document.layers.length >= maxLayers) return;
    final pages = document.pages;
    final current = document.currentPage;
    final after = current < 0
        ? document.layers.length
        : document.layers.indexOf(pages[current].last) + 1;
    final layer = ArtLayer(id: newId(), name: name);
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(after),
          layer,
          ...document.layers.skip(after),
        ],
        activeLayerId: layer.id,
      ),
    );
  }

  /// A copy of [page]'s layers (and its group, when it is one), named
  /// [name].
  (List<ArtLayer>, LayerGroup?) _copyPage(List<ArtLayer> page, String name) {
    ArtLayer copy(ArtLayer l, {String? group, String? as}) => ArtLayer(
      id: newId(),
      name: as ?? l.name,
      strokes: l.strokes,
      visible: l.visible,
      opacity: l.opacity,
      raster: l.raster,
      legacyRaster: l.legacyRaster,
      blend: l.blend,
      mask: l.mask,
      clipping: l.clipping,
      alphaLock: l.alphaLock,
      text: l.text,
      private: l.private,
      group: group,
    );
    final group = page.first.group;
    if (group == null) return ([copy(page.single, as: name)], null);
    final source = document.groups.firstWhere((g) => g.id == group);
    final twin = LayerGroup(
      id: newId(),
      name: name,
      visible: source.visible,
      opacity: source.opacity,
      blend: source.blend,
    );
    return ([for (final l in page) copy(l, group: twin.id)], twin);
  }

  /// Frame [index] copied right after it (a group with its layers).
  void duplicateFrame(int index, String name) =>
      duplicateFrames({index}, (_) => name);

  /// Frames [indices] copied, in order, right after the last of them; one
  /// undo step. [name] names the n-th new frame (from 1).
  void duplicateFrames(Set<int> indices, String Function(int n) name) {
    if (_defer(() => duplicateFrames(indices, name))) return;
    final pages = document.pages;
    final chosen = [...indices.where((i) => i >= 0 && i < pages.length)]
      ..sort();
    if (chosen.isEmpty) return;
    final adding = chosen.fold(0, (n, i) => n + pages[i].length);
    if (document.layers.length + adding > maxLayers) return;
    final copies = <ArtLayer>[], groups = <LayerGroup>[];
    final holds = {...?document.animation?.holds};
    for (final (n, i) in chosen.indexed) {
      final (layers, group) = _copyPage(pages[i], name(pages.length + n + 1));
      copies.addAll(layers);
      if (group != null) groups.add(group);
      final hold = holds[ArtDocument.frameId(pages[i])];
      if (hold != null) holds[ArtDocument.frameId(layers)] = hold;
    }
    final after = document.layers.indexOf(pages[chosen.last].last) + 1;
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(after),
          ...copies,
          ...document.layers.skip(after),
        ],
        groups: [...document.groups, ...groups],
        activeLayerId: copies.last.id,
        animation: document.animation?.copyWith(holds: holds),
      ),
    );
  }

  /// A held frame [index] in two (Dreams' Split): the first half of its
  /// time stays, a copy right after it takes the rest. One undo step.
  void splitFrame(int index, String name) {
    if (_defer(() => splitFrame(index, name))) return;
    final pages = document.pages, settings = document.animation;
    if (settings == null || index < 0 || index >= pages.length) return;
    final page = pages[index], id = ArtDocument.frameId(page);
    final total = settings.hold(id) + 1;
    if (total < 2 || document.layers.length + page.length > maxLayers) return;
    final first = (total + 1) ~/ 2;
    final (layers, group) = _copyPage(page, name);
    final after = document.layers.indexOf(page.last) + 1;
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(after),
          ...layers,
          ...document.layers.skip(after),
        ],
        groups: [...document.groups, ?group],
        activeLayerId: layers.last.id,
        animation: settings.copyWith(
          holds: {
            ...settings.holds,
            id: first - 1,
            ArtDocument.frameId(layers): total - first - 1,
          },
        ),
      ),
    );
  }

  /// Frames [indices] emptied, kept in place with their holds; one undo
  /// step. Locked layers stay as they are.
  void clearFrames(Set<int> indices) {
    if (_defer(() => clearFrames(indices))) return;
    final pages = document.pages;
    final ids = {
      for (final i in indices)
        if (i >= 0 && i < pages.length)
          for (final l in pages[i])
            if (!l.locked) l.id,
    };
    if (ids.isEmpty) return;
    _commit(
      document.copyWith(
        layers: [
          for (final l in document.layers)
            ids.contains(l.id)
                ? l.copyWith(
                    clearRaster: true,
                    clearLegacyRaster: true,
                    clearText: true,
                    strokes: const [],
                  )
                : l,
        ],
      ),
    );
  }

  /// Frames [indices] removed with their holds (one frame always stays);
  /// one undo step.
  void deleteFrames(Set<int> indices) {
    if (_defer(() => deleteFrames(indices))) return;
    final pages = document.pages, settings = document.animation;
    final gone = {
      for (final i in indices)
        if (i >= 0 && i < pages.length) i,
    };
    if (gone.isEmpty || gone.length >= pages.length) return;
    final kept = [
      for (final (i, p) in pages.indexed)
        if (!gone.contains(i)) p,
    ];
    final goneIds = {for (final i in gone) ArtDocument.frameId(pages[i])};
    final layers = [for (final p in kept) ...p];
    final first = gone.reduce(math.min);
    final active = kept[math.min(first, kept.length - 1)].last.id;
    _commit(
      document.copyWith(
        layers: layers,
        groups: [
          for (final g in document.groups)
            if (layers.any((l) => l.group == g.id)) g,
        ],
        activeLayerId: layers.any((l) => l.id == document.activeLayerId)
            ? document.activeLayerId
            : active,
        animation: settings?.copyWith(
          holds: {
            for (final MapEntry(:key, :value) in settings.holds.entries)
              if (!goneIds.contains(key)) key: value,
          },
          clearBackground: goneIds.contains(settings.background),
          clearForeground: goneIds.contains(settings.foreground),
        ),
      ),
    );
  }

  /// Frames [indices] in reverse order among themselves (Dreams' Flip
  /// frames, for back-and-forth loops); one undo step.
  void reverseFrames(Set<int> indices) {
    if (_defer(() => reverseFrames(indices))) return;
    final pages = document.pages;
    final chosen = [...indices.where((i) => i >= 0 && i < pages.length)]
      ..sort();
    if (chosen.length < 2) return;
    final next = [...pages];
    for (final (k, i) in chosen.indexed) {
      next[i] = pages[chosen[chosen.length - 1 - k]];
    }
    _commit(document.copyWith(layers: [for (final p in next) ...p]));
  }

  /// Frames [indices] each on screen for [ticks] frames (2 = on twos);
  /// one undo step.
  void setFrameDurations(Set<int> indices, int ticks) {
    final pages = document.pages, settings = document.animation;
    if (settings == null) return;
    final hold = (ticks - 1).clamp(0, AnimationSettings.maxHold);
    setFrameOptions(
      settings.copyWith(
        holds: {
          ...settings.holds,
          for (final i in indices)
            if (i >= 0 && i < pages.length) ArtDocument.frameId(pages[i]): hold,
        },
      ),
    );
  }

  /// The Flipbook shrunk to a small strip floating over the canvas
  /// (Dreams' mini Flipbook), and where it floats (top left, workspace
  /// pixels).
  bool miniFlipbook = false;
  Offset miniFlipbookAt = const Offset(24, 96);

  void setMiniFlipbook(bool on, {Offset? at}) {
    miniFlipbook = on;
    if (at != null) miniFlipbookAt = at;
    _preferences?.setBool('flipbook.mini', on);
    _notify();
  }

  void moveMiniFlipbook(Offset at) {
    miniFlipbookAt = at;
    _notify();
  }

  /// Frame [index] removed (one frame always stays).
  void deleteFrame(int index) {
    final pages = document.pages;
    if (index < 0 || index >= pages.length || pages.length < 2) return;
    final page = pages[index];
    final group = page.first.group;
    group == null ? deleteLayer(page.single.id) : deleteGroup(group);
  }

  /// Relabels the drawing's colour space (its numbers stay as they are).
  void setColorProfile(ColorProfile profile) {
    if (documentTransition || document.colorProfile == profile) return;
    _commit(document.copyWith(colorProfile: profile));
  }

  ArtDocument? _shownFor, _shown;
  int? _shownPage;

  /// What the canvas draws: the drawing, or with Page Assist only the page
  /// holding the active layer.
  ArtDocument get shownDocument {
    final doc = document;
    if (!doc.pageAssist && !doc.animating) return doc;
    final page = doc.animating
        ? playback.value ?? doc.currentPage
        : doc.currentPage;
    if (identical(_shownFor, doc) && _shownPage == page) return _shown!;
    _shownFor = doc;
    _shownPage = page;
    if (page < 0) return _shown = doc;
    if (doc.pageAssist) return _shown = doc.pageOnly(page);
    return _shown = doc.animationFrame(page);
  }

  ArtDocument? _onionFor;
  OnionView? _onion;

  /// Animation Assist with onion skins (or a see-through frame): what the
  /// canvas draws, bottom to top. Null when the plain [shownDocument] does.
  OnionView? get onionView {
    final doc = document, settings = doc.animation;
    if (!doc.animating || settings == null || playing) return null;
    if (settings.onionFrames == 0 && !settings.blendPrimary) return null;
    if (identical(_onionFor, doc)) return _onion;
    _onionFor = doc;
    final pages = doc.pages, current = doc.currentPage;
    if (current < 0) return _onion = null;
    final background = settings.background == ArtDocument.frameId(pages.first)
        ? 0
        : null;
    final foreground =
        pages.length > 1 &&
            settings.foreground == ArtDocument.frameId(pages.last)
        ? pages.length - 1
        : null;
    ArtDocument only(List<ArtLayer> layers) => doc.copyWith(
      layers: layers,
      activeLayerId: layers.any((l) => l.id == doc.activeLayerId)
          ? doc.activeLayerId
          : layers.last.id,
      backgroundHidden: true,
    );
    final n = settings.onionFrames;
    final onions = <(ArtDocument, int, double)>[];
    // Farthest first, so nearer frames lie over them.
    for (var k = n; k >= 1; k--) {
      final fade = settings.onionOpacity * (1 - (k - 1) / (n + 1));
      for (final (index, tint) in [
        (current - k, settings.onionBehind),
        (current + k, settings.onionAhead),
      ]) {
        if (index < 0 || index >= pages.length) continue;
        if (index == background || index == foreground) continue;
        onions.add((only(pages[index]), tint, fade));
      }
    }
    return _onion = OnionView(
      under: background != null && current != background
          ? only(pages[background])
          : null,
      onions: onions,
      top: only([
        ...pages[current],
        if (foreground != null && current != foreground) ...pages[foreground],
      ]),
      blendPrimary: settings.blendPrimary,
    );
  }

  /// Animation Assist: frame [page] as it plays.
  ArtDocument animationFrame(int page) => document.animationFrame(page);

  /// Page Assist: shows page [index] (its top layer becomes the active one).
  void goToPage(int index) {
    final pages = document.pages;
    if (index < 0 || index >= pages.length) return;
    selectLayer(pages[index].last.id);
    if (document.animating) onFrameShown?.call(index);
  }

  /// Told when a frame is shown by hand (a movie's Flipbook previews its
  /// sound there).
  void Function(int frame)? onFrameShown;

  /// The user's own new-canvas sizes.
  List<CanvasPreset> canvasPresets = const [];

  void _keepCanvasPresets(List<CanvasPreset> next) {
    canvasPresets = List.unmodifiable(next);
    _preferences?.setString(
      'canvas.presets',
      jsonEncode([for (final p in next) p.toJson()]),
    );
    _notify();
  }

  /// Adds [preset], or replaces the one with its id.
  void saveCanvasPreset(CanvasPreset preset) => _keepCanvasPresets([
    for (final p in canvasPresets) p.id == preset.id ? preset : p,
    if (!canvasPresets.any((p) => p.id == preset.id)) preset,
  ]);

  void deleteCanvasPreset(String id) =>
      _keepCanvasPresets([...canvasPresets.where((p) => p.id != id)]);

  /// The brush's outline follows the pen or mouse over the canvas.
  bool brushCursor = true;
  Offset? cursor;

  void setBrushCursor(bool on) {
    brushCursor = on;
    _preferences?.setBool('brush.cursor', on);
    if (!on) cursor = null;
    inkChanges.notifyListeners();
    _notify();
  }

  void setCursor(Offset? at) {
    if (at == cursor || (!brushCursor && at != null)) return;
    cursor = at;
    inkChanges.notifyListeners();
  }

  /// Each brush's last size and opacity, restored when it is picked again.
  Map<String, (double, double)> _brushMemory = {};

  /// Brushes picked lately, most recent first (their ids).
  List<String> recentBrushes = const [];
  static const maxRecentBrushes = 4;

  void selectBrush(BrushPreset preset) {
    if (documentTransition) return;
    cancelTransform();
    cancelSelectionDraft();
    finishStroke();
    recentBrushes = [
      preset.id,
      ...recentBrushes.where((id) => id != preset.id),
    ].take(maxRecentBrushes).toList();
    _preferences?.setStringList('brushes.recent', recentBrushes);
    // Size and opacity stay with the brush they were set on.
    _brushMemory[brush.id] = (size, opacity);
    final remembered = _brushMemory[preset.id];
    _preferences?.setString(
      'brushes.memory',
      jsonEncode({
        for (final MapEntry(:key, :value) in _brushMemory.entries)
          key: [value.$1, value.$2],
      }),
    );
    brush = preset;
    size = (remembered?.$1 ?? preset.size).clamp(1, 128);
    if (remembered != null) opacity = remembered.$2.clamp(.01, 1);
    tool = StudioTool.brush;
    if (preset.isNative) {
      unawaited(
        _native
            .worker(document.dimensions)
            .then((_) {}, onError: (Object _) {}),
      );
    }
    _notify();
  }

  void setSize(double value) {
    size = value.clamp(1, 128);
    _notify();
  }

  void setOpacity(double value) {
    opacity = value.clamp(.01, 1);
    _notify();
  }

  void selectColor(int value) {
    if (value == color) return;
    // Dragging through the picker is one choice: the colour before it
    // stays the previous one until painting starts or the panel closes.
    if (!_choosingColor) {
      previousColor = color;
      _choosingColor = true;
    }
    color = value;
    if (textEditing != null) setText((t) => t.copyWith(color: value));
    if (adjustment?.adjustment.kind == AdjustmentKind.recolor) {
      setAdjustment(adjustment!.adjustment.withColor(value));
    }
    _notify();
  }

  /// The colour before the current one (Procreate's hold on the swatch, X).
  int? previousColor;
  bool _choosingColor = false;

  void swapColor() {
    final previous = previousColor;
    if (previous == null) return;
    previousColor = color;
    color = previous;
    _choosingColor = false;
    if (textEditing != null) setText((t) => t.copyWith(color: previous));
    _notify();
  }

  /// Colours strokes were drawn with, most recent first.
  List<int> recentColors = const [];
  static const maxRecentColors = 12;

  void _rememberColor() {
    if (recentColors.isNotEmpty && recentColors.first == color) return;
    recentColors = [
      color,
      ...recentColors.where((c) => c != color),
    ].take(maxRecentColors).toList();
    _preferences?.setString('colors.recent', jsonEncode(recentColors));
  }

  bool beginStroke(
    InkPoint point, {
    required bool simulatePressure,
    double tiltX = 0,
    double tiltY = 0,
    Duration? time,
    StudioTool? as,
  }) {
    final strokeTool = as ?? tool;
    if (adjustment != null) {
      return _beginAdjustmentStroke(point, time, simulatePressure);
    }
    if (clone != null) return _beginCloneStroke(point, time, simulatePressure);
    if (!initialized ||
        disposed ||
        documentTransition ||
        ![
          StudioTool.brush,
          StudioTool.smudge,
          StudioTool.eraser,
        ].contains(strokeTool) ||
        document.activeLayer.locked ||
        !document.activeLayer.visible) {
      return false;
    }
    // Text stays text: painting on it asks to rasterise it first.
    if (document.activeLayer.text != null) {
      textLayerTouched.value++;
      return false;
    }
    cancelStroke();
    _choosingColor = false;
    if (strokeTool == StudioTool.brush) _rememberColor();
    if (!_replaying) {
      lastQuickShape = null;
      _shapeInput
        ..clear()
        ..add(point);
      // Drawing Assist: this stroke follows a guide line from here.
      _assistOrigin =
          document.activeLayer.assisted && guide.kind != GuideKind.none
          ? Offset(point.x, point.y)
          : null;
      _assistDirection = null;
    }
    final settings = smoothing;
    final stabilizer = settings.active && !_replaying
        ? StrokeStabilizer(settings)
        : null;
    _stabilizer = stabilizer;
    _lastTilt = (tiltX, tiltY);
    stabilizer?.start(point, time);
    final smudging = strokeTool == StudioTool.smudge;
    if (brush.isNative || smudging) {
      final session =
          NativeStrokeSession(
            documentId: document.id,
            layerId: document.activeLayerId,
            dimensions: document.dimensions,
            preset: strokeTool == StudioTool.smudge && !brush.isNative
                ? initialBrushes.firstWhere((b) => b.id == 'stamp-gouache')
                : brush,
            color: color,
            size: size,
            opacity: opacity,
            eraser: strokeTool == StudioTool.eraser,
            smudge: smudging,
            alphaLock: document.activeLayer.alphaLock,
            clip: selection,
            symmetry: symmetry,
            symmetryCentre: guide.symmetryCentreOn(document.dimensions.size),
            symmetryRotational: guide.rotational,
            onPreview: () {
              if (!disposed) inkChanges.notifyListeners();
            },
          )..add(
            point.x,
            point.y,
            point.pressure,
            tiltX: tiltX,
            tiltY: tiltY,
            time: time,
          );
      _drawingNative = session;
      _previews.add(session);
      // Commits and edits issued before this stroke, in case it cannot simply
      // continue from the worker surface.
      final before = _queueTail;
      final editsBefore = _edits;
      _workerLane(() => _startNative(session, before, editsBefore));
      _notify();
      return true;
    }
    _points.clear();
    _points.add(point);
    _pendingLayerId = document.activeLayerId;
    _pending = InkStroke(
      id: newId(),
      points: _points,
      color: color,
      size: size,
      opacity: opacity,
      eraser: strokeTool == StudioTool.eraser,
      simulatePressure: simulatePressure,
      smoothing: brush.smoothing,
      thinning: brush.thinning,
      clip: selection,
      atop: document.activeLayer.alphaLock && strokeTool != StudioTool.eraser,
    );
    inkChanges.notifyListeners();
    return true;
  }

  void appendPoint(
    InkPoint point, {
    double tiltX = 0,
    double tiltY = 0,
    Duration? time,
  }) {
    point = _assisted(point);
    if (adjustment?.drawing != null) {
      _appendAdjustmentPoint(_stabilizer?.add(point, time) ?? point);
      return;
    }
    if (clone?.drawing case final drawing?) {
      final next = _stabilizer?.add(point, time) ?? point;
      if (drawing.points.length < 20000) {
        clone!.drawing = _withPoints(drawing, [...drawing.points, next]);
        inkChanges.notifyListeners();
      }
      return;
    }
    if (quickShape case final held?) {
      held.to = Offset(point.x, point.y);
      inkChanges.notifyListeners();
      return;
    }
    if (_drawingNative == null && _pending == null) return;
    if (!_replaying && _shapeInput.length < 20000) _shapeInput.add(point);
    _lastTilt = (tiltX, tiltY);
    _append(
      _stabilizer?.add(point, time) ?? point,
      tiltX: tiltX,
      tiltY: tiltY,
      time: time,
    );
  }

  void _append(
    InkPoint point, {
    required double tiltX,
    required double tiltY,
    Duration? time,
  }) {
    final native = _drawingNative;
    if (native != null) {
      native.add(
        point.x,
        point.y,
        point.pressure,
        tiltX: tiltX,
        tiltY: tiltY,
        time: time,
      );
      return;
    }
    final pending = _pending;
    if (pending == null || _points.length >= 20000) return;
    _points.add(point);
    _pending = InkStroke(
      id: pending.id,
      points: _points,
      color: pending.color,
      size: pending.size,
      opacity: pending.opacity,
      eraser: pending.eraser,
      simulatePressure: pending.simulatePressure,
      smoothing: pending.smoothing,
      thinning: pending.thinning,
      clip: pending.clip,
      atop: pending.atop,
    );
    inkChanges.notifyListeners();
  }

  /// Ends the stroke being drawn. A native stroke is committed asynchronously,
  /// in order with later document edits; await [settleStroke] to observe it.
  void finishStroke() {
    if (adjustment?.drawing != null) {
      _finishAdjustmentStroke();
      return;
    }
    if (clone case final session? when session.drawing != null) {
      final tail = _stabilizer?.finish() ?? const <InkPoint>[];
      _stabilizer = null;
      if (tail.isNotEmpty) {
        session.drawing = _withPoints(session.drawing!, [
          ...session.drawing!.points,
          ...tail,
        ]);
      }
      session.end();
      inkChanges.notifyListeners();
      _notify();
      return;
    }
    if (quickShape case final held?) {
      quickShape = null;
      final shape = held.current;
      final entry = LastQuickShape(shape, held.pressure);
      _drawShape(shape, held.pressure);
      lastQuickShape = entry;
      unawaited(
        settleStroke().then((_) {
          if (identical(lastQuickShape, entry)) {
            entry.revision = document.revision;
            _notify();
          }
        }),
      );
      return;
    }
    final stabilizer = _stabilizer;
    _stabilizer = null;
    if (stabilizer != null) {
      final start = stabilizer.lastTime;
      final tail = stabilizer.finish();
      for (var i = 0; i < tail.length; i++) {
        _append(
          tail[i],
          tiltX: _lastTilt.$1,
          tiltY: _lastTilt.$2,
          time: start == null
              ? null
              : start + StrokeStabilizer.catchUpStep * (i + 1),
        );
      }
    }
    final native = _drawingNative;
    if (native != null) {
      _drawingNative = null;
      native.closeInput();
      final result = Completer<NativeCommit?>();
      _workerLane(() async {
        try {
          // The worker merges while the lane moves on to the next stroke.
          final pending = await native.finish();
          if (pending == null || native.baseFuture == null) {
            _native.invalidate();
            result.complete(null);
          } else {
            _native.afterStroke(native.layerId, native.committed.future);
            result.complete(pending);
          }
        } catch (error, stack) {
          _native.invalidate();
          result.completeError(error, stack);
        }
      });
      _enqueue(() => _commitNative(native, result.future), edit: false);
      return;
    }
    final pending = _pending;
    if (pending == null) return;
    final layerId = _pendingLayerId ?? document.activeLayerId;
    final strokes = pendingStrokes;
    _pending = null;
    _pendingLayerId = null;
    _points.clear();
    if (_queued > 0 && !_inQueue) {
      _enqueue(() async => _commitStroke(strokes, layerId));
    } else {
      _commitStroke(strokes, layerId);
    }
  }

  /// One undo step, however many symmetric copies.
  void _commitStroke(List<InkStroke> strokes, String layerId) {
    if (!document.layers.any((l) => l.id == layerId)) return;
    _commit(
      document.copyWith(
        layers: document.layers
            .map(
              (l) => l.id == layerId
                  ? l.copyWith(strokes: [...l.strokes, ...strokes])
                  : l,
            )
            .toList(),
      ),
    );
  }

  void cancelStroke() {
    _stabilizer = null;
    quickShape = null;
    clone?.drawing = null;
    if (adjustment case final session? when session.drawing != null) {
      session.drawing = null;
      session.undo();
    }
    final native = _drawingNative;
    if (native != null) {
      _drawingNative = null;
      native.cancel();
      _previews.remove(native);
      // Keep the worker exclusive until this stroke's in-flight calls drain;
      // its partial dabs make the surface unknown.
      _workerLane(() async {
        await native.settled;
        _native.invalidate();
      });
    }
    _pending = null;
    _pendingLayerId = null;
    _points.clear();
    if (!disposed) inkChanges.notifyListeners();
  }

  /// Finishes the current stroke and waits for every queued native step.
  Future<void> settleStroke() async {
    finishStroke();
    while (_busy && !disposed) {
      await Future.wait([_queueTail, _workerTail]);
    }
  }

  /// [edit]: anything but a native commit. A stroke that starts while edits
  /// are queued waits for them instead of continuing from the worker surface.
  void _enqueue(Future<void> Function() operation, {bool edit = true}) {
    _queued++;
    if (edit) _edits++;
    _queueTail = _queueTail
        .then((_) async {
          if (!disposed) await operation();
        })
        .catchError((Object error) {
          if (!disposed) _strokeFailures.add(error);
        })
        .whenComplete(() {
          _queued--;
          if (edit) _edits--;
          if (!_busy) _notify();
        });
  }

  void _workerLane(Future<void> Function() operation) {
    _workerQueued++;
    _workerTail = _workerTail
        .then((_) async {
          if (!disposed) await operation();
        })
        .catchError((Object error) {
          if (!disposed) _strokeFailures.add(error);
        })
        .whenComplete(() {
          _workerQueued--;
          if (!_busy) _notify();
        });
  }

  /// Runs [retry] after queued native work so edits keep the user's order.
  bool _defer(void Function() retry) {
    if (_inQueue) return false;
    finishStroke();
    if (_queued == 0) return false;
    _enqueue(() async {
      _inQueue = true;
      try {
        retry();
      } finally {
        _inQueue = false;
      }
    });
    return true;
  }

  Future<void> _startNative(
    NativeStrokeSession session,
    Future<void> before,
    int editsBefore,
  ) async {
    if (session.cancelled || disposed) return;
    ArtLayer? target() {
      if (document.id != session.documentId) return null;
      final layer = document.layers.where((l) => l.id == session.layerId);
      return layer.isEmpty ? null : layer.single;
    }

    try {
      final worker = await _native.worker(session.dimensions);
      if (session.cancelled || disposed) return;
      final layer = target();
      if (editsBefore == 0 && layer != null && _native.continues(layer)) {
        // The surface already holds this layer, possibly with an earlier
        // stroke still committing: no reload, no wait for that commit.
        await session.start(worker, _native, reloaded: false);
      } else {
        await before;
        if (session.cancelled || disposed) return;
        final settled = target();
        if (settled == null) {
          session.cancel();
          _previews.remove(session);
          return;
        }
        await _native.load(
          worker,
          settled,
          TileGrid(session.dimensions),
          rasters.images,
        );
        if (session.cancelled || disposed) return;
        await session.start(worker, _native, reloaded: true);
      }
      if (!session.cancelled && !disposed) inkChanges.notifyListeners();
    } catch (_) {
      if (identical(_drawingNative, session)) _drawingNative = null;
      session.cancel();
      _previews.remove(session);
      _native.invalidate();
      rethrow;
    }
  }

  Future<void> _commitNative(
    NativeStrokeSession session,
    Future<NativeCommit?> result,
  ) async {
    final total = Stopwatch()..start();
    List<ui.Image?>? owned;
    var reported = false;
    NativeLayerContent? applied;
    try {
      final output = await result;
      if (output == null || disposed) return;
      final base = await session.baseFuture!;
      if (base == null) {
        throw StateError('The previous stroke was not applied');
      }
      if (!output.changed) {
        applied = base;
        return;
      }
      final mergeTime = total.elapsed;
      final updates = await _tileImages(output.updates);
      owned = updates.values.map((u) => u.$2).toList();
      if (disposed) return;
      final current = document;
      final target = current.layers.where((l) => l.id == session.layerId);
      if (documentTransition ||
          current.id != session.documentId ||
          target.isEmpty ||
          !base.matches(target.single)) {
        throw StateError('The drawing changed before the stroke was applied');
      }
      // A full write replaces every tile; otherwise unchanged tiles are kept
      // (and shared with history).
      final tiles = {if (!output.full) ...?base.raster?.tiles};
      for (final MapEntry(:key, :value) in updates.entries) {
        final asset = value.$1;
        if (asset == null) {
          tiles.remove(key);
        } else {
          tiles[key] = asset;
        }
      }
      final raster = tiles.isEmpty ? null : TiledRaster(current.grid, tiles);
      final next = current.copyWith(
        layers: current.layers
            .map(
              (l) => l.id == session.layerId
                  ? l.copyWith(
                      raster: raster,
                      clearRaster: raster == null,
                      clearLegacyRaster: true,

                      strokes: const [],
                    )
                  : l,
            )
            .toList(),
      );
      checkRasterBudget(next.dimensions, documentRasters(next));
      final committed = next.layers.firstWhere((l) => l.id == session.layerId);
      for (final (asset, image, bounds) in updates.values) {
        if (asset != null) rasters.adopt(asset, image!, bounds);
      }
      owned = null;
      applied = NativeLayerContent.of(committed);
      // The document and the preview change in the same frame.
      _clearNativePreview(session);
      _commit(next);
      lastNativeStats = NativeStrokeStats(
        start: session.startCost.elapsed,
        previewFrames: session.previewFrames,
        previewBytes: session.previewBytes,
        previewTime: session.previewTime,
        merge: mergeTime,
        mergeOnly: output.mergeTime,
        commit: total.elapsed,
        dirty: output.rect,
        loadBytes: session.loadBytes,
        latencyUs: List.of(session.latencyUs),
      );
      PenProbe.instance.nativeResult(lastNativeStats!.toJson());
      reported = true;
    } catch (error) {
      applied = null;
      PenProbe.instance.nativeResult({'error': error.toString()});
      reported = true;
      rethrow;
    } finally {
      // Strokes continuing from this one learn what it left on the layer.
      if (!session.committed.isCompleted) session.committed.complete(applied);
      if (!reported) {
        PenProbe.instance.nativeResult({
          'changed': false,
          'inputToPreviewSamples': session.latencyUs.length,
        });
      }
      for (final image in owned ?? const <ui.Image?>[]) {
        image?.dispose();
      }
      _clearNativePreview(session);
    }
  }

  /// New tiles as assets with GPU images straight from their pixels (no
  /// PNG decode, no whole-layer render); a null asset clears that tile.
  Future<Map<int, (RasterAsset?, ui.Image?, Rect?)>> _tileImages(
    List<TileUpdate> updates,
  ) async {
    const size = TiledRaster.size;
    final images = await Future.wait([
      for (final update in updates)
        update.premultiplied == null
            ? Future<ui.Image?>.value()
            : imageFromPremultiplied(update.premultiplied!, size, size),
    ]);
    return {
      for (var i = 0; i < updates.length; i++)
        updates[i].index: switch (updates[i]) {
          TileUpdate(:final png?, :final bounds?) => (
            RasterAsset(id: newId(), png: png, width: size, height: size),
            images[i],
            Rect.fromLTRB(
              bounds.$1.toDouble(),
              bounds.$2.toDouble(),
              bounds.$3.toDouble(),
              bounds.$4.toDouble(),
            ),
          ),
          _ => (null, null, null),
        },
    };
  }

  /// Puts freshly rendered tiles in the cache without decoding their PNGs.
  Future<void> _adoptTiles(RenderedTiles rendered) async {
    final byIndex = await _tileImages(rendered.updates);
    final tiles = rendered.raster?.tiles ?? const {};
    for (final MapEntry(:key, :value) in byIndex.entries) {
      final (_, image, bounds) = value;
      final asset = tiles[key];
      if (asset == null || image == null || disposed) {
        image?.dispose();
        continue;
      }
      rasters.adopt(asset, image, bounds);
    }
  }

  void _clearNativePreview(NativeStrokeSession session) {
    session.disposePreview();
    if (_previews.remove(session) && !disposed) inkChanges.notifyListeners();
  }

  /// The same raster limits [ArtDocument.fromJson] enforces when reopening.
  void _commit(ArtDocument next) {
    if (disposed || documentTransition) return;
    cancelAdjustment();
    cancelLiquify();
    cancelClone();
    cancelTransform();
    _textAmending = false;
    _undo.add(document);
    if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    _redo.clear();
    document = next.copyWith(revision: document.revision + 1);
    _changed();
  }

  void undo() {
    if (documentTransition) return;
    lastQuickShape = null;
    finishText();
    if (adjustment != null) {
      undoAdjustment();
      return;
    }
    if (liquify != null) {
      undoLiquify();
      return;
    }
    if (clone != null) {
      undoClone();
      return;
    }
    if (selectionDrawing) {
      cancelSelectionDraft();
      return;
    }
    if (transformDraft != null) {
      cancelTransform();
      return;
    }
    cancelStroke();
    _restoreHistory(_undo, _redo);
  }

  void redo() {
    if (documentTransition ||
        adjustment != null ||
        liquify != null ||
        clone != null) {
      return;
    }
    lastQuickShape = null;
    if (selectionDrawing) {
      cancelSelectionDraft();
      return;
    }
    if (transformDraft != null) {
      cancelTransform();
      return;
    }
    cancelStroke();
    _restoreHistory(_redo, _undo);
  }

  /// Steps to [from]'s last document. Older history keeps only PNG bytes;
  /// when that step's pixels are not decoded, or earlier work is queued, one
  /// queued step picks its target when it runs, so bursts of undo/redo and
  /// edits between them keep the user's order.
  /// As in Procreate; older steps keep only compressed pixels.
  static const maxUndoSteps = 250;

  /// The last undo (true) or redo and what it changed, for the banner; the
  /// counter tells repeated identical steps apart.
  final historyNotice = ValueNotifier<(int, bool, HistoryChange)?>(null);

  /// Set while Edit Shape lifts its shape off: no banner for that undo.
  bool _quietHistory = false;

  void _restoreHistory(List<ArtDocument> from, List<ArtDocument> to) {
    void apply() {
      final undoing = identical(from, _undo);
      final target = from.last;
      if (!_quietHistory) {
        historyNotice.value = (
          (historyNotice.value?.$1 ?? 0) + 1,
          undoing,
          undoing
              ? describeChange(target, document)
              : describeChange(document, target),
        );
      }
      to.add(document);
      document = from.removeLast();
      _changed();
    }

    bool ready(ArtDocument step) =>
        documentRasters(step).every(rasters.images.containsKey);
    if (_queued == 0 || _inQueue) {
      if (from.isEmpty) return;
      if (ready(from.last)) {
        apply();
        return;
      }
    }
    _enqueue(() async {
      if (from.isEmpty) return;
      final target = from.last;
      if (!ready(target)) await rasters.prepare(documentRasters(target));
      if (disposed) return;
      if (documentTransition || from.isEmpty || !identical(from.last, target)) {
        _retainRasterHistory();
        return;
      }
      apply();
    });
    _notify();
  }

  static const maxLayers = 64;

  /// A new empty layer right above the active one, as in Procreate.
  void addLayer(String name) {
    if (_defer(() => addLayer(name))) return;
    if (document.layers.length >= maxLayers) return;
    // In the active layer's group, as in Procreate.
    final layer = ArtLayer(
      id: newId(),
      name: name,
      group: document.activeLayer.group,
    );
    final above =
        document.layers.indexWhere((l) => l.id == document.activeLayerId) + 1;
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(above),
          layer,
          ...document.layers.skip(above),
        ],
        activeLayerId: layer.id,
      ),
    );
  }

  /// Painting was tried on a text layer: the editor offers to rasterise it.
  final textLayerTouched = ValueNotifier<int>(0);

  /// The text layer being edited (Add Text), or null.
  String? textEditing;

  /// This edit has its undo step already: later changes amend it.
  bool _textAmending = false;

  /// Imported font families, in the order they were added.
  List<String> importedFonts = const [];

  LayerText? get editedText =>
      document.layers.where((l) => l.id == textEditing).firstOrNull?.text;

  static String _textName(LayerText text) {
    final line = text.text.trim().split('\n').first.trim();
    return line.length > 32 ? '${line.substring(0, 32)}…' : line;
  }

  /// A text layer above the active one, being edited.
  void addText(String text, {String fallbackName = 'Text'}) {
    if (_defer(() => addText(text, fallbackName: fallbackName))) return;
    if (document.layers.length >= maxLayers) return;
    finishText();
    final CanvasSize(:width, :height) = document.dimensions;
    final size = (width / 12).clamp(12.0, 600.0);
    final box = width * .6;
    final content = LayerText(
      text: text,
      origin: Offset((width - box) / 2, height * .4),
      width: box,
      size: size,
      color: color,
      font: _lastFont,
    );
    final name = _textName(content);
    final layer = ArtLayer(
      id: newId(),
      name: name.isEmpty ? fallbackName : name,
      group: document.activeLayer.group,
      text: content,
    );
    final above =
        document.layers.indexWhere((l) => l.id == document.activeLayerId) + 1;
    panel = null;
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(above),
          layer,
          ...document.layers.skip(above),
        ],
        activeLayerId: layer.id,
      ),
    );
    textEditing = layer.id;
    _textAmending = true;
    _notify();
  }

  String _lastFont = '';

  /// Opens text layer [id] for editing.
  void editText(String id) {
    if (documentTransition) return;
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer?.text == null || layer!.locked) return;
    finishText();
    cancelTransform();
    cancelSelectionDraft();
    selectedLayers = const {};
    panel = null;
    document = document.copyWith(activeLayerId: id);
    textEditing = id;
    _textAmending = false;
    _changed();
  }

  /// Changes the text being edited; one edit is one undo step.
  void setText(LayerText Function(LayerText text) change) {
    final id = textEditing;
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    final text = layer?.text;
    if (layer == null || text == null || documentTransition) return;
    final next = change(text);
    if (next == text) return;
    if (next.font != text.font) _lastFont = next.font;
    final oldName = _textName(text), newName = _textName(next);
    final doc = document.copyWith(
      layers: [
        for (final l in document.layers)
          l.id == id
              ? l.copyWith(
                  text: next,
                  name: l.name == oldName && newName.isNotEmpty
                      ? newName
                      : null,
                )
              : l,
      ],
    );
    if (_textAmending) {
      document = doc.copyWith(revision: document.revision + 1);
      _changed();
    } else {
      _commit(doc);
      _textAmending = true;
    }
  }

  /// Ends text editing; a layer left without text goes.
  void finishText() {
    final id = textEditing;
    if (id == null) return;
    textEditing = null;
    _textAmending = false;
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer?.text?.text.trim().isEmpty == true &&
        document.layers.length > 1) {
      deleteLayer(id);
    }
    _notify();
  }

  /// Turns text layer [id] into pixels: it can be painted on, no longer
  /// edited as text.
  Future<void> rasterizeText(String id) async {
    finishText();
    if (!document.layers.any((l) => l.id == id && l.text != null)) return;
    if (document.activeLayerId != id) selectLayer(id);
    await _rewriteActiveLayer((_, _, _) {});
  }

  /// Makes font [family] usable from [bytes] (TTF, OTF or a TTC's first
  /// face); text already set in it lays out again.
  Future<void> loadFont(String family, Uint8List bytes) async {
    await ui.loadFontFromList(bytes, fontFamily: family);
    if (disposed) return;
    if (!importedFonts.contains(family)) {
      importedFonts = List.unmodifiable([...importedFonts, family]);
    }
    if (!initialized) return;
    resetTextLayouts();
    // New layer objects: cached layer images are drawn again.
    document = document.copyWith(
      layers: [
        for (final l in document.layers) l.text == null ? l : l.copyWith(),
      ],
    );
    _changed();
  }

  /// A copy right above layer [id]; both share the same immutable tiles.
  void duplicateLayer(String id, String name) {
    if (_defer(() => duplicateLayer(id, name))) return;
    if (document.layers.length >= maxLayers) return;
    final index = document.layers.indexWhere((l) => l.id == id);
    if (index < 0) return;
    final source = document.layers[index];
    final copy = ArtLayer(
      id: newId(),
      name: name,
      strokes: source.strokes,
      visible: source.visible,
      opacity: source.opacity,
      raster: source.raster,
      legacyRaster: source.legacyRaster,
      text: source.text,
      private: source.private,
      blend: source.blend,
      mask: source.mask,
      group: source.group,
    );
    _commit(
      document.copyWith(
        layers: [
          ...document.layers.take(index + 1),
          copy,
          ...document.layers.skip(index + 1),
        ],
        activeLayerId: copy.id,
      ),
    );
  }

  /// Pixels cut or copied, with where they lay on the canvas; kept across
  /// drawings, so they paste into another one too.
  CanvasClipping? clipboard;

  /// The Copy & Paste menu (three-finger swipe up) is showing.
  bool copyPasteMenu = false;

  void showCopyPasteMenu([bool show = true]) {
    copyPasteMenu = show;
    _notify();
  }

  /// Copies the active layer — or, with [all], every visible layer
  /// flattened — inside the selection (with its soft edge) or whole.
  /// False when there is nothing to copy.
  Future<bool> copy({bool all = false}) async {
    if (!initialized || disposed || documentTransition) return false;
    finishStroke();
    if (_busy) await settleStroke();
    final doc = document, region = selection;
    final engine = FreehandBrushEngine();
    final layers = all
        ? [
            for (final l in doc.layers)
              if (l.visible) l,
          ]
        : [doc.activeLayer];
    Rect? content;
    for (final layer in layers) {
      final bounds = layerContentBounds(
        layer,
        engine,
        doc.dimensions,
        pixelBounds: rasters.pixelBounds,
      );
      if (bounds != null) {
        content = content == null ? bounds : content.expandToInclude(bounds);
      }
    }
    if (region != null) content = content?.intersect(region.bounds);
    content = content?.intersect(doc.dimensions.rect);
    if (content == null || content.isEmpty) return false;
    final area = Rect.fromLTRB(
      content.left.floorToDouble(),
      content.top.floorToDouble(),
      content.right.ceilToDouble(),
      content.bottom.ceilToDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..translate(-area.left, -area.top);
    final soft = region != null && region.feather > 0;
    if (soft) {
      canvas.saveLayer(area, Paint());
    } else if (region != null) {
      canvas.clipPath(region.path);
    }
    for (final layer in layers) {
      paintLayer(
        canvas,
        layer,
        engine,
        doc.dimensions,
        rasterImages: rasters.images,
        // One layer is copied as its pixels; all layers as they look.
        applyOpacity: all,
        visible: area,
      );
    }
    if (soft) {
      keepInside(canvas, region, area);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(area.width.toInt(), area.height.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return false;
      clipboard = CanvasClipping(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        area,
      );
    } finally {
      image?.dispose();
      picture.dispose();
    }
    _notify();
    return true;
  }

  /// Copies, then clears what was copied from the active layer.
  Future<void> cut() async {
    if (document.activeLayer.locked) return;
    if (await copy()) await clearActiveLayer();
  }

  /// The clipboard as a new layer above the active one, where it was cut
  /// from (fitted on a canvas too small for it).
  /// A [private] paste stays out of the time-lapse.
  Future<void> paste(String name, {bool private = false}) async {
    final clip = clipboard;
    if (clip == null) return;
    final fits =
        document.dimensions.rect.contains(clip.area.topLeft) &&
        document.dimensions.rect.contains(clip.area.bottomRight);
    await addImageLayer(
      clip.png,
      name,
      at: fits ? clip.area : null,
      private: private,
    );
  }

  /// Marks layer [id] private (out of the time-lapse) or not.
  void togglePrivateLayer(String id) =>
      updateLayer(id, (l) => l.copyWith(private: !l.private));

  /// A copy of the selection (or of the layer) on a new layer.
  Future<void> duplicateContent(String name) async {
    if (selection == null) {
      duplicateLayer(document.activeLayerId, name);
      return;
    }
    if (await copy()) await paste(name);
  }

  /// Moves the selection (or the layer's content) onto a new layer.
  Future<void> cutAndPaste(String name) async {
    if (document.activeLayer.locked) return;
    if (!await copy()) return;
    await clearActiveLayer();
    await paste(name);
  }

  /// The brush a stroke uses: the selected one, except that smudging needs
  /// a native brush — vector (JSON) brushes smudge with a soft round stamp.
  BrushPreset get smudgeBrush => tool == StudioTool.smudge && !brush.isNative
      ? initialBrushes.firstWhere((b) => b.id == 'stamp-gouache')
      : brush;

  /// ColorDrop: how different a colour may be and still be filled (0–1).
  double fillThreshold = .3;

  /// The fill in progress: further taps fill more areas in its colour, and
  /// changing the threshold redoes its last fill.
  ({Offset point, int color})? fillSession;
  ArtDocument? _lastFill;
  bool _filling = false;
  double? _refillAt;

  /// Fills the area under [point] on the active layer in [color] (the
  /// current colour by default) — bounded by the reference layer's lines
  /// when there is one, else the active layer's — inside any selection.
  Future<void> colorDrop(Offset point, {int? color}) async {
    final argb = color ?? this.color;
    fillSession = (point: point, color: argb);
    _notify();
    await _fill(point, argb);
  }

  /// Highest threshold, as in Procreate (100 % saves as 97.6 %): above it
  /// a fill would cross solid lines and flood everything.
  static const maxFillThreshold = .976;

  /// A new threshold refills the last area (as one undo step).
  void setFillThreshold(double value) {
    fillThreshold = value.clamp(0.0, maxFillThreshold);
    _preferences?.setDouble('fill.threshold', fillThreshold);
    _notify();
    final session = fillSession;
    if (session == null || !identical(_lastFill, document)) return;
    if (_filling) {
      _refillAt = fillThreshold;
      return;
    }
    undo();
    unawaited(_fill(session.point, session.color));
  }

  void endFill() {
    if (fillSession == null) return;
    fillSession = null;
    _lastFill = null;
    _notify();
  }

  Future<void> _fill(Offset point, int argb) async {
    if (!initialized || disposed || documentTransition || _filling) return;
    finishStroke();
    if (_busy) await settleStroke();
    final doc = document, layer = doc.activeLayer;
    if (layer.locked || !layer.visible || disposed || documentTransition) {
      return;
    }
    final dims = doc.dimensions;
    final x = point.dx.floor(), y = point.dy.floor();
    if (x < 0 || y < 0 || x >= dims.width || y >= dims.height) return;
    _filling = true;
    documentTransition = true;
    _notify();
    try {
      final source =
          doc.layers.where((l) => l.reference && l.visible).firstOrNull ??
          layer;
      final pixels = (await renderNativeBase(
        source,
        doc.grid,
        rasters.images,
      )).rgba;
      final region = selection;
      final clip = region == null
          ? null
          : await renderSelectionCoverage(region, dims);
      final request = (
        pixels,
        dims.width,
        dims.height,
        x,
        y,
        fillThreshold,
        clip,
        argb,
      );
      final fill = await colorDropOffThread(request);
      if (penLogging) {
        var filled = 0;
        for (var i = 3; i < (fill?.length ?? 0); i += 4) {
          if (fill![i] != 0) filled++;
        }
        debugPrint(
          'ARTBLEND_FILL ${jsonEncode({'x': x, 'y': y, 'threshold': fillThreshold, 'source': source.name, 'reference': source.reference, 'active': layer.name, 'clip': clip != null, 'filled': filled, 'of': dims.pixels})}',
        );
      }
      if (fill == null || disposed) return;
      final image = await imageFromPremultiplied(fill, dims.width, dims.height);
      final RenderedTiles rendered;
      try {
        rendered = await renderTiles(doc.grid, (canvas) {
          paintLayer(
            canvas,
            layer,
            FreehandBrushEngine(),
            dims,
            rasterImages: rasters.images,
            applyOpacity: false,
            applyMask: false,
          );
          canvas.drawImage(
            image,
            Offset.zero,
            Paint()
              ..blendMode = layer.alphaLock
                  ? BlendMode.srcATop
                  : BlendMode.srcOver,
          );
        });
      } finally {
        image.dispose();
      }
      if (disposed) return;
      final raster = rendered.raster;
      final next = doc.copyWith(
        layers: [
          for (final l in doc.layers)
            l.id == layer.id
                ? l.copyWith(
                    raster: raster,
                    clearRaster: raster == null,
                    clearLegacyRaster: true,
                    clearText: true,
                    strokes: const [],
                  )
                : l,
        ],
      );
      _validateDocument(next);
      await _adoptTiles(rendered);
      if (disposed || !identical(doc, document)) return;
      documentTransition = false;
      _commit(next);
      _lastFill = document;
    } finally {
      documentTransition = false;
      _filling = false;
      _notify();
    }
    final again = _refillAt;
    _refillAt = null;
    if (again != null) setFillThreshold(again);
  }

  /// Interface hidden: only the canvas (four-finger tap, ⌘0).
  bool fullScreen = false;

  void toggleFullScreen() {
    fullScreen = !fullScreen;
    _notify();
  }

  /// The three-finger scrub and ⌘⌫: clears the selection's pixels when
  /// there is a selection, otherwise the whole active layer.
  Future<void> clearActiveLayer() async {
    final layer = document.activeLayer;
    if (layer.locked || !layer.visible || documentTransition) return;
    if (selection != null) {
      try {
        await deleteSelectedPixels();
      } on StateError {
        // The layer became locked or hidden meanwhile: nothing cleared.
      }
    } else {
      clearLayer(layer.id);
    }
  }

  /// The background colour layer: its colour, and whether it shows.
  void setBackground(int color) {
    if (_defer(() => setBackground(color))) return;
    if (document.background == color) return;
    _commit(document.copyWith(background: color | 0xff000000));
  }

  void toggleBackground() {
    if (_defer(toggleBackground)) return;
    _commit(document.copyWith(backgroundHidden: !document.backgroundHidden));
  }

  void toggleAlphaLock(String id) =>
      updateLayer(id, (l) => l.copyWith(alphaLock: !l.alphaLock));

  /// Clips layer [id] to the one below; the bottom layer cannot clip.
  void toggleClipping(String id) {
    final index = document.layers.indexWhere((l) => l.id == id);
    if (index < 0) return;
    final layer = document.layers[index];
    if (index == 0 && !layer.clipping) return;
    updateLayer(id, (l) => l.copyWith(clipping: !l.clipping));
  }

  /// Layers hidden for Solo, to show again when Solo ends.
  Map<String, bool>? _soloSaved;
  String? soloLayerId;

  /// Shows only layer [id] (press and hold its visibility box); again, or
  /// for another layer, brings the others back as they were.
  void toggleSolo(String id) {
    final saved = _soloSaved;
    if (saved != null) {
      _soloSaved = null;
      final wasSolo = soloLayerId == id;
      soloLayerId = null;
      _commit(
        document.copyWith(
          layers: [
            for (final l in document.layers)
              l.copyWith(visible: saved[l.id] ?? l.visible),
          ],
        ),
      );
      if (wasSolo) return;
    }
    if (_defer(() => toggleSolo(id))) return;
    _soloSaved = {for (final l in document.layers) l.id: l.visible};
    soloLayerId = id;
    _commit(
      document.copyWith(
        layers: [
          for (final l in document.layers) l.copyWith(visible: l.id == id),
        ],
      ),
    );
  }

  /// Fills the active layer with the current colour: inside the selection
  /// if any, and over existing pixels only when alpha-locked.
  Future<void> fillActiveLayer() =>
      _rewriteActiveLayer((canvas, layer, bounds) {
        final region = selection;
        final paint = Paint()
          ..color = Color(color)
          ..blendMode = layer.alphaLock ? BlendMode.srcATop : BlendMode.srcOver;
        if (region != null && region.feather > 0) {
          canvas.saveLayer(bounds, Paint()..blendMode = paint.blendMode);
          canvas.drawRect(bounds, Paint()..color = Color(color));
          keepInside(canvas, region, bounds);
          canvas.restore();
          return;
        }
        if (region != null) canvas.clipPath(region.path);
        canvas.drawRect(bounds, paint);
      });

  /// Replaces the active layer's colours with their complements.
  Future<void> invertActiveLayer() =>
      _rewriteActiveLayer((canvas, layer, bounds) {}, invert: true);

  /// True while a finger or the pen is on the canvas: bars over it fade.
  final ValueNotifier<bool> canvasEngaged = ValueNotifier(false);

  /// Drawing Assist: where the stroke began and the guide line it took.
  Offset? _assistOrigin;
  Offset? _assistDirection;

  /// [point] on the guide line the stroke follows: the one nearest its
  /// first few pixels' heading; until then, its start.
  InkPoint _assisted(InkPoint point) {
    final origin = _assistOrigin;
    if (origin == null || _replaying) return point;
    final at = Offset(point.x, point.y);
    var direction = _assistDirection;
    if (direction == null) {
      if ((at - origin).distance < 6) {
        return InkPoint(origin.dx, origin.dy, point.pressure);
      }
      direction = _assistDirection = nearestDirection(
        assistDirections(guide, document.dimensions.size, origin),
        at - origin,
      );
      if (direction == null) {
        _assistOrigin = null;
        return point;
      }
    }
    final on = projectOnto(at, origin, direction);
    return InkPoint(on.dx, on.dy, point.pressure);
  }

  void toggleDrawingAssist(String id) =>
      updateLayer(id, (l) => l.copyWith(assisted: !l.assisted));

  /// QuickShape: the stroke's points so far, for recognising when held.
  final List<InkPoint> _shapeInput = [];
  bool _replaying = false;

  /// A shape snapped from a held stroke, following the pen until lifted.
  HeldQuickShape? quickShape;

  /// The shape just drawn, which Edit Shape can still change.
  LastQuickShape? lastQuickShape;

  /// The shape being edited (it is off the layer meanwhile).
  QuickShape? shapeEdit;

  /// The pen held still: the stroke so far becomes a shape, if it makes
  /// one. Its brush preview goes; the shape is drawn when the pen lifts.
  bool holdStroke({bool perfect = false}) {
    if (quickShape != null || _replaying || adjustment != null) return false;
    if (_drawingNative == null && _pending == null) return false;
    final input = [..._shapeInput];
    final shape = QuickShape.recognise([
      for (final p in input) Offset(p.x, p.y),
    ]);
    if (shape == null) return false;
    final pressure =
        input.map((p) => p.pressure).reduce((a, b) => a + b) / input.length;
    cancelStroke();
    quickShape = HeldQuickShape(
      shape,
      Offset(input.last.x, input.last.y),
      pressure,
    )..perfect = perfect;
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  /// A second finger (or Shift) held: the perfect version of the shape.
  void setQuickShapePerfect(bool perfect) {
    final held = quickShape;
    if (held == null || held.perfect == perfect) return;
    held.perfect = perfect;
    inkChanges.notifyListeners();
  }

  /// Draws [shape] as a stroke of the current brush.
  void _drawShape(QuickShape shape, double pressure) {
    final points = shape.outline(spacing: math.max(1, size / 12));
    _replaying = true;
    try {
      var time = Duration.zero;
      const step = Duration(milliseconds: 4);
      if (!beginStroke(
        InkPoint(points.first.dx, points.first.dy, pressure),
        simulatePressure: false,
        time: time,
      )) {
        return;
      }
      for (final p in points.skip(1)) {
        time += step;
        appendPoint(InkPoint(p.dx, p.dy, pressure), time: time);
      }
      finishStroke();
    } finally {
      _replaying = false;
    }
  }

  /// Takes the last shape off the layer to move its points.
  Future<bool> editQuickShape() async {
    final last = lastQuickShape;
    if (last == null || shapeEdit != null) return false;
    await settleStroke();
    if (last.revision != document.revision ||
        !identical(lastQuickShape, last)) {
      lastQuickShape = null;
      _notify();
      return false;
    }
    _quietHistory = true;
    try {
      undo();
      await settleStroke();
    } finally {
      _quietHistory = false;
    }
    lastQuickShape = last;
    shapeEdit = last.shape;
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  /// Replaces the shape just drawn with its perfect version: for a pen
  /// whose tablet ignores fingers while it touches the screen.
  Future<void> perfectQuickShape() async {
    if (shapeEdit case final shape?) {
      shapeEdit = shape.perfected();
      inkChanges.notifyListeners();
      _notify();
      return;
    }
    if (!await editQuickShape()) return;
    shapeEdit = shapeEdit!.perfected();
    finishShapeEdit();
  }

  void moveShapeNode(int index, Offset to) {
    final shape = shapeEdit;
    if (shape == null) return;
    shapeEdit = shape.withNode(index, to);
    inkChanges.notifyListeners();
  }

  /// Draws the edited shape back; [keep] false draws it as it was.
  void finishShapeEdit({bool keep = true}) {
    final shape = shapeEdit, last = lastQuickShape;
    if (shape == null || last == null) return;
    shapeEdit = null;
    final drawn = keep ? shape : last.shape;
    final entry = LastQuickShape(drawn, last.pressure);
    _drawShape(drawn, last.pressure);
    lastQuickShape = entry;
    unawaited(
      settleStroke().then((_) {
        if (identical(lastQuickShape, entry)) {
          entry.revision = document.revision;
          _notify();
        }
      }),
    );
    _notify();
  }

  /// The adjustment being tried on the active layer, until it is applied
  /// or cancelled.
  AdjustmentSession? adjustment;

  /// Starts [kind] on the active layer (inside the selection, if any).
  Future<bool> startAdjustment(AdjustmentKind kind) async {
    if (!initialized || disposed || documentTransition) return false;
    if (adjustment?.adjustment.kind == kind) return true;
    finishStroke();
    if (_busy) await settleStroke();
    cancelAdjustment();
    cancelLiquify();
    cancelClone();
    cancelTransform();
    cancelSelectionDraft();
    final doc = document, layer = doc.activeLayer;
    if (layer.locked || !layer.visible || disposed || documentTransition) {
      return false;
    }
    final shaders = await AdjustmentShaders.load();
    final recorder = PictureRecorder();
    paintLayer(
      Canvas(recorder),
      layer,
      FreehandBrushEngine(),
      doc.dimensions,
      rasterImages: rasters.images,
      applyOpacity: false,
      applyMask: false,
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(
      doc.dimensions.width,
      doc.dimensions.height,
    );
    picture.dispose();
    if (disposed || !identical(doc, document) || documentTransition) {
      source.dispose();
      return false;
    }
    panel = null;
    fillSession = null;
    adjustment = AdjustmentSession(
      layerId: layer.id,
      source: source,
      shaders: shaders,
      adjustment: kind == AdjustmentKind.recolor
          ? Adjustment.initial(kind).withColor(color)
          : Adjustment.initial(kind),
      clip: selection,
      onRendered: () {
        if (disposed) return;
        inkChanges.notifyListeners();
        _notify();
      },
    );
    inkChanges.notifyListeners();
    _notify();
    if (kind == AdjustmentKind.curves) unawaited(_countHistogram(adjustment!));
    return true;
  }

  Future<void> _countHistogram(AdjustmentSession session) async {
    // Only a backdrop for the curve: without it Curves still works.
    try {
      final data = await session.source.toByteData(
        format: ImageByteFormat.rawStraightRgba,
      );
      if (data == null || !identical(adjustment, session)) return;
      final bins = await lumaHistogramOffThread(data.buffer.asUint8List());
      if (!identical(adjustment, session)) return;
      session.histogram = bins;
      _notify();
    } catch (_) {}
  }

  /// Clone on the active layer, until applied or cancelled.
  CloneSession? clone;

  /// Where the disc stood last, for the next time Clone opens.
  Offset? _cloneDisc;
  bool _cloneLocked = false;

  Future<bool> startClone() async {
    if (!initialized || disposed || documentTransition) return false;
    if (clone != null) return true;
    finishStroke();
    if (_busy) await settleStroke();
    cancelAdjustment();
    cancelLiquify();
    cancelTransform();
    cancelSelectionDraft();
    final doc = document, layer = doc.activeLayer;
    if (layer.locked || !layer.visible || disposed || documentTransition) {
      return false;
    }
    final recorder = PictureRecorder();
    paintLayer(
      Canvas(recorder),
      layer,
      FreehandBrushEngine(),
      doc.dimensions,
      rasterImages: rasters.images,
      applyOpacity: false,
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(
      doc.dimensions.width,
      doc.dimensions.height,
    );
    picture.dispose();
    if (disposed || !identical(doc, document) || documentTransition) {
      source.dispose();
      return false;
    }
    clone = CloneSession(layerId: layer.id, source: source, disc: _cloneDisc)
      ..locked = _cloneLocked;
    panel = null;
    fillSession = null;
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  void moveCloneDisc(Offset to) {
    final session = clone;
    if (session == null) return;
    session.moveDisc(to);
    _cloneDisc = to;
    inkChanges.notifyListeners();
  }

  void setCloneLocked(bool locked) {
    final session = clone;
    if (session == null) return;
    session.locked = _cloneLocked = locked;
    _notify();
  }

  void undoClone() {
    clone?.undo();
    inkChanges.notifyListeners();
    _notify();
  }

  void cancelClone() {
    final session = clone;
    if (session == null) return;
    _cloneDisc = session.disc;
    clone = null;
    session.dispose();
    _stabilizer = null;
    if (disposed) return;
    inkChanges.notifyListeners();
    _notify();
  }

  Future<void> applyClone() async {
    final session = clone;
    if (session == null) return;
    session.drawing = null;
    if (session.strokes.isEmpty || document.activeLayerId != session.layerId) {
      cancelClone();
      return;
    }
    try {
      await _rewriteActiveLayer((_, _, _) {}, replace: session.paint);
    } finally {
      if (identical(clone, session)) cancelClone();
    }
  }

  bool _beginCloneStroke(
    InkPoint point,
    Duration? time,
    bool simulatePressure,
  ) {
    final session = clone!;
    final settings = smoothing;
    _stabilizer = settings.active
        ? (StrokeStabilizer(settings)..start(point, time))
        : null;
    session.begin(
      InkStroke(
        id: newId(),
        points: [point],
        color: 0xffffffff,
        size: size,
        opacity: opacity,
        simulatePressure: simulatePressure,
        smoothing: brush.smoothing,
        thinning: brush.thinning,
      ),
      Offset(point.x, point.y),
    );
    inkChanges.notifyListeners();
    return true;
  }

  /// Liquify on the active layer, until applied or cancelled.
  LiquifySession? liquify;
  Timer? _liquifyTicker;
  Offset? _liquifyAt;

  /// Opens Liquify on the active layer, keeping the last brush settings.
  Future<bool> startLiquify() async {
    if (!initialized || disposed || documentTransition) return false;
    if (liquify != null) return true;
    finishStroke();
    if (_busy) await settleStroke();
    cancelAdjustment();
    cancelClone();
    cancelTransform();
    cancelSelectionDraft();
    final doc = document, layer = doc.activeLayer;
    if (layer.locked || !layer.visible || disposed || documentTransition) {
      return false;
    }
    final recorder = PictureRecorder();
    paintLayer(
      Canvas(recorder),
      layer,
      FreehandBrushEngine(),
      doc.dimensions,
      rasterImages: rasters.images,
      applyOpacity: false,
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(
      doc.dimensions.width,
      doc.dimensions.height,
    );
    picture.dispose();
    if (disposed || !identical(doc, document) || documentTransition) {
      source.dispose();
      return false;
    }
    final longest = math.max(doc.dimensions.width, doc.dimensions.height);
    final previous = _liquifyBrush;
    liquify = LiquifySession(
      layerId: layer.id,
      source: source,
      cells: (longest / 12).round().clamp(64, 255),
    );
    if (previous != null) {
      liquify!
        ..mode = previous.mode
        ..size = previous.size
        ..pressure = previous.pressure
        ..distortion = previous.distortion
        ..momentum = previous.momentum;
    }
    panel = null;
    fillSession = null;
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  /// The brush settings Liquify had last, for the next time it opens.
  ({
    LiquifyMode mode,
    double size,
    double pressure,
    double distortion,
    double momentum,
  })?
  _liquifyBrush;

  void setLiquify({
    LiquifyMode? mode,
    double? size,
    double? pressure,
    double? distortion,
    double? momentum,
  }) {
    final session = liquify;
    if (session == null) return;
    session
      ..mode = mode ?? session.mode
      ..size = size ?? session.size
      ..pressure = pressure ?? session.pressure
      ..distortion = distortion ?? session.distortion
      ..momentum = momentum ?? session.momentum;
    _liquifyBrush = (
      mode: session.mode,
      size: session.size,
      pressure: session.pressure,
      distortion: session.distortion,
      momentum: session.momentum,
    );
    _notify();
  }

  void beginLiquify(Offset point, double force) {
    final session = liquify;
    if (session == null) return;
    _liquifyTicker?.cancel();
    session.begin(point, force);
    _liquifyAt = point;
    // The continuous brushes keep working while the pen is held still.
    _liquifyTicker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!identical(liquify, session)) return;
      session.hold();
      inkChanges.notifyListeners();
    });
    inkChanges.notifyListeners();
    _notify();
  }

  void moveLiquify(Offset point, double force) {
    final session = liquify;
    if (session == null) return;
    session.move(point, force);
    _liquifyAt = point;
    inkChanges.notifyListeners();
  }

  void endLiquify() {
    final session = liquify;
    _liquifyTicker?.cancel();
    _liquifyTicker = null;
    if (session == null) return;
    final at = _liquifyAt;
    if (session.end() && at != null) {
      // Momentum: the push glides on and slows down.
      _liquifyTicker = Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (!identical(liquify, session) || !session.glide(at)) {
          t.cancel();
        }
        inkChanges.notifyListeners();
      });
    }
    _notify();
  }

  void undoLiquify() {
    liquify?.undo();
    inkChanges.notifyListeners();
    _notify();
  }

  void resetLiquify() {
    liquify?.reset();
    inkChanges.notifyListeners();
    _notify();
  }

  /// Takes half of the distortion back, everywhere.
  void reconstructLiquify() {
    liquify?.reconstructAll(.5);
    inkChanges.notifyListeners();
    _notify();
  }

  void cancelLiquify() {
    final session = liquify;
    if (session == null) return;
    _liquifyTicker?.cancel();
    _liquifyTicker = null;
    liquify = null;
    session.dispose();
    if (disposed) return;
    inkChanges.notifyListeners();
    _notify();
  }

  /// Writes the liquified layer as one undo step.
  Future<void> applyLiquify() async {
    final session = liquify;
    if (session == null) return;
    _liquifyTicker?.cancel();
    _liquifyTicker = null;
    if (session.isIdentity || document.activeLayerId != session.layerId) {
      cancelLiquify();
      return;
    }
    try {
      await _rewriteActiveLayer(
        (_, _, _) {},
        replace: (canvas, _) => session.paint(canvas),
      );
    } finally {
      if (identical(liquify, session)) cancelLiquify();
    }
  }

  /// Marks an Undo step before a run of changes (a slider drag, a swipe).
  void beginAdjustmentChange() => adjustment?.checkpoint();

  void setAdjustment(Adjustment next) {
    final session = adjustment;
    if (session == null || session.adjustment.kind != next.kind) return;
    session.adjustment = next;
    inkChanges.notifyListeners();
    _notify();
  }

  void setAdjustmentValue(String id, double value) {
    final session = adjustment;
    if (session != null) setAdjustment(session.adjustment.withValue(id, value));
  }

  /// A sideways drag on the canvas: [delta] of the canvas width.
  void adjustAmountBy(double delta) {
    final session = adjustment, id = session?.adjustment.kind.swipe;
    if (session == null || id == null) return;
    setAdjustmentValue(id, session.adjustment[id] + delta);
  }

  /// Motion Blur's slide on the canvas: its direction and length, as
  /// [delta] in document pixels since the slide began.
  void slideMotionBlur(Offset delta) {
    final session = adjustment;
    if (session == null ||
        session.adjustment.kind != AdjustmentKind.motionBlur) {
      return;
    }
    final size = document.dimensions.size;
    final reach = .25 * math.max(size.width, size.height);
    var angle = math.atan2(delta.dy, delta.dx);
    if (angle < 0) angle += math.pi;
    setAdjustment(
      session.adjustment
          .withValue('amount', delta.distance / reach)
          .withValue('angle', (angle / math.pi) % 1),
    );
  }

  /// Moves Perspective Blur's centre to [point] (document pixels).
  void moveAdjustmentCentre(Offset point) {
    final session = adjustment;
    if (session == null) return;
    final size = document.dimensions.size;
    setAdjustment(
      session.adjustment
          .withValue('x', point.dx / size.width)
          .withValue('y', point.dy / size.height),
    );
  }

  void setAdjustmentPencil(bool pencil) {
    final session = adjustment;
    if (session == null || session.pencil == pencil) return;
    session
      ..checkpoint()
      ..pencil = pencil;
    inkChanges.notifyListeners();
    _notify();
  }

  void undoAdjustment() {
    adjustment?.undo();
    inkChanges.notifyListeners();
    _notify();
  }

  void resetAdjustment() {
    adjustment?.reset();
    inkChanges.notifyListeners();
    _notify();
  }

  /// Shows the layer as it was while Preview is held.
  void previewOriginal(bool original) {
    final session = adjustment;
    if (session == null || session.showOriginal == original) return;
    session.showOriginal = original;
    inkChanges.notifyListeners();
  }

  void cancelAdjustment() {
    final session = adjustment;
    if (session == null) return;
    adjustment = null;
    session.dispose();
    _stabilizer = null;
    if (disposed) return;
    inkChanges.notifyListeners();
    _notify();
  }

  /// Writes the adjusted layer as one undo step.
  Future<void> applyAdjustment() async {
    final session = adjustment;
    if (session == null) return;
    if (session.adjustment.isNeutral ||
        (session.pencil && session.strokes.isEmpty) ||
        document.activeLayerId != session.layerId) {
      cancelAdjustment();
      return;
    }
    session
      ..drawing = null
      ..showOriginal = false;
    try {
      await _rewriteActiveLayer((_, _, _) {}, replace: session.paint);
    } finally {
      if (identical(adjustment, session)) cancelAdjustment();
    }
  }

  bool _beginAdjustmentStroke(
    InkPoint point,
    Duration? time,
    bool simulatePressure,
  ) {
    final session = adjustment!;
    if (!session.pencil || session.showOriginal) return false;
    session.checkpoint();
    final settings = smoothing;
    _stabilizer = settings.active
        ? (StrokeStabilizer(settings)..start(point, time))
        : null;
    session.drawing = InkStroke(
      id: newId(),
      points: [point],
      color: 0xffffffff,
      size: size,
      opacity: opacity,
      eraser: tool == StudioTool.eraser,
      simulatePressure: simulatePressure,
      smoothing: brush.smoothing,
      thinning: brush.thinning,
    );
    inkChanges.notifyListeners();
    return true;
  }

  void _appendAdjustmentPoint(InkPoint point) {
    final session = adjustment!, drawing = session.drawing!;
    if (drawing.points.length >= 20000) return;
    session.drawing = _withPoints(drawing, [...drawing.points, point]);
    inkChanges.notifyListeners();
  }

  void _finishAdjustmentStroke() {
    final session = adjustment!;
    var drawing = session.drawing!;
    final tail = _stabilizer?.finish() ?? const <InkPoint>[];
    _stabilizer = null;
    if (tail.isNotEmpty) {
      drawing = _withPoints(drawing, [...drawing.points, ...tail]);
    }
    session
      ..drawing = null
      ..strokes.add(drawing);
    inkChanges.notifyListeners();
    _notify();
  }

  InkStroke _withPoints(InkStroke s, List<InkPoint> points) => InkStroke(
    id: s.id,
    points: points,
    color: s.color,
    size: s.size,
    opacity: s.opacity,
    eraser: s.eraser,
    simulatePressure: s.simulatePressure,
    smoothing: s.smoothing,
    thinning: s.thinning,
  );

  /// Repaints the active layer's own pixels (without its opacity, blend and
  /// mask, which it keeps) and [extra] on top, as one undo step.
  Future<void> _rewriteActiveLayer(
    void Function(Canvas canvas, ArtLayer layer, Rect bounds) extra, {
    bool invert = false,
    void Function(Canvas canvas, Rect bounds)? replace,
  }) async {
    if (!initialized || disposed || documentTransition) return;
    finishStroke();
    if (_busy) await settleStroke();
    final doc = document, layer = doc.activeLayer;
    if (layer.locked || disposed || documentTransition) return;
    documentTransition = true;
    _notify();
    try {
      final bounds = doc.dimensions.rect;
      final rendered = await renderTiles(doc.grid, (canvas) {
        if (invert) {
          canvas.saveLayer(
            bounds,
            Paint()
              ..colorFilter = const ColorFilter.matrix([
                -1, 0, 0, 0, 255, //
                0, -1, 0, 0, 255, //
                0, 0, -1, 0, 255, //
                0, 0, 0, 1, 0,
              ]),
          );
        }
        if (replace != null) {
          replace(canvas, bounds);
        } else {
          paintLayer(
            canvas,
            layer,
            FreehandBrushEngine(),
            doc.dimensions,
            rasterImages: rasters.images,
            applyOpacity: false,
            applyMask: false,
          );
        }
        if (invert) canvas.restore();
        extra(canvas, layer, bounds);
      });
      if (disposed) return;
      final raster = rendered.raster;
      final next = doc.copyWith(
        layers: [
          for (final l in doc.layers)
            l.id == layer.id
                ? l.copyWith(
                    raster: raster,
                    clearRaster: raster == null,
                    clearLegacyRaster: true,
                    clearText: true,
                    strokes: const [],
                  )
                : l,
        ],
      );
      _validateDocument(next);
      await _adoptTiles(rendered);
      if (disposed || !identical(doc, document)) return;
      documentTransition = false;
      _commit(next);
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    } finally {
      documentTransition = false;
      _notify();
    }
  }

  /// Makes layer [id] the one ColorDrop fills by (or stops it being so);
  /// there is at most one.
  void toggleReferenceLayer(String id) {
    if (_defer(() => toggleReferenceLayer(id))) return;
    final on =
        !(document.layers.where((l) => l.id == id).firstOrNull?.reference ??
            true);
    _commit(
      document.copyWith(
        layers: [
          for (final l in document.layers)
            l.copyWith(reference: on && l.id == id),
        ],
      ),
    );
  }

  /// Empties layer [id], keeping its settings.
  void clearLayer(String id) {
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer == null || layer.locked) return;
    updateLayer(
      id,
      (l) => l.copyWith(
        clearRaster: true,
        clearLegacyRaster: true,
        clearText: true,
        strokes: const [],
      ),
    );
  }

  /// Moves layer [id] to [index] in bottom-to-top order, keeping its
  /// group when it stays beside it.
  void reorderLayer(String id, int index) {
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer == null) return;
    placeLayer(id, index, group: layer.group);
  }

  /// Bakes layer [id] into the one below it, as it looks: its opacity,
  /// blend mode and mask, over the lower layer's pixels (and mask). The
  /// result keeps the lower layer's name, opacity and blend mode.
  Future<void> mergeDown(String id) async {
    final index = document.layers.indexWhere((l) => l.id == id);
    if (index < 1) return;
    await mergeLayers([document.layers[index - 1].id, id]);
  }

  /// Bakes layers [ids] into one, as they look, bottom to top. The result
  /// keeps the lowest layer's name, opacity and blend mode, and sits where
  /// the highest was (in its group).
  Future<void> mergeLayers(Iterable<String> ids) async {
    if (!initialized || disposed || documentTransition) return;
    finishStroke();
    if (_busy) await settleStroke();
    if (disposed || documentTransition) return;
    final snapshot = document;
    final wanted = ids.toSet();
    final merging = [
      for (final l in snapshot.layers)
        if (wanted.contains(l.id)) l,
    ];
    if (merging.length < 2) return;
    if (merging.any((l) => l.locked)) {
      throw StateError('A locked layer cannot be merged');
    }
    final lower = merging.first, top = merging.last;
    documentTransition = true;
    _notify();
    try {
      final engine = FreehandBrushEngine();
      final rendered = await renderTiles(snapshot.grid, (canvas) {
        paintLayer(
          canvas,
          lower,
          engine,
          snapshot.dimensions,
          rasterImages: rasters.images,
          applyOpacity: false,
        );
        for (final layer in merging.skip(1)) {
          if (!layer.visible) continue;
          paintLayer(
            canvas,
            layer,
            engine,
            snapshot.dimensions,
            rasterImages: rasters.images,
          );
        }
      });
      if (disposed) return;
      final raster = rendered.raster;
      final merged = lower.copyWith(
        raster: raster,
        clearRaster: raster == null,
        clearLegacyRaster: true,
        clearText: true,
        strokes: const [],
        clearMask: true,
        clipping: false,
        group: top.group,
        clearGroup: top.group == null,
      );
      final next = snapshot.copyWith(
        layers: [
          for (final l in snapshot.layers)
            if (l.id == top.id) merged else if (!wanted.contains(l.id)) l,
        ],
        activeLayerId: lower.id,
      );
      _validateDocument(next);
      await _adoptTiles(rendered);
      if (disposed) return;
      if (!identical(snapshot, document)) {
        throw StateError('The drawing changed during the merge');
      }
      documentTransition = false;
      selectedLayers = const {};
      _commit(next);
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    } finally {
      documentTransition = false;
      _notify();
    }
  }

  /// Layers chosen besides the active one (swiped right in the layers
  /// panel): grouping, merging and deleting act on all of them.
  Set<String> selectedLayers = const {};

  /// The active layer and the other chosen ones, bottom to top.
  List<ArtLayer> get chosenLayers => [
    for (final l in document.layers)
      if (l.id == document.activeLayerId || selectedLayers.contains(l.id)) l,
  ];

  void toggleLayerChoice(String id) {
    if (id == document.activeLayerId) return;
    final next = {...selectedLayers};
    if (!next.remove(id)) next.add(id);
    selectedLayers = next;
    _notify();
  }

  void clearLayerChoice() {
    if (selectedLayers.isEmpty) return;
    selectedLayers = const {};
    _notify();
  }

  /// The chosen layers (or [ids]) put together in a new group named
  /// [name], where the highest of them was.
  void groupLayers(String name, {Iterable<String>? ids}) {
    if (_defer(() => groupLayers(name, ids: ids))) return;
    final wanted = (ids ?? chosenLayers.map((l) => l.id)).toSet();
    final layers = document.layers;
    final top = layers.lastIndexWhere((l) => wanted.contains(l.id));
    if (top < 0) return;
    final group = LayerGroup(id: newId(), name: name);
    final moving = [
      for (final l in layers)
        if (wanted.contains(l.id)) l.copyWith(group: group.id),
    ];
    final rest = [
      for (final l in layers)
        if (!wanted.contains(l.id)) l,
    ];
    // Where the highest chosen layer was, among the others; never inside
    // another group.
    var at = layers.take(top).where((l) => !wanted.contains(l.id)).length;
    at = _outsideGroups(rest, at);
    selectedLayers = const {};
    _commit(
      document.copyWith(
        layers: [...rest.take(at), ...moving, ...rest.skip(at)],
        groups: [...document.groups, group],
      ),
    );
  }

  /// [index] in [layers], moved up past a group it would split.
  int _outsideGroups(List<ArtLayer> layers, int index) {
    while (index > 0 &&
        index < layers.length &&
        layers[index].group != null &&
        layers[index].group == layers[index - 1].group) {
      index++;
    }
    return index;
  }

  /// Group [id]'s layers stay where they are, ungrouped.
  void ungroup(String id) {
    if (_defer(() => ungroup(id))) return;
    _commit(
      document.copyWith(
        layers: [
          for (final l in document.layers)
            l.group == id ? l.copyWith(clearGroup: true) : l,
        ],
      ),
    );
  }

  void updateGroup(String id, LayerGroup Function(LayerGroup) change) {
    if (_defer(() => updateGroup(id, change))) return;
    _commit(
      document.copyWith(
        groups: [for (final g in document.groups) g.id == id ? change(g) : g],
      ),
    );
  }

  /// Folds group [id] in the layers panel (not an undo step).
  void toggleGroupCollapsed(String id) {
    if (_defer(() => toggleGroupCollapsed(id))) return;
    document = document.copyWith(
      groups: [
        for (final g in document.groups)
          g.id == id ? g.copyWith(collapsed: !g.collapsed) : g,
      ],
    );
    _changed();
  }

  /// Deletes group [id] with its layers (one layer always stays).
  void deleteGroup(String id) {
    if (_defer(() => deleteGroup(id))) return;
    final next = document.layers.where((l) => l.group != id).toList();
    if (next.isEmpty) return;
    _commit(
      document.copyWith(
        layers: next,
        activeLayerId: next.any((l) => l.id == document.activeLayerId)
            ? document.activeLayerId
            : next.last.id,
      ),
    );
  }

  /// Deletes the chosen layers (one layer always stays).
  void deleteChosenLayers() {
    if (_defer(deleteChosenLayers)) return;
    final gone = chosenLayers.map((l) => l.id).toSet();
    final next = document.layers.where((l) => !gone.contains(l.id)).toList();
    if (next.isEmpty) return;
    selectedLayers = const {};
    _commit(document.copyWith(layers: next, activeLayerId: next.last.id));
  }

  /// Moves layer [id] to [index] (bottom to top, among the others) into
  /// [group], or out of any; it stays out when that would split a group.
  void placeLayer(String id, int index, {String? group}) {
    if (_defer(() => placeLayer(id, index, group: group))) return;
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer == null) return;
    final rest = [...document.layers]..removeWhere((l) => l.id == id);
    final at = index.clamp(0, rest.length);
    bool fits(String? g) =>
        g == null ||
        (at > 0 && rest[at - 1].group == g) ||
        (at < rest.length && rest[at].group == g);
    final splits =
        at > 0 &&
        at < rest.length &&
        rest[at - 1].group != null &&
        rest[at - 1].group == rest[at].group &&
        rest[at].group != group;
    final target = fits(group) && !splits
        ? group
        : (splits ? rest[at].group : null);
    final moved = target == null
        ? layer.copyWith(clearGroup: true)
        : layer.copyWith(group: target);
    rest.insert(at, moved);
    if (identical(moved, layer) && document.layers.indexOf(layer) == at) return;
    _commit(document.copyWith(layers: rest));
  }

  /// Moves group [id] with its layers to [index] (bottom to top, among
  /// the other layers), never inside another group.
  void placeGroup(String id, int index) {
    if (_defer(() => placeGroup(id, index))) return;
    final moving = [
      for (final l in document.layers)
        if (l.group == id) l,
    ];
    if (moving.isEmpty) return;
    final rest = [
      for (final l in document.layers)
        if (l.group != id) l,
    ];
    final at = _outsideGroups(rest, index.clamp(0, rest.length));
    _commit(
      document.copyWith(
        layers: [...rest.take(at), ...moving, ...rest.skip(at)],
      ),
    );
  }

  void selectLayer(String id) {
    if (documentTransition) return;
    cancelTransform();
    cancelSelectionDraft();
    if (_defer(() => selectLayer(id))) return;
    if (!document.layers.any((l) => l.id == id)) return;
    selectedLayers = const {};
    document = document.copyWith(activeLayerId: id);
    _changed();
  }

  void updateLayer(String id, ArtLayer Function(ArtLayer) transform) {
    if (_defer(() => updateLayer(id, transform))) return;
    _commit(
      document.copyWith(
        layers: document.layers
            .map((l) => l.id == id ? transform(l) : l)
            .toList(),
      ),
    );
  }

  void deleteLayer(String id) {
    if (_defer(() => deleteLayer(id))) return;
    if (document.layers.length == 1) return;
    final next = document.layers.where((l) => l.id != id).toList();
    _commit(
      document.copyWith(
        layers: next,
        activeLayerId: document.activeLayerId == id
            ? next.last.id
            : document.activeLayerId,
      ),
    );
  }

  void moveLayer(String id, int delta) {
    final index = document.layers.indexWhere((l) => l.id == id);
    final next = index + delta;
    if (index < 0 || next < 0 || next >= document.layers.length) return;
    placeLayer(id, next, group: document.layers[index].group);
  }

  void renameDocument(String name) {
    if (name.trim().isEmpty) return;
    if (_defer(() => renameDocument(name))) return;
    _commit(document.copyWith(name: name.trim()));
  }

  Future<void> replaceDocument(ArtDocument next) async {
    if (documentTransition || disposed) return;
    stopPlayback();
    cancelTransform();
    cancelSelectionDraft();
    finishStroke();
    if (_busy) await settleStroke();
    if (documentTransition || disposed) return;
    documentTransition = true;
    _notify();
    try {
      await save();
      if (saveState == SaveState.failed || disposed) return;
      await rasters.prepare(documentRasters(next));
      final tiled = await _tileLegacyRasters(next);
      if (disposed) return;
      document = tiled;
      compositor.clear();
      selection = null;
      _undo.clear();
      _redo.clear();
      _changed();
    } finally {
      documentTransition = false;
      _notify();
    }
  }

  /// Opens [drawing] (read from another app's file) as a new drawing named
  /// [name]; layers past [maxLayers] are left out. Whether all fitted.
  Future<bool> openImported(ImportedDrawing drawing, String name) async {
    final doc = await documentFromImport(drawing, name, maxLayers: maxLayers);
    if (disposed) return false;
    await replaceDocument(doc);
    return drawing.layers.length <= maxLayers;
  }

  /// Field profiling only (pen log builds): a [dimensions] drawing of
  /// [layers] layers, each with a few large soft discs in its own colour,
  /// within the raster budget.
  Future<void> createStressDocument({
    CanvasSize dimensions = const CanvasSize(4096, 4096),
    int layers = 16,
  }) async {
    final random = math.Random(7);
    final grid = TileGrid(dimensions);
    final made = <ArtLayer>[];
    for (var i = 0; i < layers; i++) {
      final color = ui.Color.fromARGB(
        255,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      );
      final discs = [
        for (var d = 0; d < 3; d++)
          (
            Offset(
              random.nextDouble() * dimensions.width,
              random.nextDouble() * dimensions.height,
            ),
            dimensions.width * (.06 + random.nextDouble() * .05),
          ),
      ];
      final rendered = await renderTiles(grid, (canvas) {
        for (final (center, radius) in discs) {
          canvas.drawCircle(
            center,
            radius,
            ui.Paint()
              ..shader = ui.Gradient.radial(center, radius, [
                color,
                color.withValues(alpha: 0),
              ]),
          );
        }
      });
      await _adoptTiles(rendered);
      made.add(
        ArtLayer(id: newId(), name: 'Stress ${i + 1}', raster: rendered.raster),
      );
    }
    final doc = ArtDocument(
      id: newId(),
      name: 'Stress ${dimensions.width}×${dimensions.height}×$layers',
      layers: made,
      activeLayerId: made[layers ~/ 2].id,
      dimensions: dimensions,
    );
    checkRasterBudget(doc.dimensions, documentRasters(doc));
    await replaceDocument(doc);
  }

  /// Documents before version 5 hold one image placed to fit the canvas per
  /// raster layer; editing works on tiles, so they are converted on opening.
  /// A canvas-sized image is our lossless PNG and converts exactly.
  Future<ArtDocument> _tileLegacyRasters(ArtDocument doc) async {
    if (!doc.layers.any((l) => l.legacyRaster != null)) return doc;
    final layers = <ArtLayer>[];
    for (final layer in doc.layers) {
      final asset = layer.legacyRaster;
      if (asset == null) {
        layers.add(layer);
        continue;
      }
      final CanvasSize(:width, :height) = doc.dimensions;
      final exact = asset.width == width && asset.height == height
          ? await Isolate.run(() => decodeRgbaPng(asset.png, width, height))
          : null;
      final rendered = exact != null
          ? await tilesFromRgba(exact, doc.grid)
          : await placeRaster(asset, rasters.images[asset]!, doc.grid);
      await _adoptTiles(rendered);
      layers.add(
        layer.copyWith(
          raster: rendered.raster,
          clearRaster: rendered.raster == null,
          clearLegacyRaster: true,
        ),
      );
    }
    return doc.copyWith(layers: layers);
  }

  bool beginTransform() {
    if (!initialized || disposed || documentTransition) return false;
    if (transformDraft != null) return true;
    if (_defer(beginTransform)) return true;
    final layer = document.activeLayer;
    if (layer.locked || !layer.visible || layer.opacity == 0) return false;
    cancelSelectionDraft();
    var bounds = layerContentBounds(
      layer,
      FreehandBrushEngine(),
      document.dimensions,
      pixelBounds: rasters.pixelBounds,
    );
    if (bounds == null) return false;
    if (selection != null) bounds = bounds.intersect(selection!.bounds);
    bounds = Rect.fromLTRB(
      bounds.left.floorToDouble(),
      bounds.top.floorToDouble(),
      bounds.right.ceilToDouble(),
      bounds.bottom.ceilToDouble(),
    );
    if (bounds.isEmpty) return false;
    transformSelection = selection;
    _toolBeforeTransform = tool == StudioTool.selection
        ? StudioTool.brush
        : tool;
    transformLayerId = layer.id;
    transformDraft = LayerTransform(bounds: bounds);
    tool = StudioTool.transform;
    panel = null;
    if (transformMode == TransformMode.distort ||
        transformMode == TransformMode.warp) {
      setTransformMode(transformMode);
    }
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  void previewTransform(LayerTransform next) {
    final draft = transformDraft;
    if (draft == null || documentTransition || next.bounds != draft.bounds) {
      return;
    }
    transformDraft = next;
    inkChanges.notifyListeners();
    _notify();
  }

  /// Switches how handles act; Distort and Warp take over what is shown.
  void setTransformMode(TransformMode mode) {
    transformMode = mode;
    final draft = transformDraft;
    if (draft != null && !documentTransition) {
      final mesh = draft.mesh?.length;
      if (mode == TransformMode.distort && mesh != 4) {
        transformDraft = draft.toDistort(_transformSourceFor(draft));
      } else if (mode == TransformMode.warp && mesh != 16) {
        transformDraft = draft.toWarp(_transformSourceFor(draft));
      }
      inkChanges.notifyListeners();
    }
    _notify();
  }

  void setTransformFilter(FilterQuality filter) {
    final draft = transformDraft;
    if (draft != null) previewTransform(draft.copyWith(filter: filter));
  }

  /// The transformed layer's content inside the draft's bounds (and the
  /// selection), rendered once per transform.
  Image _transformSourceFor(LayerTransform draft) {
    final existing = _transformSource;
    if (existing != null) return existing;
    final layer = document.layers.firstWhere((l) => l.id == transformLayerId);
    final bounds = draft.bounds;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..translate(-bounds.left, -bounds.top);
    if (transformSelection case final region?) canvas.clipPath(region.path);
    paintLayer(
      canvas,
      layer,
      FreehandBrushEngine(),
      document.dimensions,
      rasterImages: rasters.images,
      applyOpacity: false,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      bounds.width.ceil(),
      bounds.height.ceil(),
    );
    picture.dispose();
    return _transformSource = image;
  }

  void _dropTransformSource() {
    _transformSource?.dispose();
    _transformSource = null;
  }

  void resetTransform() {
    final draft = transformDraft;
    if (draft == null) return;
    previewTransform(
      LayerTransform(bounds: draft.bounds, filter: draft.filter),
    );
    if (transformMode == TransformMode.distort ||
        transformMode == TransformMode.warp) {
      setTransformMode(transformMode);
    }
  }

  void cancelTransform() {
    if (transformDraft == null || documentTransition) return;
    _dropTransformSource();
    transformDraft = null;
    transformLayerId = null;
    transformSelection = null;
    tool = _toolBeforeTransform;
    inkChanges.notifyListeners();
    _notify();
  }

  Future<void> applyTransform() async {
    final draft = transformDraft;
    if (draft == null || disposed || documentTransition) return;
    if (draft.isIdentity) {
      cancelTransform();
      return;
    }
    finishStroke();
    if (_busy) await settleStroke();
    if (!identical(draft, transformDraft) || disposed) return;
    final region = transformSelection;
    await _rasterEdit(
      (layer) => rasterizeLayer(
        layer,
        document.grid,
        rasters.images,
        transform: draft,
        transformSelection: region,
      ),
    );
  }

  Future<void> deleteSelectedPixels() async {
    final region = selection;
    if (region == null || disposed || documentTransition) return;
    finishStroke();
    if (_busy) await settleStroke();
    if (!identical(region, selection) || disposed || documentTransition) {
      return;
    }
    await _rasterEdit(
      (layer) => rasterizeLayer(
        layer.copyWith(clearMask: true),
        document.grid,
        rasters.images,
        keepSelection: region.invert(),
      ),
      preserveMask: true,
    );
  }

  Future<void> _rasterEdit(
    Future<RenderedTiles> Function(ArtLayer) operation, {
    bool preserveMask = false,
  }) async {
    if (!initialized || disposed || documentTransition) return;
    final snapshot = document;
    final layer = snapshot.activeLayer;
    if (layer.locked || !layer.visible) {
      throw StateError('The layer is locked or hidden');
    }
    documentTransition = true;
    _notify();
    try {
      final rendered = await operation(layer);
      final raster = rendered.raster;
      if (disposed) return;
      final next = snapshot.copyWith(
        layers: snapshot.layers
            .map(
              (l) => l.id == layer.id
                  ? l.copyWith(
                      raster: raster,
                      clearRaster: raster == null,
                      clearLegacyRaster: true,
                      clearText: true,
                      strokes: [],
                      clearMask: !preserveMask,
                    )
                  : l,
            )
            .toList(),
      );
      _validateDocument(next);
      await _adoptTiles(rendered);
      if (disposed) return;
      if (!identical(snapshot, document)) {
        throw StateError('The drawing changed during the edit');
      }
      documentTransition = false;
      _dropTransformSource();
      transformDraft = null;
      transformLayerId = null;
      transformSelection = null;
      selection = null;
      cancelSelectionDraft();
      tool = tool == StudioTool.transform
          ? _toolBeforeTransform
          : StudioTool.brush;
      _commit(next);
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    } finally {
      documentTransition = false;
      _notify();
    }
  }

  /// The bounds a reopened file must meet, checked on the saved (manifest)
  /// form: tiles are referenced, never base64-encoded here.
  void _validateDocument(ArtDocument next) {
    final blobs = <String, Uint8List>{};
    ArtDocument.fromJson(next.toJson(blobs: blobs), blobs: blobs);
  }

  /// [reach]: how near (document pixels) a polygon corner must be to be
  /// taken and moved instead of placing a new one.
  bool beginSelection(Offset point, {double reach = 0}) {
    if (!initialized ||
        disposed ||
        documentTransition ||
        tool != StudioTool.selection ||
        panel != null) {
      return false;
    }
    if (selectionShape == SelectionShape.automatic) {
      _autoSeed = _clampSelectionPoint(point);
      _autoBase = selection;
      unawaited(_runAutoSelect());
      return true;
    }
    final p = _clampSelectionPoint(point);
    if (selectionShape == SelectionShape.polygon) {
      // On a corner: take it to move (or, the first, to close); elsewhere
      // a new corner.
      int? near;
      var best = reach;
      for (var i = 0; i < _selectionPoints.length; i++) {
        final d = (_selectionPoints[i] - p).distance;
        if (d <= best) {
          best = d;
          near = i;
        }
      }
      if (near != null) {
        _polygonHeld = near;
        _polygonAdded = false;
      } else {
        _selectionPoints.add(p);
        _polygonHeld = _selectionPoints.length - 1;
        _polygonAdded = true;
      }
      inkChanges.notifyListeners();
      _notify();
      return true;
    }
    _selectionPoints
      ..clear()
      ..add(p);
    inkChanges.notifyListeners();
    _notify();
    return true;
  }

  /// A polygon is being placed: its corners stay until it is closed.
  bool get selectionPolygonOpen =>
      selectionShape == SelectionShape.polygon && _selectionPoints.isNotEmpty;

  /// The polygon corner the finger holds, and whether this touch placed it.
  int? _polygonHeld;
  bool _polygonAdded = false;

  /// Takes back the corner the current touch placed (a second finger
  /// made it a pinch), keeping the polygon.
  void dropPolygonTouch() {
    if (_polygonAdded && _selectionPoints.isNotEmpty) {
      _selectionPoints.removeLast();
    }
    _polygonHeld = null;
    _polygonAdded = false;
    inkChanges.notifyListeners();
    _notify();
  }

  /// Automatic selection: how different a colour may be and still count.
  double autoThreshold = .12;
  Offset? _autoSeed;
  SelectionRegion? _autoBase;
  AutoSelectWorker? _autoWorker;
  Object? _autoWorkerFor;
  bool _autoRunning = false, _autoAgain = false;

  /// While choosing by tap: a new threshold re-selects from the same spot.
  void setAutoThreshold(double value) {
    autoThreshold = value.clamp(0.0, 1.0);
    _preferences?.setDouble('selection.threshold', autoThreshold);
    _notify();
    if (_autoSeed != null) unawaited(_runAutoSelect());
  }

  Future<void> _runAutoSelect() async {
    if (_autoRunning) {
      _autoAgain = true;
      return;
    }
    _autoRunning = true;
    try {
      do {
        _autoAgain = false;
        final seed = _autoSeed;
        if (seed == null || disposed) return;
        final worker = await _autoSelectWorker();
        final loops = await worker.select(
          seed.dx.floor().clamp(0, document.dimensions.width - 1),
          seed.dy.floor().clamp(0, document.dimensions.height - 1),
          autoThreshold,
        );
        if (disposed || _autoSeed == null) return;
        selection = _regionFromContours(loops, _autoBase);
        inkChanges.notifyListeners();
        _notify();
      } while (_autoAgain);
    } finally {
      _autoRunning = false;
    }
  }

  /// A worker holding the drawing as shown, made again when it changes.
  Future<AutoSelectWorker> _autoSelectWorker() async {
    final doc = document;
    final key = (doc.id, doc.revision, doc.backgroundHidden);
    final current = _autoWorker;
    if (current != null && _autoWorkerFor == key) return current;
    final recorder = PictureRecorder();
    paintDocument(
      Canvas(recorder),
      doc,
      FreehandBrushEngine(),
      rasterImages: rasters.images,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      doc.dimensions.width,
      doc.dimensions.height,
    );
    picture.dispose();
    final data = await image.toByteData(
      format: ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final worker = await AutoSelectWorker.start(
      data!.buffer.asUint8List(),
      doc.dimensions.width,
      doc.dimensions.height,
    );
    _autoWorker?.dispose();
    _autoWorker = worker;
    _autoWorkerFor = key;
    return worker;
  }

  /// [loops] (largest first) as a selection: a new one, or added to or
  /// taken from [base] as the selection mode says.
  SelectionRegion? _regionFromContours(
    List<Contour> loops,
    SelectionRegion? base,
  ) {
    if (loops.isEmpty) {
      return selectionMode == SelectionMode.replace ? null : base;
    }
    var region = base;
    try {
      if (base == null || selectionMode == SelectionMode.replace) {
        region = SelectionRegion.lasso(loops.first.$1);
        for (final (points, area) in loops.skip(1)) {
          if (region!.edits.length >= SelectionRegion.maxEdits) break;
          region = region.combine(
            area > 0 ? SelectionOp.add : SelectionOp.subtract,
            points,
          );
        }
      } else {
        final op = selectionMode == SelectionMode.add
            ? SelectionOp.add
            : SelectionOp.subtract;
        for (final (points, area) in loops) {
          if (area <= 0) continue;
          if (region!.edits.length >= SelectionRegion.maxEdits) break;
          region = region.combine(op, points);
        }
      }
    } on FormatException {
      // Too small or too many shapes: keep what was made.
    }
    return region;
  }

  /// Every layer redrawn onto a canvas of [size] through the affine map
  /// x' = a·x + c·y + tx, y' = b·x + d·y + ty; masks and saved selections
  /// follow it (their soft edges by [scale]). One undo step.
  Future<void> _reshapeCanvas(
    CanvasSize size,
    (double, double, double, double, double, double) affine, {
    double scale = 1,
  }) async {
    if (!initialized || disposed || documentTransition) return;
    if (!size.isValid) throw StateError('Canvas size out of range');
    finishStroke();
    if (_busy) await settleStroke();
    if (disposed || documentTransition) return;
    final (a, b, c, d, tx, ty) = affine;
    Offset map(Offset p) =>
        Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);
    final matrix = Float64List.fromList([
      a, b, 0, 0, //
      c, d, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1,
    ]);
    final snapshot = document;
    final grid = TileGrid(size);
    documentTransition = true;
    _notify();
    try {
      final layers = <ArtLayer>[];
      for (final layer in snapshot.layers) {
        final rendered = await renderTiles(grid, (canvas) {
          canvas.transform(matrix);
          paintLayer(
            canvas,
            layer,
            FreehandBrushEngine(),
            snapshot.dimensions,
            rasterImages: rasters.images,
            applyOpacity: false,
            applyMask: false,
          );
        });
        if (disposed) return;
        await _adoptTiles(rendered);
        final raster = rendered.raster;
        final mask = layer.mask?.mapped(map, featherScale: scale);
        layers.add(
          layer.copyWith(
            raster: raster,
            clearRaster: raster == null,
            clearLegacyRaster: true,
            clearText: true,
            strokes: const [],
            mask: mask,
            clearMask: mask == null,
          ),
        );
      }
      final next = snapshot.copyWith(
        dimensions: size,
        layers: layers,
        savedSelections: [
          for (final r in snapshot.savedSelections)
            ?r.mapped(map, featherScale: scale),
        ],
      );
      _validateDocument(next);
      if (!identical(snapshot, document)) {
        throw StateError('The drawing changed while the canvas changed');
      }
      documentTransition = false;
      selection = null;
      previousSelection = null;
      compositor.clear();
      _commit(next);
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    } finally {
      documentTransition = false;
      _notify();
    }
  }

  /// The canvas cut (or grown) to [rect], in canvas pixels.
  Future<void> cropCanvas(Rect rect) => _reshapeCanvas(
    CanvasSize(rect.width.round(), rect.height.round()),
    (1, 0, 0, 1, -rect.left.roundToDouble(), -rect.top.roundToDouble()),
  );

  /// The whole drawing scaled to [size].
  Future<void> resampleCanvas(CanvasSize size) {
    final from = document.dimensions;
    final sx = size.width / from.width, sy = size.height / from.height;
    return _reshapeCanvas(size, (
      sx,
      0,
      0,
      sy,
      0,
      0,
    ), scale: math.sqrt(sx * sy));
  }

  /// The canvas turned a quarter, clockwise or not.
  Future<void> rotateCanvas({required bool clockwise}) {
    final from = document.dimensions;
    final size = CanvasSize(from.height, from.width);
    return clockwise
        ? _reshapeCanvas(size, (0, 1, -1, 0, from.height.toDouble(), 0))
        : _reshapeCanvas(size, (0, -1, 1, 0, 0, from.width.toDouble()));
  }

  /// The canvas mirrored, sideways or upside down.
  Future<void> flipCanvas({required bool horizontal}) {
    final from = document.dimensions;
    return horizontal
        ? _reshapeCanvas(from, (-1, 0, 0, 1, from.width.toDouble(), 0))
        : _reshapeCanvas(from, (1, 0, 0, -1, 0, from.height.toDouble()));
  }

  /// Crop & Resize being set: the area to keep (canvas pixels, past the
  /// edges to grow it), or with [resample] the size to scale the drawing to.
  ({Rect rect, bool resample, CanvasSize target})? canvasCrop;

  void startCanvasCrop() {
    if (!initialized || documentTransition) return;
    finishStroke();
    cancelAdjustment();
    cancelLiquify();
    cancelClone();
    cancelTransform();
    cancelSelectionDraft();
    final size = document.dimensions;
    canvasCrop = (rect: size.rect, resample: false, target: size);
    panel = null;
    inkChanges.notifyListeners();
    _notify();
  }

  void setCanvasCrop({Rect? rect, bool? resample, CanvasSize? target}) {
    final crop = canvasCrop;
    if (crop == null) return;
    canvasCrop = (
      rect: rect ?? crop.rect,
      resample: resample ?? crop.resample,
      target: target ?? crop.target,
    );
    inkChanges.notifyListeners();
    _notify();
  }

  void cancelCanvasCrop() {
    if (canvasCrop == null) return;
    canvasCrop = null;
    inkChanges.notifyListeners();
    _notify();
  }

  Future<void> applyCanvasCrop() async {
    final crop = canvasCrop;
    if (crop == null) return;
    canvasCrop = null;
    _notify();
    final size = document.dimensions;
    if (crop.resample) {
      if (crop.target != size) await resampleCanvas(crop.target);
    } else if (crop.rect != size.rect) {
      await cropCanvas(crop.rect);
    }
  }

  /// Turns or flips the canvas from Crop & Resize, which starts afresh.
  Future<void> reshapeFromCrop(Future<void> Function() change) async {
    await change();
    if (canvasCrop != null) {
      final size = document.dimensions;
      canvasCrop = (rect: size.rect, resample: false, target: size);
      inkChanges.notifyListeners();
      _notify();
    }
  }

  void setDpi(int dpi) {
    if (dpi < 1 || dpi > 9600 || dpi == document.dpi) return;
    if (_defer(() => setDpi(dpi))) return;
    _commit(document.copyWith(dpi: dpi));
  }

  /// Selects layer [id]'s pixels (Procreate's Select Contents).
  Future<void> selectLayerContents(String id) async {
    final layer = document.layers.where((l) => l.id == id).firstOrNull;
    if (layer == null || disposed || documentTransition) return;
    final dims = document.dimensions;
    final pixels = await renderNativeBase(layer, document.grid, rasters.images);
    final loops = await contentContoursOffThread(
      pixels.rgba,
      dims.width,
      dims.height,
    );
    if (disposed) return;
    final previous = selectionMode;
    selectionMode = SelectionMode.replace;
    final region = _regionFromContours(loops, null);
    selectionMode = previous;
    setSelection(region);
  }

  Offset _clampSelectionPoint(Offset p) => Offset(
    p.dx.clamp(0, document.dimensions.width.toDouble()),
    p.dy.clamp(0, document.dimensions.height.toDouble()),
  );
  void appendSelection(Offset point) {
    if (selectionShape == SelectionShape.automatic ||
        !selectionDrawing ||
        tool != StudioTool.selection ||
        documentTransition) {
      return;
    }
    final p = _clampSelectionPoint(point);
    // A polygon: the corner held follows the finger.
    if (selectionShape == SelectionShape.polygon) {
      final held = _polygonHeld;
      if (held != null && held < _selectionPoints.length) {
        _selectionPoints[held] = p;
        inkChanges.notifyListeners();
      }
      return;
    }
    if (selectionShape != SelectionShape.freehand) {
      if (_selectionPoints.length == 1) {
        _selectionPoints.add(p);
      } else {
        _selectionPoints[1] = p;
      }
    } else if ((p - _selectionPoints.last).distance >= 1) {
      if (_selectionPoints.length < 4096) {
        _selectionPoints.add(p);
      } else {
        _selectionPoints[_selectionPoints.length - 1] = p;
      }
    }
    inkChanges.notifyListeners();
  }

  /// The shape being drawn, as the polygon it will become.
  List<Offset> get selectionDraftShape {
    final points = _selectionPoints;
    if (points.isEmpty) return const [];
    final rect = Rect.fromPoints(points.first, points.last);
    return switch (selectionShape) {
      SelectionShape.rectangle => SelectionRegion.rectanglePoints(rect),
      SelectionShape.ellipse => SelectionRegion.ellipsePoints(rect),
      SelectionShape.freehand ||
      SelectionShape.polygon ||
      SelectionShape.automatic => List.unmodifiable(points),
    };
  }

  /// Ends the shape being drawn. A polygon stays open until a [tap] on its
  /// first corner (or [closeSelectionPolygon]).
  void finishSelection({bool tap = false}) {
    if (selectionShape == SelectionShape.automatic) {
      _autoSeed = null;
      if (_autoBase != null) previousSelection = _autoBase;
      _notify();
      _colorFillSelection();
      return;
    }
    if (!selectionDrawing) return;
    if (selectionShape == SelectionShape.polygon) {
      final closing =
          tap &&
          !_polygonAdded &&
          _polygonHeld == 0 &&
          _selectionPoints.length >= 3;
      _polygonHeld = null;
      _polygonAdded = false;
      if (!closing) {
        inkChanges.notifyListeners();
        _notify();
        return;
      }
    }
    final shape = selectionDraftShape;
    final current = selection;
    if (current != null) previousSelection = current;
    try {
      selection = current != null && selectionMode != SelectionMode.replace
          ? current.combine(
              selectionMode == SelectionMode.add
                  ? SelectionOp.add
                  : SelectionOp.subtract,
              shape,
            )
          : SelectionRegion.lasso(shape);
    } on FormatException {
      // A too-small shape leaves an existing selection as it was.
      if (selectionMode == SelectionMode.replace) selection = null;
    }
    cancelSelectionDraft();
    _notify();
    _colorFillSelection();
  }

  /// Closes the polygon being placed (three corners or more).
  void closeSelectionPolygon() {
    if (!selectionPolygonOpen || _selectionPoints.length < 3) return;
    _polygonHeld = 0;
    _polygonAdded = false;
    finishSelection(tap: true);
  }

  void setSelectionMode(SelectionMode mode) {
    if (documentTransition) return;
    cancelSelectionDraft();
    selectionMode = mode;
    _notify();
  }

  /// Softens the selection's edge over [pixels] (0 for a hard edge).
  void featherSelection(double pixels) {
    final current = selection;
    if (current == null || documentTransition) return;
    setSelection(
      current.withFeather(pixels.clamp(0, SelectionRegion.maxFeather)),
    );
  }

  void cancelSelectionDraft() {
    if (_autoSeed != null) {
      _autoSeed = null;
      selection = _autoBase;
      inkChanges.notifyListeners();
      _notify();
    }
    _polygonHeld = null;
    _polygonAdded = false;
    if (_selectionPoints.isEmpty) return;
    _selectionPoints.clear();
    inkChanges.notifyListeners();
    _notify();
  }

  void setSelectionShape(SelectionShape shape) {
    if (documentTransition) return;
    cancelSelectionDraft();
    selectionShape = shape;
    _notify();
  }

  void setSelection(SelectionRegion? region) {
    if (documentTransition) return;
    finishStroke();
    cancelTransform();
    cancelSelectionDraft();
    _rememberSelection(region);
    selection = region;
    inkChanges.notifyListeners();
    _notify();
  }

  /// The selection before the current one (or before Deselect).
  SelectionRegion? previousSelection;

  void _rememberSelection(SelectionRegion? next) {
    final current = selection;
    if (current != null && !identical(current, next)) {
      previousSelection = current;
    }
  }

  /// Brings the previous selection back (Procreate: tap Selection again).
  void restorePreviousSelection() {
    final previous = previousSelection;
    if (previous == null) return;
    setSelection(previous);
  }

  /// Keeps the selection in the drawing, to load again later.
  void saveSelection() {
    final region = selection;
    if (region == null ||
        document.savedSelections.length >= ArtDocument.maxSavedSelections ||
        document.savedSelections.any((r) => identical(r, region))) {
      return;
    }
    if (_defer(saveSelection)) return;
    _commit(
      document.copyWith(savedSelections: [...document.savedSelections, region]),
    );
  }

  void loadSelection(int index) {
    final saved = document.savedSelections;
    if (index < 0 || index >= saved.length) return;
    setSelection(saved[index]);
  }

  void deleteSavedSelection(int index) {
    final saved = document.savedSelections;
    if (index < 0 || index >= saved.length) return;
    if (_defer(() => deleteSavedSelection(index))) return;
    _commit(document.copyWith(savedSelections: [...saved]..removeAt(index)));
  }

  /// Color Fill: each shape drawn is filled with the current colour.
  bool selectionColorFill = false;

  void toggleSelectionColorFill() {
    selectionColorFill = !selectionColorFill;
    _notify();
  }

  void _colorFillSelection() {
    if (selectionColorFill && selection != null) {
      unawaited(fillActiveLayer());
    }
  }

  void invertSelection() {
    if (selection != null) setSelection(selection!.invert());
  }

  bool maskLayerFromSelection() {
    final region = selection;
    if (region == null ||
        documentTransition ||
        document.activeLayer.locked ||
        !document.activeLayer.visible) {
      return false;
    }
    if (_defer(maskLayerFromSelection)) return true;
    final next = document.copyWith(
      layers: document.layers
          .map(
            (l) =>
                l.id == document.activeLayerId ? l.copyWith(mask: region) : l,
          )
          .toList(),
    );
    _validateDocument(next);
    selection = null;
    tool = StudioTool.brush;
    _commit(next);
    return true;
  }

  /// The selection and its surroundings for generative fill, scaled for
  /// the model (see [generativeFillArea]); the result goes back over the
  /// same area, masked by the selection.
  /// The selection's surroundings, outlined, for a vision model to see.
  Future<Uint8List?> captureSelectionPreview() async {
    final region = selection;
    if (region == null || !initialized || disposed || documentTransition) {
      return null;
    }
    finishStroke();
    if (_busy) await settleStroke();
    return renderSelectionPreview(document, rasters.images, region);
  }

  Future<AiCanvasInput> captureGenerativeFill() async {
    if (!initialized || disposed || documentTransition) {
      throw StateError('Drawing unavailable');
    }
    finishStroke();
    if (_busy) await settleStroke();
    if (disposed || documentTransition) {
      throw StateError('Drawing unavailable');
    }
    final snapshot = document;
    final region = selection;
    if (region == null || region.bounds.isEmpty) {
      throw const FormatException('Select a region first');
    }
    final bounds = region.bounds.intersect(snapshot.dimensions.rect);
    if (bounds.isEmpty) {
      throw const FormatException('The selection is outside the canvas');
    }
    final (:area, :width, :height) = generativeFillArea(
      bounds,
      snapshot.dimensions,
    );
    final image = await renderGenerativeFill(
      snapshot,
      rasters.images,
      region,
      area,
      width,
      height,
    );
    return AiCanvasInput(
      documentId: snapshot.id,
      revision: snapshot.revision,
      layerId: snapshot.activeLayerId,
      png: image,
      selection: region,
      area: area,
      width: width,
      height: height,
    );
  }

  /// Adds [bytes] as a new layer, fitted to the canvas or over [source]'s
  /// area and masked by its selection; with [replace], swaps the pixels of
  /// that layer instead (a generative fill variation). Returns the layer id.
  Future<String> addImageLayer(
    Uint8List bytes,
    String name, {
    String? expectedDocumentId,
    AiCanvasInput? source,
    String? replace,
    Rect? at,
    bool private = false,
  }) async {
    if (!initialized || disposed || documentTransition) {
      throw StateError('Document unavailable');
    }
    final id = source?.documentId ?? expectedDocumentId ?? document.id;
    void validateTarget() {
      if (disposed ||
          documentTransition ||
          document.id != id ||
          (source != null &&
              !document.layers.any((l) => l.id == source.layerId))) {
        throw StateError('The source drawing or layer is no longer available');
      }
    }

    validateTarget();
    finishStroke();
    if (_busy) await settleStroke();
    validateTarget();
    final asset = await importRaster(bytes);
    if (disposed || documentTransition || document.id != id) {
      throw StateError('The drawing changed while the image was loading');
    }
    validateTarget();
    await rasters.prepare([asset]);
    final RenderedTiles placed;
    try {
      placed = await placeRaster(
        asset,
        rasters.images[asset]!,
        document.grid,
        target: source?.area ?? at,
      );
    } finally {
      _retainRasterHistory();
    }
    if (disposed || documentTransition || document.id != id) {
      throw StateError('The drawing changed while the image was loading');
    }
    finishStroke();
    final layer = ArtLayer(
      id: newId(),
      name: name,
      raster: placed.raster,
      mask: source?.selection,
      private: private,
    );
    ArtDocument withLayer(ArtDocument doc) =>
        replace != null && doc.layers.any((l) => l.id == replace)
        ? doc.copyWith(
            layers: [
              for (final l in doc.layers)
                l.id == replace ? l.copyWith(raster: placed.raster) : l,
            ],
          )
        : doc.copyWith(layers: [...doc.layers, layer], activeLayerId: layer.id);
    final next = withLayer(document);
    // Apply the same bounds to UI imports and reopened files, before changing artwork.
    _validateDocument(next);
    await _adoptTiles(placed);
    if (disposed || documentTransition || document.id != id) {
      _retainRasterHistory();
      throw StateError('The drawing changed while the image was loading');
    }
    try {
      validateTarget();
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    }
    // Keep strokes and layer changes made during native image decoding, and
    // validate the actual snapshot that will be committed.
    finishStroke();
    if (_busy) await settleStroke();
    try {
      validateTarget();
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    }
    final current = withLayer(document);
    try {
      _validateDocument(current);
      _commit(current);
    } catch (_) {
      _retainRasterHistory();
      rethrow;
    }
    return current.layers.any((l) => l.id == replace) ? replace! : layer.id;
  }

  /// History steps around the current drawing whose pixels stay decoded, so
  /// a single undo or redo is instant. Older steps keep only PNG bytes.
  static const decodedUndoSteps = 2, decodedRedoSteps = 1;

  /// Compressed bytes history may hold; the current drawing is always kept.
  static const historyPngBudget = 128 * 1024 * 1024;

  void _retainRasterHistory() {
    Set<RasterAsset> retained() =>
        [document, ..._undo, ..._redo].expand(documentRasters).toSet();
    var assets = retained();
    while (assets.fold<int>(0, (n, r) => n + r.png.length) > historyPngBudget &&
        (_undo.isNotEmpty || _redo.isNotEmpty)) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
      assets = retained();
    }
    final decoded = {
      ...documentRasters(document),
      for (final step in _undo.reversed.take(decodedUndoSteps))
        ...documentRasters(step),
      for (final step in _redo.reversed.take(decodedRedoSteps))
        ...documentRasters(step),
    };
    rasters.retain(decoded, assets);
    // Decode the next undo/redo targets in the background.
    final missing = decoded.where((r) => !rasters.images.containsKey(r));
    if (missing.isNotEmpty && !disposed) {
      unawaited(rasters.prepare(missing.toList()).catchError((Object _) {}));
    }
  }

  void _changed() {
    _retainRasterHistory();
    saveState = SaveState.pending;
    _saveGeneration++;
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 2), save);
    inkChanges.notifyListeners();
    _notify();
    _timelapseFrame();
  }

  /// Time-lapse: recorded or not (a preference), and where frames go
  /// (null records nothing, as in tests without a folder).
  bool timelapseOn = true;
  TimelapseStore? timelapse;
  String? _framesFor;
  int _nextFrame = 0;
  (String, int)? _lastFrame;
  Timer? _frameTimer;
  bool _capturing = false;

  /// Forgets this drawing's frames; recording starts over.
  Future<void> clearTimelapse() async {
    await timelapse?.delete(document.id);
    _framesFor = null;
    _lastFrame = null;
  }

  void setTimelapseOn(bool on) {
    timelapseOn = on;
    _preferences?.setBool('timelapse.on', on);
    _notify();
  }

  /// A frame a moment after the drawing changes: one per stroke or edit,
  /// not one per point.
  void _timelapseFrame() {
    if (!timelapseOn || timelapse == null || !initialized || disposed) return;
    if (_lastFrame == (document.id, document.revision)) return;
    _frameTimer?.cancel();
    _frameTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(captureTimelapseFrame());
    });
  }

  /// Records the drawing as it is now, without its private layers, at the
  /// video size its first frame set.
  Future<void> captureTimelapseFrame() async {
    final store = timelapse;
    if (store == null || disposed) return;
    if (_capturing) {
      _timelapseFrame();
      return;
    }
    _capturing = true;
    try {
      final doc = document;
      if (_lastFrame == (doc.id, doc.revision)) return;
      if (_framesFor != doc.id) {
        _framesFor = doc.id;
        _nextFrame = (await store.frames(doc.id)).length;
      }
      var size = await store.size(doc.id);
      if (size == null) {
        size = timelapseSize(doc.dimensions.width, doc.dimensions.height);
        await store.setSize(doc.id, size.$1, size.$2);
      }
      final (width, height) = size;
      final shown = [
        for (final l in doc.layers)
          if (!l.private) l,
      ];
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = const Color(0xffffffff),
        );
      final scale = math.min(
        width / doc.dimensions.width,
        height / doc.dimensions.height,
      );
      canvas
        ..translate(
          (width - doc.dimensions.width * scale) / 2,
          (height - doc.dimensions.height * scale) / 2,
        )
        ..scale(scale);
      if (shown.isEmpty) {
        canvas.drawRect(
          doc.dimensions.rect,
          Paint()..color = Color(doc.background),
        );
      } else {
        paintDocument(
          canvas,
          doc.copyWith(layers: shown, activeLayerId: shown.last.id),
          FreehandBrushEngine(),
          rasterImages: rasters.images,
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      if (data == null || disposed) return;
      final pixels = RgbaPixels(width, height, data.buffer.asUint8List());
      final jpeg = await Isolate.run(() => encodeJpeg(pixels, quality: 85));
      if (_framesFor != doc.id) return;
      await store.add(doc.id, _nextFrame++, jpeg);
      _lastFrame = (doc.id, doc.revision);
    } on Object {
      // A frame that could not be made is skipped; the next change tries.
    } finally {
      _capturing = false;
    }
  }

  Future<void> save() {
    _autosave?.cancel();
    if (!initialized) return Future.value();
    final snapshot = document;
    final generation = _saveGeneration;
    final library = {
      'version': 1,
      'brushes': brushes.map((b) => b.toJson()).toList(),
      'palettes': palettes.map((p) => p.toJson()).toList(),
    };
    final dirtyLibrary = libraryDirty && !libraryLocked;
    final task = _saveTail.then((_) async {
      saveState = SaveState.saving;
      _notify();
      try {
        await storage.saveDocument(snapshot);
        if (dirtyLibrary) await storage.saveLibrary(library);
        if (generation == _saveGeneration) {
          saveState = SaveState.saved;
          libraryDirty = false;
        } else {
          saveState = SaveState.pending;
        }
        error = null;
      } catch (e) {
        saveState = SaveState.failed;
        error = e.toString();
      }
      _notify();
    });
    _saveTail = task.catchError((Object _) {});
    return task;
  }

  void _editBrushes(List<BrushPreset> next) {
    if (libraryLocked) throw StateError('The library could not be read');
    brushes = next;
    libraryDirty = true;
    _changed();
  }

  /// Brush Studio's Done: [preset] replaces the brush with its id (and is
  /// the brush in use if that one was).
  void saveBrush(BrushPreset preset) {
    _editBrushes([for (final b in brushes) b.id == preset.id ? preset : b]);
    if (brush.id == preset.id) selectBrush(preset);
  }

  /// A built-in brush back as it shipped.
  void resetBrush(String id) {
    final original = initialBrushes.where((b) => b.id == id).firstOrNull;
    if (original != null) saveBrush(original);
  }

  bool isEdited(BrushPreset preset) {
    final original = initialBrushes.where((b) => b.id == preset.id).firstOrNull;
    return original != null &&
        jsonEncode(original.toJson()) != jsonEncode(preset.toJson());
  }

  void duplicateBrush(String id, String name) {
    final index = brushes.indexWhere((b) => b.id == id);
    if (index < 0) return;
    _editBrushes([
      ...brushes.take(index + 1),
      brushes[index].copyWith(id: newId(), name: name),
      ...brushes.skip(index + 1),
    ]);
  }

  void renameBrush(String id, String name) => _editBrushes([
    for (final b in brushes) b.id == id ? b.copyWith(name: name) : b,
  ]);

  /// Deletes a brush; one always stays, and the brush in use moves on.
  void deleteBrush(String id) {
    if (brushes.length < 2) return;
    final next = [
      for (final b in brushes)
        if (b.id != id) b,
    ];
    _editBrushes(next);
    if (brush.id == id) selectBrush(next.first);
  }

  /// Deletes the brushes [ids] in one go; at least one brush stays.
  void deleteBrushes(Set<String> ids) {
    var next = [
      for (final b in brushes)
        if (!ids.contains(b.id)) b,
    ];
    if (next.isEmpty) next = [brushes.first];
    if (next.length == brushes.length) return;
    _editBrushes(next);
    if (!next.any((b) => b.id == brush.id)) selectBrush(next.first);
  }

  void moveBrush(int from, int to) {
    final next = [...brushes];
    final moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    _editBrushes(next);
  }

  void addBrushes(List<BrushPreset> added) {
    if (libraryLocked) throw StateError('The library could not be read');
    if (added.isEmpty) return;
    brushes = [...brushes, ...added.map((b) => b.copyWith(id: newId()))];
    libraryDirty = true;
    _changed();
  }

  /// One library change for a whole import: all palettes or none.
  void addPalettes(List<ColorPalette> added) {
    if (libraryLocked) throw StateError('The library could not be read');
    if (added.isEmpty) return;
    palettes = [
      ...palettes,
      for (final palette in added)
        ColorPalette(id: newId(), name: palette.name, colors: palette.colors),
    ];
    libraryDirty = true;
    _changed();
  }

  void addPalette(ColorPalette palette) {
    if (libraryLocked) throw StateError('The library could not be read');
    palettes = [
      ...palettes,
      ColorPalette(id: newId(), name: palette.name, colors: palette.colors),
    ];
    libraryDirty = true;
    _changed();
  }

  /// The palette shown first, its swatches under the colour views.
  String? defaultPaletteId;

  /// Palettes as cards: bigger swatches with their hex codes.
  bool paletteCards = false;

  void _editPalettes(List<ColorPalette> next) {
    if (libraryLocked) throw StateError('The library could not be read');
    palettes = next;
    libraryDirty = true;
    _changed();
  }

  void _editPalette(String id, ColorPalette Function(ColorPalette) change) =>
      _editPalettes([for (final p in palettes) p.id == id ? change(p) : p]);

  /// A new, empty palette (named [name]); returns its id.
  String createPalette(String name) {
    final palette = ColorPalette(id: newId(), name: name, colors: const []);
    _editPalettes([...palettes, palette]);
    return palette.id;
  }

  void renamePalette(String id, String name) =>
      _editPalette(id, (p) => p.copyWith(name: name));

  void duplicatePalette(String id, String name) {
    final index = palettes.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _editPalettes([
      ...palettes.take(index + 1),
      ColorPalette(id: newId(), name: name, colors: palettes[index].colors),
      ...palettes.skip(index + 1),
    ]);
  }

  void deletePalette(String id) {
    if (defaultPaletteId == id) setDefaultPalette(null);
    _editPalettes([
      for (final p in palettes)
        if (p.id != id) p,
    ]);
  }

  void setDefaultPalette(String? id) {
    defaultPaletteId = id;
    if (id == null) {
      _preferences?.remove('palette.default');
    } else {
      _preferences?.setString('palette.default', id);
    }
    _notify();
  }

  void setPaletteCards(bool cards) {
    paletteCards = cards;
    _preferences?.setBool('palette.cards', cards);
    _notify();
  }

  /// [color] into palette [id], at [index] (the end when null).
  void addSwatch(String id, int color, {int? index}) => _editPalette(id, (p) {
    final colors = [...p.colors];
    colors.insert((index ?? colors.length).clamp(0, colors.length), color);
    return p.copyWith(colors: colors);
  });

  void replaceSwatch(String id, int index, int color) => _editPalette(
    id,
    (p) => p.copyWith(colors: [...p.colors]..[index] = color),
  );

  void removeSwatch(String id, int index) => _editPalette(
    id,
    (p) => p.copyWith(colors: [...p.colors]..removeAt(index)),
  );

  void moveSwatch(String id, int from, int to) => _editPalette(id, (p) {
    final colors = [...p.colors];
    final color = colors.removeAt(from);
    colors.insert(to.clamp(0, colors.length), color);
    return p.copyWith(colors: colors);
  });

  /// Palettes in order of showing: the default first.
  List<ColorPalette> get orderedPalettes => [
    ...palettes.where((p) => p.id == defaultPaletteId),
    ...palettes.where((p) => p.id != defaultPaletteId),
  ];

  void setLanguage(String value) {
    locale = value == 'system' ? null : Locale(value);
    _preferences?.setString('language', value);
    if (!disposed) appearance.notifyListeners();
    _notify();
  }

  void setTheme(ThemeMode value) {
    themeMode = value;
    _preferences?.setString('theme', value.name);
    if (!disposed) appearance.notifyListeners();
    _notify();
  }

  /// Accessibility: interface text size (1–1.6), the picked colour's name
  /// said and shown, feedback sounds, and the single-touch gesture pad.
  double textScale = 1;
  bool colorNames = false, feedbackSounds = false, singleTouch = false;

  /// The pad's mode: a one-finger drag on the canvas moves, zooms or turns
  /// it instead of drawing.
  SingleTouchMode? singleTouchMode;

  /// A colour just picked (eyedropper or swatch): a running count and the
  /// colour, for its name to be said.
  final colorPicked = ValueNotifier<(int, int)?>(null);

  void _loadAccessibility(SharedPreferences? p) {
    textScale = (p?.getDouble('a11y.textScale') ?? 1).clamp(1, 1.6);
    colorNames = p?.getBool('a11y.colorNames') ?? false;
    feedbackSounds = p?.getBool('a11y.sounds') ?? false;
    singleTouch = p?.getBool('a11y.singleTouch') ?? false;
  }

  void setTextScale(double value) {
    textScale = value.clamp(1, 1.6);
    _preferences?.setDouble('a11y.textScale', textScale);
    if (!disposed) appearance.notifyListeners();
    _notify();
  }

  void setColorNames(bool on) {
    colorNames = on;
    _preferences?.setBool('a11y.colorNames', on);
    _notify();
  }

  void setFeedbackSounds(bool on) {
    feedbackSounds = on;
    _preferences?.setBool('a11y.sounds', on);
    _notify();
  }

  void setSingleTouch(bool on) {
    singleTouch = on;
    if (!on) singleTouchMode = null;
    _preferences?.setBool('a11y.singleTouch', on);
    _notify();
  }

  void setSingleTouchMode(SingleTouchMode? mode) {
    singleTouchMode = singleTouchMode == mode ? null : mode;
    _notify();
  }

  /// A colour chosen from a palette or picked up: [color] is used, and its
  /// name said when that is on.
  void pickedColor(int value) {
    selectColor(value);
    _choosingColor = false;
    colorPicked.value = ((colorPicked.value?.$1 ?? 0) + 1, value);
  }

  void setSidebar(bool value) {
    rightSidebar = value;
    _preferences?.setBool('rightSidebar', value);
    _notify();
  }

  void setStreamLine(double value) {
    final amount = value.clamp(0.0, 1.0);
    if (amount == 0) {
      _streamLine.remove(brush.id);
    } else {
      _streamLine[brush.id] = amount;
    }
    _preferences?.setString('smoothing.streamLine', jsonEncode(_streamLine));
    _notify();
  }

  void setSmoothing({
    double? stabilization,
    double? motionFilter,
    double? expression,
  }) {
    if (stabilization != null) {
      this.stabilization = stabilization.clamp(0, 1);
      _preferences?.setDouble('smoothing.stabilization', this.stabilization);
    }
    if (motionFilter != null) {
      this.motionFilter = motionFilter.clamp(0, 1);
      _preferences?.setDouble('smoothing.motionFilter', this.motionFilter);
    }
    if (expression != null) {
      motionExpression = expression.clamp(0, 1);
      _preferences?.setDouble('smoothing.expression', motionExpression);
    }
    _notify();
  }

  /// Starts sampling the canvas as it looks, paper included. The composite
  /// is rendered once per pick, after pending strokes have committed.
  bool beginPick(Offset point) {
    if (!initialized || disposed || documentTransition) return false;
    cancelPick();
    pickPoint = point;
    final epoch = _pickEpoch;
    unawaited(_loadPickPixels(epoch));
    inkChanges.notifyListeners();
    return true;
  }

  Future<void> _loadPickPixels(int epoch) async {
    try {
      finishStroke();
      if (_busy) await settleStroke();
      if (epoch != _pickEpoch || disposed) return;
      // What is on screen: with Page Assist, the page shown.
      final pixels = await renderDocumentRgba(shownDocument, rasters.images);
      if (epoch != _pickEpoch || disposed) return;
      _pickPixels = pixels;
      _samplePick();
      if (_pickReleased) _applyPick();
    } catch (_) {
      if (epoch == _pickEpoch) cancelPick();
    }
  }

  void movePick(Offset point) {
    if (pickPoint == null) return;
    pickPoint = point;
    _samplePick();
  }

  void _samplePick() {
    final pixels = _pickPixels, point = pickPoint;
    if (pixels == null || point == null) return;
    pickColor = sampleOpaqueColor(pixels, document.dimensions, point);
    inkChanges.notifyListeners();
  }

  /// Picks on lift; a quick tap picks as soon as the composite is ready.
  void finishPick() {
    if (pickPoint == null) return;
    if (_pickPixels == null) {
      _pickReleased = true;
    } else {
      _applyPick();
    }
  }

  void _applyPick() {
    final picked = pickColor;
    cancelPick();
    if (picked != null) {
      color = picked;
      colorPicked.value = ((colorPicked.value?.$1 ?? 0) + 1, picked);
    }
    if (tool == StudioTool.eyedropper) tool = _toolBeforePick;
    _notify();
  }

  void cancelPick() {
    _pickEpoch++;
    final visible = pickPoint != null;
    pickPoint = null;
    pickColor = null;
    _pickPixels = null;
    _pickReleased = false;
    if (visible && !disposed) inkChanges.notifyListeners();
  }

  /// Drawing guide: symmetry applies to every stroke; the guide shows, and
  /// on layers with Drawing Assist its lines steer strokes.
  SymmetryKind symmetry = SymmetryKind.off;
  DrawingGuide guide = const DrawingGuide();
  bool get gridGuide => guide.kind == GuideKind.grid;
  double get gridSize => guide.gridSize;

  /// Edit Drawing Guide: its points can be dragged on the canvas.
  bool guideEditing = false;

  void setGuide(DrawingGuide next) {
    finishStroke();
    guide = next;
    _preferences?.setString('guide.settings', jsonEncode(next.toJson()));
    inkChanges.notifyListeners();
    _notify();
  }

  void setGuideEditing(bool on) {
    if (on) {
      panel = null;
      cancelTransform();
    }
    guideEditing = on;
    inkChanges.notifyListeners();
    _notify();
  }

  void setSymmetry(SymmetryKind kind) {
    finishStroke();
    symmetry = kind;
    _preferences?.setString('guide.symmetry', kind.name);
    inkChanges.notifyListeners();
    _notify();
  }

  void setGrid({bool? visible, double? size}) => setGuide(
    guide.copyWith(
      kind: visible == null
          ? null
          : visible
          ? GuideKind.grid
          : GuideKind.none,
      gridSize: size,
    ),
  );

  void setFingerDrawing(bool value) {
    fingerDrawing = value;
    _preferences?.setBool('fingerDrawing', value);
    _notify();
  }

  /// Gesture controls: what a finger paints with, touch and hold for the
  /// eyedropper, QuickShape's hold (0: off), the two-finger hold before
  /// undo repeats, and whether multi-finger taps do anything.
  FingerTool fingerTool = FingerTool.same;
  bool eyedropperHold = false, touchGestures = true;
  double quickShapeDelay = .5, undoDelay = .5;

  /// Interface: how dark the outside of a selection is, where the sidebar
  /// sits (0 top – 1 bottom), and bars fading away while drawing.
  double selectionMask = .2, sidebarPosition = .5;
  bool autoHideInterface = false;

  void _loadGesturePrefs(SharedPreferences? p) {
    fingerTool =
        FingerTool.values.asNameMap()[p?.getString('gesture.fingerTool')] ??
        FingerTool.same;
    eyedropperHold = p?.getBool('gesture.eyedropperHold') ?? false;
    touchGestures = p?.getBool('gesture.touch') ?? true;
    quickShapeDelay = (p?.getDouble('gesture.quickShapeDelay') ?? .5).clamp(
      0,
      1.5,
    );
    undoDelay = (p?.getDouble('gesture.undoDelay') ?? .5).clamp(.2, 1.5);
    selectionMask = (p?.getDouble('selection.mask') ?? .2).clamp(0, .8);
    sidebarPosition = (p?.getDouble('sidebar.position') ?? .5).clamp(0, 1);
    autoHideInterface = p?.getBool('ui.autoHide') ?? false;
  }

  void setFingerTool(FingerTool value) {
    fingerTool = value;
    _preferences?.setString('gesture.fingerTool', value.name);
    _notify();
  }

  /// Touch and hold opens one thing: turning the eyedropper on moves the
  /// QuickMenu to four fingers.
  void setEyedropperHold(bool value) {
    eyedropperHold = value;
    _preferences?.setBool('gesture.eyedropperHold', value);
    if (value && quickMenuTrigger == QuickMenuTrigger.touchHold) {
      setQuickMenuTrigger(QuickMenuTrigger.fourFingerTap);
    }
    _notify();
  }

  void setTouchGestures(bool value) {
    touchGestures = value;
    _preferences?.setBool('gesture.touch', value);
    _notify();
  }

  void setQuickShapeDelay(double seconds) {
    quickShapeDelay = seconds.clamp(0, 1.5);
    _preferences?.setDouble('gesture.quickShapeDelay', quickShapeDelay);
    _notify();
  }

  void setUndoDelay(double seconds) {
    undoDelay = seconds.clamp(.2, 1.5);
    _preferences?.setDouble('gesture.undoDelay', undoDelay);
    _notify();
  }

  void setSelectionMask(double value) {
    selectionMask = value.clamp(0, .8);
    _preferences?.setDouble('selection.mask', selectionMask);
    inkChanges.notifyListeners();
    _notify();
  }

  void setSidebarPosition(double value) {
    sidebarPosition = value.clamp(0, 1);
    _preferences?.setDouble('sidebar.position', sidebarPosition);
    _notify();
  }

  void setAutoHideInterface(bool value) {
    autoHideInterface = value;
    _preferences?.setBool('ui.autoHide', value);
    _notify();
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    _frameTimer?.cancel();
    _playTimer?.cancel();
    playback.dispose();
    referenceImage?.dispose();
    referenceImage = null;
    adjustment?.dispose();
    adjustment = null;
    _liquifyTicker?.cancel();
    liquify?.dispose();
    liquify = null;
    clone?.dispose();
    clone = null;
    _autoWorker?.dispose();
    _autoWorker = null;
    _drawingNative?.cancel();
    _drawingNative = null;
    for (final session in _previews) {
      session.disposePreview();
    }
    _previews.clear();
    unawaited(_native.close());
    unawaited(_strokeFailures.close());
    hub.removeListener(_notify);
    hubJob.dispose();
    hub.dispose();
    _autosave?.cancel();
    rasters.dispose();
    inkChanges.dispose();
    appearance.dispose();
    historyNotice.dispose();
    textLayerTouched.dispose();
    colorPicked.dispose();
    canvasEngaged.dispose();
    compositor.dispose();
    super.dispose();
  }
}

/// A QuickShape following the pen: [shape] as snapped, turned and scaled
/// so the pen's place then ([from]) is where it is now ([to]).
class HeldQuickShape {
  HeldQuickShape(this.shape, this.from, this.pressure) : to = from;
  final QuickShape shape;
  final Offset from;
  final double pressure;
  Offset to;
  bool perfect = false;

  QuickShape get current {
    final moved = shape.movedBy(from, to);
    return perfect ? moved.perfected() : moved;
  }
}

/// The shape last drawn by QuickShape, and the drawing's revision once it
/// is on the layer (Edit Shape needs it to be the last change).
class LastQuickShape {
  LastQuickShape(this.shape, this.pressure);
  final QuickShape shape;
  final double pressure;
  int? revision;
}
