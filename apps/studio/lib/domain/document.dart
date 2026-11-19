import 'dart:math' as math;
import 'dart:ui';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

import 'builtin_mypaint_presets.dart';
import 'animation.dart';
import 'layer_text.dart';
import 'selection.dart';
import 'canvas_geometry.dart';
export 'canvas_geometry.dart';
export 'animation.dart';
export 'layer_text.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class InkPoint {
  const InkPoint(this.x, this.y, this.pressure);
  final double x, y, pressure;
  List<double> toJson() => [x, y, pressure];
  factory InkPoint.fromJson(dynamic data) {
    if (data is! List || data.length != 3) {
      throw const FormatException('Invalid point');
    }
    final values = data.map((v) => (v as num).toDouble()).toList();
    if (values.any((v) => !v.isFinite) ||
        values[0].abs() > 16384 ||
        values[1].abs() > 16384 ||
        values[2] < 0 ||
        values[2] > 1) {
      throw const FormatException('Point outside document limits');
    }
    return InkPoint(values[0], values[1], values[2]);
  }
}

class InkStroke {
  InkStroke({
    required this.id,
    required List<InkPoint> points,
    required this.color,
    required this.size,
    required this.opacity,
    this.eraser = false,
    this.simulatePressure = false,
    this.smoothing = .5,
    this.thinning = .5,
    this.clip,
    this.atop = false,
  }) : points = List.unmodifiable(points);
  final String id;
  final List<InkPoint> points;
  final int color;
  final double size, opacity, smoothing, thinning;
  final bool eraser, simulatePressure;

  /// Drawn on an alpha-locked layer: paints only over what is there.
  final bool atop;
  final SelectionRegion? clip;
  Map<String, dynamic> toJson({Map<String, SelectionRegion>? regions}) => {
    'id': id,
    if (clip != null && regions == null) 'clip': clip!.toJson(),
    if (clip != null && regions != null)
      'clipId': registerSelection(clip!, regions),
    'points': points.map((p) => p.toJson()).toList(),
    'color': color,
    'size': size,
    'opacity': opacity,
    'eraser': eraser,
    'simulatePressure': simulatePressure,
    'smoothing': smoothing,
    'thinning': thinning,
    if (atop) 'atop': true,
  };
  factory InkStroke.fromJson(
    Map<String, dynamic> json, {
    Map<String, SelectionRegion> regions = const {},
  }) {
    final size = (json['size'] as num).toDouble();
    final opacity = (json['opacity'] as num).toDouble();
    final smoothing = (json['smoothing'] as num? ?? .5).toDouble();
    final thinning = (json['thinning'] as num? ?? .5).toDouble();
    if (!size.isFinite ||
        size <= 0 ||
        size > 256 ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        !smoothing.isFinite ||
        smoothing < 0 ||
        smoothing > 1 ||
        !thinning.isFinite ||
        thinning < -1 ||
        thinning > 1) {
      throw const FormatException('Invalid stroke settings');
    }
    final raw = json['points'] as List;
    if (raw.isEmpty || raw.length > 20000) {
      throw const FormatException('Invalid stroke length');
    }
    return InkStroke(
      id: json['id'] as String,
      clip: readSelection(json, 'clip', regions),
      points: raw.map(InkPoint.fromJson).toList(),
      color: readColor(json['color']),
      size: size,
      opacity: opacity,
      eraser: json['eraser'] as bool? ?? false,
      simulatePressure: json['simulatePressure'] as bool? ?? false,
      smoothing: smoothing,
      thinning: thinning,
      atop: json['atop'] as bool? ?? false,
    );
  }
}

/// Canonical PNG pixels, portable inside .artdoc without external file paths.
String pngDigest(Uint8List png) => crypto.sha256.convert(png).toString();

/// Digests every referenced tile in [json] (layers' `tiles[].sha256`).
Set<String> referencedBlobs(Map<String, dynamic> json) => {
  for (final layer in json['layers'] as List? ?? const [])
    if (layer is Map)
      for (final tile in layer['tiles'] as List? ?? const [])
        if (tile is Map && tile['sha256'] is String) tile['sha256'] as String,
};

/// Keeps only blobs whose bytes match their name; run on a background
/// isolate. A torn or altered tile file then reads as missing.
Map<String, Uint8List> verifiedBlobs(Map<String, Uint8List> blobs) => {
  for (final MapEntry(:key, :value) in blobs.entries)
    if (pngDigest(value) == key) key: value,
};

/// Bytes that `jsonEncode` writes as a base64 string.
class Base64Json {
  const Base64Json(this.bytes);
  final Uint8List bytes;
  String toJson() => base64Encode(bytes);
}

class RasterAsset {
  RasterAsset({
    required this.id,
    required Uint8List png,
    required this.width,
    required this.height,
  }) : png = Uint8List.fromList(png).asUnmodifiableView() {
    if (id.isEmpty ||
        id.length > 128 ||
        png.length > maxBytes ||
        png.length < 33 ||
        width < 1 ||
        height < 1 ||
        width > 4096 ||
        height > 4096) {
      throw const FormatException('Invalid raster asset');
    }
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < signature.length; i++) {
      if (png[i] != signature[i]) {
        throw const FormatException('Raster must be PNG');
      }
    }
    final header = ByteData.sublistView(png);
    if (header.getUint32(8) != 13 ||
        header.getUint32(12) != 0x49484452 ||
        header.getUint32(16) != width ||
        header.getUint32(20) != height) {
      throw const FormatException('Raster dimensions do not match PNG header');
    }
  }
  static const maxBytes = 6 * 1024 * 1024;
  final String id;
  final Uint8List png;
  final int width, height;

  String? _sha256;

  /// Hex SHA-256 of [png]: the tile's file name in the store, so equal
  /// pixels are stored once and a damaged file is detected on reading.
  String get sha256 => _sha256 ??= pngDigest(png);

  /// Hashes assets that have none yet on a background isolate.
  static Future<void> hashAll(Iterable<RasterAsset> assets) async {
    final missing = assets.where((a) => a._sha256 == null).toSet().toList();
    if (missing.isEmpty) return;
    final pngs = [for (final asset in missing) asset.png];
    final digests = await Isolate.run(() => pngs.map(pngDigest).toList());
    for (var i = 0; i < missing.length; i++) {
      missing[i]._sha256 = digests[i];
    }
  }

  /// [deferPng]: leave the PNG as [Base64Json], so base64 happens inside
  /// `jsonEncode`, e.g. on a background isolate. With [blobs] the PNG is
  /// referenced by [sha256] and added to [blobs] instead of embedded.
  Map<String, dynamic> toJson({
    bool deferPng = false,
    Map<String, Uint8List>? blobs,
  }) {
    blobs?[sha256] = png;
    return {
      'id': id,
      if (blobs != null)
        'sha256': sha256
      else
        'png': deferPng ? Base64Json(png) : base64Encode(png),
      'width': width,
      'height': height,
    };
  }

  /// [blobs]: PNG bytes by SHA-256 for assets stored outside the JSON; each
  /// must match its digest (see [verifiedBlobs]).
  factory RasterAsset.fromJson(
    Map<String, dynamic> json, {
    Map<String, Uint8List> blobs = const {},
  }) {
    final digest = json['sha256'];
    final Uint8List png;
    if (digest != null) {
      final stored = digest is String ? blobs[digest] : null;
      if (stored == null) throw const FormatException('Missing raster tile');
      png = stored;
    } else {
      final encoded = json['png'];
      if (encoded is! String || encoded.length > maxBytes * 4 ~/ 3 + 4) {
        throw const FormatException('Raster exceeds size limit');
      }
      png = base64Decode(encoded);
    }
    final asset = RasterAsset(
      id: json['id'] as String,
      png: png,
      width: json['width'] as int,
      height: json['height'] as int,
    );
    if (digest != null) asset._sha256 = digest as String;
    return asset;
  }
}

/// How a canvas is cut into [TiledRaster.size]² tiles, row by row. Edge
/// tiles may reach past the canvas; those pixels stay transparent.
class TileGrid {
  TileGrid(this.dimensions)
    : columns = (dimensions.width + TiledRaster.size - 1) ~/ TiledRaster.size,
      rows = (dimensions.height + TiledRaster.size - 1) ~/ TiledRaster.size;
  final CanvasSize dimensions;
  final int columns, rows;
  int get count => columns * rows;

  /// Top-left pixel of tile [index].
  (int, int) origin(int index) => (
    (index % columns) * TiledRaster.size,
    (index ~/ columns) * TiledRaster.size,
  );

  @override
  bool operator ==(Object other) =>
      other is TileGrid && other.dimensions == dimensions;
  @override
  int get hashCode => dimensions.hashCode;
}

/// A layer's pixels at document resolution, cut into [size]² tiles keyed by
/// `row * columns + column` of its [grid]. Absent tiles are fully
/// transparent. History steps share every tile they did not change, so undo
/// costs only what a stroke touched.
class TiledRaster {
  TiledRaster(this.grid, Map<int, RasterAsset> tiles)
    : tiles = Map.unmodifiable(tiles) {
    if (tiles.isEmpty) throw const FormatException('A raster has no tiles');
    for (final MapEntry(:key, :value) in tiles.entries) {
      if (key < 0 ||
          key >= grid.count ||
          value.width != size ||
          value.height != size) {
        throw const FormatException('Invalid raster tile');
      }
    }
  }
  static const size = 256;
  final TileGrid grid;
  final Map<int, RasterAsset> tiles;

  List<Map<String, dynamic>> toJson({
    bool deferPng = false,
    Map<String, Uint8List>? blobs,
  }) => [
    for (final MapEntry(:key, :value) in tiles.entries)
      {'index': key, ...value.toJson(deferPng: deferPng, blobs: blobs)},
  ];

  factory TiledRaster.fromJson(
    List<dynamic> json,
    TileGrid grid, {
    Map<String, Uint8List> blobs = const {},
  }) {
    if (json.length > grid.count) {
      throw const FormatException('Too many tiles');
    }
    final tiles = <int, RasterAsset>{};
    for (final raw in json) {
      final tile = Map<String, dynamic>.from(raw as Map);
      final index = tile['index'];
      if (index is! int || tiles.containsKey(index)) {
        throw const FormatException('Invalid tile index');
      }
      tiles[index] = RasterAsset.fromJson(tile, blobs: blobs);
    }
    return TiledRaster(grid, tiles);
  }
}

/// Procreate's blend modes, in its menu's order; saved by name.
enum LayerBlend {
  normal,
  darken,
  multiply,
  colorBurn,
  linearBurn,
  darkerColor,
  lighten,
  screen,
  colorDodge,
  add,
  lighterColor,
  overlay,
  softLight,
  hardLight,
  vividLight,
  linearLight,
  pinLight,
  hardMix,
  difference,
  exclusion,
  subtract,
  divide,
  hue,
  saturation,
  color,
  luminosity,
}

class ArtLayer {
  ArtLayer({
    required this.id,
    required this.name,
    List<InkStroke> strokes = const [],
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.raster,
    this.legacyRaster,
    this.blend = LayerBlend.normal,
    this.mask,
    this.reference = false,
    this.alphaLock = false,
    this.clipping = false,
    this.group,
    this.assisted = false,
    this.text,
    this.private = false,
  }) : strokes = List.unmodifiable(strokes);
  final String id, name;

  /// A text layer's editable text, drawn over its pixels.
  final LayerText? text;

  /// Kept out of the time-lapse recording (Procreate's private layers).
  final bool private;

  /// The [LayerGroup] it belongs to, if any.
  final String? group;

  /// Drawing Assist: strokes on it follow the drawing guide's lines.
  final bool assisted;
  final List<InkStroke> strokes;

  /// Pixels under the strokes.
  final TiledRaster? raster;

  /// One image placed to fit the canvas, as documents before version 5
  /// stored rasters. Painted and saved as is until the editor converts it
  /// into [raster] tiles on opening.
  final RasterAsset? legacyRaster;
  final LayerBlend blend;
  final SelectionRegion? mask;
  final bool visible, locked;
  final double opacity;

  /// ColorDrop fills by this layer's lines whichever layer it paints on.
  final bool reference;

  /// Painting changes only the colour of pixels already there.
  final bool alphaLock;

  /// Shows only where the layer below (the nearest one that is not itself
  /// clipping) has pixels.
  final bool clipping;
  ArtLayer copyWith({
    String? name,
    List<InkStroke>? strokes,
    bool? visible,
    bool? locked,
    double? opacity,
    TiledRaster? raster,
    bool clearRaster = false,
    RasterAsset? legacyRaster,
    bool clearLegacyRaster = false,
    LayerBlend? blend,
    SelectionRegion? mask,
    bool clearMask = false,
    bool? reference,
    bool? alphaLock,
    bool? clipping,
    String? group,
    bool clearGroup = false,
    bool? assisted,
    LayerText? text,
    bool clearText = false,
    bool? private,
  }) => ArtLayer(
    id: id,
    private: private ?? this.private,
    text: clearText ? null : text ?? this.text,
    assisted: assisted ?? this.assisted,
    group: clearGroup ? null : group ?? this.group,
    name: name ?? this.name,
    strokes: strokes ?? this.strokes,
    raster: clearRaster ? null : (raster ?? this.raster),
    legacyRaster: clearLegacyRaster
        ? null
        : (legacyRaster ?? this.legacyRaster),
    blend: blend ?? this.blend,
    mask: clearMask ? null : (mask ?? this.mask),
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    opacity: opacity ?? this.opacity,
    reference: reference ?? this.reference,
    alphaLock: alphaLock ?? this.alphaLock,
    clipping: clipping ?? this.clipping,
  );
  Map<String, dynamic> toJson({
    Map<String, SelectionRegion>? regions,
    bool deferPng = false,
    Map<String, Uint8List>? blobs,
  }) => {
    'id': id,
    'name': name,
    if (mask != null && regions == null) 'mask': mask!.toJson(),
    if (mask != null && regions != null)
      'maskId': registerSelection(mask!, regions),
    'visible': visible,
    'locked': locked,
    'opacity': opacity,
    'strokes': strokes.map((s) => s.toJson(regions: regions)).toList(),
    if (raster != null)
      'tiles': raster!.toJson(deferPng: deferPng, blobs: blobs),
    if (legacyRaster != null)
      'raster': legacyRaster!.toJson(deferPng: deferPng),
    if (blend != LayerBlend.normal) 'blend': blend.name,
    if (reference) 'reference': true,
    if (alphaLock) 'alphaLock': true,
    if (clipping) 'clipping': true,
    if (group != null) 'group': group,
    if (assisted) 'assisted': true,
    if (text != null) 'text': text!.toJson(),
    if (private) 'private': true,
  };
  factory ArtLayer.fromJson(
    Map<String, dynamic> json,
    TileGrid grid, {
    Map<String, SelectionRegion> regions = const {},
    Map<String, Uint8List> blobs = const {},
  }) {
    final opacity = (json['opacity'] as num? ?? 1).toDouble();
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw const FormatException('Invalid layer opacity');
    }
    final strokes = json['strokes'] as List;
    if (strokes.length > 10000) throw const FormatException('Too many strokes');
    return ArtLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      mask: readSelection(json, 'mask', regions),
      blend: json['blend'] == null
          ? LayerBlend.normal
          : LayerBlend.values.asNameMap()[json['blend']] ??
                (throw const FormatException('Unsupported layer blend mode')),
      raster: json['tiles'] == null
          ? null
          : TiledRaster.fromJson(json['tiles'] as List, grid, blobs: blobs),
      legacyRaster: json['raster'] == null
          ? null
          : RasterAsset.fromJson(
              Map<String, dynamic>.from(json['raster'] as Map),
            ),
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      reference: json['reference'] as bool? ?? false,
      alphaLock: json['alphaLock'] as bool? ?? false,
      clipping: json['clipping'] as bool? ?? false,
      group: json['group'] as String?,
      assisted: json['assisted'] as bool? ?? false,
      private: json['private'] as bool? ?? false,
      text: json['text'] == null
          ? null
          : LayerText.fromJson(Map<String, dynamic>.from(json['text'] as Map)),
      opacity: opacity,
      strokes: strokes
          .map(
            (s) => InkStroke.fromJson(
              Map<String, dynamic>.from(s as Map),
              regions: regions,
            ),
          )
          .toList(),
    );
  }
}

/// Layers kept together (Procreate's groups, one level deep): shown,
/// hidden, faded and blended as one. Its layers sit next to each other.
class LayerGroup {
  const LayerGroup({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.collapsed = false,
  });
  final String id, name;
  final bool visible;
  final double opacity;
  final LayerBlend blend;

  /// Its layers are folded away in the layers panel.
  final bool collapsed;

  /// Full opacity in Normal: its layers blend straight with those below,
  /// as if ungrouped.
  bool get passThrough => opacity == 1 && blend == LayerBlend.normal;

  LayerGroup copyWith({
    String? name,
    bool? visible,
    double? opacity,
    LayerBlend? blend,
    bool? collapsed,
  }) => LayerGroup(
    id: id,
    name: name ?? this.name,
    visible: visible ?? this.visible,
    opacity: opacity ?? this.opacity,
    blend: blend ?? this.blend,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (!visible) 'visible': false,
    if (opacity != 1) 'opacity': opacity,
    if (blend != LayerBlend.normal) 'blend': blend.name,
    if (collapsed) 'collapsed': true,
  };

  factory LayerGroup.fromJson(Map<String, dynamic> json) {
    final opacity = (json['opacity'] as num? ?? 1).toDouble();
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw const FormatException('Invalid group opacity');
    }
    return LayerGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      visible: json['visible'] as bool? ?? true,
      opacity: opacity,
      blend: json['blend'] == null
          ? LayerBlend.normal
          : LayerBlend.values.asNameMap()[json['blend']] ??
                (throw const FormatException('Unsupported group blend mode')),
      collapsed: json['collapsed'] as bool? ?? false,
    );
  }
}

/// The colour space a drawing's numbers mean, written into its exports.
enum ColorProfile { srgb, displayP3, cmyk }

class ArtDocument {
  ArtDocument({
    required this.id,
    required this.name,
    required List<ArtLayer> layers,
    required this.activeLayerId,
    this.dimensions = CanvasSize.legacy,
    this.background = 0xfffffdf8,
    this.backgroundHidden = false,
    this.revision = 0,
    List<LayerGroup> groups = const [],
    List<SelectionRegion> savedSelections = const [],
    this.dpi = 132,
    this.pageAssist = false,
    this.colorProfile = ColorProfile.srgb,
    this.animation,
  }) : layers = List.unmodifiable(layers),
       savedSelections = List.unmodifiable(savedSelections),
       // A group with no layers left is gone.
       groups = List.unmodifiable(
         groups.where((g) => layers.any((l) => l.group == g.id)),
       ) {
    if (!dimensions.isValid) throw const FormatException('Invalid canvas size');
    final known = {for (final g in groups) g.id};
    if (known.length != groups.length) {
      throw const FormatException('Duplicate group identities');
    }
    final seen = <String>{};
    String? previous;
    for (final layer in layers) {
      final group = layer.group;
      if (group != null && !known.contains(group)) {
        throw const FormatException('Layer in an unknown group');
      }
      if (group != previous) {
        if (group != null && !seen.add(group)) {
          throw const FormatException('A group\'s layers must be together');
        }
        previous = group;
      }
    }
    if (layers.any((l) => l.raster != null && l.raster!.grid != grid)) {
      throw const FormatException('Layer tiles do not match the canvas');
    }
  }
  final String id, name, activeLayerId;

  /// Canvas size in pixels; fixed for the life of a drawing.
  final CanvasSize dimensions;
  TileGrid get grid => TileGrid(dimensions);

  /// Bottom to top, matching painter compositing order.
  final List<ArtLayer> layers;

  /// The groups layers belong to, in no particular order.
  final List<LayerGroup> groups;

  /// Dots per inch, for the printed size Canvas Info shows.
  final int dpi;

  /// Page Assist: each top-level layer or group is a page, shown alone.
  final bool pageAssist;

  final ColorProfile colorProfile;

  /// Animation Assist's settings, kept when it is turned off.
  final AnimationSettings? animation;

  bool get animating => animation?.enabled ?? false;

  /// The id a page (frame) is known by: its group's, or its one layer's.
  static String frameId(List<ArtLayer> page) =>
      page.first.group ?? page.first.id;

  /// The pages Page Assist shows, bottom to top: each top-level layer, or
  /// a group's layers together.
  List<List<ArtLayer>> get pages {
    final out = <List<ArtLayer>>[];
    for (final layer in layers) {
      final group = layer.group;
      if (group != null && out.isNotEmpty && out.last.first.group == group) {
        out.last.add(layer);
      } else {
        out.add([layer]);
      }
    }
    return out;
  }

  /// The page holding the active layer.
  int get currentPage =>
      pages.indexWhere((p) => p.any((l) => l.id == activeLayerId));

  /// Only page [index]'s layers (the same layer objects), to draw it alone.
  ArtDocument pageOnly(int index) {
    final page = pages[index];
    return copyWith(
      layers: page,
      activeLayerId: page.any((l) => l.id == activeLayerId)
          ? activeLayerId
          : page.last.id,
    );
  }

  /// Animation Assist: frame [page] over the background frame and under
  /// the foreground frame, as it plays.
  ArtDocument animationFrame(int page) {
    final pages = this.pages, settings = animation!;
    final first = pages.first, last = pages.last;
    final background =
        page != 0 && settings.background == ArtDocument.frameId(first);
    final foreground =
        page != pages.length - 1 &&
        settings.foreground == ArtDocument.frameId(last);
    return copyWith(
      layers: [
        if (background) ...first,
        ...pages[page],
        if (foreground) ...last,
      ],
    );
  }

  /// Selections kept to load again (Procreate's Save & Load).
  final List<SelectionRegion> savedSelections;
  static const maxSavedSelections = 16;

  LayerGroup? groupOf(ArtLayer layer) {
    final id = layer.group;
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  final int background, revision;

  /// The background colour layer is off: the drawing is transparent where
  /// no layer paints (and so are its PNG exports).
  final bool backgroundHidden;
  ArtLayer get activeLayer => layers.firstWhere((l) => l.id == activeLayerId);
  factory ArtDocument.empty({
    String name = 'Untitled',
    CanvasSize dimensions = CanvasSize.legacy,
  }) {
    final layer = ArtLayer(id: newId(), name: 'Layer 1');
    return ArtDocument(
      id: newId(),
      name: name,
      layers: [layer],
      activeLayerId: layer.id,
      dimensions: dimensions,
    );
  }
  ArtDocument copyWith({
    String? id,
    String? name,
    List<ArtLayer>? layers,
    String? activeLayerId,
    int? background,
    bool? backgroundHidden,
    int? revision,
    List<LayerGroup>? groups,
    List<SelectionRegion>? savedSelections,
    CanvasSize? dimensions,
    int? dpi,
    bool? pageAssist,
    ColorProfile? colorProfile,
    AnimationSettings? animation,
  }) => ArtDocument(
    dpi: dpi ?? this.dpi,
    pageAssist: pageAssist ?? this.pageAssist,
    colorProfile: colorProfile ?? this.colorProfile,
    animation: animation ?? this.animation,
    groups: groups ?? this.groups,
    savedSelections: savedSelections ?? this.savedSelections,
    id: id ?? this.id,
    name: name ?? this.name,
    layers: layers ?? this.layers,
    activeLayerId: activeLayerId ?? this.activeLayerId,
    dimensions: dimensions ?? this.dimensions,
    background: background ?? this.background,
    backgroundHidden: backgroundHidden ?? this.backgroundHidden,
    revision: revision ?? this.revision,
  );

  /// [deferPng], [blobs]: see [RasterAsset.toJson]; with [blobs] this is a
  /// manifest whose tiles live outside it.
  Map<String, dynamic> toJson({
    bool deferPng = false,
    Map<String, Uint8List>? blobs,
  }) {
    final regions = <String, SelectionRegion>{};
    final serializedLayers = layers
        .map(
          (l) => l.toJson(regions: regions, deferPng: deferPng, blobs: blobs),
        )
        .toList();
    final saved = [
      for (final region in savedSelections) registerSelection(region, regions),
    ];
    return {
      'format': 'atelier.document',
      'version': dimensions != CanvasSize.legacy
          ? 6
          : layers.any((l) => l.raster != null)
          ? 5
          : regions.isNotEmpty
          ? 4
          : layers.any((l) => l.blend != LayerBlend.normal)
          ? 3
          : layers.any((l) => l.legacyRaster != null)
          ? 2
          : 1,
      'engine': 'perfect_freehand-v1',
      'width': dimensions.width,
      'height': dimensions.height,
      'id': id,
      'name': name,
      'activeLayerId': activeLayerId,
      'background': background,
      if (backgroundHidden) 'backgroundHidden': true,
      if (dpi != 132) 'dpi': dpi,
      if (pageAssist) 'pageAssist': true,
      if (colorProfile != ColorProfile.srgb) 'colorProfile': colorProfile.name,
      if (animation != null) 'animation': animation!.toJson(),
      'revision': revision,
      if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
      if (saved.isNotEmpty) 'savedSelections': saved,
      if (regions.isNotEmpty)
        'regions': regions.map((key, value) => MapEntry(key, value.toJson())),
      'layers': serializedLayers,
    };
  }

  factory ArtDocument.fromJson(
    Map<String, dynamic> json, {
    Map<String, Uint8List> blobs = const {},
  }) {
    if (json['format'] != 'atelier.document' ||
        ![1, 2, 3, 4, 5, 6].contains(json['version']) ||
        json['engine'] != 'perfect_freehand-v1') {
      throw const FormatException(
        'Unsupported document format, engine or version',
      );
    }
    // Before version 6 every drawing was 1024² and said so as `extent`.
    final width = json['width'], height = json['height'];
    final CanvasSize dimensions;
    if (width is int && height is int) {
      dimensions = CanvasSize(width, height);
    } else if (json['extent'] == CanvasSize.legacy.width) {
      dimensions = CanvasSize.legacy;
    } else {
      throw const FormatException('Missing or unsupported canvas size');
    }
    if (!dimensions.isValid) throw const FormatException('Invalid canvas size');
    final grid = TileGrid(dimensions);
    final rawRegions = json['regions'];
    final regions = <String, SelectionRegion>{};
    if (rawRegions != null) {
      if (rawRegions is! Map ||
          rawRegions.length > 1024 ||
          (json['version'] as int) < 4) {
        throw const FormatException('Invalid document selections');
      }
      var points = 0;
      for (final entry in rawRegions.entries) {
        final region = SelectionRegion.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (entry.key != region.id) {
          throw const FormatException('Invalid selection identity');
        }
        points += region.pointCount;
        if (points > 128000) {
          throw const FormatException('Too many selection points');
        }
        regions[region.id] = region;
      }
    }
    final raw = json['layers'] as List;
    if (raw.isEmpty || raw.length > 64) {
      throw const FormatException('Invalid layer count');
    }
    final layers = raw
        .map(
          (l) => ArtLayer.fromJson(
            Map<String, dynamic>.from(l as Map),
            grid,
            regions: regions,
            blobs: blobs,
          ),
        )
        .toList();
    if ((json['version'] as int) < 4 &&
        layers.any(
          (l) => l.mask != null || l.strokes.any((s) => s.clip != null),
        )) {
      throw const FormatException('Selection masks require document version 4');
    }
    if ((json['version'] as int) < 3 &&
        layers.any((l) => l.blend != LayerBlend.normal)) {
      throw const FormatException('Layer blending requires document version 3');
    }
    if ((json['version'] as int) < 5 && layers.any((l) => l.raster != null)) {
      throw const FormatException('Raster tiles require document version 5');
    }
    final rasters = [
      for (final layer in layers) ...?layer.raster?.tiles.values,
      ...layers.map((l) => l.legacyRaster).whereType<RasterAsset>(),
    ];
    if ((json['version'] == 1 && rasters.isNotEmpty) ||
        rasters.map((r) => r.id).toSet().length != rasters.length) {
      throw const FormatException('Invalid raster collection');
    }
    checkRasterBudget(dimensions, rasters);
    final documentId = json['id'];
    if (documentId is! String ||
        documentId.isEmpty ||
        documentId.length > 128) {
      throw const FormatException('Invalid document identity');
    }
    final ids = layers.map((l) => l.id).toSet();
    final active = json['activeLayerId'] as String;
    if (ids.length != layers.length || !ids.contains(active)) {
      throw const FormatException('Invalid layer identities');
    }
    final strokes = layers.expand((l) => l.strokes).toList();
    if (strokes.map((s) => s.id).toSet().length != strokes.length ||
        strokes.fold<int>(0, (sum, s) => sum + s.points.length) > 250000) {
      throw const FormatException('Invalid or oversized stroke collection');
    }
    return ArtDocument(
      id: json['id'] as String,
      name: json['name'] as String,
      layers: layers,
      activeLayerId: active,
      dimensions: dimensions,
      background: readColor(json['background']),
      backgroundHidden: json['backgroundHidden'] as bool? ?? false,
      dpi: switch (json['dpi']) {
        final int d when d >= 1 && d <= 9600 => d,
        null => 132,
        _ => throw const FormatException('Invalid DPI'),
      },
      revision: json['revision'] as int? ?? 0,
      pageAssist: json['pageAssist'] as bool? ?? false,
      colorProfile:
          ColorProfile.values.asNameMap()[json['colorProfile']] ??
          ColorProfile.srgb,
      animation: json['animation'] == null
          ? null
          : AnimationSettings.fromJson(json['animation']),
      groups: [
        for (final g in (json['groups'] as List? ?? const []))
          LayerGroup.fromJson(Map<String, dynamic>.from(g as Map)),
      ],
      savedSelections: [
        for (final id in (json['savedSelections'] as List? ?? const []))
          regions[id] ??
              (throw const FormatException('Invalid saved selection')),
      ],
    );
  }
}

/// Compressed bytes all of a drawing's rasters may hold in memory.
const maxRasterPngBytes = 256 * 1024 * 1024;

/// Raster pixels a drawing may hold: the 1024² allowance of earlier versions
/// (32 full layers) or four full layers of a larger canvas, whichever is
/// more. Every history step keeps its pixels decodable, so this bounds GPU
/// memory as well; per-device budgets come later.
int maxRasterPixels(CanvasSize dimensions) =>
    math.max(32 * 1024 * 1024, 4 * dimensions.pixels);

void checkRasterBudget(CanvasSize dimensions, Iterable<RasterAsset> rasters) {
  var bytes = 0, pixels = 0;
  for (final raster in rasters) {
    bytes += raster.png.length;
    pixels += raster.width * raster.height;
  }
  if (bytes > maxRasterPngBytes || pixels > maxRasterPixels(dimensions)) {
    throw const FormatException('Document raster storage limit reached');
  }
}

int readColor(dynamic value) {
  if (value is! int || value < 0 || value > 0xffffffff) {
    throw const FormatException('Invalid ARGB color');
  }
  return value;
}

enum BrushEngineKind { freehand, mypaint, stamp }

class BrushPreset {
  const BrushPreset({
    required this.id,
    required this.name,
    this.size = 12,
    this.thinning = .5,
    this.smoothing = .5,
    this.engine = BrushEngineKind.freehand,
    this.mypaint,
    this.stamp,
    this.tip,
    this.grain,
    this.dual,
    this.dualTip,
  }) : assert(engine != BrushEngineKind.mypaint || mypaint != null),
       assert((dual == null) == (dualTip == null)),
       assert(
         engine != BrushEngineKind.stamp || (stamp != null && tip != null),
       );
  static const mypaintEngineId = 'mypaint-1.6.1';
  static const stampEngineId = 'artblend-stamp-1';
  static const maxMypaintBytes = 1024 * 1024;

  /// A stamp image: `builtin:<name>` or `png:<base64>` (at most 2 MiB).
  static const maxShapeChars = 2 * 1024 * 1024;
  final String id, name;
  final double size, thinning, smoothing;
  final BrushEngineKind engine;

  /// MyPaint v3 JSON, validated by the native loader before it is accepted.
  final String? mypaint;

  /// A stamp brush: how dabs are laid, the tip shape and the canvas grain.
  final StampSettings? stamp;
  final String? tip, grain;

  /// A dual brush (stamp only): a second tip combined with [tip].
  final DualStamp? dual;
  final String? dualTip;

  /// Drawn by the native engine (MyPaint or stamp) into raster tiles.
  bool get isNative => engine != BrushEngineKind.freehand;
  bool get isStamp => engine == BrushEngineKind.stamp;
  BrushPreset copyWith({
    String? id,
    String? name,
    double? size,
    double? thinning,
    double? smoothing,
    StampSettings? stamp,
    String? tip,
    String? grain,
    bool clearGrain = false,
    DualStamp? dual,
    String? dualTip,
    bool clearDual = false,
  }) => BrushPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    size: size ?? this.size,
    thinning: thinning ?? this.thinning,
    smoothing: smoothing ?? this.smoothing,
    engine: engine,
    mypaint: mypaint,
    stamp: stamp ?? this.stamp,
    tip: tip ?? this.tip,
    grain: clearGrain ? null : grain ?? this.grain,
    dual: clearDual ? null : dual ?? this.dual,
    dualTip: clearDual ? null : dualTip ?? this.dualTip,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'thinning': thinning,
    'smoothing': smoothing,
    if (engine == BrushEngineKind.mypaint) 'engine': mypaintEngineId,
    if (engine == BrushEngineKind.mypaint) 'mypaint': mypaint,
    if (isStamp) 'engine': stampEngineId,
    if (isStamp) 'stamp': stamp!.toJson(),
    if (isStamp) 'tip': tip,
    if (isStamp && grain != null) 'grain': grain,
    if (isStamp && dual != null) 'dual': dual!.toJson(),
    if (isStamp && dual != null) 'dualTip': dualTip,
  };

  static String? _shape(Object? value, {required bool required}) {
    if (value == null && !required) return null;
    if (value is! String ||
        value.length > maxShapeChars ||
        !(RegExp(r'^builtin:[a-z0-9-]{1,40}$').hasMatch(value) ||
            value.startsWith('png:'))) {
      throw const FormatException('Invalid stamp brush shape');
    }
    return value;
  }

  factory BrushPreset.fromJson(Map<String, dynamic> data) {
    final size = (data['size'] as num).toDouble();
    final thin = (data['thinning'] as num? ?? .5).toDouble();
    final smooth = (data['smoothing'] as num? ?? .5).toDouble();
    if (!size.isFinite ||
        size <= 0 ||
        size > 256 ||
        !thin.isFinite ||
        thin < -1 ||
        thin > 1 ||
        !smooth.isFinite ||
        smooth < 0 ||
        smooth > 1) {
      throw const FormatException('Invalid brush settings');
    }
    final engine = switch (data['engine']) {
      null || 'perfect_freehand' => BrushEngineKind.freehand,
      mypaintEngineId => BrushEngineKind.mypaint,
      stampEngineId => BrushEngineKind.stamp,
      _ => throw const FormatException('Unsupported brush engine'),
    };
    final mypaint = data['mypaint'];
    if (engine == BrushEngineKind.mypaint &&
        (mypaint is! String ||
            mypaint.isEmpty ||
            mypaint.length > maxMypaintBytes)) {
      throw const FormatException('Invalid MyPaint preset');
    }
    final stamp = data['stamp'];
    if (engine == BrushEngineKind.stamp && stamp is! Map) {
      throw const FormatException('Invalid stamp brush');
    }
    final name = data['name'];
    if (name is! String || name.trim().isEmpty || name.length > 128) {
      throw const FormatException('Invalid brush name');
    }
    final stamped = engine == BrushEngineKind.stamp;
    return BrushPreset(
      id: data['id'] as String? ?? newId(),
      name: name,
      size: size,
      thinning: thin,
      smoothing: smooth,
      engine: engine,
      mypaint: engine == BrushEngineKind.mypaint ? mypaint as String : null,
      stamp: stamped
          ? StampSettings.fromJson((stamp as Map).cast<String, Object?>())
          : null,
      tip: stamped ? _shape(data['tip'], required: true) : null,
      grain: stamped ? _shape(data['grain'], required: false) : null,
      dual: stamped && data['dual'] is Map
          ? DualStamp.fromJson((data['dual'] as Map).cast<String, Object?>())
          : null,
      dualTip: stamped && data['dual'] is Map
          ? _shape(data['dualTip'], required: true)
          : null,
    );
  }
}

class ColorPalette {
  ColorPalette({
    required this.id,
    required this.name,
    required List<int> colors,
  }) : colors = List.unmodifiable(colors);
  final String id, name;
  final List<int> colors;
  ColorPalette copyWith({String? name, List<int>? colors}) => ColorPalette(
    id: id,
    name: name ?? this.name,
    colors: colors ?? this.colors,
  );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'colors': colors};
  factory ColorPalette.fromJson(Map<String, dynamic> data) {
    final colors = (data['colors'] as List).map(readColor).toList();
    // An empty palette is one just made, waiting for colours.
    if (colors.length > 1024) {
      throw const FormatException('Invalid palette size');
    }
    return ColorPalette(
      id: data['id'] as String? ?? newId(),
      name: data['name'] as String,
      colors: colors,
    );
  }
}

const initialBrushes = [
  BrushPreset(id: 'ink', name: 'ink', size: 10, thinning: .65, smoothing: .6),
  BrushPreset(
    id: 'pencil',
    name: 'pencil',
    size: 4,
    thinning: .4,
    smoothing: .4,
  ),
  BrushPreset(
    id: 'marker',
    name: 'marker',
    size: 28,
    thinning: 0,
    smoothing: .75,
  ),
  BrushPreset(
    id: 'mypaint-charcoal',
    name: 'charcoal',
    size: 14,
    engine: BrushEngineKind.mypaint,
    mypaint: charcoalPreset,
  ),
  BrushPreset(
    id: 'mypaint-modelling',
    name: 'modelling',
    size: 18,
    engine: BrushEngineKind.mypaint,
    mypaint: modellingPreset,
  ),
  BrushPreset(
    id: 'stamp-graphite',
    name: 'graphite',
    size: 6,
    engine: BrushEngineKind.stamp,
    tip: 'builtin:graphite',
    grain: 'builtin:paper',
    stamp: StampSettings(
      spacing: .08,
      sizeJitter: .1,
      rotationJitter: 1,
      pressureSize: .5,
      pressureOpacity: .8,
      flow: .55,
      grainDepth: .85,
    ),
  ),
  BrushPreset(
    id: 'stamp-pastel',
    name: 'pastel',
    size: 40,
    engine: BrushEngineKind.stamp,
    tip: 'builtin:chalk',
    grain: 'builtin:rough',
    stamp: StampSettings(
      spacing: .12,
      rotationJitter: 1,
      pressureSize: .3,
      pressureOpacity: .6,
      flow: .6,
      grainDepth: .9,
    ),
  ),
  BrushPreset(
    id: 'stamp-dry-brush',
    name: 'dry brush',
    size: 36,
    engine: BrushEngineKind.stamp,
    tip: 'builtin:bristle',
    grain: 'builtin:canvas',
    stamp: StampSettings(
      spacing: .04,
      sizeJitter: .1,
      followStroke: true,
      pressureSize: .4,
      pressureOpacity: .4,
      flow: .35,
      grainDepth: .5,
    ),
  ),
  BrushPreset(
    id: 'stamp-gouache',
    name: 'gouache',
    size: 30,
    engine: BrushEngineKind.stamp,
    tip: 'builtin:round-soft',
    grain: 'builtin:canvas',
    stamp: StampSettings(
      spacing: .06,
      pressureSize: .3,
      pressureOpacity: .5,
      flow: .25,
      grainDepth: .35,
    ),
  ),
  BrushPreset(
    id: 'stamp-splatter',
    name: 'splatter',
    size: 60,
    engine: BrushEngineKind.stamp,
    tip: 'builtin:splatter',
    stamp: StampSettings(
      spacing: .9,
      scatter: 1.2,
      sizeJitter: .6,
      opacityJitter: .3,
      rotationJitter: 1,
      pressureSize: .5,
      pressureOpacity: 0,
    ),
  ),
];

final initialPalettes = [
  ColorPalette(
    id: 'coast',
    name: 'coast',
    colors: [
      0xff346b70,
      0xff6b9695,
      0xff9fb2a6,
      0xffd0aaa0,
      0xffedc6a3,
      0xffd18b6c,
      0xff3b4b43,
      0xff2b3034,
      0xfff5f1e8,
      0xffbc6261,
      0xffbda75e,
      0xff7b83a6,
    ],
  ),
];

Color inkColor(int argb) => Color(argb);
