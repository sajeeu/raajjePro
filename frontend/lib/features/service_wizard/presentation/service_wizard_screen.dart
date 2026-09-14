import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/data/service_listing.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/availability_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/details_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/extras_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/location_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/media_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/pricing_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/review_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/publish_sheets.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_chrome.dart';
import 'package:raajjepro/shared/shared.dart';

/// The Create/Edit Service Wizard (§Phase 9), seven steps behind one route.
///
/// §Phase 6a hands off here with **nothing in arguments**, and that is what
/// makes step 1 open on a genuinely fresh draft rather than on whatever the
/// provider last touched. An id in the arguments resumes an existing listing;
/// §Phase 10's dashboard is what will pass one.
class ServiceWizardScreen extends ConsumerStatefulWidget {
  const ServiceWizardScreen({this.args = const ServiceWizardArgs(), super.key});

  static const routeName = AppRoutes.createService;

  final ServiceWizardArgs args;

  @override
  ConsumerState<ServiceWizardScreen> createState() =>
      _ServiceWizardScreenState();
}

class _ServiceWizardScreenState extends ConsumerState<ServiceWizardScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // Coming back to the foreground is the most likely moment a provider has
    // regained a signal, and it costs one call to find out.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(offlineQueueProvider.notifier).retryNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  ServiceWizardController get _controller =>
      ref.read(serviceWizardControllerProvider(widget.args.listingId).notifier);

  /// The header's back control: a step at a time, and out of the flow from
  /// step 1.
  Future<void> _back() async {
    final state = ref.read(
      serviceWizardControllerProvider(widget.args.listingId),
    );
    final view = state.value;
    if (view != null && view.step != WizardStep.details) {
      await _controller.back();
      return;
    }
    await _exit();
  }

  /// Leaves the wizard.
  ///
  /// **Nothing is saved here** — every step autosaved on its way past and
  /// anything the network refused is in the queue — which is why step 7's
  /// "Save draft" is this and not a write. Inventing a second save path
  /// beside the autosave would give a provider two ideas about when their
  /// work is safe.
  Future<void> _exit() async {
    await _controller.flush();
    if (!mounted) return;
    // `pop`, not `maybePop`: the [PopScope] below reports "do not pop" on
    // every step but the first, so that Android's back gesture walks the
    // steps — and `maybePop` would consult it and send this control backwards
    // instead of out.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Sheets are presented from here rather than from the controller: a
  /// notifier that pushed routes could not be tested without a navigator, and
  /// the controller holds *which* sheet, which is state.
  void _syncSheet(WizardView view) {
    if (view.sheet == PublishSheet.none || _sheetOpen) return;
    _sheetOpen = true;
    final sheet = view.sheet;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showAppBottomSheet<void>(
        context: context,
        builder: (sheetContext) => switch (sheet) {
          PublishSheet.published => PublishedSheet(
            listing: view.listing,
            categoryName: view.category?.name,
            onDone: () => Navigator.of(sheetContext).pop(),
          ),
          PublishSheet.capReached => ListingCapSheet(
            detail:
                view.capDetail ??
                const ListingCapDetail(cap: 1, liveListingNames: []),
            onKeepDraft: () => Navigator.of(sheetContext).pop(),
          ),
          PublishSheet.none => const SizedBox.shrink(),
        },
      );
      _sheetOpen = false;
      if (mounted) _controller.dismissSheet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      serviceWizardControllerProvider(widget.args.listingId),
    );
    final view = state.value;
    if (view != null) _syncSheet(view);

    return PopScope(
      canPop: view == null || view.step == WizardStep.details,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_controller.back());
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          bottom: false,
          child: switch (state) {
            AsyncData(:final value) => _Loaded(
              view: value,
              controller: _controller,
              onBack: _back,
              onExit: _exit,
            ),
            AsyncError(:final error) => _WizardError(
              error: error,
              onRetry: _controller.reload,
            ),
            _ => const _WizardLoading(),
          },
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.view,
    required this.controller,
    required this.onBack,
    required this.onExit,
  });

  final WizardView view;
  final ServiceWizardController controller;
  final Future<void> Function() onBack;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WizardHeader(view: view, onBack: onBack, onStep: controller.goTo),
        if (view.save == SaveState.offline) const _OfflineBanner(),
        Expanded(
          child: AnimatedSwitcher(
            duration: context.motion.base,
            child: SingleChildScrollView(
              key: ValueKey(view.step),
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.screen,
                AppSpacing.md2,
                AppSpacing.screen,
                AppSpacing.xxl + AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (view.formError != null &&
                      view.step != WizardStep.review) ...[
                    NoticeBanner(
                      message: view.formError!,
                      actionLabel: 'Dismiss',
                      onAction: controller.clearFormError,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  switch (view.step) {
                    WizardStep.details => DetailsStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.location => LocationStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.pricing => PricingStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.media => MediaStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.availability => AvailabilityStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.extras => ExtrasStep(
                      view: view,
                      controller: controller,
                    ),
                    WizardStep.review => ReviewStep(
                      view: view,
                      controller: controller,
                    ),
                  },
                ],
              ),
            ),
          ),
        ),
        WizardFooter(
          view: view,
          onBack: controller.back,
          onNext: controller.next,
          // "Save draft" saves nothing new — every step already did — so it
          // flushes anything pending and leaves.
          onSaveDraft: onExit,
          onPublish: controller.publish,
        ),
      ],
    );
  }
}

/// The queue is holding work. It says what is true — the changes are on the
/// device and will send — and never that anything was lost.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.warningTint,
        border: Border.symmetric(
          horizontal: BorderSide(color: colors.warningBorder),
        ),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.screen,
        vertical: AppSpacing.sm + 1,
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 14, color: colors.warningText),
          const SizedBox(width: AppSpacing.sm + 1),
          Expanded(
            child: Text(
              "You're offline — changes are queued and will sync "
              'automatically.',
              style: context.type.secondary.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

/// A skeleton in the shape of what is coming, not a centred spinner
/// (frontend/CLAUDE.md).
class _WizardLoading extends StatelessWidget {
  const _WizardLoading();

  @override
  Widget build(BuildContext context) {
    return const SkeletonLoader(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.screen,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonBox.line(width: 200, height: 16),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox.line(width: 120),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(height: AppSizes.inputHeight, radius: AppRadius.input),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(height: 120, radius: AppRadius.panel),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(height: 120, radius: AppRadius.panel),
          ],
        ),
      ),
    );
  }
}

/// A dropped connection gets the app's own no-connection state — the
/// explainer, the retry and the list of what still works — rather than a
/// generic "something went wrong", because the two call for different
/// actions.
class _WizardError extends StatelessWidget {
  const _WizardError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiNetworkException) {
      return NoConnectionView(onRetry: onRetry);
    }
    return Center(
      child: Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState.error(
          title: "We couldn't open your draft",
          body: genericErrorCopy,
          onRetry: onRetry,
        ),
      ),
    );
  }
}
