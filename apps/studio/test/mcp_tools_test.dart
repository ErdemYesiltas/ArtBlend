import 'dart:convert';
import 'dart:io';

import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/mcp/artblend_tools.dart';
import 'package:atelier_studio/mcp/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioController c;
  late McpServer server;
  late Directory exports;

  setUp(() async {
    c = StudioController(storage: MemoryStorage());
    await c.initialize();
    exports = await Directory.systemTemp.createTemp('mcp-exports');
    server = McpServer(
      tools: ArtBlendTools(c, exports: () async => exports).tools,
      token: 't',
    );
  });

  tearDown(() async {
    await exports.delete(recursive: true);
  });

  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final reply = await server.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    });
    return (reply!['result'] as Map).cast<String, Object?>();
  }

  Object? json(Map<String, Object?> result) {
    expect(result['isError'], isNull, reason: '${result['content']}');
    final text = ((result['content'] as List).first as Map)['text'] as String;
    return jsonDecode(text);
  }

  void ok(Map<String, Object?> result) =>
      expect(result['isError'], isNull, reason: '${result['content']}');

  String error(Map<String, Object?> result) {
    expect(result['isError'], isTrue);
    return ((result['content'] as List).first as Map)['text'] as String;
  }

  Future<List<int>> pixel(int x, int y) async {
    final p = await Exporter(c).composite();
    final i = (y * p.width + x) * 4;
    return p.bytes.sublist(i, i + 4);
  }

  test('every tool has a schema and a description', () {
    final names = {for (final t in server.tools.values) t.name};
    expect(names, containsAll(['get_document', 'draw_strokes', 'snapshot']));
    for (final t in server.tools.values) {
      expect(t.description, isNotEmpty);
      expect(jsonEncode(t.toJson()), isNotEmpty);
    }
  });

  test('get_document describes the drawing', () async {
    final doc = json(await call('get_document')) as Map;
    expect(doc['width'], c.document.dimensions.width);
    expect((doc['layers'] as List).length, 1);
    expect(doc['active_layer'], c.document.activeLayerId);
    expect(doc['color'], startsWith('#ff'));
  });

  test('fill a rectangle, then undo it', () async {
    ok(
      await call('fill', {
        'color': '#ff0000',
        'rect': [10, 10, 50, 50],
      }),
    );
    expect(await pixel(20, 20), [255, 0, 0, 255]);
    expect((await pixel(200, 200))[1], greaterThan(200));
    expect(c.selection, isNull);
    json(await call('undo'));
    expect((await pixel(20, 20))[1], greaterThan(200));
  });

  test('strokes with the chosen brush colour, on a new layer', () async {
    final added = json(await call('add_layer', {'name': 'Ink'})) as Map;
    expect(c.document.activeLayer.name, 'Ink');
    json(
      await call('set_brush', {'color': '#0000ff', 'size': 30, 'opacity': 1}),
    );
    expect(c.color, 0xff0000ff);
    final drawn = await call('draw_strokes', {
      'strokes': [
        [
          for (var x = 100; x <= 400; x += 4) [x, 300, 1],
        ],
      ],
    });
    expect(drawn['isError'], isNull, reason: '${drawn['content']}');
    expect(c.canUndo, isTrue);
    final px = await pixel(250, 300);
    expect(px[2], greaterThan(150));
    expect(px[0], lessThan(100));
    final hide = await call('update_layer', {
      'layer_id': added['layer_id'],
      'visible': false,
      'blend': 'multiply',
      'opacity': .5,
    });
    final layer = json(hide) as Map;
    expect(layer['visible'], isFalse);
    expect(layer['blend'], 'multiply');
    expect(
      error(
        await call('draw_strokes', {
          'strokes': [
            [
              [1, 1],
              [5, 5],
            ],
          ],
        }),
      ),
      contains('hidden'),
    );
  });

  test('a snapshot is a scaled PNG', () async {
    final result = await call('snapshot', {'max_side': 256});
    final content = result['content'] as List;
    final image = content.last as Map;
    expect(image['type'], 'image');
    final png = base64Decode(image['data'] as String);
    expect(png.sublist(1, 4), utf8.encode('PNG'));
    expect((content.first as Map)['text'], startsWith('256×'));
  });

  test('text layers and adjustments', () async {
    final text = json(
      await call('add_text', {
        'text': 'Merhaba',
        'x': 40,
        'y': 50,
        'size': 64,
        'color': '#112233',
      }),
    ) as Map;
    final layer = c.document.layers.firstWhere((l) => l.id == text['layer_id']);
    expect(layer.text?.text, 'Merhaba');
    expect(layer.text?.origin, const Offset(40, 50));
    expect(layer.text?.color, 0xff112233);
    expect(c.textEditing, isNull);

    json(await call('add_layer'));
    ok(await call('fill', {'color': '#808080'}));
    expect(
      error(
        await call('adjust', {
          'kind': 'gaussianBlur',
          'values': {'hue': .3},
        }),
      ),
      contains('amount'),
    );
    final adjusted = await call('adjust', {
      'kind': 'hueSaturationBrightness',
      'values': {'brightness': 0},
    });
    expect(adjusted['isError'], isNull, reason: '${adjusted['content']}');
    expect((await pixel(600, 600))[0], lessThan(100));
  });

  test('wrong arguments come back as tool errors', () async {
    expect(error(await call('update_layer', {'layer_id': 'x'})), contains('x'));
    expect(error(await call('set_brush', {'color': 'red'})), contains('#'));
    expect(error(await call('set_brush', {'brush': 'zzz'})), contains('zzz'));
    expect(
      error(await call('new_drawing', {'width': 10, 'height': 10})),
      contains('64'),
    );
  });

  test('new drawing, then back to the first from the gallery', () async {
    final first = c.document.id;
    ok(await call('fill', {'color': '#ff0000'}));
    final made = json(
      await call('new_drawing', {
        'name': 'Agent',
        'width': 640,
        'height': 480,
        'background': '#000000',
      }),
    ) as Map;
    expect(made['width'], 640);
    expect(c.document.name, 'Agent');
    expect(c.document.background, 0xff000000);
    final listed = json(await call('list_drawings')) as List;
    expect([for (final d in listed) (d as Map)['id']], contains(first));
    json(await call('open_drawing', {'id': first}));
    expect(c.document.id, first);
  });

  test('export_drawing writes a file in the exports folder', () async {
    final result = await call('export_drawing', {
      'format': 'png',
      'name': 'out/../x',
      'inline': true,
    });
    final content = result['content'] as List;
    expect((content.first as Map)['text'], contains(exports.path));
    expect((content.last as Map)['type'], 'image');
    final files = exports.listSync();
    expect(files, hasLength(1));
    expect(files.single.path, isNot(contains('..')));
    expect(
      error(await call('export_drawing', {'format': 'gif'})),
      contains('Animation'),
    );
  });

  test('movies: create, add text, move, keyframe', () async {
    final movie = json(
      await call('create_movie', {
        'name': 'Agent movie',
        'aspect': 'square',
        'short_side': 512,
        'fps': 12,
        'seconds': 4,
      }),
    ) as Map;
    final id = movie['id'] as String;
    expect(movie['width'], 512);
    expect(movie['frames'], 48);
    expect(error(await call('get_movie')), contains('movie_id'));

    final added = json(
      await call('add_movie_content', {
        'movie_id': id,
        'kind': 'text',
        'text': 'Selam',
        'start': 6,
        'length': 30,
        'color': '#ff0000',
      }),
    ) as Map;
    final content = added['content_id'] as String;
    json(
      await call('update_movie_content', {
        'movie_id': id,
        'content_id': content,
        'x': .25,
        'rotation': 90,
        'text': 'Selam dünya',
      }),
    );
    json(
      await call('set_movie_keyframes', {
        'movie_id': id,
        'content_id': content,
        'param': 'y',
        'keys': [
          {'frame': 6, 'value': .2},
          {'frame': 35, 'value': .8, 'easing': 'easeOut'},
        ],
      }),
    );
    expect(
      error(
        await call('set_movie_keyframes', {
          'movie_id': id,
          'content_id': content,
          'param': 'y',
          'keys': [
            {'frame': 40, 'value': 1},
          ],
        }),
      ),
      contains('outside'),
    );

    final read = json(await call('get_movie', {'movie_id': id})) as Map;
    final track = (read['tracks'] as List).single as Map;
    expect(track['kind'], 'text');
    final x = (track['contents'] as List).single as Map;
    expect(x['start'], 6);
    expect(x['length'], 30);
    expect(x['x'], .25);
    expect((x['rotation'] as num).round(), 90);
    expect(x['text'], 'Selam dünya');
    expect((x['keyframes'] as Map)['y'], [6, 35]);

    final listed = json(await call('list_movies')) as List;
    expect((listed.single as Map)['tracks'], 1);
  });
}
