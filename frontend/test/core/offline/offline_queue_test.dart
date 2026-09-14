import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/offline/offline_queue_store.dart';
import 'package:raajjepro/core/offline/pending_request.dart';

import '../../helpers/fake_api.dart';

/// The store, without a platform channel. The real one is a JSON file in the
/// app documents directory; what matters to these tests is that something
/// outlives the notifier.
class FakeQueueStore implements OfflineQueueStore {
  List<PendingRequest> saved = const [];
  int writes = 0;

  @override
  Future<List<PendingRequest>> read() async => saved;

  @override
  Future<void> write(List<PendingRequest> queue) async {
    writes++;
    saved = queue;
  }
}

/// §Phase 9's offline resilience, and the one queue §0.0 item 14 allows —
/// the wizard's autosave now, the slot/request accept prompt at §Phase 17.1,
/// chat sends at §Phase 18, and the emergency accept never.
void main() {
  late FakeApiClient api;
  late FakeQueueStore store;

  ProviderContainer boot() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        offlineQueueStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 14)),
        // Long enough never to fire inside a test: a live timer outliving the
        // container is a failure, not a flake.
        offlineRetryDelayProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    api = FakeApiClient();
    store = FakeQueueStore();
  });

  PendingRequest patch(OfflineQueue queue, Map<String, dynamic> body) =>
      queue.request(
        method: 'PATCH',
        path: '/v1/providers/me/listings/l1',
        label: 'Saving a step of the service wizard',
        mergeKey: 'listing:l1:patch',
        body: body,
      );

  group('a write the network carried', () {
    test('goes straight out and nothing is queued', () async {
      api.on('PATCH', '/v1/providers/me/listings/l1', (_) => {'id': 'l1'});
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);

      final response = await queue.submit(patch(queue, {'name': 'Wiring'}));

      expect(response, isNotNull);
      expect(container.read(offlineQueueProvider).pending, isEmpty);
      expect(container.read(offlineQueueProvider).online, isTrue);
    });
  });

  group('a write the network refused', () {
    test(
      'is recorded before the caller hears about it, and persisted',
      () async {
        api.offline('PATCH', '/v1/providers/me/listings/l1');
        final container = boot();
        final queue = container.read(offlineQueueProvider.notifier);

        final response = await queue.submit(patch(queue, {'name': 'Wiring'}));

        // Null is "it is queued", never "it is gone".
        expect(response, isNull);
        final state = container.read(offlineQueueProvider);
        expect(state.online, isFalse);
        expect(state.pending.single.body, {'name': 'Wiring'});
        expect(store.saved.single.body, {'name': 'Wiring'});
      },
    );

    test('merges with a later write of the same intention', () async {
      api.offline('PATCH', '/v1/providers/me/listings/l1');
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);

      await queue.submit(patch(queue, {'name': 'W'}));
      await queue.submit(patch(queue, {'name': 'Wi'}));
      await queue.submit(patch(queue, {'shortDescription': 'Fast'}));

      // Three keystrokes on one step are one PATCH, and the newer value wins
      // key by key — which is exactly what the server would have ended up
      // with had every one of them arrived.
      final pending = container.read(offlineQueueProvider).pending;
      expect(pending, hasLength(1));
      expect(pending.single.body, {'name': 'Wi', 'shortDescription': 'Fast'});
    });

    test('never overtakes something already waiting', () async {
      api.offline('PATCH', '/v1/providers/me/listings/l1');
      api.offline('POST', '/v1/providers/me/listings/l1/note');
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);
      await queue.submit(patch(queue, {'name': 'Wiring'}));

      final second = await queue.submit(
        queue.request(
          method: 'POST',
          path: '/v1/providers/me/listings/l1/note',
          label: 'A later write',
          mergeKey: 'listing:l1:note',
        ),
      );

      // Queued behind it rather than sent first — a reconnect must not apply
      // an old autosave over a newer one.
      expect(second, isNull);
      expect(container.read(offlineQueueProvider).pending.map((r) => r.path), [
        '/v1/providers/me/listings/l1',
        '/v1/providers/me/listings/l1/note',
      ]);

      api.on('PATCH', '/v1/providers/me/listings/l1', (_) => {'id': 'l1'});
      api.on('POST', '/v1/providers/me/listings/l1/note', (_) => {'id': 'l1'});
      await queue.retryNow();

      expect(
        api.calls
            .where((c) => c.method != 'GET')
            .map((c) => c.path)
            .toList()
            .sublist(2),
        ['/v1/providers/me/listings/l1', '/v1/providers/me/listings/l1/note'],
      );
    });
  });

  group('replay', () {
    test(
      'sends everything waiting, oldest first, and clears the queue',
      () async {
        api.offline('PATCH', '/v1/providers/me/listings/l1');
        final container = boot();
        final queue = container.read(offlineQueueProvider.notifier);
        await queue.submit(patch(queue, {'name': 'Wiring'}));

        api.on('PATCH', '/v1/providers/me/listings/l1', (_) => {'id': 'l1'});
        await queue.replay();

        final state = container.read(offlineQueueProvider);
        expect(state.pending, isEmpty);
        expect(state.online, isTrue);
        expect(store.saved, isEmpty);
      },
    );

    test('keeps the queue when the connection is still gone', () async {
      api.offline('PATCH', '/v1/providers/me/listings/l1');
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);
      await queue.submit(patch(queue, {'name': 'Wiring'}));

      await queue.retryNow();

      expect(container.read(offlineQueueProvider).pending, hasLength(1));
      expect(container.read(offlineQueueProvider).online, isFalse);
    });

    test('surfaces a server refusal instead of retrying it forever', () async {
      api.offline('PATCH', '/v1/providers/me/listings/l1');
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);
      await queue.submit(patch(queue, {'name': 'Wiring'}));

      api.fail(
        'PATCH',
        '/v1/providers/me/listings/l1',
        status: 422,
        code: 'VALIDATION_FAILED',
        message: 'Service name is too long',
      );
      await queue.replay();

      final state = container.read(offlineQueueProvider);
      // Out of the queue — a refusal will never succeed on a retry — but
      // never silently: the user is told what the server said.
      expect(state.pending, isEmpty);
      expect(state.rejection!.message, 'Service name is too long');
      expect(state.rejection!.request.body, {'name': 'Wiring'});
    });
  });

  group('what an earlier run left behind', () {
    test('is picked up and sent on the next launch', () async {
      store.saved = const [
        PendingRequest(
          id: 'q0',
          method: 'PATCH',
          path: '/v1/providers/me/listings/l1',
          label: 'Saving a step of the service wizard',
          mergeKey: 'listing:l1:patch',
          body: {'name': 'Wiring'},
        ),
      ];
      api.on('PATCH', '/v1/providers/me/listings/l1', (_) => {'id': 'l1'});
      final container = boot();

      await container.read(offlineQueueProvider.notifier).replay();

      expect(api.calls.single.body, {'name': 'Wiring'});
      expect(container.read(offlineQueueProvider).pending, isEmpty);
    });

    test('survives a round trip through the file format', () {
      const queue = [
        PendingRequest(
          id: 'q0',
          method: 'POST',
          path: '/v1/providers/me/listings',
          label: 'Saving a step of the service wizard',
          mergeKey: 'listing:create',
          body: {'categoryId': 'c1'},
          idempotencyKey: 'listing.create-1',
        ),
      ];

      final decoded = PendingRequest.decode(PendingRequest.encode(queue));

      expect(decoded.single.idempotencyKey, 'listing.create-1');
      expect(decoded.single.body, {'categoryId': 'c1'});
    });

    test('a half-written file is an empty queue, never a crash', () {
      expect(PendingRequest.decode('{"not":'), isEmpty);
      expect(PendingRequest.decode('null'), isEmpty);
    });
  });

  test(
    'an idempotency key travels with the request through a replay',
    () async {
      api.offline('POST', '/v1/providers/me/listings');
      final container = boot();
      final queue = container.read(offlineQueueProvider.notifier);
      final key = queue.newIdempotencyKey('listing.create');
      await queue.submit(
        queue.request(
          method: 'POST',
          path: '/v1/providers/me/listings',
          label: 'Saving a step of the service wizard',
          mergeKey: 'listing:create',
          idempotencyKey: key,
        ),
      );

      api.on('POST', '/v1/providers/me/listings', (_) => {'id': 'l1'});
      await queue.replay();

      // Built once and carried, which is what makes a retry return the original
      // answer rather than create a second row (§1a).
      expect(store.saved, isEmpty);
      expect(container.read(offlineQueueProvider).pending, isEmpty);
    },
  );
}
