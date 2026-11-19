import 'dart:convert';
import 'dart:io';

import 'package:atelier_studio/mcp/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late McpServer server;
  late HttpClient http;
  final order = <String>[];

  setUp(() async {
    order.clear();
    server = McpServer(
      token: 'secret-token-1234567890',
      instructions: 'Hi.',
      tools: [
        McpTool(
          'echo',
          'Says it back.',
          properties: {
            'text': {'type': 'string'},
          },
          readOnly: true,
          run: (a) async => McpResult.text('${a['text']}'),
        ),
        McpTool(
          'slow',
          'Waits.',
          run: (a) async {
            order.add('start ${a['n']}');
            await Future<void>.delayed(Duration(milliseconds: a['ms'] as int));
            order.add('end ${a['n']}');
            return McpResult.text('ok');
          },
        ),
        McpTool(
          'fail',
          'Always wrong.',
          destructive: true,
          run: (_) async => throw const McpToolError('Bad layer.'),
        ),
      ],
    );
    await server.start(InternetAddress.loopbackIPv4, port: 0);
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await server.stop();
  });

  Future<(int, Object?)> post(
    Object? body, {
    String? token = 'secret-token-1234567890',
    String? origin,
    String method = 'POST',
  }) async {
    final request = await http.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    );
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (origin != null) request.headers.set('Origin', origin);
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  Map<String, Object?> rpc(String method, [Map<String, Object?>? params]) => {
    'jsonrpc': '2.0',
    'id': 7,
    'method': method,
    'params': ?params,
  };

  test('only requests with the key get in', () async {
    expect((await post(rpc('ping'), token: null)).$1, 401);
    expect((await post(rpc('ping'), token: 'secret-token-123456789X')).$1, 401);
    expect((await post(rpc('ping'), origin: 'https://evil.example')).$1, 403);
    expect((await post(rpc('ping'), origin: 'http://localhost:3000')).$1, 200);
    expect((await post(null, method: 'GET')).$1, 405);
  });

  test('initialize, notifications and the tool list', () async {
    final (status, reply) = await post(
      rpc('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      }),
    );
    expect(status, 200);
    final result = (reply as Map)['result'] as Map;
    expect(result['protocolVersion'], '2025-06-18');
    expect((result['serverInfo'] as Map)['name'], 'artblend');
    expect(result['instructions'], 'Hi.');
    expect((result['capabilities'] as Map).containsKey('tools'), isTrue);

    final note = await post({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    expect(note.$1, 202);

    final (_, list) = await post(rpc('tools/list'));
    final tools = ((list as Map)['result'] as Map)['tools'] as List;
    expect(
      [for (final t in tools) (t as Map)['name']],
      ['echo', 'slow', 'fail'],
    );
    final echo = tools.first as Map;
    expect((echo['inputSchema'] as Map)['type'], 'object');
    expect((echo['annotations'] as Map)['readOnlyHint'], isTrue);
    expect(((tools[2] as Map)['annotations'] as Map)['destructiveHint'], true);
  });

  test('an unknown version is answered with the newest', () async {
    final (_, reply) = await post(
      rpc('initialize', {'protocolVersion': '1999-01-01'}),
    );
    expect(
      ((reply as Map)['result'] as Map)['protocolVersion'],
      McpServer.protocols.first,
    );
  });

  test('tool calls: results, tool errors, protocol errors', () async {
    final (_, ok) = await post(
      rpc('tools/call', {
        'name': 'echo',
        'arguments': {'text': 'merhaba'},
      }),
    );
    final result = (ok as Map)['result'] as Map;
    expect(result['content'], [
      {'type': 'text', 'text': 'merhaba'},
    ]);
    expect(result.containsKey('isError'), isFalse);

    final (_, bad) = await post(rpc('tools/call', {'name': 'fail'}));
    final failed = (bad as Map)['result'] as Map;
    expect(failed['isError'], isTrue);
    expect((failed['content'] as List).single, {
      'type': 'text',
      'text': 'Bad layer.',
    });

    final (_, unknown) = await post(rpc('tools/call', {'name': 'nope'}));
    expect(((unknown as Map)['error'] as Map)['code'], -32602);
    final (_, method) = await post(rpc('resources/list'));
    expect(((method as Map)['error'] as Map)['code'], -32601);
    final request = await http.post('127.0.0.1', server.port!, '/mcp');
    request.headers.set('Authorization', 'Bearer ${server.token}');
    request.write('{not json');
    final response = await request.close();
    final parsed = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect((parsed['error'] as Map)['code'], -32700);
  });

  test('batches get a reply list', () async {
    final (status, reply) = await post([
      rpc('ping'),
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      {'jsonrpc': '2.0', 'id': 8, 'method': 'ping'},
    ]);
    expect(status, 200);
    expect([for (final r in reply as List) (r as Map)['id']], [7, 8]);
  });

  test('tool calls run one at a time, in order', () async {
    Map<String, Object?> slow(int n, int ms) => rpc('tools/call', {
      'name': 'slow',
      'arguments': {'n': n, 'ms': ms},
    });
    await Future.wait([post(slow(1, 120)), post(slow(2, 10))]);
    expect(order, ['start 1', 'end 1', 'start 2', 'end 2']);
  });

  test('the activity shows the running tool', () async {
    final seen = <String?>[];
    server.activity.addListener(() => seen.add(server.activity.value));
    await post(rpc('tools/call', {'name': 'echo', 'arguments': {}}));
    expect(seen, ['echo']);
  });

  test('a new token shuts the old one out', () async {
    final old = server.token;
    server.token = McpServer.newToken();
    expect(server.token.length, greaterThanOrEqualTo(32));
    expect((await post(rpc('ping'), token: old)).$1, 401);
    expect((await post(rpc('ping'), token: server.token)).$1, 200);
  });
}
