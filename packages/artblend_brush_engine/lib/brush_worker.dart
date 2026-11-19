import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'artblend_brush_engine.dart';

/// One native surface owned by a persistent worker, keeping C off the UI thread.
final class BrushWorker {
  final ReceivePort _responses = ReceivePort();
  final Completer<SendPort> _ready = Completer();
  final Map<int, Completer<Object?>> _pending = {};
  Isolate? _isolate;
  Future<void>? _closeFuture;
  int _nextId = 1;
  bool _closed = false;
  bool _closing = false;

  BrushWorker._() {
    _responses.listen((Object? message) {
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
        _fail(StateError('Brush worker exited: $message'));
      }
    });
  }

  static Future<BrushWorker> create({
    required int width,
    required int height,
  }) async {
    final worker = BrushWorker._();
    try {
      worker._isolate = await Isolate.spawn(
        _runWorker,
        (worker._responses.sendPort, width, height),
        onError: worker._responses.sendPort,
        onExit: worker._responses.sendPort,
        errorsAreFatal: true,
        debugName: 'ArtBlend MyPaint',
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
      throw StateError('Brush worker is closed.');
    }
    final port = await _ready.future;
    // close() can run while an earlier call waits for startup.
    if (_closed || (_closing && operation != 'close')) {
      throw StateError('Brush worker is closed.');
    }
    final id = _nextId++;
    final result = Completer<Object?>();
    _pending[id] = result;
    port.send((id, operation, argument));
    return result.future;
  }

  Future<void> loadPreset(String json) async => await _request('preset', json);

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

  /// Batches preserve ordering. Tuples: x, y, pressure, tiltX, tiltY, seconds.
  Future<void> points(
    List<(double, double, double, double, double, double)> samples,
  ) async {
    if (samples.isEmpty || samples.length > 2048) {
      throw ArgumentError('Expected 1–2048 samples.');
    }
    await _request('points', List.of(samples));
  }

  Future<void> loadRgba(Uint8List rgba) async =>
      await _request('load', TransferableTypedData.fromList([rgba]));

  Future<Uint8List> readRgba() async {
    final data = await _request('read') as TransferableTypedData;
    return data.materialize().asUint8List();
  }

  /// Premultiplied RGBA8, as `decodeImageFromPixels` and GPU images expect.
  /// Converted inside the worker so the UI isolate only receives the bytes.
  Future<Uint8List> readRgbaPremultiplied() async {
    final data = await _request('readPremultiplied') as TransferableTypedData;
    return data.materialize().asUint8List();
  }

  Future<void> loadRgbaRect(int x, int y, int w, int h, Uint8List rgba) async =>
      await _request('loadRect', (
        x,
        y,
        w,
        h,
        TransferableTypedData.fromList([rgba]),
      ));

  Future<Uint8List> readRgbaRect(
    int x,
    int y,
    int w,
    int h, {
    bool premultiplied = false,
  }) async {
    final data = await _request('readRect', (
      x,
      y,
      w,
      h,
      premultiplied,
    )) as TransferableTypedData;
    return data.materialize().asUint8List();
  }

  /// Clears and returns the chunks (square blocks of [chunk] pixels, a
  /// multiple of 64) that dabs touched since the previous call. With [read],
  /// also their premultiplied pixels, concatenated in index order; edge
  /// chunks are clipped to the surface.
  Future<DirtyChunks> takeDirtyChunks({
    int chunk = 128,
    bool read = true,
  }) async {
    final (indices, data) = await _request('dirty', (
      chunk,
      read,
    )) as (List<int>, TransferableTypedData?);
    return DirtyChunks(chunk, indices, data?.materialize().asUint8List());
  }

  Future<int> get allocatedTiles async => await _request('tiles') as int;

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      await _request('close');
    } finally {
      _closed = true;
      _responses.close();
      // Worker acknowledges only after releasing all native allocations.
      _isolate?.kill(priority: Isolate.immediate);
    }
  }
}

final class DirtyChunks {
  const DirtyChunks(this.chunk, this.indices, this.pixels);
  final int chunk;

  /// Row-major chunk indices: `row * columns + column`.
  final List<int> indices;
  final Uint8List? pixels;
}

(List<int>, TransferableTypedData?) _dirtyChunks(
  NativeBrushSurface surface,
  int chunk,
  bool read,
) {
  const tile = NativeBrushSurface.tileSize;
  if (chunk < tile || chunk % tile != 0) {
    throw ArgumentError('Chunk must be a multiple of the tile size.');
  }
  final tiles = surface.takeDirtyTiles();
  final per = chunk ~/ tile;
  final columns = (surface.width + chunk - 1) ~/ chunk;
  final indices = <int>{};
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i] == 0) continue;
    final tx = i % surface.tileColumns, ty = i ~/ surface.tileColumns;
    indices.add((ty ~/ per) * columns + tx ~/ per);
  }
  final sorted = indices.toList()..sort();
  if (!read || sorted.isEmpty) return (sorted, null);
  final out = BytesBuilder(copy: false);
  for (final index in sorted) {
    final x = (index % columns) * chunk, y = (index ~/ columns) * chunk;
    out.add(
      surface.readRgbaRect(
        x,
        y,
        math.min(chunk, surface.width - x),
        math.min(chunk, surface.height - y),
        premultiplied: true,
      ),
    );
  }
  return (sorted, TransferableTypedData.fromList([out.takeBytes()]));
}

/// Straight → premultiplied RGBA8 in place, rounding to nearest.
Uint8List premultiplyRgba(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      rgba[i] = rgba[i + 1] = rgba[i + 2] = 0;
      continue;
    }
    rgba[i] = (rgba[i] * a + 127) ~/ 255;
    rgba[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
    rgba[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
  }
  return rgba;
}

Future<void> _runWorker((SendPort, int, int) init) async {
  final (replies, width, height) = init;
  final requests = ReceivePort();
  NativeBrushSurface? surface;
  try {
    surface = NativeBrushSurface(width: width, height: height);
    replies.send([0, true, requests.sendPort]);
    await for (final message in requests) {
      final (id, operation, argument) = message as (int, String, Object?);
      try {
        Object? result;
        switch (operation) {
          case 'preset':
            surface.loadPreset(argument as String);
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
            surface.beginStroke();
          case 'points':
            for (final (x, y, pressure, tx, ty, seconds)
                in argument
                    as List<(double, double, double, double, double, double)>) {
              surface.point(
                x: x,
                y: y,
                pressure: pressure,
                tiltX: tx,
                tiltY: ty,
                seconds: seconds,
              );
            }
          case 'load':
            surface.loadRgba(
              (argument as TransferableTypedData).materialize().asUint8List(),
            );
          case 'read':
            result = TransferableTypedData.fromList([surface.readRgba()]);
          case 'readPremultiplied':
            result = TransferableTypedData.fromList([
              premultiplyRgba(surface.readRgba()),
            ]);
          case 'loadRect':
            final (x, y, w, h, data) =
                argument as (int, int, int, int, TransferableTypedData);
            surface.loadRgbaRect(x, y, w, h, data.materialize().asUint8List());
          case 'readRect':
            final (x, y, w, h, premultiplied) =
                argument as (int, int, int, int, bool);
            result = TransferableTypedData.fromList([
              surface.readRgbaRect(x, y, w, h, premultiplied: premultiplied),
            ]);
          case 'dirty':
            final (chunk, read) = argument as (int, bool);
            result = _dirtyChunks(surface, chunk, read);
          case 'tiles':
            result = surface.allocatedTiles;
          case 'close':
            surface.close();
            replies.send([id, true, null]);
            return;
          default:
            throw ArgumentError('Unknown brush operation.');
        }
        replies.send([id, true, result]);
      } catch (error) {
        replies.send([id, false, error.toString()]);
      }
    }
  } catch (error) {
    replies.send([0, false, error.toString()]);
  } finally {
    surface?.close();
    requests.close();
  }
}
