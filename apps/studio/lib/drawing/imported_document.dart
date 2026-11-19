import '../data/import_formats.dart';
import '../domain/document.dart';
import 'raster_tiles.dart';

/// [drawing] (a file's layers, bottom first) as an ArtBlend document named
/// [name]: its layers as tiles (at most [maxLayers], the top ones), its
/// groups; see-through, the file's background being one of its layers.
Future<ArtDocument> documentFromImport(
  ImportedDrawing drawing,
  String name, {
  required int maxLayers,
}) async {
  final grid = TileGrid(drawing.size);
  final kept = drawing.layers.length > maxLayers
      ? drawing.layers.sublist(drawing.layers.length - maxLayers)
      : drawing.layers;
  final layers = <ArtLayer>[];
  for (final (i, layer) in kept.indexed) {
    final rendered = await tilesFromRgba(layer.rgba, grid);
    layers.add(
      ArtLayer(
        id: newId(),
        name: layer.name.trim().isEmpty ? 'Layer ${i + 1}' : layer.name,
        raster: rendered.raster,
        opacity: layer.opacity.clamp(0, 1),
        blend: layer.blend,
        visible: layer.visible,
        clipping: layer.clipping && i > 0,
        group: layer.group,
      ),
    );
  }
  return ArtDocument(
    id: newId(),
    name: name,
    dimensions: drawing.size,
    dpi: drawing.dpi,
    layers: layers,
    activeLayerId: layers.last.id,
    backgroundHidden: true,
    groups: [
      for (final g in drawing.groups)
        LayerGroup(
          id: g.id,
          name: g.name,
          visible: g.visible,
          opacity: g.passThrough ? 1 : g.opacity.clamp(0, 1),
          blend: g.passThrough ? LayerBlend.normal : g.blend,
        ),
    ],
  );
}
