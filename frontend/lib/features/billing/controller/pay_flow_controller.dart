import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/features/billing/controller/billing_controller.dart';
import 'package:raajjepro/features/billing/data/billing_api.dart';

/// The pay screen's own, local state: which intent it is showing, the receipt
/// the provider attached, and whether a submit is in flight. Everything about
/// the *payment* — amount, code, bank details, period, status — is the
/// server's and lives in [BillingController]; this holds only what has not
/// left the device yet.
class PayFlow {
  const PayFlow({
    this.intentId,
    this.proof,
    this.opening = false,
    this.submitting = false,
    this.error,
    this.offline = false,
  });

  /// The submission the form is for. Null while it is being opened.
  final String? intentId;

  /// Attached on this device, not yet sent. Cleared by a successful submit.
  final PickedImage? proof;
  final bool opening;
  final bool submitting;

  /// What to say inline, under the submit button. Null when nothing is wrong.
  final String? error;

  /// The request never got an answer. Rendered as the no-connection state
  /// with the form intact — **not** queued (§0.0 item 14).
  final bool offline;

  bool get canSubmit =>
      intentId != null && proof != null && !submitting && !opening;

  PayFlow copyWith({
    String? intentId,
    Object? proof = _keep,
    bool? opening,
    bool? submitting,
    Object? error = _keep,
    bool? offline,
  }) => PayFlow(
    intentId: intentId ?? this.intentId,
    proof: proof == _keep ? this.proof : proof as PickedImage?,
    opening: opening ?? this.opening,
    submitting: submitting ?? this.submitting,
    error: error == _keep ? this.error : error as String?,
    offline: offline ?? this.offline,
  );
}

const _keep = Object();

final payFlowProvider = NotifierProvider<PayFlowController, PayFlow>(
  PayFlowController.new,
);

class PayFlowController extends Notifier<PayFlow> {
  @override
  PayFlow build() => const PayFlow();

  /// Opens (or resumes) the intent the form renders. Called once when the
  /// form phase is entered and again from "Resubmit now".
  Future<void> open() async {
    if (state.opening) return;
    state = state.copyWith(opening: true, error: null, offline: false);
    try {
      final intent = await ref
          .read(billingControllerProvider.notifier)
          .ensureOpenIntent();
      state = state.copyWith(intentId: intent.id, opening: false);
    } on ApiNetworkException {
      state = state.copyWith(opening: false, offline: true);
    } on ApiException catch (e) {
      state = state.copyWith(opening: false, error: e.message);
    }
  }

  /// A fresh intent after a rejection — §1b step 5's immediate resubmit. The
  /// rejected row is left exactly as it is; the server creates a new one.
  Future<void> resubmit() async {
    state = const PayFlow(opening: true);
    try {
      final created = await ref.read(billingApiProvider).requestUpgrade();
      await ref.read(billingControllerProvider.notifier).refreshQuietly();
      state = state.copyWith(intentId: created.submission.id, opening: false);
    } on ApiNetworkException {
      state = state.copyWith(opening: false, offline: true);
    } on ApiException catch (e) {
      state = state.copyWith(opening: false, error: e.message);
    }
  }

  /// The picker's answer, or why there is none. A cancel says nothing.
  Future<String?> attach() async {
    final result = await ref.read(mediaPickerProvider).pickImage();
    final image = result.image;
    if (image != null) {
      state = state.copyWith(proof: image, error: null, offline: false);
      return null;
    }
    return switch (result.failure) {
      PickFailure.cancelled || null => null,
      PickFailure.unsupportedType =>
        'That file type isn’t supported — use a JPEG, PNG or WebP.',
      PickFailure.tooLarge => 'That image is over 10 MB — try a smaller one.',
    };
  }

  void removeProof() => state = state.copyWith(proof: null, error: null);

  /// §1b step 3. Nothing is granted by this — the status that comes back
  /// still says free or trial or whatever it said before, and the screen
  /// shows "pending confirmation" from the submission alone.
  Future<bool> submit() async {
    final id = state.intentId;
    final proof = state.proof;
    if (id == null || proof == null || state.submitting) return false;
    state = state.copyWith(submitting: true, error: null, offline: false);
    try {
      await ref.read(billingApiProvider).uploadProofAndSubmit(id, proof);
      await ref.read(billingControllerProvider.notifier).refreshQuietly();
      state = const PayFlow();
      return true;
    } on ApiNetworkException {
      // The receipt stays attached and the form stays as it was. It is not
      // queued: §0.0 item 14, and a promise that money proof "will send" when
      // nothing will send it is the one claim this screen may never make.
      state = state.copyWith(submitting: false, offline: true);
      return false;
    } on MediaUploadException {
      state = state.copyWith(
        submitting: false,
        error: 'The receipt couldn’t be uploaded. Try attaching it again.',
      );
      return false;
    } on ApiException catch (e) {
      state = state.copyWith(submitting: false, error: e.message);
      return false;
    }
  }

  /// Leaving the screen: the local state should not follow the provider to
  /// their next visit, where the server's status decides what shows.
  void reset() => state = const PayFlow();
}
