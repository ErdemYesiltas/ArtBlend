import 'dart:math' as math;
import 'dart:ui' as ui;

import '../domain/document.dart';
import 'brush_engine.dart';

/// What a frame draws instead of every layer: the paper and the layers below
/// the active one flattened into [below], the active layer itself, and the
/// layers above it flattened into [above] when they all blend normally
/// (source-over is associative, so the result is identical). Otherwise the
/// layers above are drawn one by one.
class CompositeFrame {
  const CompositeFrame(this.below, this.above, this.activeIndex, this.flat);
  final CompositeChunks below;

  /// Empty when nothing visible lies above the active layer.
  final CompositeChunks above;
  final int activeIndex;
  final bool flat;
}

/// A flattened image in [LayerCompositor.chunk]² pieces at their document
/// positions: each piece is rendered between frames, so building never holds
/// the GPU for a whole large canvas.
typedef CompositeChunks = List<(ui.Offset, ui.Image)>;

class _Composite {
  _Composite(this.key, this.chunks);
  final List<Object?> key;
  final CompositeChunks chunks;
  bool matches(List<Object?> other) {
    if (other.length != key.length) return false;
    for (var i = 0; i < key.length; i++) {
      if (!identical(key[i], other[i]) && key[i] != other[i]) return false;
    }
    return true;
  }

  void dispose() {
    for (final (_, image) in chunks) {
      image.dispose();
    }
  }
}

/// Keeps the flattened layers of the drawing being edited at document
/// resolution. Keys are layer identities: painting on the active layer never
/// invalidates them; changing any other layer, its order, or which layer is
/// active rebuilds them in the background, while frames draw every layer.
class LayerCompositor {
  LayerCompositor({required this.onReady});

  /// Side of each rendered piece.
  static const chunk = 512;

  /// Called when new composites are ready to draw.
  final void Function() onReady;
  _Composite? _below, _above;
  bool _building = false, _disposed = false;

  /// The composites for [doc] as it is now, or null when they are being
  /// (re)built and the frame should draw every layer.
  CompositeFrame? frame(ArtDocument doc, Map<RasterAsset, ui.Image> images) {
    final index = doc.layers.indexWhere((l) => l.id == doc.activeLayerId);
    // A live layer inside a clipping group, or in a layer group that is
    // composited as one (or hidden), is drawn with its group.
    if (index < 0 || inClippingGroup(doc.layers, index)) return null;
    final group = doc.groupOf(doc.layers[index]);
    if (group != null && (!group.passThrough || !group.visible)) return null;
    // A live layer in a mode the blend shader paints needs what is under
    // it as an image: drawn with everything.
    if (customBlend(doc.layers[index].blend) != null) return null;
    final aboveLayers = doc.layers.sublist(index + 1);
    final flat = aboveLayers.every(
      (l) =>
          l.blend == LayerBlend.normal &&
          (doc.groupOf(l)?.blend ?? LayerBlend.normal) == LayerBlend.normal,
    );
    final belowKey = _keyBelow(doc, index);
    final aboveKey = flat ? _keyAbove(doc, index) : null;
    final below = _below, above = _above;
    final belowReady = below != null && below.matches(belowKey);
    final aboveReady =
        aboveKey == null || (above != null && above.matches(aboveKey));
    if (belowReady && aboveReady) {
      return CompositeFrame(
        below.chunks,
        flat ? above!.chunks : const [],
        index,
        flat,
      );
    }
    _build(
      doc,
      images,
      belowReady ? null : belowKey,
      aboveReady ? null : aboveKey,
    );
    return null;
  }

  static List<Object?> _keyBelow(ArtDocument doc, int index) => [
    doc.dimensions,
    doc.background,
    doc.backgroundHidden,
    ...doc.groups,
    ...doc.layers.take(index),
  ];

  static List<Object?> _keyAbove(ArtDocument doc, int index) => [
    doc.dimensions,
    ...doc.groups,
    ...doc.layers.skip(index + 1),
  ];

  Future<void> _build(
    ArtDocument doc,
    Map<RasterAsset, ui.Image> images,
    List<Object?>? belowKey,
    List<Object?>? aboveKey,
  ) async {
    if (_building || _disposed) return;
    _building = true;
    try {
      final index = doc.layers.indexWhere((l) => l.id == doc.activeLayerId);
      if (belowKey != null) {
        final chunks = await _render(
          doc,
          doc.layers.take(index).toList(),
          images,
          paper: true,
        );
        if (_disposed) {
          _Composite(belowKey, chunks).dispose();
          return;
        }
        _below?.dispose();
        _below = _Composite(belowKey, chunks);
      }
      if (aboveKey != null) {
        final layers = doc.layers.skip(index + 1).toList();
        // Nothing above: an empty composite, nothing to draw.
        final chunks = layers.any((l) => l.visible && l.opacity > 0)
            ? await _render(doc, layers, images, paper: false)
            : <(ui.Offset, ui.Image)>[];
        if (_disposed) {
          _Composite(aboveKey, chunks).dispose();
          return;
        }
        _above?.dispose();
        _above = _Composite(aboveKey, chunks);
      }
    } catch (_) {
      // A missing image or a failed render: frames keep drawing every layer.
    } finally {
      _building = false;
    }
    if (!_disposed) onReady();
  }

  static Future<CompositeChunks> _render(
    ArtDocument doc,
    List<ArtLayer> layers,
    Map<RasterAsset, ui.Image> images, {
    required bool paper,
  }) async {
    final dimensions = doc.dimensions;
    final chunks = <(ui.Offset, ui.Image)>[];
    try {
      for (var y = 0; y < dimensions.height; y += chunk) {
        for (var x = 0; x < dimensions.width; x += chunk) {
          final area = ui.Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            math.min(chunk, dimensions.width - x).toDouble(),
            math.min(chunk, dimensions.height - y).toDouble(),
          );
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder)
            ..translate(-area.left, -area.top)
            ..clipRect(area);
          void background(ui.Canvas c) {
            if (paper && !doc.backgroundHidden) {
              c.drawRect(area, ui.Paint()..color = ui.Color(doc.background));
            }
          }

          background(canvas);
          paintGroupedLayers(
            canvas,
            layers,
            doc.groups,
            area,
            under: background,
            (canvas, layer, {required asBase}) => paintLayer(
              canvas,
              layer,
              FreehandBrushEngine(),
              dimensions,
              rasterImages: images,
              visible: area,
              applyOpacity: !asBase,
            ),
          );
          final picture = recorder.endRecording();
          // One piece at a time: frames reach the GPU between pieces.
          try {
            chunks.add((
              area.topLeft,
              await picture.toImage(area.width.toInt(), area.height.toInt()),
            ));
          } finally {
            picture.dispose();
          }
        }
      }
      return chunks;
    } catch (_) {
      for (final (_, image) in chunks) {
        image.dispose();
      }
      rethrow;
    }
  }

  /// Drops the composites, e.g. when another drawing opens.
  void clear() {
    _below?.dispose();
    _above?.dispose();
    _below = _above = null;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
