import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/onboarding/data/provider_onboarding_api.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a's three steps. Step 1 persists nothing, which is why it is not
/// in the resume calculation below.
enum OnboardingStep {
  intro,
  accountDetails,
  serviceAreas;

  /// 1-based, for "Step 2 of 3".
  int get number => index + 1;
  static int get count => OnboardingStep.values.length;
}

/// What the onboarding screen renders.
class OnboardingView {
  const OnboardingView({
    required this.step,
    required this.profile,
    this.submitting = false,
    this.editingPhone = false,
    this.fieldErrors = const {},
    this.formError,
    this.offline = false,
    this.finished = false,
  });

  final OnboardingStep step;

  /// The server's state, refreshed after every write. The steps read their
  /// pre-fill from here.
  final ProviderOnboardingState profile;

  /// Step 2's Continue is in flight ("Setting up your profile…").
  final bool submitting;

  /// §Phase 6a: the phone is "pre-filled from Phase 3 and confirmed, never
  /// re-typed — an `editingPhone` state reveals the input only on request".
  final bool editingPhone;

  /// Keyed by the artboard's field names: `businessName`, `providerType`,
  /// `phone`, `email`, `bankAccountName`, `bankAccountNumber`, `bankName`.
  /// Rendered under the field, never as a toast (frontend/CLAUDE.md).
  final Map<String, String> fieldErrors;

  /// A failure with no field to hang on.
  final String? formError;

  /// The request never left the device. Distinct from [formError] because the
  /// user can act on it.
  final bool offline;

  /// Step 3's CTA has been taken and the confirmation sheet is up.
  final bool finished;

  OnboardingView copyWith({
    OnboardingStep? step,
    ProviderOnboardingState? profile,
    bool? submitting,
    bool? editingPhone,
    Map<String, String>? fieldErrors,
    Object? formError = _keep,
    bool? offline,
    bool? finished,
  }) => OnboardingView(
    step: step ?? this.step,
    profile: profile ?? this.profile,
    submitting: submitting ?? this.submitting,
    editingPhone: editingPhone ?? this.editingPhone,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    formError: formError == _keep ? this.formError : formError as String?,
    offline: offline ?? this.offline,
    finished: finished ?? this.finished,
  );

  static const _keep = Object();
}

// `retry: null`: this notifier renders its own error state with a Try again,
// and Riverpod 3's default would silently retry a failed `build()` for ~30s
// behind it (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

final providerOnboardingControllerProvider =
    AsyncNotifierProvider<ProviderOnboardingController, OnboardingView>(
      ProviderOnboardingController.new,
      isAutoDispose: true,
      retry: _noRetry,
    );

/// §Phase 6a's flow controller: which step is showing, what the server holds,
/// and the two writes.
///
/// **Resume is derived from the server, not from a local draft.** §Phase 6a:
/// "A provider who abandons onboarding after step 1 or 2 (backs out, closes
/// the app) and returns later resumes from wherever they left off — this
/// reuses Phase 9's existing resume-a-draft logic pattern, applied one level
/// earlier in the funnel." Phase 9's pattern is a draft that lives on the
/// server, and here the provider profile *is* that draft: step 2's Continue
/// creates it (§1a's implicit-creation moment) and step 3's picks write
/// straight through. So [build] reads `GET /v1/providers/me` and the fields
/// that came back say which step to open on. Nothing is cached on the device
/// and nothing has to be reconciled.
///
/// **Step 2 deliberately does not autosave per keystroke**, which is where
/// this departs from `wizard-step-pattern`'s debounced-PATCH rule. That rule
/// exists for §Phase 9's wizard, which patches a draft *listing* that already
/// exists. Here the first write is what creates the provider profile — and
/// `isProvider` is `providerProfile !== null`, nothing is ever hard-deleted
/// (invariant 8), and §Phase 6's role switcher routes on it. Autosaving would
/// turn a customer who typed one character into a provider permanently, which
/// is the exact failure `docs/decisions/17-phase-5-provider-profiles.md`
/// decision 11 was written to close. The artboard agrees: step 2 has one
/// Continue, with a "Setting up your profile…" state on it.
class ProviderOnboardingController extends AsyncNotifier<OnboardingView> {
  @override
  Future<OnboardingView> build() async {
    final profile = await ref.read(providerOnboardingApiProvider).read();
    final auth = ref.read(authControllerProvider);
    return OnboardingView(
      step: _resumeStep(
        profile,
        emailVerified: auth is AuthSignedIn && auth.user.emailVerified,
      ),
      profile: profile ?? const ProviderOnboardingState.blank(),
    );
  }

  /// Where a returning user picks up.
  ///
  /// - No profile at all: they have never sent anything. Step 1.
  /// - A profile whose step-2 fields are incomplete: step 2, pre-filled with
  ///   whatever is there. This covers §1a's implicit path too — a provider who
  ///   registered as one, or who reached §Phase 8's wizard first, has a
  ///   profile with a business name and nothing else.
  /// - Step 2 done but no default service area: step 3, which is the state the
  ///   plan's resume line is really about.
  ///
  /// 🔧 **An unverified email resumes at step 2, however complete the fields
  /// are.** Step 2 is the only screen carrying the block and the Verify
  /// button beside it, and the server will not call this flow complete
  /// without a verified address (`providers/onboarding.ts`) — so resuming
  /// past it would show a provider a "you're all set" sheet and a handoff
  /// into the wizard while the switcher went on routing them back here with
  /// nothing on screen explaining why. Step 2 is also therefore the single
  /// place the email is enforced client-side: step 3 is unreachable except
  /// through a Continue that validates it.
  ///
  /// A finished flow does not reach this through the app at all — §Phase 6's
  /// role switcher sends an onboarded provider to the dashboard, on the same
  /// derived flag. Opened directly it lands on step 3 with every island
  /// already ticked, which is harmless and deliberately not special-cased:
  /// there is no deep link to this route, and a redirect on arrival would be
  /// a second place the completeness rule is acted on.
  static OnboardingStep _resumeStep(
    ProviderOnboardingState? profile, {
    required bool emailVerified,
  }) {
    if (profile == null) return OnboardingStep.intro;
    if (!_accountDetailsDone(profile) || !emailVerified) {
      return OnboardingStep.accountDetails;
    }
    return OnboardingStep.serviceAreas;
  }

  /// Step 2's required fields, as §Phase 6a lists them. Deliberately **not**
  /// the whole completeness rule — that includes the verified email and lives
  /// on the server (`providers/onboarding.ts`). This one only answers "is
  /// there anything left to type on step 2?", which is a navigation question.
  static bool _accountDetailsDone(ProviderOnboardingState p) =>
      (p.businessName?.trim().isNotEmpty ?? false) &&
      p.providerType != null &&
      (p.bankName?.trim().isNotEmpty ?? false) &&
      (p.bankAccountName?.trim().isNotEmpty ?? false) &&
      (p.bankAccountNumber?.trim().isNotEmpty ?? false);

  OnboardingView get _view => state.requireValue;

  /// Guarded on both sides, because the last write of the flow races its own
  /// teardown: the confirmation sheet's CTA pops the sheet and then replaces
  /// this route, and the sheet's completion callback lands after the screen —
  /// and therefore this autoDispose notifier — may already be gone.
  void _set(OnboardingView view) {
    if (!ref.mounted || !state.hasValue) return;
    state = AsyncData(view);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  void goTo(OnboardingStep step) => _set(
    _view.copyWith(
      step: step,
      fieldErrors: const {},
      formError: null,
      offline: false,
    ),
  );

  /// Back from step 2 or 3. Step 1's back is the screen's own — it leaves the
  /// flow.
  void back() {
    final step = _view.step;
    if (step == OnboardingStep.intro) return;
    goTo(OnboardingStep.values[step.index - 1]);
  }

  void startEditingPhone() => _set(_view.copyWith(editingPhone: true));

  /// Saves step 2's typed values before the provider leaves to verify their
  /// email, and hands them back on return.
  ///
  /// Phase 3's Verify Email screen finishes with `pushNamedAndRemoveUntil`
  /// back to the root, so the whole stack — including this flow — is gone by
  /// the time the address is confirmed. Step 2 does not autosave (deliberately;
  /// the first write creates the provider profile), so without this the
  /// provider comes back to an empty form having typed a name, an
  /// introduction and three bank fields. frontend/CLAUDE.md: never silently
  /// discard user input.
  ///
  /// [FormDraftStore] is Phase 3's own mechanism for exactly this — **in
  /// memory, this session only, never written to disk and never logged**,
  /// which is what makes it acceptable for the destination account (§1d keeps
  /// payment details out of logs, and a process restart legitimately loses
  /// this). It is read once, so a provider who abandons instead gets a clean
  /// form next time.
  void saveDraft(AccountDetailsInput input) =>
      ref.read(formDraftStoreProvider).save(_draftKey, {
        'businessName': input.businessName,
        if (input.providerType != null)
          'providerType': input.providerType!.wire,
        'bio': input.bio,
        'bankName': input.bankName,
        'bankAccountName': input.bankAccountName,
        'bankAccountNumber': input.bankAccountNumber,
      });

  /// What was typed before leaving, or null. Consumed on read.
  Map<String, String>? takeDraft() =>
      ref.read(formDraftStoreProvider).take(_draftKey);

  static const _draftKey = AppRoutes.becomeProvider;

  void clearError(String field) => _set(
    _view.copyWith(fieldErrors: Map.of(_view.fieldErrors)..remove(field)),
  );

  /// Step 2's Continue.
  ///
  /// Two requests, in this order, because they are two different resources:
  /// the phone is the **account's** and goes to Phase 3's
  /// `PATCH /v1/users/me/phone`; everything else is the **provider profile's**
  /// and goes to Phase 5's `PATCH /v1/providers/me`. §Phase 6a's Done-when
  /// puts both on the second endpoint, which it cannot do — there is no phone
  /// column on `ProviderProfile` and §Phase 5's single-copy rule keeps it that
  /// way (`docs/decisions/17-phase-5-provider-profiles.md`, disagreement 2).
  ///
  /// The phone goes first. If the number is taken, nothing else should have
  /// been written — and a provider profile created ahead of a failed phone
  /// change would be a permanent flip (invariant 8) for a step that did not
  /// complete.
  ///
  /// Returns true when the step is done and the flow may advance.
  Future<bool> submitAccountDetails(
    AccountDetailsInput input, {
    required bool emailVerified,
  }) async {
    final local = _validateAccountDetails(input, emailVerified: emailVerified);
    if (local.isNotEmpty) {
      _set(_view.copyWith(fieldErrors: local, formError: null, offline: false));
      return false;
    }

    final draft = AccountDetailsDraft(
      businessName: input.businessName,
      // Non-null past the validator: `providerType` is the first thing it
      // checks, so a null here cannot reach this line.
      providerType: input.providerType!,
      bio: input.bio,
      bankName: input.bankName,
      bankAccountName: input.bankAccountName,
      bankAccountNumber: input.bankAccountNumber,
      acceptingNewCustomers: input.acceptingNewCustomers,
    );

    _set(
      _view.copyWith(
        submitting: true,
        fieldErrors: const {},
        formError: null,
        offline: false,
      ),
    );
    try {
      if (input.phoneChanged) {
        final user = await ref
            .read(authApiProvider)
            .changePhone(input.dialCode, input.phoneNumber);
        ref.read(authControllerProvider.notifier).applyUser(user);
      }
      final profile = await ref
          .read(providerOnboardingApiProvider)
          .saveAccountDetails(draft);
      _set(
        _view.copyWith(
          submitting: false,
          editingPhone: false,
          profile: profile,
          step: OnboardingStep.serviceAreas,
        ),
      );
      return true;
    } on ApiException catch (e) {
      _set(
        _view.copyWith(
          submitting: false,
          fieldErrors: _mapError(e),
          formError: _formError(e),
        ),
      );
      return false;
    } on ApiNetworkException {
      _set(_view.copyWith(submitting: false, offline: true));
      return false;
    }
  }

  /// §Phase 6a's phone rules, checked here for the keystroke-level feedback
  /// and again on the server, which is where they actually hold (invariant 4).
  ///
  /// **6 to 15 digits, and no Maldivian pattern.** Round 17 removed the
  /// 7-digit 7-or-9 restriction because expatriate residents hold foreign
  /// numbers, and this is the field they hold them in.
  Map<String, String> _validateAccountDetails(
    AccountDetailsInput input, {
    required bool emailVerified,
  }) {
    final errors = <String, String>{};

    final name = input.businessName.trim();
    if (name.isEmpty) {
      errors['businessName'] = 'Please enter your provider name.';
    } else if (name.length < 3) {
      errors['businessName'] = 'Name must be at least 3 characters.';
    }

    if (input.providerType == null) {
      errors['providerType'] = "Choose how you'll offer services.";
    }

    final digits = input.phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      errors['phone'] = 'Please enter a mobile number we can reach you on.';
    } else if (digits.length < 6 || digits.length > 15) {
      errors['phone'] = 'Enter a valid mobile number, including area code if outside the Maldives.';
    } else if (input.dialCode.replaceAll(RegExp(r'\D'), '').isEmpty) {
      errors['phone'] = 'Add a country code, e.g. +960.';
    }

    // §Phase 6a: "Unverified blocks Continue with its own message, since
    // booking notifications go there." The server holds the same line —
    // onboarding is not complete without it — but the block belongs here,
    // where there is a Verify email button beside the message.
    if (!emailVerified) {
      errors['email'] = 'Verify your email before continuing — booking notifications are sent there.';
    }

    if (input.bankAccountName.trim().isEmpty) {
      errors['bankAccountName'] = "Enter the account holder's name.";
    }
    // The server's floor is 4 (`updateOwnProviderBody`); the artboard's was 7.
    // Taking the server's, because a client that refuses what the server
    // accepts blocks a real account and the message would be wrong about why.
    final account = input.bankAccountNumber.replaceAll(' ', '');
    if (account.isEmpty) {
      errors['bankAccountNumber'] = 'Enter your account number.';
    } else if (account.length < 4) {
      errors['bankAccountNumber'] = 'That account number looks too short.';
    }
    if (input.bankName.trim().isEmpty) {
      errors['bankName'] = 'Select your bank.';
    }
    return errors;
  }

  Map<String, String> _mapError(ApiException e) {
    final fromServer = <String, String>{
      for (final f in e.fieldErrors) _fieldOf(f.path): f.message,
    };
    if (fromServer.isNotEmpty) return fromServer;
    // §Phase 3, Round 15: a number already held at Bronze or above is taken,
    // and the message names the field rather than the account behind it.
    if (e.code == 'PHONE_IN_USE') {
      return {'phone': 'This number belongs to a verified provider account.'};
    }
    return const {};
  }

  String? _formError(ApiException e) =>
      _mapError(e).isEmpty && e.code != 'PHONE_IN_USE'
      ? genericErrorCopy
      : null;

  /// `phone.number` and `phone.dialCode` both land on the one `phone` field
  /// this step renders. Everything else arrives flat and passes through —
  /// `.last` is defensive rather than load-bearing.
  static String _fieldOf(String path) {
    final leaf = path.split('.').last;
    return switch (leaf) {
      'number' || 'dialCode' => 'phone',
      _ => leaf,
    };
  }

  /// Step 3. Each tap is a real write against §Phase 7's endpoints, so the
  /// selection cannot be lost by leaving the screen — which is what makes
  /// resuming at step 3 work without a local draft.
  Future<void> toggleServiceArea(Island island) async {
    final selected = _view.profile.serviceAreas.any((i) => i.id == island.id);
    _set(_view.copyWith(formError: null, offline: false));
    try {
      final api = ref.read(providerOnboardingApiProvider);
      final areas = selected
          ? await api.removeServiceArea(island.id)
          : await api.addServiceArea(island.id);
      _set(_view.copyWith(profile: _withAreas(areas)));
    } on ApiException {
      _set(_view.copyWith(formError: genericErrorCopy));
    } on ApiNetworkException {
      _set(_view.copyWith(offline: true));
    }
  }

  /// Step 3's CTA. Nothing is written here — every island already is — so this
  /// only raises the confirmation the artboard shows before the handoff.
  void finish() => _set(_view.copyWith(finished: true));
  void dismissFinished() => _set(_view.copyWith(finished: false));

  /// The service-area writes return the resulting list, and it is authoritative
  /// — but they do not re-derive `onboardingComplete`, so that one field is
  /// carried forward from the last full read and recomputed on the next one.
  /// The screen never routes on it; §Phase 6's switcher does, from
  /// `profile-summary`.
  ProviderOnboardingState _withAreas(List<Island> areas) =>
      ProviderOnboardingState(
        businessName: _view.profile.businessName,
        providerType: _view.profile.providerType,
        bio: _view.profile.bio,
        bankName: _view.profile.bankName,
        bankAccountName: _view.profile.bankAccountName,
        bankAccountNumber: _view.profile.bankAccountNumber,
        acceptingNewCustomers: _view.profile.acceptingNewCustomers,
        serviceAreas: areas,
        onboardingComplete: _view.profile.onboardingComplete,
      );
}
