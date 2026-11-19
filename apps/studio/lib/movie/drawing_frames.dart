import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import '../domain/movie.dart';
import '../drawing/brush_engine.dart';
import '../drawing/raster_cache.dart';

/// What [content] shows at movie [frame] from [drawing]: a Flipbook's
/// frame (holds counted, its frames looping over the content's length), or
/// the whole drawing; null when it is not on screen then.
({ArtDocument view, int page})? drawingAt(
  MovieContent content,
  ArtDocument drawing,
  int frame,
) {
  final source = content.sourceFrame(frame);
  if (source == null) return null;
  final settings = drawing.animation;
  if (!drawing.animating || settings == null) return (view: drawing, page: -1);
  final order = settings.copyWith(mode: PlaybackMode.loop).playOrder([
    for (final p in drawing.pages) ArtDocument.frameId(p),
  ]);
  if (order.isEmpty) return (view: drawing, page: -1);
  final page = order[source % order.length];
  return (view: drawing.animationFrame(page), page: page);
}

/// Drawings and Flipbook frames rendered once for the stage (at most
/// [longest] pixels on a side), the most recently used kept. A changed
/// drawing renders again while the old picture still shows.
class DrawingFrames extends ChangeNotifier {
  DrawingFrames({this.longest = 1280, this.keep = 120});
  final double longest;
  final int keep;

  /// Least recently used first (map literals keep insertion order).
  final _images = <(String, int), ({ArtDocument doc, ui.Image image})>{};
  final _pending = <(String, int)>{};
  final _failed = <(String, int), ArtDocument>{};
  final _rasters = RasterCache();
  bool _disposed = false;

  /// The picture of [content]'s drawing at [frame] if one is ready (an
  /// older one while a newer renders); renders it otherwise.
  ui.Image? image(MovieContent content, ArtDocument drawing, int frame) {
    final at = drawingAt(content, drawing, frame);
    if (at == null) return null;
    final key = (content.id, at.page);
    final hit = _images.remove(key);
    if (hit != null) _images[key] = hit;
    if ((hit == null || !identical(hit.doc, drawing)) &&
        !identical(_failed[key], drawing)) {
      _render(key, drawing, at.view);
    }
    return hit?.image;
  }

  Future<void> _render(
    (String, int) key,
    ArtDocument drawing,
    ArtDocument view,
  ) async {
    if (!_pending.add(key)) return;
    ui.Picture? picture;
    try {
      await _rasters.prepare(documentRasters(view));
      if (_disposed) return;
      final size = view.dimensions;
      final scale = math.min(1.0, longest / math.max(size.width, size.height));
      final recorder = ui.PictureRecorder();
      paintDocument(
        ui.Canvas(recorder)..scale(scale),
        view,
        FreehandBrushEngine(),
        rasterImages: _rasters.images,
      );
      picture = recorder.endRecording();
      final image = await picture.toImage(
        math.max(1, (size.width * scale).round()),
        math.max(1, (size.height * scale).round()),
      );
      if (_disposed) {
        image.dispose();
        return;
      }
      _images.remove(key)?.image.dispose();
      _images[key] = (doc: drawing, image: image);
      while (_images.length > keep) {
        final oldest = _images.keys.first;
        _images.remove(oldest)!.image.dispose();
      }
      notifyListeners();
    } catch (_) {
      // A drawing that cannot render shows its frame only, until it changes.
      _failed[key] = drawing;
    } finally {
      picture?.dispose();
      _pending.remove(key);
    }
  }

  /// Something is still being rendered or loaded.
  bool get busy => _pending.isNotEmpty || _loadingFiles.isNotEmpty;

  final _files = <String, ui.Image>{};
  final _loadingFiles = <String>{}, _badFiles = <String>{};

  /// The picture in file [path] (a video's proxy frame) if loaded; loads
  /// it otherwise.
  ui.Image? fileImage(String path) {
    final hit = _files.remove(path);
    if (hit != null) {
      _files[path] = hit;
      return hit;
    }
    if (!_badFiles.contains(path) && _loadingFiles.add(path)) {
      () async {
        try {
          final codec = await ui.instantiateImageCodec(
            await File(path).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          codec.dispose();
          if (_disposed) return frame.image.dispose();
          _files[path] = frame.image;
          while (_files.length > keep) {
            _files.remove(_files.keys.first)!.dispose();
          }
          notifyListeners();
        } catch (_) {
          _badFiles.add(path);
        } finally {
          _loadingFiles.remove(path);
        }
      }();
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _files.values) {
      image.dispose();
    }
    _files.clear();
    for (final entry in _images.values) {
      entry.image.dispose();
    }
    _images.clear();
    _rasters.dispose();
    super.dispose();
  }
}
