import '../domain/document.dart';

/// What one history step did, read from the drawing before and after it,
/// for the banner that names an undo or redo.
enum HistoryChange {
  paint,
  addLayer,
  deleteLayer,
  mergeLayers,
  moveLayer,
  layerMask,
  layerSettings,
  rename,
  canvas,
  edit,
}

/// What was done to turn [earlier] into [later].
HistoryChange describeChange(ArtDocument earlier, ArtDocument later) {
  if (earlier.dimensions != later.dimensions ||
      earlier.background != later.background ||
      earlier.backgroundHidden != later.backgroundHidden) {
    return HistoryChange.canvas;
  }
  if (earlier.name != later.name) return HistoryChange.rename;
  final before = {for (final l in earlier.layers) l.id: l};
  final after = {for (final l in later.layers) l.id: l};
  // Layers rewrap their stroke list on every copy: compare the strokes.
  bool sameStrokes(List<InkStroke> a, List<InkStroke> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  bool pixels(ArtLayer a, ArtLayer b) =>
      !identical(a.raster, b.raster) ||
      !sameStrokes(a.strokes, b.strokes) ||
      !identical(a.legacyRaster, b.legacyRaster) ||
      a.text != b.text;
  final kept = [
    for (final MapEntry(:key, :value) in after.entries)
      if (before[key] case final old?) (old, value),
  ];
  if (after.length > before.length) return HistoryChange.addLayer;
  if (after.length < before.length) {
    return kept.any((pair) => pixels(pair.$1, pair.$2))
        ? HistoryChange.mergeLayers
        : HistoryChange.deleteLayer;
  }
  if (!after.keys.every(before.containsKey)) return HistoryChange.edit;
  final changed = [
    for (final (a, b) in kept)
      if (!identical(a, b)) (a, b),
  ];
  if (changed.isEmpty) {
    final order = [for (final l in earlier.layers) l.id];
    final next = [for (final l in later.layers) l.id];
    for (var i = 0; i < order.length; i++) {
      if (order[i] != next[i]) return HistoryChange.moveLayer;
    }
    return HistoryChange.edit;
  }
  if (changed.length > 1) return HistoryChange.edit;
  final (a, b) = changed.single;
  if (pixels(a, b)) return HistoryChange.paint;
  if (!identical(a.mask, b.mask)) return HistoryChange.layerMask;
  return HistoryChange.layerSettings;
}
