import 'package:flutter/material.dart';

import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/shared/shared.dart';

/// The wizard's top chrome: the back control, the progress framing, the save
/// pill, seven segments and the step pills.
///
/// **The headline is the required-field count, not the step count**
/// (§Phase 9). "Step 3 of 7" leads with the commitment; "3 required fields
/// left to publish" leads with what is actually left to do, and the step
/// count keeps its place on the line underneath.
class WizardHeader extends StatelessWidget {
  const WizardHeader({
    required this.view,
    required this.onBack,
    required this.onStep,
    super.key,
  });

  final WizardView view;
  final VoidCallback onBack;
  final ValueChanged<WizardStep> onStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.screen,
            AppSpacing.lg,
            AppSpacing.screen,
            0,
          ),
          child: Row(
            children: [
              CircleBackButton(
                semanticLabel: view.step == WizardStep.details
                    ? 'Leave the wizard'
                    : 'Back to ${WizardStep.values[view.step.index - 1].label}',
                onTap: onBack,
              ),
              const SizedBox(width: AppSpacing.sm2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.requirementHeadline,
                      style: type.bodyStrong.copyWith(
                        fontWeight: FontWeight.w800,
                        color: view.isReadyToPublish
                            ? colors.successText
                            : colors.ink,
                      ),
                    ),
                    Text(
                      'Step ${view.step.number} of ${WizardStep.count} · '
                      '${view.step.label}',
                      style: type.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SavePill(state: view.save),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: AppSpacing.screenInsets,
          child: ExcludeSemantics(
            child: Row(
              children: [
                for (final step in WizardStep.values) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: context.motion.fast,
                      height: 4,
                      decoration: BoxDecoration(
                        color: step.index <= view.step.index
                            ? colors.primary
                            : colors.disabledFill,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  if (step != WizardStep.review) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.screenInsets,
          child: Row(
            children: [
              for (final step in WizardStep.values) ...[
                _StepPill(
                  step: step,
                  selected: step == view.step,
                  incomplete: view.stepHasMissing(step),
                  onTap: () => onStep(step),
                ),
                if (step != WizardStep.review)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Every step is reachable from every other one, always — §Phase 9's "step
/// navigation never blocked; Review always reachable". The amber dot marks a
/// step still holding a required field; it is a signpost, never a lock.
class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.step,
    required this.selected,
    required this.incomplete,
    required this.onTap,
  });

  final WizardStep step;
  final bool selected;
  final bool incomplete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: incomplete && !selected
          ? '${step.label}, required fields still empty'
          : step.label,
      selected: selected,
      onTap: onTap,
      focusRadius: AppRadius.pill,
      builder: (context, state) => AnimatedContainer(
        duration: context.motion.fast,
        height: AppSizes.chipHeight,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md2,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: AppSizes.inputStroke,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              step.label,
              style: context.type.secondary.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? colors.onPrimary : colors.textTertiary,
              ),
            ),
            if (incomplete && !selected) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.warning,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Saved just now" · "Saving…" · "Saved offline".
///
/// The third one is deliberately not "Not saved". An edit the queue accepted
/// **is** saved — on this device, and it will reach the server — and telling a
/// provider otherwise on a weak connection would make them retype work that
/// was never lost.
class SavePill extends StatelessWidget {
  const SavePill({required this.state, super.key});

  final SaveState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, foreground, background, border) = switch (state) {
      SaveState.saving => (
        'Saving…',
        colors.textTertiary,
        colors.surface,
        colors.border,
      ),
      SaveState.saved => (
        'Saved just now',
        colors.successText,
        colors.surface,
        colors.border,
      ),
      SaveState.offline => (
        'Saved offline',
        colors.warningText,
        colors.warningTint,
        colors.warningBorder,
      ),
    };

    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        height: 30,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.n11,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (state) {
              SaveState.saving => AppSpinner(
                size: 11,
                strokeWidth: 2,
                color: colors.primary,
              ),
              SaveState.saved => Icon(
                Icons.check_rounded,
                size: AppSizes.iconSm,
                color: foreground,
              ),
              SaveState.offline => Icon(
                Icons.wifi_off_rounded,
                size: AppSizes.iconSm,
                color: foreground,
              ),
            },
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: context.type.caption.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The footer: Back and Continue on steps 1–6, Save draft and Publish on 7.
class WizardFooter extends StatelessWidget {
  const WizardFooter({
    required this.view,
    required this.onBack,
    required this.onNext,
    required this.onSaveDraft,
    required this.onPublish,
    super.key,
  });

  final WizardView view;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isReview = view.step == WizardStep.review;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.screen,
            AppSpacing.md,
            AppSpacing.screen,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isReview) ...[
                Text(
                  'Next · ${WizardStep.values[view.step.index + 1].label}',
                  textAlign: TextAlign.center,
                  style: type.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.n9),
              ],
              Row(
                children: [
                  if (isReview)
                    AppButton.secondary(
                      label: 'Save draft',
                      onPressed: onSaveDraft,
                    )
                  else if (view.step != WizardStep.details)
                    AppButton.secondary(label: 'Back', onPressed: onBack),
                  if (isReview || view.step != WizardStep.details)
                    const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: isReview
                        ? AppButton.primary(
                            key: const Key('wizard-publish'),
                            label: 'Publish service',
                            expand: true,
                            loading: view.publishing,
                            onPressed: view.publishing ? null : onPublish,
                          )
                        : AppButton.primary(
                            key: const Key('wizard-continue'),
                            label: view.navWaiting
                                ? 'Saving this step…'
                                : 'Continue',
                            expand: true,
                            loading: view.navWaiting,
                            onPressed: view.navWaiting ? null : onNext,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
