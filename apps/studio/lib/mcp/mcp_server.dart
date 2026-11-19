import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

typedef McpArgs = Map<String, Object?>;

/// One tool an agent may call: its JSON Schema input and what it does.
class McpTool {
  const McpTool(
    this.name,
    this.description, {
    this.properties = const {},
    this.required = const [],
    this.readOnly = false,
    this.destructive = false,
    required this.run,
  });
  final String name, description;
  final Map<String, Object?> properties;
  final List<String> required;
  final bool readOnly, destructive;
  final Future<McpResult> Function(McpArgs args) run;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    },
    'annotations': {
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'openWorldHint': false,
    },
  };
}

class McpResult {
  const McpResult(this.content, {this.isError = false});
  McpResult.text(String text, {bool isError = false})
    : this([
        {'type': 'text', 'text': text},
      ], isError: isError);
  McpResult.json(Object? value)
    : this.text(const JsonEncoder.withIndent(' ').convert(value));
  McpResult.image(Uint8List png, {String? caption})
    : this([
        if (caption != null) {'type': 'text', 'text': caption},
        {'type': 'image', 'data': base64Encode(png), 'mimeType': 'image/png'},
      ]);

  final List<Map<String, Object?>> content;
  final bool isError;

  Map<String, Object?> toJson() => {
    'content': content,
    if (isError) 'isError': true,
  };
}

/// A mistake in a tool call the agent can fix (a bad argument, a missing
/// layer …): reported to it as the tool's result, not a protocol error.
class McpToolError implements Exception {
  const McpToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RpcError implements Exception {
  const _RpcError(this.code, this.message);
  final int code;
  final String message;
}

/// The Model Context Protocol over Streamable HTTP, JSON responses only:
/// POST /mcp with a JSON-RPC message (or batch), a bearer token on every
/// request. Tool calls run one at a time, in arrival order.
class McpServer {
  McpServer({
    required List<McpTool> tools,
    required this.token,
    this.name = 'artblend',
    this.version = '1.0.0',
    this.instructions,
  }) : tools = {for (final t in tools) t.name: t};

  static const defaultPort = 47821;
  static const maxBody = 64 * 1024 * 1024;
  static const protocols = ['2025-11-25', '2025-06-18', '2025-03-26'];

  final Map<String, McpTool> tools;
  final String name, version;
  final String? instructions;
  String token;

  /// The tool being run, or the last one for a few seconds after.
  final ValueNotifier<String?> activity = ValueNotifier(null);

  HttpServer? _http;
  Future<void> _queue = Future.value();
  Timer? _idle;

  bool get running => _http != null;
  int? get port => _http?.port;

  static String newToken() {
    final random = Random.secure();
    return base64Url
        .encode([for (var i = 0; i < 24; i++) random.nextInt(256)])
        .replaceAll('=', '');
  }

  Future<void> start(InternetAddress address, {int port = defaultPort}) async {
    await stop();
    final http = await HttpServer.bind(address, port);
    _http = http;
    http.listen(
      (request) => unawaited(_serve(request)),
      onError: (Object _) {},
    );
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  void dispose() {
    _idle?.cancel();
    unawaited(stop());
    activity.dispose();
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != '/mcp') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final origin = request.headers.value('origin');
      if (origin != null && !_localOrigin(origin)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (!_authorized(request.headers.value('authorization'))) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.set('WWW-Authenticate', 'Bearer');
        return;
      }
      if (request.method == 'DELETE') return;
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set('Allow', 'POST, DELETE');
        return;
      }
      final body = await _read(request);
      if (body == null) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      Object? message;
      try {
        message = jsonDecode(body);
      } on FormatException {
        _json(response, _error(null, -32700, 'Parse error'));
        return;
      }
      final Object? reply;
      if (message is List) {
        final replies = [for (final m in message) ?await handle(m)];
        reply = replies.isEmpty ? null : replies;
      } else {
        reply = await handle(message);
      }
      if (reply == null) {
        response.statusCode = HttpStatus.accepted;
        return;
      }
      _json(response, reply);
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  static void _json(HttpResponse response, Object? value) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
  }

  static Future<String?> _read(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxBody) return null;
    }
    return utf8.decode(bytes.takeBytes());
  }

  static bool _localOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host;
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  bool _authorized(String? header) {
    const prefix = 'Bearer ';
    if (header == null || !header.startsWith(prefix)) return false;
    final given = utf8.encode(header.substring(prefix.length).trim());
    final expected = utf8.encode(token);
    if (given.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// One JSON-RPC message; null for a notification (no reply).
  Future<Map<String, Object?>?> handle(Object? message) async {
    if (message is! Map) return _error(null, -32600, 'Invalid Request');
    final id = message['id'];
    final method = message['method'];
    final params = message['params'];
    if (method is! String) {
      return id == null ? null : _error(id, -32600, 'Invalid Request');
    }
    if (id == null) return null;
    try {
      final McpArgs args = params is Map
          ? params.cast<String, Object?>()
          : const {};
      final Object result = switch (method) {
        'initialize' => _initialize(args),
        'ping' => const <String, Object?>{},
        'tools/list' => {
          'tools': [for (final t in tools.values) t.toJson()],
        },
        'tools/call' => await _call(args),
        _ => throw _RpcError(-32601, 'Method not found: $method'),
      };
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _RpcError catch (e) {
      return _error(id, e.code, e.message);
    }
  }

  Map<String, Object?> _initialize(McpArgs params) {
    final asked = params['protocolVersion'];
    return {
      'protocolVersion': protocols.contains(asked) ? asked : protocols.first,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': name, 'title': 'ArtBlend', 'version': version},
      if (instructions != null) 'instructions': instructions,
    };
  }

  Future<Map<String, Object?>> _call(McpArgs params) async {
    final tool = tools[params['name']];
    if (tool == null) {
      throw _RpcError(-32602, 'Unknown tool: ${params['name']}');
    }
    final raw = params['arguments'];
    final args = raw is Map ? raw.cast<String, Object?>() : <String, Object?>{};
    final run = _queue.then((_) => _run(tool, args));
    _queue = run.then((_) {}, onError: (Object _) {});
    return (await run).toJson();
  }

  Future<McpResult> _run(McpTool tool, McpArgs args) async {
    _idle?.cancel();
    activity.value = tool.name;
    try {
      return await tool.run(args);
    } on McpToolError catch (e) {
      return McpResult.text(e.message, isError: true);
    } catch (e) {
      return McpResult.text('$e', isError: true);
    } finally {
      _idle = Timer(const Duration(seconds: 3), () => activity.value = null);
    }
  }

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
