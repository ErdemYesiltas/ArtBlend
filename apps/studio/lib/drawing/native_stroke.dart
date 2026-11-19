import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:artblend_brush_engine/artblend_brush_engine.dart';
import 'package:artblend_brush_engine/brush_worker.dart' show premultiplyRgba;
import 'package:material_ui/material_ui.dart' show HSVColor;

import '../domain/document.dart';
import '../domain/selection.dart';
import 'brush_engine.dart';
import 'layer_worker.dart';

export 'layer_worker.dart';
import 'raster_tiles.dart';
import 'stamp_shapes.dart';
import 'symmetry.dart';

/// x, y, pressure, tiltX, tiltY, seconds since the previous sample.
typedef NativeSample = (double, double, double, double, double, double);

class NativeStrokeStats {
  const NativeStrokeStats({
    required this.start,
    required this.previewFrames,
    required this.previewBytes,
    required this.previewTime,
    required this.merge,
    this.mergeOnly = Duration.zero,
    required this.commit,
    required this.dirty,
    required this.loadBytes,
    this.latencyUs = const [],
  });

  /// Per preview frame: longest wait of an input sample until its dabs were
  /// decoded for display (excludes the final GPU frame).
  final List<int> latencyUs;

  Map<String, Object?> toJson() {
    int q(double p) {
      if (latencyUs.isEmpty) return 0;
      final sorted = [...latencyUs]..sort();
      return sorted[math.min(sorted.length - 1, (sorted.length * p).floor())];
    }

    return {
      'startMs': start.inMilliseconds,
      'previewFrames': previewFrames,
      'previewKiBPerFrame': previewFrames == 0
          ? 0
          : previewBytes ~/ previewFrames ~/ 1024,
      'previewDecodeUsAvg': previewFrames == 0
          ? 0
          : previewTime.inMicroseconds ~/ previewFrames,
      'inputToPreviewUs': {'p50': q(.5), 'p95': q(.95), 'max': q(1)},
      'mergeMs': merge.inMilliseconds,
      'mergeOnlyMs': mergeOnly.inMilliseconds,
      'penUpToCommitMs': commit.inMilliseconds,
      'dirty': dirty == null ? null : [dirty!.$3, dirty!.$4],
      'loadKiB': loadBytes ~/ 1024,
    };
  }

  /// Worker (re)load, round-trip baseline, preset and configure before dabs.
  final Duration start;
  final int previewFrames, previewBytes;

  /// Sum of dirty-chunk read + decode for live preview frames.
  final Duration previewTime;

  /// Input drained, final dirty read and merge; [commit] adds the GPU image.
  final Duration merge, commit;

  /// Merging and encoding alone, after the worker finished and was read.
  final Duration mergeOnly;

  /// Rectangle the stroke touched, the only part read and merged.
  final PixelRect? dirty;

  /// Layer pixels moved into the worker before this stroke.
  final int loadBytes;
  @override
  String toString() =>
      'start ${start.inMilliseconds}ms, preview $previewFrames frames '
      '${previewFrames == 0 ? 0 : previewBytes ~/ previewFrames ~/ 1024} KiB/'
      '${previewFrames == 0 ? 0 : previewTime.inMicroseconds ~/ previewFrames}µs avg, '
      'merge ${merge.inMilliseconds}ms (alone ${mergeOnly.inMilliseconds}ms), commit ${commit.inMilliseconds}ms, '
      'dirty ${dirty == null ? '-' : '${dirty!.$3}×${dirty!.$4}'}, '
      'load ${loadBytes ~/ 1024} KiB';
}

/// One persistent layer worker per canvas size, its preset, the selection
/// coverage it holds, and which layer content it holds, so a following
/// stroke on the same content continues without loading anything.
class NativeBrushRuntime {
  Future<LayerWorker>? _worker;
  CanvasSize? _workerSize;

  /// The MyPaint JSON or stamp the worker's surface has loaded.
  Object? _loadedPreset;
  bool _closed = false;

  /// The worker holds layer [_layerId] as [_content] will be once it
  /// resolves (a commit that may still be in flight).
  String? _layerId;
  Future<NativeLayerContent?>? _content;
  NativeLayerContent? _resolved;
  bool _settled = false;
  SelectionRegion? _clip;
  bool _clipKnown = false;

  /// Bytes moved into the worker by the last load, for profiling.
  int lastLoadBytes = 0;

  /// The worker for a canvas of [dimensions]; a drawing of another size
  /// gets a new worker (its surface size is fixed at creation).
  Future<LayerWorker> worker(CanvasSize dimensions) {
    if (_closed) return Future.error(StateError('Brush runtime closed'));
    final current = _worker;
    if (current != null && _workerSize == dimensions) return current;
    invalidate();
    _loadedPreset = null;
    _symmetry = null;
    _smudge = null;
    _alphaLock = null;
    _clipKnown = false;
    if (current != null) {
      unawaited(current.then((w) => w.close(), onError: (Object _) {}));
    }
    _workerSize = dimensions;
    return _worker = LayerWorker.create(dimensions).catchError((Object error) {
      _worker = null;
      _workerSize = null;
      throw error;
    });
  }

  Future<void> usePreset(LayerWorker worker, BrushPreset preset) async {
    final Object brush = preset.isStamp
        ? (
            await resolveStampShapes(preset),
            preset.stamp!,
            await resolveDualShape(preset),
          )
        : preset.mypaint!;
    if (identical(_loadedPreset, brush) || _loadedPreset == brush) return;
    _loadedPreset = null;
    if (brush case (
      (final StampImage tip, final StampImage? grain),
      final StampSettings settings,
      final (StampImage, DualStamp)? dual,
    )) {
      await worker.loadStamp(tip, settings, grain: grain, dual: dual);
    } else {
      await worker.loadPreset(brush as String);
    }
    _loadedPreset = brush;
  }

  (SymmetryKind, ui.Offset, bool)? _symmetry;
  bool? _smudge, _alphaLock;

  Future<void> useAlphaLock(LayerWorker worker, bool on) async {
    if (_alphaLock == on) return;
    _alphaLock = null;
    await worker.setAlphaLock(on);
    _alphaLock = on;
  }

  Future<void> useSmudge(LayerWorker worker, bool on) async {
    if (_smudge == on) return;
    _smudge = null;
    await worker.setSmudge(on);
    _smudge = on;
  }

  /// Sends the symmetry only when it changed.
  Future<void> useSymmetry(
    LayerWorker worker,
    SymmetryKind kind, {
    ui.Offset? centre,
    bool rotational = false,
  }) async {
    final size = _workerSize!;
    final at = centre ?? ui.Offset(size.width / 2, size.height / 2);
    final key = (kind, at, rotational);
    if (_symmetry == key) return;
    _symmetry = null;
    await worker.setSymmetry(
      symmetryMatrices(kind, rotational: rotational),
      at.dx,
      at.dy,
    );
    _symmetry = key;
  }

  /// Sends the selection's coverage only when the selection changed.
  Future<void> useClip(LayerWorker worker, SelectionRegion? region) async {
    if (_clipKnown && identical(region, _clip)) return;
    _clipKnown = false;
    await worker.setClip(
      region == null
          ? null
          : await renderSelectionCoverage(region, _workerSize!),
    );
    _clip = region;
    _clipKnown = true;
  }

  void _track(Future<NativeLayerContent?> content) {
    _content = content;
    _resolved = null;
    _settled = false;
    content.then(
      (value) {
        if (!identical(_content, content)) return;
        if (value == null) {
          invalidate(); // the stroke it depends on was not applied
        } else {
          _resolved = value;
          _settled = true;
        }
      },
      onError: (Object _) {
        if (identical(_content, content)) invalidate();
      },
    );
  }

  /// Whether a stroke on [layer] can continue from the worker as it is,
  /// without waiting for earlier commits: same layer and, once the pending
  /// commit resolved, the layer still holds exactly that content.
  bool continues(ArtLayer layer) =>
      _content != null &&
      _layerId == layer.id &&
      (!_settled || _resolved!.matches(layer));

  /// The content the worker holds once pending commits resolve.
  Future<NativeLayerContent?> get content => _content!;

  /// Loads [layer] into the worker: its tiles' PNGs, decoded there, or
  /// rendered pixels when it has vector strokes or an old image.
  Future<void> load(
    LayerWorker worker,
    ArtLayer layer,
    TileGrid grid,
    Map<RasterAsset, ui.Image> images,
  ) async {
    invalidate();
    var loaded = false;
    if (layer.strokes.isEmpty && layer.legacyRaster == null) {
      final pngs = {
        for (final MapEntry(:key, :value)
            in (layer.raster?.tiles ?? {}).entries)
          key: value.png,
      };
      loaded = await worker.loadTiles(pngs);
      lastLoadBytes = pngs.values.fold(0, (n, png) => n + png.length);
    }
    if (!loaded) {
      final pixels = await renderNativeBase(layer, grid, images);
      await worker.loadPixels(pixels.rgba, exact: pixels.exact);
      lastLoadBytes = pixels.rgba.length;
    }
    _layerId = layer.id;
    _track(Future.value(NativeLayerContent.of(layer)));
  }

  /// After a stroke's commit was sent: the worker already holds its result,
  /// which becomes layer content once [committed] resolves.
  void afterStroke(String layerId, Future<NativeLayerContent?> committed) {
    if (_content == null || _layerId != layerId) {
      invalidate();
      return;
    }
    _track(committed);
  }

  void invalidate() {
    _layerId = null;
    _content = null;
    _resolved = null;
    _settled = false;
  }

  Future<void> close() async {
    _closed = true;
    invalidate();
    final pending = _worker;
    _worker = null;
    if (pending == null) return;
    try {
      await (await pending).close();
    } catch (_) {}
  }
}

/// Which layer content the worker holds: identities, not pixels.
class NativeLayerContent {
  const NativeLayerContent(this.raster, this.strokes, this.legacyRaster);
  NativeLayerContent.of(ArtLayer layer)
    : this(layer.raster, layer.strokes, layer.legacyRaster);
  final TiledRaster? raster;
  final List<InkStroke> strokes;
  final RasterAsset? legacyRaster;
  bool matches(ArtLayer layer) =>
      identical(raster, layer.raster) &&
      identical(strokes, layer.strokes) &&
      identical(legacyRaster, layer.legacyRaster);
}

/// Raw layer pixels before opacity, blend and the editable mask are applied.
/// [exact]: they are exactly the layer's tiles.
class LayerPixels {
  const LayerPixels(this.rgba, {required this.exact});
  final Uint8List rgba;
  final bool exact;
}

Future<LayerPixels> renderNativeBase(
  ArtLayer layer,
  TileGrid grid,
  Map<RasterAsset, ui.Image> images,
) async {
  final dimensions = grid.dimensions;
  // Tiles are our own lossless PNGs: decode them exactly instead of reading
  // back premultiplied GPU pixels, which would round low-alpha colors.
  if (layer.strokes.isEmpty && layer.legacyRaster == null) {
    final pngs = {
      for (final MapEntry(:key, :value) in (layer.raster?.tiles ?? {}).entries)
        key: value.png,
    };
    final exact = await Isolate.run(() => assembleTiles(pngs, grid));
    if (exact != null) return LayerPixels(exact, exact: true);
  }
  final recorder = ui.PictureRecorder();
  paintLayer(
    ui.Canvas(recorder),
    layer,
    FreehandBrushEngine(),
    dimensions,
    rasterImages: images,
    applyOpacity: false,
    applyMask: false,
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(dimensions.width, dimensions.height);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) throw StateError('Cannot read layer pixels');
    return LayerPixels(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      exact: false,
    );
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Anti-aliased selection coverage, one byte per pixel.
Future<Uint8List> renderSelectionCoverage(
  SelectionRegion region,
  CanvasSize dimensions,
) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawPath(region.path, region.coveragePaint);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(dimensions.width, dimensions.height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Cannot read selection coverage');
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final coverage = Uint8List(rgba.length ~/ 4);
    for (var i = 0; i < coverage.length; i++) {
      coverage[i] = rgba[i * 4 + 3];
    }
    return coverage;
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// A short S-curve rendered by the real preset in black, for tinting.
/// The real native dabs of a preset (MyPaint or stamp) on a short wave,
/// rendered off the UI isolate.
/// [path]: points (x, y in pixels, pressure) to draw instead of the
/// sample S-curve, as on the Brush Studio's drawing pad.
Future<ui.Image> renderNativePreview(
  BrushPreset preset, {
  int width = 400,
  int height = 56,
  double diameter = 10,
  List<(double, double, double)>? path,
}) async {
  final shapes = preset.isStamp ? await resolveStampShapes(preset) : null;
  final dual = preset.isStamp ? await resolveDualShape(preset) : null;
  final json = preset.mypaint, settings = preset.stamp;
  final size = preset.isStamp ? math.min(preset.size, height * .6) : diameter;
  final rgba = await Isolate.run(() {
    final surface = NativeBrushSurface(width: width, height: height);
    try {
      if (shapes != null) {
        surface.loadStamp(shapes.$1, settings!, grain: shapes.$2, dual: dual);
      } else {
        surface.loadPreset(json!);
      }
      surface.configure(diameter: size);
      surface.beginStroke();
      if (path != null && path.length > 1) {
        for (final (i, (x, y, pressure)) in path.indexed) {
          surface.point(
            x: x,
            y: y,
            pressure: pressure,
            seconds: i == 0 ? 1 : 1 / 120,
          );
        }
        surface.point(x: path.last.$1, y: path.last.$2, pressure: 0);
        return premultiplyRgba(surface.readRgba());
      }
      const steps = 80;
      var x = 0.0, y = 0.0;
      for (var i = 0; i <= steps; i++) {
        x = 12 + i * (width - 24) / steps;
        y = height / 2 + math.sin(i / 10) * height * .22;
        surface.point(
          x: x,
          y: y,
          pressure: .25 + .7 * math.sin(math.pi * i / steps),
          seconds: i == 0 ? 1 : 1 / 120,
        );
      }
      surface.point(x: x, y: y, pressure: 0);
      return premultiplyRgba(surface.readRgba());
    } finally {
      surface.close();
    }
  });
  return imageFromPremultiplied(rgba, width, height);
}

/// [rgba] must be premultiplied: the engine treats raw pixels that way.
Future<ui.Image> imageFromPremultiplied(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Input, preview and final pixels of one native stroke on one layer.
///
/// The session never touches the document: its owner commits the result.
class NativeStrokeSession {
  NativeStrokeSession({
    required this.documentId,
    required this.layerId,
    required this.dimensions,
    required this.preset,
    required this.color,
    required this.size,
    required this.opacity,
    required this.eraser,
    required this.clip,
    this.symmetry = SymmetryKind.off,
    this.symmetryCentre,
    this.symmetryRotational = false,
    this.smudge = false,
    this.alphaLock = false,
    required this.onPreview,
  });
  final String documentId, layerId;
  final CanvasSize dimensions;
  final BrushPreset preset;
  final int color;
  final double size, opacity;
  final bool eraser;
  final SelectionRegion? clip;
  final SymmetryKind symmetry;

  /// Where symmetry turns around (the canvas centre when null), and whether
  /// it turns copies instead of mirroring them.
  final ui.Offset? symmetryCentre;
  final bool symmetryRotational;

  /// Drags paint instead of laying it (opacity is the strength).
  final bool smudge;

  /// The layer is alpha-locked: the stroke recolours existing pixels only.
  final bool alphaLock;
  final void Function() onPreview;

  static const maxSamples = 100000;
  static const _batch = 256;
  static const _previewInterval = Duration(milliseconds: 33);

  final List<NativeSample> _queue = [];

  /// Arrival time of each queued sample, for input → preview latency.
  final List<int> _queuedAtUs = [];
  final Stopwatch _clock = Stopwatch()..start();
  int? _oldestUnshownUs;
  final List<int> latencyUs = [];
  int _received = 0;
  Duration? _lastTime;
  (double, double)? _lastPosition;
  double _pathLength = 0, _lastPressure = 0;
  Completer<void>? _wake;
  bool _inputClosed = false, _cancelled = false, _starting = false;
  final Completer<void> _done = Completer();
  final Stopwatch _sincePreview = Stopwatch();

  LayerWorker? _worker;

  /// The layer content this stroke paints on. It may be the result of an
  /// earlier stroke whose commit is still in flight (null if that failed).
  Future<NativeLayerContent?>? baseFuture;

  /// Completed by the owner after the commit: the content this stroke left
  /// (its own base when nothing changed), or null when it was not applied.
  final Completer<NativeLayerContent?> committed = Completer();

  /// Live preview blocks keyed by chunk index; each replaces its square of
  /// the base image. Only blocks the brush touched are ever uploaded.
  final Map<int, ui.Image> _chunks = {};
  int _previewGeneration = 0;

  /// Diagnostics for the cost report.
  final Stopwatch startCost = Stopwatch();
  int previewFrames = 0, previewBytes = 0, loadBytes = 0;
  Duration previewTime = Duration.zero;

  bool get cancelled => _cancelled;
  bool get started => _worker != null;

  /// Completes once no worker call of this session is in flight.
  Future<void> get settled => _done.future;

  void add(
    double x,
    double y,
    double pressure, {
    double tiltX = 0,
    double tiltY = 0,
    Duration? time,
  }) {
    if (_inputClosed || _cancelled || _received >= maxSamples) return;
    if (!x.isFinite || !y.isFinite || !pressure.isFinite) return;
    // libmypaint applies slow tracking from the previous stroke's position
    // even while resetting; a long first interval places the reset exactly.
    var seconds = _received == 0 ? 1.0 : 1 / 120;
    final last = _lastTime;
    if (_received > 0 && time != null && last != null) {
      seconds = (time - last).inMicroseconds / 1e6;
    }
    if (time != null) _lastTime = time;
    _received++;
    final previous = _lastPosition;
    if (previous != null) {
      _pathLength += math.sqrt(
        math.pow(x - previous.$1, 2) + math.pow(y - previous.$2, 2),
      );
    }
    _lastPosition = (x, y);
    _lastPressure = pressure.clamp(0.0, 1.0);
    _queue.add((
      x,
      y,
      pressure.clamp(0.0, 1.0),
      tiltX.clamp(-1.0, 1.0),
      tiltY.clamp(-1.0, 1.0),
      seconds.clamp(.0005, 1.0),
    ));
    _queuedAtUs.add(_clock.elapsedMicroseconds);
    _wakeUp();
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    wake?.complete();
  }

  /// Called on the worker lane once the worker is exclusively ours and holds
  /// this stroke's layer ([NativeBrushRuntime.content]): just loaded
  /// ([reloaded]) or as the previous stroke left it.
  Future<void> start(
    LayerWorker worker,
    NativeBrushRuntime runtime, {
    required bool reloaded,
  }) async {
    _starting = true;
    startCost.start();
    try {
      baseFuture = runtime.content;
      loadBytes = reloaded ? runtime.lastLoadBytes : 0;
      await runtime.useClip(worker, clip);
      if (_cancelled) {
        _finish();
        return;
      }
      await runtime.usePreset(worker, preset);
      await runtime.useSymmetry(
        worker,
        symmetry,
        centre: symmetryCentre,
        rotational: symmetryRotational,
      );
      await runtime.useSmudge(worker, smudge);
      await runtime.useAlphaLock(worker, alphaLock);
      final hsv = HSVColor.fromColor(ui.Color(color));
      await worker.configure(
        diameter: size,
        hue: hsv.hue / 360,
        saturation: hsv.saturation,
        value: hsv.value,
        opacity: (opacity * ui.Color(color).a).clamp(0.0, 1.0),
        eraser: eraser,
      );
      await worker.beginStroke();
    } catch (_) {
      _finish();
      rethrow;
    } finally {
      startCost.stop();
    }
    if (_cancelled) {
      _finish();
      return;
    }
    _worker = worker;
    onPreview();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    final worker = _worker!;
    _sincePreview.start();
    try {
      while (!_cancelled) {
        if (_queue.isEmpty) {
          if (_inputClosed) break;
          final wake = _wake = Completer();
          await wake.future;
          continue;
        }
        final count = math.min(_batch, _queue.length);
        final batch = _queue.sublist(0, count);
        _queue.removeRange(0, count);
        if (_queuedAtUs.isNotEmpty) {
          _oldestUnshownUs ??= _queuedAtUs.first;
          _queuedAtUs.removeRange(0, math.min(count, _queuedAtUs.length));
        }
        await worker.points(batch);
        if (!_inputClosed &&
            !_cancelled &&
            (_queue.isEmpty || _sincePreview.elapsed > _previewInterval)) {
          await _refreshPreview(worker);
        }
      }
    } catch (error) {
      _failure = error;
    } finally {
      _finish();
    }
  }

  Object? _failure;

  Future<void> _refreshPreview(LayerWorker worker) async {
    final watch = Stopwatch()..start();
    final generation = ++_previewGeneration;
    final (indices, pixels) = await worker.takeDirtyChunks();
    if (pixels == null || _cancelled || generation != _previewGeneration) {
      return;
    }
    // Edge blocks are smaller; the worker packs each at its own size.
    var offset = 0;
    final images = await Future.wait([
      for (final index in indices)
        if (chunkRect(index, dimensions) case (_, _, final w, final h))
          imageFromPremultiplied(
            Uint8List.sublistView(pixels, offset, offset += w * h * 4),
            w,
            h,
          ),
    ]);
    if (_cancelled || generation != _previewGeneration) {
      for (final image in images) {
        image.dispose();
      }
      return;
    }
    for (var i = 0; i < images.length; i++) {
      _chunks.remove(indices[i])?.dispose();
      _chunks[indices[i]] = images[i];
    }
    final oldest = _oldestUnshownUs;
    if (oldest != null) latencyUs.add(_clock.elapsedMicroseconds - oldest);
    _oldestUnshownUs = null;
    previewFrames++;
    previewBytes += pixels.length;
    previewTime += watch.elapsed;
    _sincePreview.reset();
    onPreview();
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  /// Ends input; the final zero-pressure sample lifts the MyPaint brush.
  void closeInput() {
    if (_inputClosed) return;
    final last = _lastPosition;
    if (last != null && !_cancelled) {
      // MyPaint places dabs by distance, so a tap would leave nothing. Trace
      // a tiny circle well inside the brush radius to leave a round dot.
      final radius = size / 2;
      if (_pathLength < radius / 2) {
        final r = math.max(.5, radius / 4);
        final pressure = math.max(_lastPressure, .5);
        for (var i = 1; i <= 12; i++) {
          final a = i * math.pi / 6;
          _queue.add((
            last.$1 + r * math.sin(a),
            last.$2 - r + r * math.cos(a),
            pressure,
            0,
            0,
            1 / 240,
          ));
        }
      }
      _queue.add((last.$1, last.$2, 0, 0, 0, 1 / 120));
    }
    _inputClosed = true;
    _wakeUp();
  }

  /// Worker lane, after input ends: shows the last dabs, then asks the
  /// worker to merge the stroke. Returns that pending result without waiting
  /// for it, so the next stroke can start painting meanwhile; null when
  /// cancelled or never started.
  Future<Future<NativeCommit>?> finish() async {
    closeInput();
    await settled;
    final failure = _failure;
    if (failure != null) throw failure;
    final worker = _worker;
    if (_cancelled || worker == null) return null;
    // A tap or the last dabs may not have reached the preview yet.
    await _refreshPreview(worker);
    if (_cancelled) return null;
    return worker.commit();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _queue.clear();
    _wakeUp();
    if (_worker == null && !_starting) _finish();
    disposePreview();
  }

  void disposePreview() {
    _previewGeneration++;
    for (final image in _chunks.values) {
      image.dispose();
    }
    _chunks.clear();
  }

  /// Live blocks of this stroke, drawn over the layer's committed content.
  NativeOverlay get preview => NativeOverlay([
    for (final MapEntry(:key, :value) in _chunks.entries)
      (
        ui.Offset(
          chunkRect(key, dimensions).$1.toDouble(),
          chunkRect(key, dimensions).$2.toDouble(),
        ),
        value,
      ),
  ], clip);
}
