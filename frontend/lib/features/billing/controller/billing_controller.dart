import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/listings/listing_api.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/features/billing/data/billing_api.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';

// `retry: null`, for the reason every controller here passes it: Riverpod 3
// retries a failed `build()` with exponential backoff for ~30s before the
// screen's own error branch is reached, which fights the explicit "Try again"
// the error state offers (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Everything the billing screens render, fetched together.
///
/// The listings travel with the status for one card: §1b's "hiding, never
/// deleting" list on a downgraded account, which names the listings that are
/// `hidden_over_cap` and offers "Keep this one instead". Which ones those are
/// is the **server's** answer — it is on each listing's `visibility`, written
/// by the entitlement system alone — so this state carries the listings and
/// computes nothing about them.
class BillingState {
  const BillingState({
    required this.status,
    required this.provider,
    required this.listings,
  });

  final SubscriptionStatusView status;
  final BillingProviderFacts provider;
  final List<ServiceListing> listings;

  /// The listings a downgrade hid. `hidden_over_cap` is set and cleared only
  /// by the entitlement system (§1b, Round 17), so this is a read of the
  /// server's decision, not a rule.
  List<ServiceListing> get hiddenOverCap =>
      listings.where((l) => l.isOverCap).toList(growable: false);

  /// Published listings a customer can find right now.
  List<ServiceListing> get live =>
      listings.where((l) => l.isLive).toList(growable: false);

  BillingState withStatus(SubscriptionStatusView status) =>
      BillingState(status: status, provider: provider, listings: listings);
}

final billingControllerProvider =
    AsyncNotifierProvider<BillingController, BillingState>(
      BillingController.new,
      retry: _noRetry,
    );

/// §Phase 10a part 1's one source of billing truth on the device: the three
/// screens watch this and every mutation adopts what the server hands back.
///
/// **Every mutation writes through the server and renders its answer.** A
/// trial started, a pause, a resume, an intent opened, a proof submitted, an
/// appeal filed — each returns the new status (or is followed by a re-read),
/// and the screen draws that. Nothing here predicts a state the server has
/// not confirmed, because §1b's whole mechanism is that nothing activates
/// until an admin says so.
class BillingController extends AsyncNotifier<BillingState> {
  @override
  Future<BillingState> build() => _load();

  Future<BillingState> _load() async {
    final api = ref.read(billingApiProvider);
    final results = await Future.wait<Object>([
      api.status(),
      api.providerFacts(),
      ref.read(listingApiProvider).listOwn(),
    ]);
    return BillingState(
      status: results[0] as SubscriptionStatusView,
      provider: results[1] as BillingProviderFacts,
      listings: results[2] as List<ServiceListing>,
    );
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// A re-read that keeps the current data on screen while it runs. Used
  /// after a submission or an appeal, where the screen already shows the
  /// last known state and a skeleton would be a flicker.
  Future<void> refreshQuietly() async {
    try {
      state = AsyncData(await _load());
    } on Object {
      // The data on screen is still the last thing the server said. A failed
      // background refresh is not an error state.
    }
  }

  /// §0.4's "Try Premium". Returns the refusal to say out loud, or null.
  Future<String?> startTrial() => _adopt((api) => api.startTrial());

  Future<String?> pause() => _adopt((api) => api.pause());

  Future<String?> resume() => _adopt((api) => api.resume());

  /// §1b step 1. Returns the intent the pay screen renders — the one already
  /// open if there is one, so a reference code a provider may already have
  /// written on a transfer is not replaced under them; otherwise a new one.
  ///
  /// Throws [ApiException] / [ApiNetworkException]: the pay screen renders
  /// the failure inline, because without a reference code there is no form.
  Future<PaymentSubmission> ensureOpenIntent() async {
    final current = state.value;
    final latest = current?.status.latestSubmission;
    if (latest != null && latest.isOpenIntent) return latest;
    final created = await ref.read(billingApiProvider).requestUpgrade();
    // The status read is where the bank details and the period come from, so
    // the fresh intent is read back through it rather than kept beside it —
    // one shape for the screen whether the intent is new or resumed.
    await refreshQuietly();
    return created.submission;
  }

  /// §1b step 5's appeal. Returns the refusal, or null.
  Future<String?> appeal(String submissionId, {String? note}) async {
    try {
      await ref.read(billingApiProvider).appeal(submissionId, note: note);
      await refreshQuietly();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiNetworkException {
      return 'No connection — the appeal was not sent. Try again when you’re '
          'back online.';
    }
  }

  /// §1b's override, the same door §Phase 10's dashboard uses: a pin the
  /// server ranks on. The server re-runs its reconcile, so this re-reads —
  /// which listing came back and which went is §1b's ranking to decide.
  Future<String?> keepVisible(ServiceListing listing) async {
    try {
      await ref.read(listingApiProvider).keepVisible(listing.id);
      state = AsyncData(await _load());
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiNetworkException {
      return 'No connection — nothing was changed.';
    }
  }

  Future<String?> _adopt(
    Future<SubscriptionStatusView> Function(BillingApi api) call,
  ) async {
    final current = state.value;
    if (current == null) return null;
    try {
      final status = await call(ref.read(billingApiProvider));
      state = AsyncData(current.withStatus(status));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiNetworkException {
      return 'No connection — nothing was changed.';
    }
  }
}
