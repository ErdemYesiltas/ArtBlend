import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:localhub_client/localhub_client.dart';

import 'local_network_permission.dart';

/// The hub session, bearer token included, in the platform keychain; never
/// preferences or a plain file.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'localhub.session.v1';

  @override
  Future<HubSession?> load() async {
    final json = await _storage.read(key: _key);
    return json == null
        ? null
        : HubSession.fromJson(
            (jsonDecode(json) as Map).cast<String, Object?>(),
          );
  }

  @override
  Future<void> save(HubSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Thrown for a pairing QR from the retired ArtBlend Companion.
class CompanionRetired implements Exception {
  const CompanionRetired();
}

/// LocalHub on the user's Mac: pairing, what this device may use, and the
/// hub's integrations. AI features show only when [can] says so.
class HubService extends ChangeNotifier {
  HubService({HubClient? client})
    : client = client ?? HubClient(SecureSessionStore());

  final HubClient client;
  static const app = 'artblend';

  /// What ArtBlend asks for; the Mac grants the intersection with its
  /// defaults and may change it later.
  static const requestedScopes = ['chat', 'image.create', 'image.edit'];

  List<Map<String, Object?>> models = const [];
  List<Map<String, Object?>> integrations = const [];
  bool busy = false;
  String? error;
  bool _disposed = false;
  StreamSubscription<DeviceEvent>? _events;

  HubSession? get session => client.session;
  bool get paired => session != null;

  /// Granted at pairing, then as the Mac changes them (`session` events).
  List<String>? _liveScopes;
  List<String> get scopes => _liveScopes ?? session?.scopes ?? const [];

  Future<void> restore() async {
    try {
      if (await client.restore() != null) await refresh();
    } catch (e) {
      error = e.toString();
    }
    _notify();
  }

  Future<void> pair(HubInvite invite, {required String deviceName}) async {
    if (busy) return;
    if (invite.version != 2) throw const CompanionRetired();
    busy = true;
    error = null;
    _notify();
    try {
      await ensureLocalNetworkAccess();
      _liveScopes = null;
      await client.pair(
        invite,
        deviceName: deviceName,
        app: app,
        scopes: requestedScopes,
      );
      await refresh();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> unpair() async {
    await _events?.cancel();
    _events = null;
    try {
      await client.unpair();
    } finally {
      models = integrations = const [];
      _notify();
    }
  }

  /// Models and integrations as the Mac has them now; also starts following
  /// permission changes and revocation.
  Future<void> refresh() async {
    if (!paired) return;
    await ensureLocalNetworkAccess();
    try {
      final results = await Future.wait([
        client.models(),
        client.integrations(),
      ]);
      models = results[0];
      integrations = results[1];
      error = null;
      _follow();
    } on HubException catch (e) {
      if (e.code == 'unauthorized') {
        await _forget();
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }
    _notify();
  }

  void _follow() {
    if (_events != null) return;
    _events = client.deviceEvents().listen(
      (event) {
        if (event.type == 'revoked') {
          unawaited(_forget());
        } else if (event.type == 'session') {
          // The Mac changed this device's permissions.
          final granted = event.data['scopes'];
          if (granted is List) _liveScopes = granted.cast<String>();
          unawaited(refresh());
        }
      },
      onError: (Object _) => _events = null,
      onDone: () => _events = null,
    );
  }

  Future<void> _forget() async {
    await _events?.cancel();
    _events = null;
    _liveScopes = null;
    await client.store.clear();
    await client.restore();
    models = integrations = const [];
    _notify();
  }

  /// Models this device may use for [capability] (`chat`, `image.edit`…).
  List<Map<String, Object?>> modelsFor(String capability) => [
    for (final model in models)
      if ((model['capabilities'] as List?)?.contains(capability) ?? false)
        model,
  ];

  /// A feature shows only with the permission and a model or workflow for it.
  bool can(String capability) =>
      scopes.contains(capability) && modelsFor(capability).isNotEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    client.close();
    super.dispose();
  }
}
