import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';

/// Typed calls onto §Phase 8a's billing endpoints — the same endpoints the
/// admin panel and, if §Phase 23's contingency is ever needed, a web billing
/// page would drive. Nothing here decides anything.
///
/// **Nothing here is queued.** §0.0 item 14 bounds the offline queue to three
/// surfaces — the wizard's autosave, the slot/request accept prompt and chat
/// sends — and a payment is none of them. A submission that fails offline is
/// reported as failed with the form intact; telling a provider their proof of
/// payment is "saved and will send" when nothing will send it is a false
/// promise about money. The queue is used for exactly one thing: minting
/// idempotency keys, which is where the app's one key generator lives.
class BillingApi {
  const BillingApi(this._api, this._queue, this._uploader);

  final ApiClient _api;
  final OfflineQueue _queue;
  final MediaUploader _uploader;

  static const _subscription = '/v1/providers/me/subscription';
  static const _submissions = '/v1/providers/me/payment-submissions';

  /// Page bound for [invoices], the same as `ListingApi.listOwn`'s.
  static const int _maxPages = 20;

  /// A 404 is an answer: the read never creates a provider profile, so a user
  /// without one reads as §1b's free tier (§Phase 8a: "the absence *is* the
  /// answer").
  Future<SubscriptionStatusView> status() async {
    try {
      return SubscriptionStatusView.fromJson(await _api.get(_subscription));
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') {
        return const SubscriptionStatusView.free();
      }
      rethrow;
    }
  }

  Future<BillingProviderFacts> providerFacts() async {
    try {
      return BillingProviderFacts.fromJson(await _api.get('/v1/providers/me'));
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') {
        return const BillingProviderFacts.none();
      }
      rethrow;
    }
  }

  /// §0.4's explicit "Try Premium". Idempotent on the server — one trial per
  /// account, and a double tap must not turn "started" into an error.
  Future<SubscriptionStatusView> startTrial() async =>
      SubscriptionStatusView.fromJson(
        await _api.post(
          '$_subscription/start-trial',
          headers: {
            'idempotency-key': _queue.newIdempotencyKey(
              'subscription.start-trial',
            ),
          },
        ),
      );

  Future<SubscriptionStatusView> pause() async =>
      SubscriptionStatusView.fromJson(await _api.post('$_subscription/pause'));

  Future<SubscriptionStatusView> resume() async =>
      SubscriptionStatusView.fromJson(await _api.post('$_subscription/resume'));

  /// §1b step 1: the intent. Generates the reference code; grants nothing and
  /// reaches no admin until [submit].
  Future<UpgradeRequest> requestUpgrade() async => UpgradeRequest.fromJson(
    await _api.post(
      '$_subscription/upgrade-request',
      headers: {
        'idempotency-key': _queue.newIdempotencyKey(
          'subscription.upgrade-request',
        ),
      },
    ),
  );

  /// §1b step 3 as the client performs it: ask for a target, PUT the bytes
  /// straight to the store, then submit — where the server sniffs the real
  /// type, checks the real size and strips the EXIF (a receipt is a phone
  /// photo of a bank-app screen and carries a location like any other).
  Future<PaymentSubmission> uploadProofAndSubmit(
    String submissionId,
    PickedImage proof,
  ) async {
    final created = await _api.post(
      '$_submissions/$submissionId/proof',
      body: {'contentType': proof.contentType},
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('payment-submission.proof'),
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
    return PaymentSubmission.fromJson(
      await _api.post(
        '$_submissions/$submissionId/submit',
        headers: {
          'idempotency-key': _queue.newIdempotencyKey(
            'payment-submission.submit',
          ),
        },
      ),
    );
  }

  /// §1b step 5's appeal for re-review. Stamps the rejected row; changes no
  /// status and grants nothing.
  Future<PaymentSubmission> appeal(String submissionId, {String? note}) async =>
      PaymentSubmission.fromJson(
        await _api.post(
          '$_submissions/$submissionId/appeal',
          body: note == null || note.trim().isEmpty ? null : {'note': note},
          headers: {
            'idempotency-key': _queue.newIdempotencyKey(
              'payment-submission.appeal',
            ),
          },
        ),
      );

  /// Every invoice, paged to the end. A provider renewing monthly accumulates
  /// them without limit, and the summary card is a total.
  Future<List<Invoice>> invoices() async {
    final all = <Invoice>[];
    String? cursor;
    for (var page = 0; page < _maxPages; page++) {
      final query = cursor == null
          ? ''
          : '&cursor=${Uri.encodeQueryComponent(cursor)}';
      final response = await _api.get(
        '/v1/providers/me/invoices?limit=50$query',
      );
      final data = response['_list'];
      if (data is List) {
        all.addAll(
          data.whereType<Map<String, dynamic>>().map(Invoice.fromJson),
        );
      }
      final meta = response['_meta'];
      cursor = meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null;
      if (cursor == null) break;
    }
    return List.unmodifiable(all);
  }
}

final billingApiProvider = Provider<BillingApi>(
  (ref) => BillingApi(
    ref.watch(apiClientProvider),
    ref.watch(offlineQueueProvider.notifier),
    ref.watch(mediaUploaderProvider),
  ),
);
