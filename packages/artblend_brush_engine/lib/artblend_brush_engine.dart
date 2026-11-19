/// Native MyPaint brush surfaces. Own a surface in a worker isolate while drawing.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'artblend_brush_engine_bindings_generated.dart' as native;
import 'stamp_settings.dart';

export 'stamp_settings.dart';

/// A sparse RGBA16 tile surface backed by libmypaint 1.6.1.
///
/// Calls are synchronous; use a persistent worker isolate for interactive input.
/// Each instance has one owner and must never be shared between isolates.
final class NativeBrushSurface implements Finalizable {
  static final _finalizer = NativeFinalizer(
    Native.addressOf<
          NativeFunction<Void Function(Pointer<native.ABBrushSurface>)>
        >(native.ab_surface_destroy)
        .cast(),
  );

  static String get engineVersion =>
      native.ab_engine_version().cast<Utf8>().toDartString();

  final int width;
  final int height;
  Pointer<native.ABBrushSurface> _handle;

  NativeBrushSurface({required this.width, required this.height})
    : _handle = native.ab_surface_create(width, height) {
    if (_handle == nullptr) {
      throw ArgumentError('Surface dimensions must be 1–4096 pixels per edge.');
    }
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  void _checkOpen() {
    if (_handle == nullptr) throw StateError('Brush surface is closed.');
  }

  /// Version 3 MyPaint JSON. Invalid files leave the current brush intact.
  void loadPreset(String json) {
    _checkOpen();
    final bytes = utf8.encode(json);
    if (bytes.isEmpty || bytes.length > 1024 * 1024 || bytes.contains(0)) {
      throw const FormatException('Invalid MyPaint preset size or encoding.');
    }
    using((arena) {
      final data = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      if (native.ab_brush_load(_handle, data.cast(), bytes.length) == 0) {
        throw const FormatException(
          'Unsupported or invalid MyPaint version 3 preset.',
        );
      }
    });
  }

  /// Switches to a stamp brush: [tip] stamped along each stroke, [grain]
  /// tiled over the canvas. Stays until the next [loadPreset]. Invalid input
  /// leaves the current brush intact.
  /// A [dual] secondary tip makes it a dual brush.
  void loadStamp(
    StampImage tip,
    StampSettings settings, {
    StampImage? grain,
    (StampImage, DualStamp)? dual,
  }) {
    _checkOpen();
    if (tip.width > 512 || tip.height > 512) {
      throw ArgumentError('Stamp tips are at most 512 pixels per edge.');
    }
    if (grain != null && (grain.width > 1024 || grain.height > 1024)) {
      throw ArgumentError('Stamp grains are at most 1024 pixels per edge.');
    }
    using((arena) {
      final shape = arena<Uint8>(tip.pixels.length)
        ..asTypedList(tip.pixels.length).setAll(0, tip.pixels);
      final texture = grain == null
          ? nullptr
          : (arena<Uint8>(grain.pixels.length)
              ..asTypedList(grain.pixels.length).setAll(0, grain.pixels));
      final values = settings.params;
      final params = arena<Float>(values.length)
        ..asTypedList(values.length).setAll(0, values);
      if (native.ab_stamp_load(
            _handle,
            shape,
            tip.width,
            tip.height,
            texture,
            grain?.width ?? 0,
            grain?.height ?? 0,
            params,
            values.length,
          ) ==
          0) {
        throw const FormatException('Invalid stamp brush.');
      }
      if (settings.wet &&
          native.ab_stamp_wet(
                _handle,
                settings.dilution,
                settings.charge,
                settings.pull,
              ) ==
              0) {
        throw const FormatException('Invalid wet mix.');
      }
      if (dual case (final second, final settings2)) {
        if (second.width > 512 || second.height > 512) {
          throw ArgumentError('Stamp tips are at most 512 pixels per edge.');
        }
        final shape2 = arena<Uint8>(second.pixels.length)
          ..asTypedList(second.pixels.length).setAll(0, second.pixels);
        final values2 = settings2.params;
        final params2 = arena<Float>(values2.length)
          ..asTypedList(values2.length).setAll(0, values2);
        if (native.ab_stamp_dual(
              _handle,
              shape2,
              second.width,
              second.height,
              params2,
              values2.length,
            ) ==
            0) {
          throw const FormatException('Invalid dual brush.');
        }
      }
    });
  }

  /// Smudges instead of painting until turned off: the configured opacity
  /// is the strength. Set between strokes.
  void setSmudge(bool on) {
    _checkOpen();
    native.ab_brush_smudge(_handle, on ? 1 : 0);
  }

  /// Draws each stroke point also at `center + M (p − center)` for every
  /// row-major 2×2 [matrices] entry (1–8, entries in −1…1; the first is
  /// usually the identity). Set between strokes.
  void setSymmetry(
    List<(double, double, double, double)> matrices,
    double cx,
    double cy,
  ) {
    _checkOpen();
    if (matrices.isEmpty || matrices.length > native.AB_MAX_COPIES) {
      throw ArgumentError(
        'Expected 1–${native.AB_MAX_COPIES} symmetry copies.',
      );
    }
    using((arena) {
      final values = arena<Float>(matrices.length * 4);
      for (final (i, (a, b, c, d)) in matrices.indexed) {
        values[i * 4] = a;
        values[i * 4 + 1] = b;
        values[i * 4 + 2] = c;
        values[i * 4 + 3] = d;
      }
      if (native.ab_symmetry(_handle, values, matrices.length, cx, cy) == 0) {
        throw ArgumentError('Invalid symmetry.');
      }
    });
  }

  /// Overrides size and HSV color and scales the preset's opacity by
  /// [opacity]; pressure and tilt curves remain active.
  void configure({
    required double diameter,
    double hue = 0,
    double saturation = 0,
    double value = 0,
    double opacity = 1,
    bool eraser = false,
  }) {
    _checkOpen();
    if (native.ab_brush_configure(
          _handle,
          diameter,
          hue,
          saturation,
          value,
          opacity,
          eraser ? 1 : 0,
        ) ==
        0) {
      throw ArgumentError('Invalid brush size, HSV color or opacity.');
    }
  }

  void beginStroke() {
    _checkOpen();
    native.ab_stroke_begin(_handle);
  }

  void point({
    required double x,
    required double y,
    required double pressure,
    double tiltX = 0,
    double tiltY = 0,
    double seconds = 1 / 120,
  }) {
    _checkOpen();
    if (native.ab_stroke_point(
          _handle,
          x,
          y,
          pressure,
          tiltX,
          tiltY,
          seconds,
        ) ==
        0) {
      throw StateError('Invalid brush input or native tile allocation failed.');
    }
  }

  /// Replaces pixels; straight-alpha RGBA8, exactly width × height × 4 bytes.
  void loadRgba(Uint8List rgba) {
    _checkOpen();
    if (rgba.length != width * height * 4) {
      throw ArgumentError('Incorrect RGBA byte count.');
    }
    using((arena) {
      final data = arena<Uint8>(rgba.length)
        ..asTypedList(rgba.length).setAll(0, rgba);
      if (native.ab_surface_load_rgba(_handle, data, rgba.length) == 0) {
        throw StateError('Native pixel import failed.');
      }
    });
  }

  Uint8List readRgba() {
    _checkOpen();
    return using((arena) {
      final length = width * height * 4;
      final data = arena<Uint8>(length);
      if (native.ab_surface_read_rgba(_handle, data, length) == 0) {
        throw StateError('Native pixel export failed.');
      }
      return Uint8List.fromList(data.asTypedList(length));
    });
  }

  /// Edge of the native tiles reported by [takeDirtyTiles].
  static const tileSize = 64;
  int get tileColumns => (width + tileSize - 1) ~/ tileSize;
  int get tileRows => (height + tileSize - 1) ~/ tileSize;

  void _checkRect(int x, int y, int w, int h) {
    if (x < 0 || y < 0 || w < 1 || h < 1 || x + w > width || y + h > height) {
      throw RangeError('Rectangle outside the surface.');
    }
  }

  /// Replaces one rectangle; straight-alpha RGBA8, exactly w × h × 4 bytes.
  void loadRgbaRect(int x, int y, int w, int h, Uint8List rgba) {
    _checkOpen();
    _checkRect(x, y, w, h);
    if (rgba.length != w * h * 4) {
      throw ArgumentError('Incorrect RGBA byte count.');
    }
    using((arena) {
      final data = arena<Uint8>(rgba.length)
        ..asTypedList(rgba.length).setAll(0, rgba);
      if (native.ab_surface_load_rgba_rect(
            _handle,
            x,
            y,
            w,
            h,
            data,
            rgba.length,
          ) ==
          0) {
        throw StateError('Native pixel import failed.');
      }
    });
  }

  /// One rectangle as RGBA8, straight or premultiplied alpha.
  Uint8List readRgbaRect(
    int x,
    int y,
    int w,
    int h, {
    bool premultiplied = false,
  }) {
    _checkOpen();
    _checkRect(x, y, w, h);
    return using((arena) {
      final length = w * h * 4;
      final data = arena<Uint8>(length);
      if (native.ab_surface_read_rgba_rect(
            _handle,
            x,
            y,
            w,
            h,
            premultiplied ? 1 : 0,
            data,
            length,
          ) ==
          0) {
        throw StateError('Native pixel export failed.');
      }
      return Uint8List.fromList(data.asTypedList(length));
    });
  }

  /// Row-major flags of the 64×64 tiles dabs wrote since the previous call.
  /// Loading pixels never marks tiles.
  Uint8List takeDirtyTiles() {
    _checkOpen();
    return using((arena) {
      final length = tileColumns * tileRows;
      final data = arena<Uint8>(length);
      if (native.ab_surface_take_dirty(_handle, data, length) < 0) {
        throw StateError('Native dirty tile query failed.');
      }
      return Uint8List.fromList(data.asTypedList(length));
    });
  }

  int get allocatedTiles {
    _checkOpen();
    return native.ab_surface_allocated_tiles(_handle);
  }

  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    native.ab_surface_destroy(_handle);
    _handle = nullptr;
  }
}
