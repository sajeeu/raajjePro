import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/onboarding/controller/provider_onboarding_controller.dart';
import 'package:raajjepro/features/onboarding/presentation/steps/account_details_step.dart';
import 'package:raajjepro/features/onboarding/presentation/steps/intro_step.dart';
import 'package:raajjepro/features/onboarding/presentation/steps/service_areas_step.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/onboarding_done_sheet.dart';
import 'package:raajjepro/features/onboarding/presentation/widgets/onboarding_progress.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Become a Provider** — §Phase 6a's onboarding flow
/// (`mockups/design-composer/Become a Provider.dc.html`).
///
/// Three steps behind one route: the intro, the grouped account details, and
/// the default service areas. §Phase 6's role switcher sends a first switch
/// here rather than to the wizard, which is §Phase 6a's first Done-when line;
/// the last one — "a provider who already completed onboarding never sees it
/// again" — is the switcher's too, and both turn on the same derived flag the
/// server computes (`backend/src/modules/providers/onboarding.ts`).
///
/// **The scaffold is the artboard's:** a progress header that stays, a
/// scrolling step, and a footer holding the CTA. The footer is separate from
/// the step so that Continue does not travel to the bottom of a long form,
/// and so that "Setting up your profile…" renders on the button itself rather
/// than over the screen (frontend/CLAUDE.md: a button that triggers a network
/// call shows its own loading state).
///
/// All four screen states are here: a skeleton while the profile loads, the
/// error state with a retry, and — because there is no such thing as an empty
/// onboarding flow — the populated state for each step. The empty case is the
/// first step itself, which is what a brand-new account gets.
class BecomeProviderScreen extends ConsumerStatefulWidget {
  const BecomeProviderScreen({super.key});

  static const routeName = AppRoutes.becomeProvider;

  @override
  ConsumerState<BecomeProviderScreen> createState() =>
      _BecomeProviderScreenState();
}

class _BecomeProviderScreenState extends ConsumerState<BecomeProviderScreen> {
  /// Reaches into the account-details step for what the provider typed. The
  /// CTA lives in the footer, outside that widget's subtree, because the
  /// artboard pins it to the bottom of the screen.
  final _detailsKey = GlobalKey<AccountDetailsStepState>();

  /// Read once per visit, not per build: `takeDraft` consumes it, so reading
  /// it inside `build` would hand the first frame the values and every frame
  /// after it nothing.
  Map<String, String>? _draft;
  bool _draftRead = false;

  Map<String, String>? _takeDraftOnce() {
    if (!_draftRead) {
      _draftRead = true;
      _draft = ref
          .read(providerOnboardingControllerProvider.notifier)
          .takeDraft();
    }
    return _draft;
  }

  Future<void> _continueFromDetails(UserAccount account) async {
    final step = _detailsKey.currentState;
    if (step == null) return;
    await ref
        .read(providerOnboardingControllerProvider.notifier)
        .submitAccountDetails(
          step.collect(),
          emailVerified: account.emailVerified,
        );
  }

  /// §Phase 6a's "Not right now": *returns the user to customer mode cleanly,
  /// leaving no orphaned draft and no resume prompt nagging them from the
  /// role switcher. Choosing it again later starts the flow fresh.*
  ///
  /// It is clean by construction rather than by cleanup — step 1 writes
  /// nothing at all, so there is nothing to undo. That is the whole reason
  /// step 2 submits on Continue instead of autosaving.
  void _notNow() => Navigator.of(context).maybePop();

  /// Phase 3's Verify Email screen, pushed with the untyped arguments its
  /// `VerifyEmailArgs.fromRouteArguments` already accepts. The typed record
  /// lives in the auth feature's controller and `lib/README.md` says no
  /// feature imports another; the map is the meeting point that already
  /// exists.
  /// **What is typed is saved first.** That screen finishes with
  /// `pushNamedAndRemoveUntil` back to the root, so this flow is gone by the
  /// time the address is confirmed — see
  /// `ProviderOnboardingController.saveDraft`.
  void _verifyEmail(UserAccount account) {
    final step = _detailsKey.currentState;
    if (step != null) {
      ref
          .read(providerOnboardingControllerProvider.notifier)
          .saveDraft(step.collect());
    }
    Navigator.of(context).pushNamed(
      AppRoutes.verifyEmail,
      arguments: <String, dynamic>{
        'email': account.email,
        'purpose': 'verifyEmail',
      },
    );
  }

  /// §Phase 6a step 4: *hand off directly into the Phase 9 wizard's Step 1,
  /// pre-populated with nothing (a fresh draft)*.
  ///
  /// `pushReplacementNamed`, so Back from the wizard does not land on a
  /// finished onboarding flow.
  void _startFirstService() =>
      Navigator.of(context).pushReplacementNamed(AppRoutes.createService);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(providerOnboardingControllerProvider);
    final controller = ref.read(providerOnboardingControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final account = auth is AuthSignedIn ? auth.user : null;

    ref.listen(providerOnboardingControllerProvider, (previous, next) {
      // On the transition into `finished` only. Every `_set` makes a new
      // `AsyncData`, so listening for the flag alone would raise a second
      // sheet on any state change while the first is still up.
      final done = next.value;
      if (done != null && done.finished && previous?.value?.finished != true) {
        _showDone(done, controller);
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: switch (state) {
        AsyncLoading() => const _LoadingState(),
        AsyncError() => _ErrorState(onRetry: controller.reload),
        // Signed out under the flow. The auth state machine moves the root
        // route on its own; this only avoids drawing a form with no account
        // behind it in the frame before that happens.
        AsyncData() when account == null => const _LoadingState(),
        AsyncData(value: final view) => _Flow(
          view: view,
          account: account!,
          detailsKey: _detailsKey,
          draft: _takeDraftOnce(),
          onBack: view.step == OnboardingStep.intro ? _notNow : controller.back,
          onContinueIntro: () => controller.goTo(OnboardingStep.accountDetails),
          onNotNow: _notNow,
          onContinueDetails: () => _continueFromDetails(account),
          onEditPhone: controller.startEditingPhone,
          onClearError: controller.clearError,
          onVerifyEmail: () => _verifyEmail(account),
          onToggleIsland: controller.toggleServiceArea,
          onFinish: controller.finish,
        ),
      },
    );
  }

  void _showDone(OnboardingView view, ProviderOnboardingController controller) {
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => OnboardingDoneSheet(
        firstName: view.profile.businessName ?? '',
        islands: view.profile.serviceAreas,
        onStart: () {
          Navigator.of(sheetContext).pop();
          _startFirstService();
        },
        onBack: () => Navigator.of(sheetContext).pop(),
      ),
    ).whenComplete(controller.dismissFinished);
  }
}

class _Flow extends StatelessWidget {
  const _Flow({
    required this.view,
    required this.account,
    required this.detailsKey,
    required this.draft,
    required this.onBack,
    required this.onContinueIntro,
    required this.onNotNow,
    required this.onContinueDetails,
    required this.onEditPhone,
    required this.onClearError,
    required this.onVerifyEmail,
    required this.onToggleIsland,
    required this.onFinish,
  });

  final OnboardingView view;
  final UserAccount account;
  final GlobalKey<AccountDetailsStepState> detailsKey;

  /// What was typed before leaving to verify an email, if anything.
  final Map<String, String>? draft;
  final VoidCallback onBack;
  final VoidCallback onContinueIntro;
  final VoidCallback onNotNow;
  final VoidCallback onContinueDetails;
  final VoidCallback onEditPhone;
  final ValueChanged<String> onClearError;
  final VoidCallback onVerifyEmail;
  final ValueChanged<Island> onToggleIsland;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;

    return Column(
      children: [
        OnboardingProgress(
          step: view.step,
          onBack: view.submitting ? null : onBack,
        ),
        if (view.offline)
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: NoticeBanner(
              icon: Icons.wifi_off_rounded,
              // 🔧 **It does not say "nothing was saved".** Step 2 makes two
              // writes to two resources, and an offline failure on the second
              // leaves the first — the account phone — already changed. The
              // phone row above shows the number that actually stands, so the
              // screen tells the truth by not claiming.
              message:
                  "You're offline. Try again when you're back on a "
                  'connection — what you typed is still here.',
            ),
          ),
        if (view.formError != null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: NoticeBanner(message: view.formError!),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: motion.page,
            switchInCurve: AppMotion.easeOut,
            child: SingleChildScrollView(
              // Keyed so the switcher animates between steps rather than
              // scrolling one long list, and so a step's scroll offset does
              // not carry into the next.
              key: ValueKey(view.step),
              child: switch (view.step) {
                OnboardingStep.intro => const IntroStep(),
                OnboardingStep.accountDetails => AccountDetailsStep(
                  key: detailsKey,
                  profile: view.profile,
                  account: account,
                  draft: draft,
                  errors: view.fieldErrors,
                  editingPhone: view.editingPhone,
                  onEditPhone: onEditPhone,
                  onClearError: onClearError,
                  onVerifyEmail: onVerifyEmail,
                ),
                OnboardingStep.serviceAreas => ServiceAreasStep(
                  selected: view.profile.serviceAreas,
                  onToggle: onToggleIsland,
                ),
              },
            ),
          ),
        ),
        _Footer(
          view: view,
          onContinueIntro: onContinueIntro,
          onNotNow: onNotNow,
          onContinueDetails: onContinueDetails,
          onFinish: onFinish,
        ),
      ],
    );
  }
}

/// The CTA bar the artboard pins to the bottom, one variant per step.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.view,
    required this.onContinueIntro,
    required this.onNotNow,
    required this.onContinueDetails,
    required this.onFinish,
  });

  final OnboardingView view;
  final VoidCallback onContinueIntro;
  final VoidCallback onNotNow;
  final VoidCallback onContinueDetails;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final chosen = view.profile.serviceAreas.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.lg - 2,
            AppSpacing.xl,
            AppSpacing.xxl - 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (view.step) {
              OnboardingStep.intro => [
                AppButton.primary(
                  label: 'Continue',
                  expand: true,
                  onPressed: onContinueIntro,
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                AppButton.text(
                  label: 'Not right now',
                  expand: true,
                  onPressed: onNotNow,
                ),
              ],
              OnboardingStep.accountDetails => [
                AppButton.primary(
                  key: const Key('onboarding-continue'),
                  label: view.submitting
                      ? 'Setting up your profile…'
                      : 'Continue',
                  expand: true,
                  loading: view.submitting,
                  onPressed: view.submitting ? null : onContinueDetails,
                ),
              ],
              OnboardingStep.serviceAreas => [
                if (chosen > 0) ...[
                  Text(
                    chosen == 1
                        ? '1 island selected'
                        : '$chosen islands selected',
                    textAlign: TextAlign.center,
                    style: type.secondary.copyWith(color: colors.successText),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                ],
                AppButton.primary(
                  key: const Key('onboarding-finish'),
                  label: 'Create Your First Service',
                  expand: true,
                  // §Phase 6a's step 3 has no skip: the default is what
                  // pre-fills every listing, and an empty one pre-fills
                  // nothing. Disabled rather than absent, because the count
                  // above says what to do about it.
                  onPressed: chosen == 0 ? null : onFinish,
                ),
              ],
            },
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(
      padding: AppSpacing.screenInsets,
      child: SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonBox(height: 160, radius: AppRadius.feature),
            SizedBox(height: AppSpacing.xl),
            SkeletonRow(),
            SizedBox(height: AppSpacing.md),
            SkeletonRow(),
            SizedBox(height: AppSpacing.md),
            SkeletonRow(),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: AppSpacing.screenInsets,
      child: Center(
        child: EmptyState.error(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your details",
          body:
              'We could not reach RaajjePro just now. Nothing has been saved.',
          onRetry: onRetry,
        ),
      ),
    ),
  );
}
