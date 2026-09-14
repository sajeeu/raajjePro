import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/offline/offline_queue_store.dart';
import 'package:raajjepro/core/offline/pending_request.dart';

/// What the app knows about the connection, and what is waiting on it.
class OfflineState {
  const OfflineState({
    this.online = true,
    this.pending = const [],
    this.retrying = false,
    this.rejection,
  });

  /// **Starts true and only ever flips on evidence.** Nothing here probes the
  /// network on launch: a request that failed is what proves there is no
  /// connection, and a request that succeeded is what proves there is one.
  /// Guessing from a radio state would be the same mistake `AuthController`
  /// declined at launch — offline is not signed out, and unknown is not
  /// offline.
  final bool online;

  /// Oldest first. Replay preserves this order.
  final List<PendingRequest> pending;

  /// A replay is in flight.
  final bool retrying;

  /// The last write the **server** refused, still unseen by the user.
  final RejectedRequest? rejection;

  bool get hasPending => pending.isNotEmpty;

  OfflineState copyWith({
    bool? online,
    List<PendingRequest>? pending,
    bool? retrying,
    Object? rejection = _keep,
  }) => OfflineState(
    online: online ?? this.online,
    pending: pending ?? this.pending,
    retrying: retrying ?? this.retrying,
    rejection: rejection == _keep
        ? this.rejection
        : rejection as RejectedRequest?,
  );

  static const _keep = Object();
}

/// How long to wait before trying the queue again after a failed attempt.
/// Injected so a test can make it long enough never to fire — a live timer
/// outliving a widget test is a test failure, not a flake.
final offlineRetryDelayProvider = Provider<Duration>(
  (_) => const Duration(seconds: 8),
);

final offlineQueueProvider = NotifierProvider<OfflineQueue, OfflineState>(
  OfflineQueue.new,
);

/// Queue-and-replay, built once (`offline-queue-and-replay` skill).
///
/// Three surfaces reach it and no others (§0.0 item 14):
///
///  1. §Phase 9's wizard autosave — built here, and the reason this exists.
///  2. §Phase 17.1's slot and request accept prompt.
///  3. §Phase 18's chat sends.
///
/// **§Phase 17.3's emergency accept is deliberately excluded.** It carries the
/// provider's callout fee and their own `etaMinutes` in one call, on-time rate
/// is scored against that `etaMinutes`, and offers are collected for 90
/// seconds — so a replayed offer would commit a provider to a price and an
/// arrival promise made from somewhere else at some other time, and then
/// measure them against it. Offline, that control is an offline notice with a
/// live retry, never a pending state. If a later phase finds itself adding
/// `emergency-accept` to this queue, that is the bug.
///
/// ## The three rules
///
/// **Record before sending.** A request the network refused is written to the
/// queue and to disk before anything is reported to the caller, so the answer
/// "it did not send" is never also "it is gone".
///
/// **Order is kept.** Once anything is queued, later writes queue behind it
/// rather than overtaking it — otherwise a reconnect could apply an old
/// autosave on top of a newer one.
///
/// **A server refusal is not a connection problem.** It leaves the queue and
/// surfaces as a [RejectedRequest]; retrying it forever would never succeed
/// and would hide it.
class OfflineQueue extends Notifier<OfflineState> {
  Timer? _retryTimer;
  Future<void>? _restoring;
  int _seq = 0;

  /// Set the moment the provider starts being torn down.
  ///
  /// `ref.mounted` alone is not enough: an in-flight replay can land while the
  /// container is disposing, and Riverpod refuses a `state` write from there
  /// with "you tried to use Ref inside onDispose". Every write below goes
  /// through [_alive].
  bool _disposed = false;

  bool get _alive => !_disposed && ref.mounted;

  @override
  OfflineState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _retryTimer?.cancel();
      _retryTimer = null;
    });
    _restoring = _restore();
    return const OfflineState();
  }

  /// Reads what an earlier run left behind. Awaited by [replay], so a caller
  /// never races the restore.
  Future<void> _restore() async {
    final saved = await ref.read(offlineQueueStoreProvider).read();
    if (saved.isEmpty || !_alive) return;
    state = state.copyWith(pending: [...saved, ...state.pending]);
  }

  /// A key a creating call can be retried under safely (§1a). Built once,
  /// when the request is, and carried through every replay — that is what
  /// makes a retry return the original answer instead of a second row.
  String newIdempotencyKey(String operation) {
    final now = ref
        .read<DateTime Function()>(clockProvider)()
        .microsecondsSinceEpoch;
    final noise = Random().nextInt(1 << 32).toRadixString(36);
    return '$operation-$now-$noise';
  }

  String _newId() =>
      'q${_seq++}-${ref.read<DateTime Function()>(clockProvider)().microsecondsSinceEpoch}';

  PendingRequest request({
    required String method,
    required String path,
    required String label,
    required String mergeKey,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) => PendingRequest(
    id: _newId(),
    method: method,
    path: path,
    label: label,
    mergeKey: mergeKey,
    body: body,
    idempotencyKey: idempotencyKey,
  );

  /// Sends [request] now, or queues it if the network refuses.
  ///
  /// Returns the decoded response, or **null when it was queued** — which is
  /// the caller's signal to show a pending state rather than a result. An
  /// [ApiException] is rethrown: the server answered, and what it said is the
  /// caller's to render.
  Future<Map<String, dynamic>?> submit(PendingRequest request) async {
    // Anything already waiting goes first, so a reconnect cannot apply an old
    // autosave over a newer one.
    if (state.hasPending) {
      await _enqueue(request);
      // Awaited, not fired and forgotten: the caller has just been told its
      // write is queued, and draining now is the honest next thing to try.
      await replay();
      return null;
    }
    try {
      final response = await _send(request);
      if (!state.online && _alive) state = state.copyWith(online: true);
      return response;
    } on ApiNetworkException {
      await _enqueue(request);
      return null;
    }
  }

  /// Sends everything waiting, oldest first, and stops at the first request
  /// the network refuses. Safe to call at any time.
  Future<void> replay() async {
    await _restoring;
    if (!_alive || state.retrying) return;
    if (!state.hasPending) {
      if (!state.online) state = state.copyWith(online: true);
      return;
    }
    _retryTimer?.cancel();
    state = state.copyWith(retrying: true);

    while (_alive && state.hasPending) {
      final head = state.pending.first;
      try {
        await _send(head);
        await _drop(head);
      } on ApiNetworkException {
        if (!_alive) return;
        state = state.copyWith(online: false, retrying: false);
        _scheduleRetry();
        return;
      } on ApiException catch (e) {
        // The server answered and said no. Keep it out of the queue and put it
        // where the user can see it.
        await _drop(head);
        if (!_alive) return;
        state = state.copyWith(
          rejection: RejectedRequest(request: head, message: e.message),
        );
      }
    }
    if (!_alive) return;
    state = state.copyWith(online: true, retrying: false);
  }

  /// The no-connection screen's "Try Again", and the app coming back to the
  /// foreground.
  Future<void> retryNow() {
    _retryTimer?.cancel();
    return replay();
  }

  void clearRejection() {
    if (state.rejection == null) return;
    state = state.copyWith(rejection: null);
  }

  Future<Map<String, dynamic>> _send(PendingRequest request) {
    final api = ref.read(apiClientProvider);
    final headers = request.idempotencyKey == null
        ? null
        : {'idempotency-key': request.idempotencyKey!};
    return switch (request.method) {
      'POST' => api.post(request.path, body: request.body, headers: headers),
      'PATCH' => api.patch(request.path, body: request.body),
      'DELETE' => api.delete(request.path),
      _ => throw ArgumentError('unqueueable method ${request.method}'),
    };
  }

  Future<void> _enqueue(PendingRequest request) async {
    if (!_alive) return;
    final next = [...state.pending];
    final existing = next.indexWhere((r) => r.mergeKey == request.mergeKey);
    if (existing >= 0) {
      next[existing] = next[existing].mergedWith(request);
    } else {
      next.add(request);
    }
    state = state.copyWith(online: false, pending: next);
    await _persist(next);
    _scheduleRetry();
  }

  Future<void> _drop(PendingRequest request) async {
    final next = [...state.pending]..removeWhere((r) => r.id == request.id);
    if (_alive) state = state.copyWith(pending: next);
    await _persist(next);
  }

  Future<void> _persist(List<PendingRequest> queue) =>
      ref.read(offlineQueueStoreProvider).write(queue);

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!state.hasPending) return;
    _retryTimer = Timer(ref.read(offlineRetryDelayProvider), () {
      _retryTimer = null;
      unawaited(replay());
    });
  }
}
