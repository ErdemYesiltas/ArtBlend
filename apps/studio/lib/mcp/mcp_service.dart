import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mcp_server.dart';

/// ArtBlend's MCP server as a setting: off until the user turns it on,
/// on this computer only (or the local network, for a tablet), its key
/// kept in the platform keychain.
class McpService extends ChangeNotifier {
  McpService(
    List<McpTool> tools, {
    String? instructions,
    this.preferences,
    FlutterSecureStorage? secrets,
    this.port = McpServer.defaultPort,
  }) : server = McpServer(tools: tools, token: '', instructions: instructions),
       _secrets =
           secrets ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );

  final McpServer server;
  final SharedPreferences? preferences;
  final FlutterSecureStorage _secrets;
  final int port;
  static const _tokenKey = 'artblend.mcp.token.v1';

  bool enabled = false;

  /// Listening on every network interface, not just this device: what a
  /// tablet needs (the agent runs on a computer).
  bool lan = false;

  /// Why the server is not running although enabled.
  String? error;

  /// This device's addresses an agent can reach it on.
  List<String> hosts = const [];

  bool get running => server.running;
  String get token => server.token;

  List<String> get urls => [
    for (final h in hosts) 'http://$h:${server.port ?? port}/mcp',
  ];

  /// How to add it to Claude Code, one line an address.
  List<String> get commands => [
    for (final u in urls)
      'claude mcp add --transport http artblend $u '
          '--header "Authorization: Bearer $token"',
  ];

  Future<void> restore() async {
    enabled = preferences?.getBool('mcp.enabled') ?? false;
    lan =
        preferences?.getBool('mcp.lan') ??
        (Platform.isAndroid || Platform.isIOS);
    if (enabled) await _start();
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    enabled = on;
    await preferences?.setBool('mcp.enabled', on);
    on ? await _start() : await _stop();
    notifyListeners();
  }

  Future<void> setLan(bool on) async {
    lan = on;
    await preferences?.setBool('mcp.lan', on);
    if (enabled) await _start();
    notifyListeners();
  }

  /// A new key: agents holding the old one are shut out.
  Future<void> renewToken() async {
    server.token = McpServer.newToken();
    await _secrets.write(key: _tokenKey, value: server.token);
    notifyListeners();
  }

  Future<void> _start() async {
    error = null;
    try {
      if (server.token.isEmpty) {
        final saved = await _secrets.read(key: _tokenKey);
        if (saved == null || saved.length < 16) {
          await renewToken();
        } else {
          server.token = saved;
        }
      }
      await server.start(
        lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        port: port,
      );
      hosts = lan ? await _lanHosts() : const ['127.0.0.1'];
    } catch (e) {
      await server.stop();
      error = e is SocketException ? (e.osError?.message ?? e.message) : '$e';
      hosts = const [];
    }
  }

  Future<void> _stop() async {
    await server.stop();
    error = null;
    hosts = const [];
  }

  static Future<List<String>> _lanHosts() async {
    final found = [
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
    return found.isEmpty ? const ['127.0.0.1'] : found;
  }

  @override
  void dispose() {
    server.dispose();
    super.dispose();
  }
}
