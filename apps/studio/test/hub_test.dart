import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:atelier_studio/data/hub_service.dart';
import 'package:atelier_studio/editor/hub_jobs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localhub_client/localhub_client.dart';

import 'support/hub_fixture.dart';

class _RevokedHub extends FakeHubClient {
  _RevokedHub() : super(session: fakeHubSession());

  @override
  Future<List<Map<String, Object?>>> models() async =>
      throw const HubException(401, 'unauthorized', 'Device revoked');
}

void main() {
  test('a retired Companion QR is refused before anything is sent', () async {
    final hub = fakeHub();
    final invite = HubInvite.parse(
      'artblend-companion://pair?v=1&u=https%3A%2F%2F127.0.0.1%3A8765'
      '&fp=${List.filled(32, 'AB').join()}&c=123456',
    );
    await expectLater(
      hub.pair(invite, deviceName: 'Tablet'),
      throwsA(isA<CompanionRetired>()),
    );
    expect((hub.client as FakeHubClient).calls, isEmpty);
    expect(hub.paired, isFalse);
  });

  test('features need both the permission and a model for it', () async {
    final hub = fakeHub(
      session: fakeHubSession(scopes: ['chat', 'image.edit']),
      models: [
        {
          'id': 'comfyui/inpaint',
          'capabilities': ['image.edit', 'image.create'],
        },
      ],
    );
    await hub.refresh();
    expect(hub.can('image.edit'), isTrue);
    expect(hub.can('image.create'), isFalse, reason: 'not granted');
    expect(hub.can('chat'), isFalse, reason: 'no chat model');
  });

  test('a revoked device forgets its session', () async {
    final hub = HubService(client: _RevokedHub());
    await hub.refresh();
    expect(hub.paired, isFalse);
  });

  test(
    'a job follows the hub, reports failures and stops on request',
    () async {
      final hub = fakeHub(session: fakeHubSession());
      final client = hub.client as FakeHubClient;
      final job = HubImageJob(
        hub,
        place: (image, source, replace) async => 'layer',
        remove: (_) {},
      );
      addTearDown(job.dispose);

      await job.create(prompt: 'A lighthouse', width: 1024, height: 640);
      expect(client.lastEdit!['size'], '1024x640');
      expect(job.state, HubJobState.queued);
      client.jobs.add({
        'id': 'job-1',
        'status': 'queued',
        'queue_position': 2,
        'eta_seconds': 90,
      });
      await pumpEventQueue();
      expect((job.queuePosition, job.etaSeconds), (2, 90));
      client.jobs.add({
        'id': 'job-1',
        'status': 'in_progress',
        'progress': .25,
        'current_node': 'KSampler',
      });
      await pumpEventQueue();
      expect(job.state, HubJobState.running);
      expect(job.detail, 'KSampler');
      expect(job.queuePosition, isNull);
      await job.cancel();
      expect(client.calls, contains('cancel'));
      expect(job.state, HubJobState.cancelled);
      expect(job.busy, isFalse);

      await job.create(prompt: 'Again', width: 512, height: 512);
      client.jobs.add({
        'id': 'job-1',
        'status': 'failed',
        'error': 'Out of memory',
      });
      await pumpEventQueue();
      expect(job.state, HubJobState.failed);
      expect(job.error, 'Out of memory');
    },
  );

  test('variations swap one layer; discarding removes it', () async {
    final hub = fakeHub(session: fakeHubSession());
    final client = hub.client as FakeHubClient;
    final placed = <(int, String?)>[];
    final removed = <String>[];
    final job = HubImageJob(
      hub,
      place: (image, source, replace) async {
        placed.add((image.first, replace));
        return 'layer-1';
      },
      remove: removed.add,
    );
    addTearDown(job.dispose);
    client.contents['a'] = Uint8List.fromList([1]);
    client.contents['b'] = Uint8List.fromList([2]);

    Future<void> complete(String file) async {
      client.jobs.add({
        'id': 'job-1',
        'status': 'completed',
        'output_file_ids': [file],
      });
      await pumpEventQueue();
    }

    await job.create(prompt: 'A fox', width: 512, height: 512);
    final firstSeed = client.lastEdit!['seed'];
    await complete('a');
    expect(job.pending, isTrue);
    await job.more();
    expect(client.lastEdit!['seed'], isNot(firstSeed));
    await complete('b');
    expect(placed, [(1, null), (2, 'layer-1')]);
    expect((job.variations.length, job.selected), (2, 1));
    await job.select(0);
    expect(placed.last, (1, 'layer-1'));
    job.discard();
    expect(removed, ['layer-1']);
    expect(job.pending, isFalse);
  });

  test('a written prompt drops thinking, labels and quotes', () {
    expect(
      cleanImagePrompt('<think>keywords…</think>\nPrompt: "A tiger at dusk."'),
      'A tiger at dusk.',
    );
    expect(cleanImagePrompt('<think>still thinking'), '');
    expect(cleanImagePrompt('**Prompt:** A fox'), 'A fox');
  });

  test(
    'a job in flight survives a restart and lands where it was asked',
    () async {
      final hub = fakeHub(session: fakeHubSession());
      final client = hub.client as FakeHubClient;
      Map<String, Object?>? store;
      final placed = <(Rect?, String?)>[];
      HubImageJob job() => HubImageJob(
        hub,
        place: (image, source, replace) async {
          placed.add((source?.area, source?.selection?.id));
          return 'layer-1';
        },
        remove: (_) {},
        save: (value) => store = value,
        saved: () => store,
      );

      final first = job();
      await first.create(prompt: 'A heron', width: 512, height: 512);
      expect(store?['id'], 'job-1');
      expect(store?['prompt'], 'A heron');
      first.dispose();

      // The app reopens; the hub finished meanwhile.
      client.contents['out'] = Uint8List.fromList([7]);
      client.known['job-1'] = {
        'id': 'job-1',
        'status': 'completed',
        'output_file_ids': ['out'],
      };
      final second = job();
      addTearDown(second.dispose);
      await second.resume();
      expect(second.pending, isTrue);
      expect(second.canVary, isFalse, reason: 'the request is gone');
      expect(placed, hasLength(1));
      expect(store, isNull);

      // A job the hub no longer has is forgotten quietly.
      store = {'id': 'job-gone'};
      final third = job();
      addTearDown(third.dispose);
      await third.resume();
      expect((third.busy, third.error, store), (false, null, null));
    },
  );
}
