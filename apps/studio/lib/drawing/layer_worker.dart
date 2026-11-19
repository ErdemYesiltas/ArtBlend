import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:artblend_brush_engine/artblend_brush_engine.dart';

import '../domain/document.dart';
import 'raster_tiles.dart';

/// Pixel rectangle: x, y, width, height.
typedef PixelRect = (int, int, int, int);

/// Side of the square preview blocks moved between the worker and the GPU.
const nativeChunk = 128;

/// Preview block [index] of a canvas, row by row; edge blocks are cut to the
/// canvas, as the worker reads them.
PixelRect chunkRect(int index, CanvasSize dimensions) {
  final columns = (dimensions.width + nativeChunk - 1) ~/ nativeChunk;
  final x = (index % columns) * nativeChunk;
  final y = (index ~/ columns) * nativeChunk;
  return (
    x,
    y,
    math.min(nativeChunk, dimensions.width - x),
    math.min(nativeChunk, dimensions.height - y),
  );
}

PixelRect? chunkBounds(Iterable<int> indices, CanvasSize dimensions) {
  int? left, top, right, bottom;
  for (final index in indices) {
    final (x, y, w, h) = chunkRect(index, dimensions);
    left = left == null ? x : math.min(left, x);
    top = top == null ? y : math.min(top, y);
    right = right == null ? x + w : math.max(right, x + w);
    bottom = bottom == null ? y + h : math.max(bottom, y + h);
  }
  return left == null ? null : (left, top!, right! - left, bottom! - top);
}

/// Copies [rect] out of a row-major buffer of [width] pixels, [bytes] each.
Uint8List cropPixels(
  Uint8List source,
  int width,
  PixelRect rect, [
  int bytes = 4,
]) {
  final (x, y, w, h) = rect;
  final out = Uint8List(w * h * bytes);
  for (var row = 0; row < h; row++) {
    final from = ((y + row) * width + x) * bytes;
    out.setRange(row * w * bytes, (row + 1) * w * bytes, source, from);
  }
  return out;
}

void pastePixels(Uint8List target, int width, PixelRect rect, Uint8List patch) {
  final (x, y, w, h) = rect;
  for (var row = 0; row < h; row++) {
    target.setRange(
      ((y + row) * width + x) * 4,
      ((y + row) * width + x + w) * 4,
      patch,
      row * w * 4,
    );
  }
}

/// Merged rows and the tiles they changed, cut out for encoding.
class NativeMerge {
  const NativeMerge(this.rows, this.changed, this.tiles);
  final Uint8List rows;
  final bool changed;
  final List<(int, Uint8List)> tiles;
}

/// What the merge isolate returns: merged rows and encoded tiles.
class NativeTilesResult {
  const NativeTilesResult(this.rows, this.changed, this.updates);
  final Uint8List rows;
  final bool changed;
  final List<TileUpdate> updates;
}

/// Merges [result] (the worker's pixels inside [rect]) into a copy of
/// [rows], the base rows starting at [rowStart] (a tile edge, full width).
/// [baseline] is the surface read back right after loading the base, cropped
/// to [rect], so the RGBA16 round trip of untouched pixels is not mistaken for
/// paint. [coverage] (one byte per pixel, also cropped) limits the selection.
/// Cuts out the tiles [rect] changed, or every non-empty tile with
/// [allTiles]; [encodeTiles] then encodes them.
NativeMerge mergeNativeTiles(
  Uint8List rows,
  int rowStart,
  Uint8List baseline,
  Uint8List result,
  Uint8List? coverage,
  PixelRect rect,
  TileGrid grid, {
  bool allTiles = false,
  bool lockAlpha = false,
}) {
  const size = TiledRaster.size;
  final CanvasSize(:width, :height) = grid.dimensions;
  final (rx, ry, rw, rh) = rect;
  final rowCount = rows.length ~/ 4 ~/ width;
  if (baseline.length != rw * rh * 4 ||
      result.length != baseline.length ||
      (coverage != null && coverage.length * 4 != baseline.length) ||
      ry < rowStart ||
      ry + rh > rowStart + rowCount ||
      rowStart % size != 0 ||
      (allTiles && (rowStart != 0 || rowCount != height))) {
    throw ArgumentError('Mismatched native stroke buffers');
  }
  final out = Uint8List.fromList(rows);
  var changed = false;
  for (var py = 0; py < rh; py++) {
    for (var px = 0; px < rw; px++) {
      final p = py * rw + px;
      final r = p * 4, i = ((ry - rowStart + py) * width + rx + px) * 4;
      final m = coverage == null ? 255 : coverage[p];
      if (m == 0 ||
          (result[r] == baseline[r] &&
              result[r + 1] == baseline[r + 1] &&
              result[r + 2] == baseline[r + 2] &&
              result[r + 3] == baseline[r + 3])) {
        continue;
      }
      if (lockAlpha && rows[i + 3] == 0) continue;
      if (m == 255) {
        out.setRange(i, i + 4, result, r);
      } else {
        // Blend premultiplied colors so a soft selection edge cannot halo.
        final t = m / 255, s = 1 - t;
        final ba = rows[i + 3] / 255, ra = result[r + 3] / 255;
        final a = ba * s + ra * t;
        out[i + 3] = (a * 255).round();
        for (var c = 0; c < 3; c++) {
          out[i + c] = a == 0
              ? 0
              : ((rows[i + c] * ba * s + result[r + c] * ra * t) / a)
                    .round()
                    .clamp(0, 255);
        }
      }
      // Alpha lock: the colour changes, the layer's alpha stays.
      if (lockAlpha) out[i + 3] = rows[i + 3];
      if (out[i] != rows[i] ||
          out[i + 1] != rows[i + 1] ||
          out[i + 2] != rows[i + 2] ||
          out[i + 3] != rows[i + 3]) {
        changed = true;
      }
    }
  }
  if (!changed) return NativeMerge(rows, false, const []);
  if (allTiles) return NativeMerge(out, true, cutAllTiles(out, grid));
  final tiles = <(int, Uint8List)>[];
  for (var ty = ry ~/ size; ty <= (ry + rh - 1) ~/ size; ty++) {
    for (var tx = rx ~/ size; tx <= (rx + rw - 1) ~/ size; tx++) {
      // Edge tiles are cut to the canvas.
      final tileWidth = math.min(size, width - tx * size);
      final tileHeight = math.min(size, rowStart + rowCount - ty * size);
      var differs = false;
      for (var row = 0; row < tileHeight && !differs; row++) {
        final from = ((ty * size - rowStart + row) * width + tx * size) * 4;
        for (var b = from; b < from + tileWidth * 4; b++) {
          if (out[b] != rows[b]) {
            differs = true;
            break;
          }
        }
      }
      if (!differs) continue;
      // Tile indices are absolute; the rows start at a tile edge.
      tiles.add((
        ty * grid.columns + tx,
        cropTile(out, width, rowCount, tx * size, ty * size - rowStart),
      ));
    }
  }
  return NativeMerge(out, true, tiles);
}

/// One stroke's result from the worker: the rectangle it touched and the
/// tiles that changed there, already encoded. [full]: [updates] hold every
/// tile of the layer, not changes over the previous content.
class NativeCommit {
  const NativeCommit({
    required this.rect,
    required this.changed,
    required this.full,
    required this.updates,
    required this.mergeTime,
  });
  final PixelRect? rect;
  final bool changed, full;
  final List<TileUpdate> updates;

  /// Reading, merging and encoding inside the worker.
  final Duration mergeTime;
}

/// Brush sample: x, y, pressure, tiltX, tiltY, seconds since the previous.
typedef BrushSample = (double, double, double, double, double, double);

/// A persistent isolate that owns one layer's pixels while it is painted:
/// the libmypaint surface, the layer content it was loaded from and how that
/// content reads back. A stroke is merged, its changed tiles encoded and the
/// layer updated in place there; the UI isolate only receives those tiles,
/// never a whole-layer buffer.
final class LayerWorker {
  LayerWorker._();
  final ReceivePort _responses = ReceivePort();
  final Completer<SendPort> _ready = Completer();
  final Map<int, Completer<Object?>> _pending = {};
  Isolate? _isolate;
  Future<void>? _closeFuture;
  int _nextId = 1;
  bool _closed = false, _closing = false;

  static Future<LayerWorker> create(CanvasSize dimensions) async {
    final worker = LayerWorker._();
    worker._responses.listen(worker._receive);
    try {
      worker._isolate = await Isolate.spawn(
        _runLayerWorker,
        (worker._responses.sendPort, dimensions.width, dimensions.height),
        onError: worker._responses.sendPort,
        onExit: worker._responses.sendPort,
        errorsAreFatal: true,
        debugName: 'ArtBlend layer',
      );
      await worker._ready.future.timeout(const Duration(seconds: 15));
      return worker;
    } catch (_) {
      worker._closed = true;
      worker._responses.close();
      worker._isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  void _receive(Object? message) {
    if (message is List && message.length == 3 && message[0] is int) {
      final id = message[0] as int;
      if (id == 0) {
        if (message[1] == true) {
          _ready.complete(message[2] as SendPort);
        } else {
          _fail(StateError(message[2].toString()));
        }
        return;
      }
      final request = _pending.remove(id);
      if (request == null) return;
      if (message[1] == true) {
        request.complete(message[2]);
      } else {
        request.completeError(StateError(message[2].toString()));
      }
    } else {
      _fail(StateError('Layer worker exited: $message'));
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
    _responses.close();
  }

  Future<Object?> _request(String operation, [Object? argument]) async {
    if (_closed || (_closing && operation != 'close')) {
      throw StateError('Layer worker is closed.');
    }
    final port = await _ready.future;
    if (_closed || (_closing && operation != 'close')) {
      throw StateError('Layer worker is closed.');
    }
    final id = _nextId++;
    final result = Completer<Object?>();
    _pending[id] = result;
    port.send((id, operation, argument));
    return result.future;
  }

  /// Loads a layer from its tiles' PNGs, decoded exactly in the worker.
  /// False when a tile is not in the form we write; load pixels instead.
  Future<bool> loadTiles(Map<int, Uint8List> pngs) async =>
      await _request('loadTiles', pngs) as bool;

  /// Loads a layer from straight RGBA. [exact]: the pixels are exactly the
  /// layer's tiles; otherwise the next change rewrites every tile.
  Future<void> loadPixels(Uint8List rgba, {required bool exact}) async =>
      await _request('loadPixels', (
        TransferableTypedData.fromList([rgba]),
        exact,
      ));

  /// Selection coverage (one byte per pixel) for following strokes, or none.
  Future<void> setClip(Uint8List? coverage) async => await _request(
    'clip',
    coverage == null ? null : TransferableTypedData.fromList([coverage]),
  );

  Future<void> loadPreset(String json) async => await _request('preset', json);

  /// Alpha lock for following strokes.
  Future<void> setAlphaLock(bool on) async => await _request('alphaLock', on);

  /// Smudge instead of paint for following strokes.
  Future<void> setSmudge(bool on) async => await _request('smudge', on);

  /// Symmetric copies of following strokes (see `ab_symmetry`).
  Future<void> setSymmetry(
    List<(double, double, double, double)> matrices,
    double cx,
    double cy,
  ) async => await _request('symmetry', (matrices, cx, cy));

  /// Switches the surface to a stamp brush until the next [loadPreset].
  Future<void> loadStamp(
    StampImage tip,
    StampSettings settings, {
    StampImage? grain,
    (StampImage, DualStamp)? dual,
  }) async => await _request('stamp', (tip, grain, settings, dual));

  Future<void> configure({
    required double diameter,
    double hue = 0,
    double saturation = 0,
    double value = 0,
    double opacity = 1,
    bool eraser = false,
  }) async => await _request('configure', (
    diameter,
    hue,
    saturation,
    value,
    opacity,
    eraser,
  ));

  Future<void> beginStroke() async => await _request('begin');

  Future<void> points(List<BrushSample> samples) async {
    if (samples.isEmpty || samples.length > 2048) {
      throw ArgumentError('Expected 1–2048 samples.');
    }
    await _request('points', List.of(samples));
  }

  /// Preview blocks dabs touched since the last call, premultiplied and
  /// concatenated in index order (edge blocks cut to the canvas).
  Future<(List<int>, Uint8List?)> takeDirtyChunks() async {
    final (indices, data) =
        await _request('dirty') as (List<int>, TransferableTypedData?);
    return (indices, data?.materialize().asUint8List());
  }

  /// Merges the stroke into the worker's layer and returns its changed
  /// tiles. The layer is updated in place: if the UI does not apply them it
  /// must load the layer again.
  Future<NativeCommit> commit() async {
    final (rect, changed, full, meta, data, micros) =
        await _request('commit')
            as (
              PixelRect?,
              bool,
              bool,
              List<(int, int, int, TileBounds?)>,
              TransferableTypedData?,
              int,
            );
    final bytes = data?.materialize().asUint8List();
    const tileBytes = TiledRaster.size * TiledRaster.size * 4;
    return NativeCommit(
      rect: rect,
      changed: changed,
      full: full,
      mergeTime: Duration(microseconds: micros),
      updates: [
        for (final (index, offset, pngLength, bounds) in meta)
          pngLength < 0
              ? TileUpdate(index, null, null, null)
              : TileUpdate(
                  index,
                  Uint8List.sublistView(bytes!, offset, offset + pngLength),
                  Uint8List.sublistView(
                    bytes,
                    offset + pngLength,
                    offset + pngLength + tileBytes,
                  ),
                  bounds,
                ),
      ],
    );
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      await _request('close');
    } finally {
      _closed = true;
      _responses.close();
      _isolate?.kill(priority: Isolate.immediate);
    }
  }
}

/// The worker isolate's state.
class _Layer {
  _Layer(this.surface, this.dimensions) : grid = TileGrid(dimensions);
  final NativeBrushSurface surface;
  final CanvasSize dimensions;
  final TileGrid grid;
  int get width => dimensions.width;

  /// Layer content as loaded and since updated by merges; [baseline] is how
  /// it reads back from the RGBA16 surface.
  Uint8List? layer, baseline;
  Uint8List? coverage;
  bool exact = false;

  /// Alpha lock: strokes recolour pixels but never change the layer's alpha.
  bool lockAlpha = false;

  /// Preview blocks this stroke touched; the merge covers their bounds.
  final Set<int> touched = {};

  void load(Uint8List rgba, bool exact) {
    surface.loadRgba(rgba);
    layer = rgba;
    baseline = surface.readRgba();
    this.exact = exact;
    surface.takeDirtyTiles();
  }

  (List<int>, TransferableTypedData?) dirty({required bool read}) {
    const tile = NativeBrushSurface.tileSize, per = nativeChunk ~/ tile;
    final tiles = surface.takeDirtyTiles();
    final columns = (width + nativeChunk - 1) ~/ nativeChunk;
    final indices = <int>{};
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i] == 0) continue;
      final tx = i % surface.tileColumns, ty = i ~/ surface.tileColumns;
      indices.add((ty ~/ per) * columns + tx ~/ per);
    }
    touched.addAll(indices);
    final sorted = indices.toList()..sort();
    if (!read || sorted.isEmpty) return (sorted, null);
    final out = BytesBuilder(copy: false);
    final layer = this.layer;
    for (final index in sorted) {
      final (x, y, w, h) = chunkRect(index, dimensions);
      final block = surface.readRgbaRect(x, y, w, h, premultiplied: true);
      if (lockAlpha && layer != null) {
        // Preview what the merge will keep: the surface's colour at the
        // layer's own alpha.
        for (var row = 0; row < h; row++) {
          for (var col = 0; col < w; col++) {
            final p = (row * w + col) * 4;
            final a0 = layer[((y + row) * width + x + col) * 4 + 3];
            final a = block[p + 3];
            if (a0 == 0 || a == 0) {
              block.fillRange(p, p + 4, 0);
              continue;
            }
            for (var c = 0; c < 3; c++) {
              block[p + c] = (block[p + c] * a0 / a).round().clamp(0, a0);
            }
            block[p + 3] = a0;
          }
        }
      }
      out.add(block);
    }
    return (sorted, TransferableTypedData.fromList([out.takeBytes()]));
  }

  /// The previous stroke's merge; the next merge builds on its layer.
  Future<void> pendingMerge = Future.value();

  /// Reads this stroke's pixels now, before the next stroke can paint, and
  /// returns the merge to run once the previous merge has updated [layer].
  Future<Object?> Function() prepare() {
    final layer = this.layer, baseline = this.baseline;
    if (layer == null || baseline == null) {
      throw StateError('No layer loaded');
    }
    final watch = Stopwatch()..start();
    dirty(read: false);
    final rect = chunkBounds(touched, dimensions);
    if (rect == null) {
      return () async =>
          (null, false, false, const <(int, int, int, TileBounds?)>[], null, 0);
    }
    final (rx, y, rw, h) = rect;
    final result = surface.readRgbaRect(rx, y, rw, h);
    final baselineRect = cropPixels(baseline, width, rect);
    final coverage = this.coverage, lockAlpha = this.lockAlpha;
    final coverageRect = coverage == null
        ? null
        : cropPixels(coverage, width, rect, 1);
    // A selection or alpha lock keeps only part of what the surface holds.
    final restricted = coverage != null || lockAlpha;
    // Otherwise the surface now holds the result: the next stroke reads its
    // untouched pixels against that.
    if (!restricted) pastePixels(baseline, width, rect, result);
    final previous = pendingMerge;
    return () async {
      await previous;
      final updates = await _merge(
        layer,
        rect,
        result,
        baselineRect,
        coverageRect,
        lockAlpha,
      );
      if (restricted && identical(this.layer, layer)) {
        // Dabs outside the selection are taken back from the surface.
        surface.loadRgbaRect(rx, y, rw, h, cropPixels(layer, width, rect));
        pastePixels(baseline, width, rect, surface.readRgbaRect(rx, y, rw, h));
      }
      return _pack(rect, updates, watch.elapsedMicroseconds);
    };
  }

  /// Merges into [layer] in place: the tile rows the stroke touched, split
  /// into bands merged and encoded in parallel. A layer that is not exactly
  /// its tiles (vector strokes or an old image rendered in) is rewritten
  /// whole.
  Future<(bool, bool, List<TileUpdate>)> _merge(
    Uint8List layer,
    PixelRect rect,
    Uint8List result,
    Uint8List baselineRect,
    Uint8List? coverageRect,
    bool lockAlpha,
  ) async {
    const size = TiledRaster.size;
    final height = dimensions.height, grid = this.grid;
    final (rx, y, rw, h) = rect;
    final full = !exact;
    final firstRow = full ? 0 : y ~/ size;
    final lastRow = full ? grid.rows - 1 : (y + h - 1) ~/ size;
    final bands = full ? 1 : math.min(tileEncoders, lastRow - firstRow + 1);
    final work = <Future<(int, int, NativeTilesResult)>>[];
    for (var b = 0; b < bands; b++) {
      final span = lastRow - firstRow + 1;
      final rowStart = (firstRow + span * b ~/ bands) * size;
      final rowEnd = math.min(
        height,
        (firstRow + span * (b + 1) ~/ bands) * size,
      );
      final top = math.max(y, rowStart), bottom = math.min(y + h, rowEnd);
      final rows = Uint8List.sublistView(
        layer,
        rowStart * width * 4,
        rowEnd * width * 4,
      );
      Uint8List? slice(Uint8List? source, int bytes) => source == null
          ? null
          : Uint8List.sublistView(
              source,
              (top - y) * rw * bytes,
              (bottom - y) * rw * bytes,
            );
      final bandBaseline = slice(baselineRect, 4)!;
      final bandResult = slice(result, 4)!;
      final bandCoverage = slice(coverageRect, 1);
      final spread = bands == 1;
      work.add(
        Isolate.run(() async {
          final merge = mergeNativeTiles(
            rows,
            rowStart,
            bandBaseline,
            bandResult,
            bandCoverage,
            (rx, top, rw, bottom - top),
            grid,
            allTiles: full,
            lockAlpha: lockAlpha,
          );
          final updates = !merge.changed
              ? const <TileUpdate>[]
              : spread
              ? await encodeTiles(merge.tiles)
              : [for (final (i, t) in merge.tiles) encodeCutTile(i, t)];
          return (
            rowStart,
            rowEnd,
            NativeTilesResult(merge.rows, merge.changed, updates),
          );
        }),
      );
    }
    final merged = await Future.wait(work);
    final changed = merged.any((m) => m.$3.changed);
    for (final (rowStart, rowEnd, band) in merged) {
      if (band.changed) {
        layer.setRange(rowStart * width * 4, rowEnd * width * 4, band.rows);
      }
    }
    if (changed && identical(this.layer, layer)) exact = true;
    return (
      changed,
      full && changed,
      [for (final (_, _, band) in merged) ...band.updates],
    );
  }

  /// One transferable buffer of every new tile's PNG followed by its
  /// premultiplied pixels, so the UI isolate receives them without a copy.
  Object _pack(
    PixelRect rect,
    (bool, bool, List<TileUpdate>) merged,
    int micros,
  ) {
    final (changed, full, updates) = merged;
    const tileBytes = TiledRaster.size * TiledRaster.size * 4;
    var total = 0;
    for (final update in updates) {
      if (update.png != null) total += update.png!.length + tileBytes;
    }
    final packed = Uint8List(total);
    final meta = <(int, int, int, TileBounds?)>[];
    var offset = 0;
    for (final update in updates) {
      final png = update.png;
      if (png == null) {
        meta.add((update.index, 0, -1, null));
        continue;
      }
      meta.add((update.index, offset, png.length, update.bounds));
      packed.setRange(offset, offset + png.length, png);
      packed.setRange(
        offset + png.length,
        offset + png.length + tileBytes,
        update.premultiplied!,
      );
      offset += png.length + tileBytes;
    }
    return (
      rect,
      changed,
      full,
      meta,
      total == 0 ? null : TransferableTypedData.fromList([packed]),
      micros,
    );
  }
}

Future<void> _runLayerWorker((SendPort, int, int) init) async {
  final (replies, width, height) = init;
  final requests = ReceivePort();
  _Layer? state;
  try {
    state = _Layer(
      NativeBrushSurface(width: width, height: height),
      CanvasSize(width, height),
    );
    replies.send([0, true, requests.sendPort]);
    await for (final message in requests) {
      final (id, operation, argument) = message as (int, String, Object?);
      try {
        Object? result;
        final surface = state.surface;
        switch (operation) {
          case 'loadTiles':
            await state.pendingMerge;
            final pixels = assembleTiles(
              argument as Map<int, Uint8List>,
              state.grid,
            );
            if (pixels != null) state.load(pixels, true);
            result = pixels != null;
          case 'loadPixels':
            await state.pendingMerge;
            final (data, exact) = argument as (TransferableTypedData, bool);
            state.load(data.materialize().asUint8List(), exact);
          case 'alphaLock':
            state.lockAlpha = argument as bool;
          case 'clip':
            state.coverage = (argument as TransferableTypedData?)
                ?.materialize()
                .asUint8List();
          case 'preset':
            surface.loadPreset(argument as String);
          case 'smudge':
            surface.setSmudge(argument as bool);
          case 'symmetry':
            final (matrices, cx, cy) =
                argument
                    as (List<(double, double, double, double)>, double, double);
            surface.setSymmetry(matrices, cx, cy);
          case 'stamp':
            final (tip, grain, settings, dual) =
                argument
                    as (
                      StampImage,
                      StampImage?,
                      StampSettings,
                      (StampImage, DualStamp)?,
                    );
            surface.loadStamp(tip, settings, grain: grain, dual: dual);
          case 'configure':
            final (diameter, hue, saturation, value, opacity, eraser) =
                argument as (double, double, double, double, double, bool);
            surface.configure(
              diameter: diameter,
              hue: hue,
              saturation: saturation,
              value: value,
              opacity: opacity,
              eraser: eraser,
            );
          case 'begin':
            state.touched.clear();
            surface.takeDirtyTiles();
            surface.beginStroke();
          case 'points':
            for (final (x, y, pressure, tx, ty, seconds)
                in argument as List<BrushSample>) {
              surface.point(
                x: x,
                y: y,
                pressure: pressure,
                tiltX: tx,
                tiltY: ty,
                seconds: seconds,
              );
            }
          case 'dirty':
            result = state.dirty(read: true);
          case 'commit':
            final merge = state.prepare();
            if (state.coverage != null || state.lockAlpha) {
              // A selection-limited stroke must be taken back from the
              // surface before the next one paints: wait for it.
              final done = merge();
              state.pendingMerge = done.then((_) {}, onError: (Object _) {});
              result = await done;
            } else {
              // The next stroke may paint while this one merges.
              final done = merge();
              state.pendingMerge = done.then((_) {}, onError: (Object _) {});
              done.then(
                (value) => replies.send([id, true, value]),
                onError: (Object error) =>
                    replies.send([id, false, error.toString()]),
              );
              continue;
            }
          case 'close':
            surface.close();
            replies.send([id, true, null]);
            return;
          default:
            throw ArgumentError('Unknown layer operation.');
        }
        replies.send([id, true, result]);
      } catch (error) {
        replies.send([id, false, error.toString()]);
      }
    }
  } catch (error) {
    replies.send([0, false, error.toString()]);
  } finally {
    state?.surface.close();
    requests.close();
  }
}
