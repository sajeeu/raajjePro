import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';

/// Typed calls onto §Phase 17.3's endpoints.
///
/// ## Nothing here is queued
///
/// §0.0 item 14 excludes the emergency accept from the offline queue by name:
/// a replayed offer would commit a provider to a callout fee and an arrival
/// promise worked out somewhere else, at some other time, and §1f measures
/// on-time rate against it. Offline, the accept control is replaced by a notice
/// with a live retry. The customer's calls are not queued either — a request
/// that has not reached anyone must not be shown as live. The queue is used
/// only to mint idempotency keys, which is where the app's one generator lives.
///
/// ## One call here returns phone numbers
///
/// [revealContact], and only it — `POST /v1/bookings/:id/reveal-contact`, the
/// single exception in the system (§1c).
class EmergencyApi {
  const EmergencyApi(this._api, this._queue, this._uploader);

  final ApiClient _api;
  final OfflineQueue _queue;
  final MediaUploader _uploader;

  static const _requests = '/v1/emergency-requests';

  /// The ASAP request — by category and island, never against a listing
  /// (owner's decision 2026-09-28; Round 23: "dispatch never targets a
  /// provider").
  Future<EmergencyRequest> create({
    required String categoryId,
    required String islandId,
    required String jobNotes,
    String? addressDetail,
  }) async => EmergencyRequest.fromJson(
    await _api.post(
      _requests,
      body: {
        'categoryId': categoryId,
        'islandId': islandId,
        'jobNotes': jobNotes.trim(),
        'addressDetail': ?_blankToNull(addressDetail),
      },
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('emergency.create'),
      },
    ),
  );

  Future<EmergencyRequest> read(String requestId) async =>
      EmergencyRequest.fromJson(await _api.get('$_requests/$requestId'));

  /// Picks one of the offers the customer was shown. Creates the booking and
  /// incurs the MVR 200 dispatch fee.
  Future<EmergencyRequest> select(String requestId, String offerId) =>
      _respond(requestId, {'offerId': offerId});

  /// Rejects every offer; the request goes out again to everyone else.
  Future<EmergencyRequest> rejectAll(String requestId) =>
      _respond(requestId, {'rejectAll': true});

  Future<EmergencyRequest> cancel(String requestId) async =>
      EmergencyRequest.fromJson(
        await _api.patch('$_requests/$requestId/cancel', body: const {}),
      );

  /// Round 15's "provider has not arrived", on the booking. Answers with the
  /// request, which has gone out again.
  Future<EmergencyRequest> markNotArrived(String bookingId) async =>
      EmergencyRequest.fromJson(
        await _api.patch(
          '/v1/bookings/$bookingId/provider-not-arrived',
          body: const {},
        ),
      );

  // -- The provider's side --------------------------------------------------

  Future<EmergencyBroadcast> readAsProvider(String requestId) async =>
      EmergencyBroadcast.fromJson(
        await _api.get('/v1/providers/me/emergency-requests/$requestId'),
      );

  /// The fee and the arrival estimate, in one call (Round 22). Not queued —
  /// see the class note.
  Future<EmergencyBroadcast> offer(
    String requestId, {
    required int calloutFeeLaari,
    required int etaMinutes,
  }) async => EmergencyBroadcast.fromJson(
    await _api.patch(
      '$_requests/$requestId/emergency-accept',
      body: {'calloutFeeLaari': calloutFeeLaari, 'etaMinutes': etaMinutes},
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('emergency.accept'),
      },
    ),
  );

  /// "Decline this request" — recorded, never counted, and nobody is told.
  Future<EmergencyBroadcast> pass(String requestId) async =>
      EmergencyBroadcast.fromJson(
        await _api.patch('$_requests/$requestId/pass', body: const {}),
      );

  // -- The reveal -----------------------------------------------------------

  /// **The one call in the app that returns phone numbers.**
  Future<ContactReveal> revealContact(String bookingId) async =>
      ContactReveal.fromJson(
        await _api.post('/v1/bookings/$bookingId/reveal-contact'),
      );

  // -- The dispatch fee -----------------------------------------------------

  Future<DispatchFees> dispatchFees() async =>
      DispatchFees.fromJson(await _api.get('/v1/users/me/dispatch-fees'));

  /// §Phase 8a's three steps — target, PUT, submit — against the customer's
  /// fee. Submitting **is** what lifts the new-booking block; no admin needs
  /// to act first (§1c).
  Future<void> uploadFeeProofAndSubmit(String feeId, PickedImage proof) async {
    final created = await _api.post(
      '/v1/users/me/dispatch-fees/$feeId/proof',
      body: {'contentType': proof.contentType},
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('dispatch-fee.proof'),
      },
    );
    final upload = created['upload'] as Map<String, dynamic>? ?? const {};
    await _uploader.put(
      url: upload['url'] as String,
      headers: {
        for (final entry
            in (upload['headers'] as Map<String, dynamic>? ?? const {}).entries)
          entry.key: entry.value as String,
      },
      bytes: proof.bytes,
    );
    await _api.post(
      '/v1/users/me/dispatch-fees/$feeId/submit',
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('dispatch-fee.submit'),
      },
    );
  }

  /// A rejected proof leaves the fee unsettled (§0.0 item 24). This issues a
  /// fresh owed fee with a new reference; the hold stays until its proof is
  /// submitted.
  Future<DispatchFee> retryFee(String feeId) async => DispatchFee.fromJson(
    await _api.post(
      '/v1/users/me/dispatch-fees/$feeId/retry',
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('dispatch-fee.retry'),
      },
    ),
  );

  Future<EmergencyRequest> _respond(
    String requestId,
    Map<String, dynamic> body,
  ) async => EmergencyRequest.fromJson(
    await _api.patch(
      '$_requests/$requestId/emergency-offer-response',
      body: body,
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('emergency.offer-response'),
      },
    ),
  );

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final emergencyApiProvider = Provider<EmergencyApi>(
  (ref) => EmergencyApi(
    ref.watch(apiClientProvider),
    ref.watch(offlineQueueProvider.notifier),
    ref.watch(mediaUploaderProvider),
  ),
);
