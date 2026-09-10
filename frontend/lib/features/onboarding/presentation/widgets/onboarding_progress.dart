import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/onboarding/controller/provider_onboarding_controller.dart';
import 'package:raajjepro/shared/shared.dart';

/// The flow's header (`Become a Provider.dc.html`): a 44 dp round back
/// control, "Step N of 3" centred, and three segments under it that fill as
/// the provider advances.
///
/// The back glyph changes with the step, exactly as the artboard does — a ×
/// on step 1, because backing out of the intro leaves the flow, and an arrow
/// on steps 2 and 3, because those go back one step.
///
/// **The segments are decorative.** The step count beside them says the same
/// thing in words, so they are hidden from the semantics tree rather than
/// announced as three unlabelled bars.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    required this.step,
    required this.onBack,
    super.key,
  });

  final OnboardingStep step;

  /// Null while step 2 is submitting — the artboard's `goBack` returns early
  /// during `loading`, and a back tap mid-write would leave the provider
  /// looking at step 1 while their profile was being created.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final leaving = step == OnboardingStep.intro;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.xl,
          AppSpacing.lg + 2,
          AppSpacing.xl,
          AppSpacing.md + 2,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _RoundBack(
                  icon: leaving
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                  label: leaving ? 'Close' : 'Back',
                  onTap: onBack,
                ),
                Expanded(
                  child: Text(
                    'Step ${step.number} of ${OnboardingStep.count}',
                    textAlign: TextAlign.center,
                    style: type.bodyStrong.copyWith(color: colors.textTertiary),
                  ),
                ),
                // Balances the back control so the label stays centred.
                const SizedBox(width: AppSizes.iconButtonSize),
              ],
            ),
            const SizedBox(height: AppSpacing.lg - 2),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < OnboardingStep.count; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: AnimatedContainer(
                        duration: context.motion.fast,
                        height: AppSpacing.xxs,
                        decoration: BoxDecoration(
                          color: i <= step.index
                              ? colors.primary
                              : colors.neutralBorder,
                          borderRadius: AppRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBack extends StatelessWidget {
  const _RoundBack({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      focusRadius: AppRadius.pill,
      builder: (context, states) => Container(
        width: AppSizes.iconButtonSize,
        height: AppSizes.iconButtonSize,
        decoration: BoxDecoration(
          color: states.pressed || states.hovered
              ? colors.accentTint
              : colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, size: AppSizes.iconLg + 2, color: colors.ink),
      ),
    );
  }
}
