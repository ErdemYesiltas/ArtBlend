import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';

import '../data/export_formats.dart';
import '../domain/document.dart';
import '../domain/movie.dart';
import '../domain/selection.dart';
import '../drawing/adjustments.dart';
import '../editor/exporter.dart';
import '../editor/studio_controller.dart';
import '../movie/movie_controller.dart';
import '../movie/movie_export.dart';
import 'mcp_server.dart';

const artBlendInstructions = '''
ArtBlend is a drawing and animation app; these tools drive the copy open on
the user's screen, live: every change shows at once and can be undone there.
Drawing coordinates are canvas pixels, origin top-left (get_document gives
the size). Colours are "#rrggbb" or "#aarrggbb". Layers are listed bottom to
top. Look at your work with snapshot after drawing. Movies: frames are
counted from 0 at the movie's fps; positions x/y are shares of the stage
(0.5, 0.5 is the centre); tools act on the movie open on screen, or on
movie_id when none is.''';

/// ArtBlend's tools for agents, acting on [c] (the drawing on screen) and
/// on the movie open in the Theater ([MovieController.active]).
class ArtBlendTools {
  ArtBlendTools(this.c, {Future<Directory> Function()? exports})
    : _exports = exports ?? _defaultExports;

  final StudioController c;
  final Future<Directory> Function() _exports;

  static Future<Directory> _defaultExports() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}/MCP Exports',
  ).create(recursive: true);

  static const _movie = {
    'movie_id': {
      'type': 'string',
      'description': 'A movie from list_movies; omit for the one on screen.',
    },
  };

  late final List<McpTool> tools = [
    McpTool(
      'get_document',
      'The drawing open on screen: size, layers (bottom to top), the active '
          'layer, brush, colour, and whether undo/redo are possible.',
      readOnly: true,
      run: (_) async => McpResult.json(_document()),
    ),
    McpTool(
      'list_drawings',
      'Drawings in the gallery, most recently saved first.',
      readOnly: true,
      run: (_) async {
        final listing = await c.storage.listDocuments();
        return McpResult.json([
          for (final d in listing.documents)
            {
              'id': d.id,
              'name': d.name,
              'width': d.dimensions.width,
              'height': d.dimensions.height,
              'layers': d.layers.length,
              'open': d.id == c.document.id,
            },
        ]);
      },
    ),
    McpTool(
      'list_brushes',
      'The brush library: ids and names for set_brush.',
      readOnly: true,
      run: (_) async => McpResult.json([
        for (final b in c.brushes) {'id': b.id, 'name': b.name},
      ]),
    ),
    McpTool(
      'snapshot',
      'A PNG of the drawing as it looks (or of one layer alone).',
      readOnly: true,
      properties: {
        'max_side': {
          'type': 'integer',
          'description': 'Longest side in pixels (default 1024).',
        },
        'layer_id': {'type': 'string'},
      },
      run: _snapshot,
    ),
    McpTool(
      'new_drawing',
      'Saves the drawing on screen and opens a new blank one.',
      properties: {
        'name': {'type': 'string'},
        'width': {'type': 'integer'},
        'height': {'type': 'integer'},
        'background': {'type': 'string', 'description': 'Paper colour.'},
      },
      run: (a) async {
        await _ready();
        final w = _int(a, 'width') ?? 2048, h = _int(a, 'height') ?? 2048;
        if ([
          w,
          h,
        ].any((v) => v < CanvasSize.minSide || v > CanvasSize.maxSide)) {
          throw McpToolError(
            'Sides must be ${CanvasSize.minSide}–${CanvasSize.maxSide} px.',
          );
        }
        var doc = ArtDocument.empty(
          name: _str(a, 'name') ?? 'Untitled',
          dimensions: CanvasSize(w, h),
        );
        if (_color(a, 'background') case final paper?) {
          doc = doc.copyWith(background: paper);
        }
        await c.replaceDocument(doc);
        return McpResult.json(_document());
      },
    ),
    McpTool(
      'open_drawing',
      'Saves the drawing on screen and opens a gallery drawing.',
      properties: {
        'id': {'type': 'string'},
      },
      required: ['id'],
      run: (a) async {
        await _ready();
        final id = _str(a, 'id');
        final doc = (await c.storage.listDocuments()).documents
            .where((d) => d.id == id)
            .firstOrNull;
        if (doc == null) throw McpToolError('No drawing $id in the gallery.');
        await c.replaceDocument(doc);
        return McpResult.json(_document());
      },
    ),
    McpTool(
      'add_layer',
      'A new empty layer above the active one; it becomes active.',
      properties: {
        'name': {'type': 'string'},
      },
      run: (a) async {
        await _ready();
        final before = c.document.layers.length;
        c.addLayer(_str(a, 'name') ?? 'Layer ${before + 1}');
        if (c.document.layers.length == before) {
          throw McpToolError(
            'No room for another layer (${StudioController.maxLayers} at most).',
          );
        }
        return McpResult.json({'layer_id': c.document.activeLayerId});
      },
    ),
    McpTool(
      'update_layer',
      'Changes a layer: make it active, rename, show/hide, opacity, blend '
          'mode, lock, alpha lock.',
      properties: {
        'layer_id': {'type': 'string'},
        'active': {'type': 'boolean'},
        'name': {'type': 'string'},
        'visible': {'type': 'boolean'},
        'opacity': {'type': 'number', 'minimum': 0, 'maximum': 1},
        'blend': {
          'type': 'string',
          'enum': [for (final b in LayerBlend.values) b.name],
        },
        'locked': {'type': 'boolean'},
        'alpha_lock': {'type': 'boolean'},
      },
      required: ['layer_id'],
      run: (a) async {
        await _ready();
        final layer = _layer(_str(a, 'layer_id'));
        if (_bool(a, 'active') ?? false) c.selectLayer(layer.id);
        final blend = _str(a, 'blend');
        c.updateLayer(
          layer.id,
          (l) => l.copyWith(
            name: _str(a, 'name'),
            visible: _bool(a, 'visible'),
            opacity: _num(a, 'opacity')?.clamp(0, 1),
            blend: blend == null ? null : _enum(LayerBlend.values, blend),
            locked: _bool(a, 'locked'),
          ),
        );
        if (_bool(a, 'alpha_lock') case final lock?
            when lock != _layer(layer.id).alphaLock) {
          c.toggleAlphaLock(layer.id);
        }
        return McpResult.json(_layerJson(_layer(layer.id)));
      },
    ),
    McpTool(
      'delete_layer',
      'Deletes a layer (undoable in the app).',
      destructive: true,
      properties: {
        'layer_id': {'type': 'string'},
      },
      required: ['layer_id'],
      run: (a) async {
        await _ready();
        final layer = _layer(_str(a, 'layer_id'));
        if (c.document.layers.length < 2) {
          throw const McpToolError('A drawing keeps at least one layer.');
        }
        c.deleteLayer(layer.id);
        return McpResult.text('Deleted ${layer.name}.');
      },
    ),
    McpTool(
      'clear_layer',
      'Erases everything on a layer (the active one by default).',
      destructive: true,
      properties: {
        'layer_id': {'type': 'string'},
      },
      run: (a) async {
        await _ready();
        _activate(a);
        await c.clearActiveLayer();
        return McpResult.text('Cleared ${c.document.activeLayer.name}.');
      },
    ),
    McpTool(
      'set_brush',
      'Chooses the brush (id or name from list_brushes), colour, size in '
          'pixels and opacity used by draw_strokes.',
      properties: {
        'brush': {'type': 'string'},
        'color': {'type': 'string'},
        'size': {'type': 'number'},
        'opacity': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
      run: (a) async {
        await _ready();
        if (_str(a, 'brush') case final want?) {
          final lower = want.toLowerCase();
          final brush =
              c.brushes.where((b) => b.id == want).firstOrNull ??
              c.brushes
                  .where((b) => b.name.toLowerCase() == lower)
                  .firstOrNull ??
              c.brushes
                  .where((b) => b.name.toLowerCase().contains(lower))
                  .firstOrNull;
          if (brush == null) throw McpToolError('No brush "$want".');
          c.selectBrush(brush);
        }
        if (_color(a, 'color') case final color?) c.selectColor(color);
        if (_num(a, 'size') case final size?) c.setSize(size);
        if (_num(a, 'opacity') case final opacity?) {
          c.setOpacity(opacity.clamp(0, 1));
        }
        return McpResult.json(_tools());
      },
    ),
    McpTool(
      'draw_strokes',
      'Draws strokes with the current brush on the active layer (or '
          'layer_id), each an undo step. A stroke is a list of points '
          '[x, y] or [x, y, pressure 0–1]; give points a few pixels apart '
          'for smooth lines.',
      properties: {
        'strokes': {
          'type': 'array',
          'items': {
            'type': 'array',
            'items': {
              'type': 'array',
              'items': {'type': 'number'},
              'minItems': 2,
              'maxItems': 3,
            },
          },
        },
        'tool': {
          'type': 'string',
          'enum': ['brush', 'eraser', 'smudge'],
        },
        'layer_id': {'type': 'string'},
      },
      required: ['strokes'],
      run: _draw,
    ),
    McpTool(
      'fill',
      'Fills an area of the active layer (or layer_id) with a colour: a '
          'rectangle, an ellipse, a polygon, or the current selection (or '
          'the whole layer) when no shape is given.',
      properties: {
        'color': {'type': 'string'},
        'rect': _numbers('[x, y, width, height]', 4),
        'ellipse': _numbers('[centre x, centre y, radius x, radius y]', 4),
        'polygon': {
          'type': 'array',
          'description': 'Points [[x, y], …], at least three.',
          'items': _numbers('[x, y]', 2),
        },
        'layer_id': {'type': 'string'},
      },
      run: _fill,
    ),
    McpTool(
      'add_image',
      'Places a picture (PNG, JPEG, WebP …) on a new layer, fitted to the '
          'canvas or into [x, y, width, height]. Give base64 data, or a '
          'path the app may read.',
      properties: {
        'data': {'type': 'string', 'description': 'Base64 file bytes.'},
        'path': {'type': 'string'},
        'name': {'type': 'string'},
        'rect': _numbers('[x, y, width, height]', 4),
      },
      run: (a) async {
        await _ready();
        final bytes = await _bytes(a);
        final rect = _rect(a['rect']);
        final id = await c.addImageLayer(
          bytes,
          _str(a, 'name') ?? 'Image',
          at: rect,
        );
        return McpResult.json({'layer_id': id});
      },
    ),
    McpTool(
      'add_text',
      'A text layer (vector words, editable in the app).',
      properties: {
        'text': {'type': 'string'},
        'x': {'type': 'number', 'description': 'Text box left.'},
        'y': {'type': 'number', 'description': 'Text box top.'},
        'width': {'type': 'number', 'description': 'Box width; lines wrap.'},
        'size': {'type': 'number', 'description': 'Font size in pixels.'},
        'color': {'type': 'string'},
        'font': {'type': 'string'},
        'weight': {'type': 'integer', 'minimum': 100, 'maximum': 900},
        'italic': {'type': 'boolean'},
        'alignment': {
          'type': 'string',
          'enum': [for (final t in TextAlignment.values) t.name],
        },
      },
      required: ['text'],
      run: _text,
    ),
    McpTool(
      'adjust',
      'Applies an adjustment to the active layer (or layer_id). Values are '
          '0–1; each kind lists its own (e.g. hueSaturationBrightness: hue, '
          'saturation, brightness, 0.5 = unchanged; gaussianBlur: amount).',
      properties: {
        'kind': {
          'type': 'string',
          'enum': [for (final k in _adjustable) k.name],
        },
        'values': {
          'type': 'object',
          'additionalProperties': {'type': 'number'},
          'description': {
            for (final k in _adjustable)
              k.name: [for (final p in k.params) p.id].join(', '),
          }.toString(),
        },
        'layer_id': {'type': 'string'},
      },
      required: ['kind'],
      run: _adjust,
    ),
    McpTool(
      'undo',
      'Undoes (or redoes) the last steps of the drawing, or of the movie '
          'on screen.',
      properties: {
        'steps': {'type': 'integer', 'minimum': 1},
        'redo': {'type': 'boolean'},
        'target': {
          'type': 'string',
          'enum': ['drawing', 'movie'],
        },
      },
      run: (a) async {
        final steps = (_int(a, 'steps') ?? 1).clamp(1, 100);
        final redo = _bool(a, 'redo') ?? false;
        if (_str(a, 'target') == 'movie') {
          final m = MovieController.active.value;
          if (m == null) throw const McpToolError('No movie is open.');
          for (var i = 0; i < steps; i++) {
            redo ? m.redo() : m.undo();
          }
          return McpResult.text('Done.');
        }
        await _ready();
        for (var i = 0; i < steps; i++) {
          redo ? c.redo() : c.undo();
        }
        await c.settleStroke();
        return McpResult.json(_document());
      },
    ),
    McpTool(
      'export_drawing',
      'Exports the drawing to a file in the app\'s "MCP Exports" folder '
          '(gif/apng/mp4 need Animation Assist on). Returns the path; '
          'inline also returns the bytes.',
      properties: {
        'format': {
          'type': 'string',
          'enum': [for (final f in ExportFormat.values) f.name],
        },
        'name': {'type': 'string'},
        'inline': {'type': 'boolean'},
      },
      required: ['format'],
      run: _export,
    ),
    McpTool(
      'list_movies',
      'Movies in the Theater.',
      readOnly: true,
      run: (_) async {
        final open = MovieController.active.value?.movie.id;
        return McpResult.json([
          for (final m in (await c.storage.listMovies()).movies)
            {
              'id': m.id,
              'name': m.name,
              'width': m.width,
              'height': m.height,
              'fps': m.fps,
              'frames': m.frames,
              'tracks': m.tracks.length,
              'open': m.id == open,
            },
        ]);
      },
    ),
    McpTool(
      'create_movie',
      'A new empty movie in the Theater (not opened on screen).',
      properties: {
        'name': {'type': 'string'},
        'aspect': {
          'type': 'string',
          'enum': ['wide', 'cinema', 'portrait', 'square'],
        },
        'short_side': {
          'type': 'integer',
          'description': 'Pixels on the short side (default 1080).',
        },
        'fps': {'type': 'integer'},
        'seconds': {'type': 'number'},
        'background': {'type': 'string'},
        'transparent': {'type': 'boolean'},
      },
      run: (a) async {
        final aspect = _enum(MovieAspect.values, _str(a, 'aspect') ?? 'wide');
        final (w, h) = movieSize(aspect, _int(a, 'short_side') ?? 1080);
        final movie = MovieDocument.create(
          name: _str(a, 'name') ?? 'Movie',
          width: w,
          height: h,
          fps: _int(a, 'fps') ?? 24,
          seconds: _num(a, 'seconds') ?? 10,
          background: _color(a, 'background') ?? 0xffffffff,
          transparent: _bool(a, 'transparent') ?? false,
          start: MovieStart.blank,
        );
        await c.storage.saveMovie(movie);
        return McpResult.json(_movieJson(movie, null));
      },
    ),
    McpTool(
      'get_movie',
      'A movie\'s tracks (top first) and their contents.',
      readOnly: true,
      properties: _movie,
      run: (a) => _withMovie(a, (m) => McpResult.json(_movieJson(m.movie, m))),
    ),
    McpTool(
      'add_movie_content',
      'A new track on top holding one content: text (words on the stage), '
          'drawing (an empty canvas to paint in the app) or flipbook.',
      properties: {
        ..._movie,
        'kind': {
          'type': 'string',
          'enum': ['text', 'drawing', 'flipbook'],
        },
        'name': {'type': 'string'},
        'text': {'type': 'string'},
        'start': {'type': 'integer', 'description': 'First frame.'},
        'length': {'type': 'integer', 'description': 'Frames.'},
        'color': {'type': 'string', 'description': 'Text colour.'},
        'size': {'type': 'number', 'description': 'Text size in pixels.'},
      },
      required: ['kind'],
      run: (a) => _withMovie(a, (m) => _addContent(m, a)),
    ),
    McpTool(
      'update_movie_content',
      'Changes a content: timing, place (x/y shares of the stage), scale, '
          'rotation in degrees, opacity, visibility, name, or a text '
          'content\'s words and colour. One undo step.',
      properties: {
        ..._movie,
        'content_id': {'type': 'string'},
        'name': {'type': 'string'},
        'start': {'type': 'integer'},
        'length': {'type': 'integer'},
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'scale': {'type': 'number'},
        'rotation': {'type': 'number'},
        'opacity': {'type': 'number', 'minimum': 0, 'maximum': 1},
        'hidden': {'type': 'boolean'},
        'text': {'type': 'string'},
        'color': {'type': 'string'},
      },
      required: ['content_id'],
      run: (a) => _withMovie(a, (m) => _updateContent(m, a)),
    ),
    McpTool(
      'set_movie_keyframes',
      'Animates a content: keyframes for one parameter (x, y as stage '
          'shares, scale, rotation in degrees, volume 0–1) at movie frames. '
          'Existing keys at those frames are replaced; clear removes the '
          'parameter\'s other keys first.',
      properties: {
        ..._movie,
        'content_id': {'type': 'string'},
        'param': {
          'type': 'string',
          'enum': [...MoveParam.values.map((p) => p.name), 'volume'],
        },
        'keys': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'frame': {'type': 'integer'},
              'value': {'type': 'number'},
              'easing': {
                'type': 'string',
                'enum': [for (final e in KeyEasing.values) e.name],
              },
            },
            'required': ['frame', 'value'],
          },
        },
        'clear': {'type': 'boolean'},
      },
      required: ['content_id', 'param', 'keys'],
      run: (a) => _withMovie(a, (m) => _keyframes(m, a)),
    ),
    McpTool(
      'delete_movie_content',
      'Deletes a content from its track.',
      destructive: true,
      properties: {
        ..._movie,
        'content_id': {'type': 'string'},
      },
      required: ['content_id'],
      run: (a) => _withMovie(a, (m) {
        _content(m, _str(a, 'content_id'));
        m.deleteContents(_str(a, 'content_id'));
        return McpResult.text('Deleted.');
      }),
    ),
    McpTool(
      'import_movie_media',
      'Brings a picture, video or sound into a movie on a new track at the '
          'playhead. Give base64 data with a file name, or a path the app '
          'may read.',
      properties: {
        ..._movie,
        'data': {'type': 'string'},
        'path': {'type': 'string'},
        'name': {'type': 'string', 'description': 'File name, extension too.'},
      },
      run: (a) => _withMovie(a, (m) => _importMedia(m, a)),
    ),
    McpTool(
      'seek_movie',
      'Moves the playhead of the movie on screen.',
      properties: {
        'frame': {'type': 'integer'},
      },
      required: ['frame'],
      run: (a) async {
        final m = MovieController.active.value;
        if (m == null) throw const McpToolError('No movie is open.');
        m.stop();
        m.seek(_int(a, 'frame') ?? 0);
        return McpResult.json({'playhead': m.playhead.value});
      },
    ),
    McpTool(
      'export_movie',
      'Exports a movie to the app\'s "MCP Exports" folder: mp4 (with '
          'sound), hevc (macOS, transparent), gif, png/jpeg frame sequence '
          '(zip), frame (one PNG at frame), project (.artmovie).',
      properties: {
        ..._movie,
        'format': {
          'type': 'string',
          'enum': [for (final f in MovieFormat.values) f.name],
        },
        'preview': {'type': 'boolean', 'description': 'Half size.'},
        'frame': {'type': 'integer'},
        'inline': {'type': 'boolean'},
      },
      required: ['format'],
      run: (a) => _withMovie(a, (m) => _exportMovie(m, a)),
    ),
  ];

  static final _adjustable = [
    for (final k in AdjustmentKind.values)
      if (k.params.isNotEmpty && k != AdjustmentKind.recolor) k,
  ];

  static Map<String, Object?> _numbers(String description, int n) => {
    'type': 'array',
    'description': description,
    'items': {'type': 'number'},
    'minItems': n,
    'maxItems': n,
  };

  // ── Arguments ──

  static String? _str(McpArgs a, String key) => switch (a[key]) {
    null => null,
    final String s => s,
    final v => throw McpToolError('$key must be a string, not $v.'),
  };

  static double? _num(McpArgs a, String key) => switch (a[key]) {
    null => null,
    final num n when n.isFinite => n.toDouble(),
    final v => throw McpToolError('$key must be a number, not $v.'),
  };

  static int? _int(McpArgs a, String key) => _num(a, key)?.round();

  static bool? _bool(McpArgs a, String key) => switch (a[key]) {
    null => null,
    final bool b => b,
    final v => throw McpToolError('$key must be true or false, not $v.'),
  };

  static T _enum<T extends Enum>(List<T> values, String name) =>
      values.where((v) => v.name == name).firstOrNull ??
      (throw McpToolError(
        '"$name" is not one of ${values.map((v) => v.name).join(', ')}.',
      ));

  /// "#rrggbb" / "#aarrggbb" as ARGB.
  static int? _color(McpArgs a, String key) {
    final s = _str(a, key);
    if (s == null) return null;
    final hex = s.startsWith('#') ? s.substring(1) : s;
    final v = int.tryParse(hex, radix: 16);
    if (v == null || (hex.length != 6 && hex.length != 8)) {
      throw McpToolError('$key must be "#rrggbb" or "#aarrggbb", not "$s".');
    }
    return hex.length == 6 ? 0xff000000 | v : v;
  }

  static List<double> _list(Object? v, int n, String what) {
    if (v is! List || v.length != n || v.any((x) => x is! num)) {
      throw McpToolError('$what must be $n numbers.');
    }
    return [for (final x in v) (x as num).toDouble()];
  }

  static Rect? _rect(Object? v) {
    if (v == null) return null;
    final [x, y, w, h] = _list(v, 4, 'rect');
    if (w <= 0 || h <= 0) throw const McpToolError('rect needs a size.');
    return Rect.fromLTWH(x, y, w, h);
  }

  Future<Uint8List> _bytes(McpArgs a) async {
    if (_str(a, 'data') case final data?) {
      try {
        return base64Decode(data);
      } on FormatException {
        throw const McpToolError('data is not base64.');
      }
    }
    final path = _str(a, 'path');
    if (path == null) throw const McpToolError('Give data or path.');
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw McpToolError(
        'The app cannot read $path (${e.osError?.message ?? e.message}); '
        'sandboxed apps only read their own folders: send the bytes as '
        'base64 data instead.',
      );
    }
  }

  // ── Drawing ──

  /// Ends whatever the user left half-done that would catch the call.
  Future<void> _ready() async {
    if (!c.initialized || c.disposed) {
      throw const McpToolError('The drawing is not loaded.');
    }
    c.cancelAdjustment();
    c.cancelLiquify();
    c.cancelClone();
    c.cancelTransform();
    c.finishText();
    await c.settleStroke();
    if (c.documentTransition) {
      throw const McpToolError('A drawing is opening; try again.');
    }
  }

  ArtLayer _layer(String? id) =>
      c.document.layers.where((l) => l.id == id).firstOrNull ??
      (throw McpToolError('No layer $id; get_document lists them.'));

  void _activate(McpArgs a) {
    if (_str(a, 'layer_id') case final id?) c.selectLayer(_layer(id).id);
  }

  Map<String, Object?> _layerJson(ArtLayer l) => {
    'id': l.id,
    'name': l.name,
    'visible': l.visible,
    'opacity': l.opacity,
    'blend': l.blend.name,
    'locked': l.locked,
    'alpha_lock': l.alphaLock,
    'clipping': l.clipping,
    if (l.group != null) 'group': l.group,
    if (l.text != null) 'text': l.text!.text,
  };

  static String _hex(int argb) => '#${argb.toRadixString(16).padLeft(8, '0')}';

  Map<String, Object?> _tools() => {
    'brush': {'id': c.brush.id, 'name': c.brush.name},
    'color': _hex(c.color),
    'size': c.size,
    'opacity': c.opacity,
  };

  Map<String, Object?> _document() {
    final d = c.document;
    return {
      'id': d.id,
      'name': d.name,
      'width': d.dimensions.width,
      'height': d.dimensions.height,
      'dpi': d.dpi,
      'background': d.backgroundHidden ? null : _hex(d.background),
      'layers': [for (final l in d.layers) _layerJson(l)],
      'active_layer': d.activeLayerId,
      ..._tools(),
      'can_undo': c.canUndo,
      'can_redo': c.canRedo,
    };
  }

  Future<McpResult> _snapshot(McpArgs a) async {
    await c.settleStroke();
    final d = c.document;
    final longest = (_int(a, 'max_side') ?? 1024).clamp(16, 4096);
    final scale = math.min(
      1.0,
      longest / math.max(d.dimensions.width, d.dimensions.height),
    );
    final size = (
      math.max(1, (d.dimensions.width * scale).round()),
      math.max(1, (d.dimensions.height * scale).round()),
    );
    final id = _str(a, 'layer_id');
    final doc = id == null
        ? null
        : d.copyWith(layers: [_layer(id)], backgroundHidden: true);
    final pixels = await Exporter(c).composite(doc, size);
    final png = await Isolate.run(() => encodePngPixels(pixels));
    return McpResult.image(
      png,
      caption:
          '${size.$1}×${size.$2} (canvas ${d.dimensions.width}×'
          '${d.dimensions.height}, scale ${scale.toStringAsFixed(3)})',
    );
  }

  Future<McpResult> _draw(McpArgs a) async {
    await _ready();
    _activate(a);
    final as = _enum([
      StudioTool.brush,
      StudioTool.eraser,
      StudioTool.smudge,
    ], _str(a, 'tool') ?? 'brush');
    final strokes = a['strokes'];
    if (strokes is! List || strokes.isEmpty) {
      throw const McpToolError('strokes must be a list of point lists.');
    }
    var drawn = 0;
    for (final stroke in strokes) {
      if (stroke is! List || stroke.isEmpty) continue;
      final points = [
        for (final p in stroke)
          if (p case [final num x, final num y, ...final rest])
            InkPoint(
              x.toDouble(),
              y.toDouble(),
              rest.firstOrNull is num
                  ? (rest.first as num).toDouble().clamp(0, 1)
                  : .6,
            )
          else
            throw McpToolError('A point must be [x, y] or [x, y, p], not $p.'),
      ];
      var time = Duration.zero;
      if (!c.beginStroke(
        points.first,
        simulatePressure: false,
        time: time,
        as: as,
      )) {
        throw McpToolError(
          'Cannot draw on "${c.document.activeLayer.name}": it is hidden, '
          'locked or a text layer.',
        );
      }
      for (final p in points.skip(1)) {
        time += const Duration(milliseconds: 8);
        c.appendPoint(p, time: time);
      }
      c.finishStroke();
      await c.settleStroke();
      drawn++;
    }
    return McpResult.text(
      'Drew $drawn stroke(s) on ${c.document.activeLayer.name}.',
    );
  }

  Future<McpResult> _fill(McpArgs a) async {
    await _ready();
    _activate(a);
    final List<Offset>? shape;
    if (_rect(a['rect']) case final r?) {
      shape = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    } else if (a['ellipse'] case final e?) {
      final [cx, cy, rx, ry] = _list(e, 4, 'ellipse');
      shape = [
        for (var i = 0; i < 96; i++)
          Offset(
            cx + rx * math.cos(i / 96 * 2 * math.pi),
            cy + ry * math.sin(i / 96 * 2 * math.pi),
          ),
      ];
    } else if (a['polygon'] case final List p) {
      if (p.length < 3) throw const McpToolError('polygon needs 3 points.');
      shape = [
        for (final q in p)
          if (_list(q, 2, 'A polygon point') case [final x, final y])
            Offset(x, y),
      ];
    } else {
      shape = null;
    }
    final color = _color(a, 'color');
    final before = c.color, kept = c.selection;
    try {
      if (color != null) c.selectColor(color);
      if (shape != null) {
        c.setSelection(SelectionRegion(id: newId(), points: shape));
      }
      await c.fillActiveLayer();
    } on FormatException {
      throw const McpToolError('The shape is not a usable area.');
    } finally {
      if (shape != null) c.setSelection(kept);
      if (color != null) c.selectColor(before);
    }
    return McpResult.text('Filled on ${c.document.activeLayer.name}.');
  }

  Future<McpResult> _text(McpArgs a) async {
    await _ready();
    final words = _str(a, 'text') ?? '';
    if (words.trim().isEmpty) throw const McpToolError('text is empty.');
    final before = c.document.layers.length;
    c.addText(words);
    if (c.document.layers.length == before) {
      throw const McpToolError('No room for another layer.');
    }
    final id = c.textEditing!;
    final align = _str(a, 'alignment');
    c.setText(
      (t) => t.copyWith(
        origin: Offset(
          _num(a, 'x') ?? t.origin.dx,
          _num(a, 'y') ?? t.origin.dy,
        ),
        width: _num(a, 'width'),
        size: _num(a, 'size'),
        color: _color(a, 'color'),
        font: _str(a, 'font'),
        weight: _int(a, 'weight'),
        italic: _bool(a, 'italic'),
        alignment: align == null ? null : _enum(TextAlignment.values, align),
      ),
    );
    c.finishText();
    return McpResult.json({'layer_id': id});
  }

  Future<McpResult> _adjust(McpArgs a) async {
    await _ready();
    _activate(a);
    final kind = _enum(_adjustable, _str(a, 'kind') ?? '');
    final values = switch (a['values']) {
      null => const <String, Object?>{},
      final Map m => m.cast<String, Object?>(),
      _ => throw const McpToolError('values must be an object.'),
    };
    final ids = {for (final p in kind.params) p.id};
    for (final key in values.keys) {
      if (!ids.contains(key)) {
        throw McpToolError('${kind.name} takes ${ids.join(', ')}; not $key.');
      }
    }
    if (!await c.startAdjustment(kind)) {
      throw McpToolError(
        'Cannot adjust "${c.document.activeLayer.name}" (hidden, locked, '
        'empty or a text layer).',
      );
    }
    for (final MapEntry(:key, :value) in values.entries) {
      if (value is! num) throw McpToolError('$key must be a number.');
      c.setAdjustmentValue(key, value.toDouble().clamp(0, 1));
    }
    await c.applyAdjustment();
    return McpResult.text('Applied ${kind.name}.');
  }

  Future<File> _write(String name, String extension, Uint8List bytes) async {
    final safe = name.replaceAll(RegExp(r'[^\w\- ]+'), '_').trim();
    final file = File(
      '${(await _exports()).path}/${safe.isEmpty ? 'export' : safe}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static McpResult _saved(
    File file,
    Uint8List bytes,
    String mimeType, {
    required bool inline,
  }) => McpResult([
    {'type': 'text', 'text': 'Saved ${file.path} (${bytes.length} bytes).'},
    if (inline && mimeType.startsWith('image/') && mimeType != 'image/tiff')
      {'type': 'image', 'data': base64Encode(bytes), 'mimeType': mimeType}
    else if (inline)
      {
        'type': 'resource',
        'resource': {
          'uri': Uri.file(file.path).toString(),
          'mimeType': mimeType,
          'blob': base64Encode(bytes),
        },
      },
  ]);

  Future<McpResult> _export(McpArgs a) async {
    await _ready();
    final format = _enum(ExportFormat.values, _str(a, 'format') ?? '');
    if (format.animated && !c.document.animating) {
      throw const McpToolError('Turn Animation Assist on for animations.');
    }
    if (format == ExportFormat.pagesPdf && !c.document.pageAssist) {
      throw const McpToolError('pagesPdf needs Page Assist.');
    }
    final bytes = await Exporter(c).export(format);
    final file = await _write(
      _str(a, 'name') ?? c.document.name,
      format.extension,
      bytes,
    );
    return _saved(
      file,
      bytes,
      format.mimeType,
      inline: _bool(a, 'inline') ?? false,
    );
  }

  // ── Movies ──

  /// [run] on the movie on screen (live, undoable there), or on movie_id
  /// loaded here and saved after.
  Future<McpResult> _withMovie(
    McpArgs a,
    FutureOr<McpResult> Function(MovieController m) run,
  ) async {
    final id = _str(a, 'movie_id');
    final open = MovieController.active.value;
    if (open != null && (id == null || id == open.movie.id)) return run(open);
    if (id == null) {
      throw const McpToolError(
        'No movie is open in ArtBlend: pass movie_id (list_movies).',
      );
    }
    final movie = (await c.storage.listMovies()).movies
        .where((m) => m.id == id)
        .firstOrNull;
    if (movie == null) throw McpToolError('No movie $id.');
    final m = MovieController(storage: c.storage, movie: movie);
    try {
      await m.loadDrawings();
      final result = await run(m);
      await c.storage.saveMovie(m.movie, drawings: m.drawings);
      return result;
    } finally {
      m.dispose();
    }
  }

  static MovieContent _content(MovieController m, String? id) =>
      m.content(id) ??
      (throw McpToolError('No content $id; get_movie lists them.'));

  Map<String, Object?> _movieJson(MovieDocument movie, MovieController? m) => {
    'id': movie.id,
    'name': movie.name,
    'width': movie.width,
    'height': movie.height,
    'fps': movie.fps,
    'frames': movie.frames,
    'background': _hex(movie.background),
    'transparent': movie.transparent,
    if (m != null) 'playhead': m.playhead.value,
    'tracks': [
      for (final t in movie.tracks)
        {
          'id': t.id,
          'name': t.name,
          'kind': t.kind.name,
          if (t.hidden) 'hidden': true,
          'contents': [
            for (final x in t.contents)
              {
                'id': x.id,
                'name': x.name,
                'start': x.start,
                'length': x.length,
                'x': x.transform.x,
                'y': x.transform.y,
                'scale': x.transform.scaleX,
                'rotation': x.transform.rotation * 180 / math.pi,
                'opacity': x.opacity,
                if (x.hidden) 'hidden': true,
                if (x.keys.isNotEmpty)
                  'keyframes': {
                    for (final MapEntry(:key, :value) in x.keys.entries)
                      key: [for (final k in value) x.start + k.frame],
                  },
                if (m?.textOf(x.id) case final text?) 'text': text.text,
              },
          ],
        },
    ],
  };

  Future<McpResult> _addContent(MovieController m, McpArgs a) async {
    final kind = _enum([
      TrackKind.text,
      TrackKind.drawing,
      TrackKind.flipbook,
    ], _str(a, 'kind') ?? '');
    final start = (_int(a, 'start') ?? m.playhead.value).clamp(
      0,
      m.movie.frames - 1,
    );
    m.stop();
    m.seek(start);
    if (kind == TrackKind.text) {
      final words = _str(a, 'text') ?? '';
      if (words.trim().isEmpty) throw const McpToolError('text is empty.');
      var text = m.newText(words);
      text = text.copyWith(color: _color(a, 'color'), size: _num(a, 'size'));
      m.addText(text, _str(a, 'name') ?? 'Text');
    } else {
      m.addTrack(kind, _str(a, 'name') ?? kind.name);
    }
    final id = m.selected!;
    if (_int(a, 'length') case final length?) {
      m.edit(
        m.withContent(
          id,
          (x) => x.copyWith(length: length.clamp(1, m.movie.frames - start)),
        ),
      );
    }
    return McpResult.json({'content_id': id});
  }

  Future<McpResult> _updateContent(MovieController m, McpArgs a) async {
    final id = _str(a, 'content_id');
    _content(m, id);
    final rotation = _num(a, 'rotation'), scale = _num(a, 'scale');
    final next = m.withContent(id!, (x) {
      final t = x.transform;
      return x.copyWith(
        name: _str(a, 'name'),
        start: _int(a, 'start')?.clamp(0, m.movie.frames - 1),
        length: _int(a, 'length')?.clamp(1, m.movie.frames),
        hidden: _bool(a, 'hidden'),
        opacity: _num(a, 'opacity')?.clamp(0, 1),
        transform: t.copyWith(
          x: _num(a, 'x'),
          y: _num(a, 'y'),
          scaleX: scale?.clamp(
            ContentTransform.minScale,
            ContentTransform.maxScale,
          ),
          scaleY: scale?.clamp(
            ContentTransform.minScale,
            ContentTransform.maxScale,
          ),
          rotation: rotation == null ? null : rotation * math.pi / 180,
        ),
      );
    });
    m.edit(next);
    final words = _str(a, 'text'), color = _color(a, 'color');
    if (words != null || color != null) {
      final text = m.textOf(id);
      if (text == null) throw const McpToolError('Not a text content.');
      m.setText(id, text.copyWith(text: words, color: color));
    }
    return McpResult.json(_movieJson(m.movie, m));
  }

  Future<McpResult> _keyframes(MovieController m, McpArgs a) async {
    final id = _str(a, 'content_id');
    final content = _content(m, id);
    final param = _str(a, 'param')!;
    if (![...MoveParam.values.map((p) => p.name), 'volume'].contains(param)) {
      throw McpToolError('No parameter $param.');
    }
    final raw = a['keys'];
    if (raw is! List || raw.isEmpty) {
      throw const McpToolError('keys must be a list.');
    }
    var keys = (_bool(a, 'clear') ?? false)
        ? <Keyframe>[]
        : [...?content.keys[param]];
    for (final k in raw) {
      if (k is! Map) throw const McpToolError('A key is {frame, value}.');
      final key = k.cast<String, Object?>();
      final frame = _int(key, 'frame'), value = _num(key, 'value');
      if (frame == null || value == null) {
        throw const McpToolError('A key needs frame and value.');
      }
      final local = frame - content.start;
      if (local < 0 || local >= content.length) {
        throw McpToolError(
          'Frame $frame is outside the content (${content.start}–'
          '${content.start + content.length - 1}).',
        );
      }
      final easing = _str(key, 'easing');
      keys = withKey(
        keys,
        Keyframe(
          local,
          param == MoveParam.rotation.name ? value * math.pi / 180 : value,
          easing: easing == null
              ? KeyEasing.linear
              : _enum(KeyEasing.values, easing),
        ),
      );
    }
    m.edit(
      m.withContent(id!, (x) => x.copyWith(keys: {...x.keys, param: keys})),
    );
    return McpResult.json({
      'content_id': id,
      param: [for (final k in keys) content.start + k.frame],
    });
  }

  static const _pictures = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};

  Future<McpResult> _importMedia(MovieController m, McpArgs a) async {
    final path = _str(a, 'path');
    final name = _str(a, 'name') ?? path?.split('/').last ?? 'Media';
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final title = dot < 0 ? name : name.substring(0, dot);
    final before = {
      for (final t in m.movie.tracks)
        for (final x in t.contents) x.id,
    };
    final bool ok;
    if (_pictures.contains(extension)) {
      ok = await m.importPicture(await _bytes(a), title);
    } else if (_str(a, 'data') != null) {
      final dir = await Directory.systemTemp.createTemp('artblend-mcp');
      try {
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(await _bytes(a));
        ok = await m.importMedia(file.path, title);
      } finally {
        await dir.delete(recursive: true);
      }
    } else if (path != null) {
      if (!await File(path).exists()) {
        throw McpToolError(
          'The app cannot read $path; send the bytes as base64 data.',
        );
      }
      ok = await m.importMedia(path, title);
    } else {
      throw const McpToolError('Give data (with name) or path.');
    }
    if (!ok) throw McpToolError('Could not read $name as a picture or media.');
    return McpResult.json({
      'contents': [
        for (final t in m.movie.tracks)
          for (final x in t.contents)
            if (!before.contains(x.id)) {'id': x.id, 'name': x.name},
      ],
    });
  }

  Future<McpResult> _exportMovie(MovieController m, McpArgs a) async {
    final format = _enum(MovieFormat.values, _str(a, 'format') ?? '');
    if (_int(a, 'frame') case final frame?) {
      m.stop();
      m.seek(frame);
    }
    final bytes = await MovieExporter(
      m,
    ).export(MovieExportOptions(format, preview: _bool(a, 'preview') ?? false));
    final file = await _write(m.movie.name, format.extension, bytes);
    return _saved(
      file,
      bytes,
      format.mimeType,
      inline: _bool(a, 'inline') ?? false,
    );
  }
}
