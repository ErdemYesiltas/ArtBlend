import 'dart:async';
import 'dart:typed_data';

import 'package:atelier_studio/data/hub_service.dart';
import 'package:localhub_client/localhub_client.dart';

HubSession fakeHubSession({
  List<String> scopes = const ['chat', 'image.create', 'image.edit'],
}) => HubSession(
  address: Uri.parse('https://127.0.0.1:8790'),
  fingerprint: List.filled(32, 'AB').join(':'),
  token: 'unit-token',
  deviceID: 'device-unit',
  scopes: scopes,
  hubName: 'Unit Mac',
);

/// Holds the session synchronously, so the fake starts paired.
class _Store implements SessionStore {
  _Store(this.session);
  HubSession? session;
  @override
  Future<HubSession?> load() async => session;
  @override
  Future<void> save(HubSession session) async => this.session = session;
  @override
  Future<void> clear() async => session = null;
}

/// A hub that answers from memory: no sockets, every call recorded.
class FakeHubClient extends HubClient {
  FakeHubClient({HubSession? session, this.modelList = const []})
    : super(_Store(session));

  List<Map<String, Object?>> modelList;
  final calls = <String>[];
  final stored = <Map<String, Object?>>[];
  final contents = <String, Uint8List>{};
  final jobs = StreamController<Map<String, Object?>>.broadcast();
  List<Map<String, Object?>> servers = const [];
  Map<String, Object?>? lastEdit;
  HubInput? lastImage, lastMask;
  List<Map<String, Object?>>? lastChat;
  String? chatError;
  bool rejectImages = false;
  Map<String, Object?>? lastChatBody;

  @override
  HubSession? get session => (store as _Store).session;

  @override
  Future<HubSession?> restore() async => session;

  @override
  Future<HubSession> pair(
    HubInvite invite, {
    required String deviceName,
    required String app,
    List<String>? scopes,
  }) async {
    calls.add('pair');
    return (store as _Store).session = fakeHubSession();
  }

  @override
  Future<void> unpair() async {
    calls.add('unpair');
    await store.clear();
  }

  @override
  Future<List<Map<String, Object?>>> models() async {
    calls.add('models');
    return modelList;
  }

  @override
  Future<List<Map<String, Object?>>> integrations() async => [
    {'id': 'comfyui', 'name': 'ComfyUI', 'state': 'running'},
  ];

  @override
  Stream<DeviceEvent> deviceEvents() => const Stream.empty();

  @override
  Future<Map<String, Object?>> editImage(
    Map<String, Object?> fields, {
    required HubInput image,
    HubInput? mask,
    bool async = false,
  }) async {
    calls.add('edit');
    lastEdit = fields;
    lastImage = image;
    lastMask = mask;
    return {'id': 'job-1', 'status': 'queued', 'progress': 0};
  }

  @override
  Future<Map<String, Object?>> generateImage(
    Map<String, Object?> body, {
    bool async = false,
  }) async {
    calls.add('create');
    lastEdit = body;
    return {'id': 'job-1', 'status': 'queued', 'progress': 0};
  }

  @override
  Stream<Map<String, Object?>> jobEvents(String id) => jobs.stream;

  /// Jobs the hub knows by id, for resuming after a restart.
  final known = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> job(String id) async =>
      known[id] ?? (throw const HubException(404, 'not_found', 'No such job'));

  @override
  Future<Map<String, Object?>> cancelJob(String id) async {
    calls.add('cancel');
    return {'id': id, 'status': 'cancelled'};
  }

  @override
  Future<Uint8List> fileContent(String id) async {
    calls.add('content $id');
    return contents[id] ?? (throw const HubException(404, 'not_found', 'gone'));
  }

  @override
  Future<List<Map<String, Object?>>> files() async {
    calls.add('files');
    return [...stored];
  }

  @override
  Future<Map<String, Object?>> uploadFile(
    Uint8List bytes,
    String filename, {
    String contentType = 'application/octet-stream',
    String? purpose,
  }) async {
    final file = {
      'id': 'file-${stored.length + 1}',
      'filename': filename,
      'bytes': bytes.length,
      'mime_type': contentType,
      'source': 'upload',
      'created_at': stored.length,
    };
    stored.add(file);
    contents[file['id'] as String] = bytes;
    return file;
  }

  @override
  Future<void> deleteFile(String id) async {
    calls.add('delete $id');
    stored.removeWhere((f) => f['id'] == id);
  }

  @override
  Stream<Map<String, Object?>> chatStream(Map<String, Object?> body) async* {
    // As LocalHub: chat needs a model.
    if (body['model'] is! String) {
      throw const HubException(
        400,
        'bad_request',
        'Expect a chat completion body with a model',
      );
    }
    final messages = (body['messages'] as List).cast<Map<String, Object?>>();
    if (rejectImages && messages.last['content'] is List) {
      throw const HubException(
        400,
        'bad_request',
        'Model does not support images',
      );
    }
    lastChat = messages;
    lastChatBody = body;
    // A reasoning model thinks first, in a field the reply skips.
    yield {
      'choices': [
        {
          'delta': {'reasoning_content': 'Keywords: …'},
        },
      ],
    };
    if (chatError case final message?) {
      yield {
        'error': {'message': message},
      };
      return;
    }
    for (final part in ['Try ', 'hatching.']) {
      yield {
        'choices': [
          {
            'delta': {'content': part},
          },
        ],
      };
    }
  }

  @override
  Future<List<Map<String, Object?>>> mcpServers() async => servers;

  @override
  void close() {}
}

HubService fakeHub({
  HubSession? session,
  List<Map<String, Object?>> models = const [],
}) => HubService(
  client: FakeHubClient(session: session, modelList: models),
);
