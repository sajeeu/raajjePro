import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The confirmation §Phase 6a's step 3 raises before handing off
/// (`Become a Provider.dc.html`'s "You're all set" sheet).
///
/// It is a moment, not a step: nothing is saved here, because every island
/// was written as it was tapped and the account details landed on the
/// previous Continue. What it does is name the handoff — §Phase 6a's step 4
/// is *"hand off directly into the Phase 9 wizard's Step 1, pre-populated
/// with nothing (a fresh draft), so the very next thing the provider does is
/// describe their first service"* — and give the way back, because a provider
/// who reached it by accident should be able to keep editing their islands.
///
/// **The subtitle names the islands rather than counting them.** §0.0 item 12
/// bans an island *total* in UI copy, and while that rule is about the 192-row
/// register rather than a provider's own selection, naming what was chosen is
/// better copy anyway — a provider reads their own list back and can see if it
/// is wrong. Past three, it falls back to a count of the provider's own
/// choices, which is not the register's denominator.
class OnboardingDoneSheet extends StatelessWidget {
  const OnboardingDoneSheet({
    required this.firstName,
    required this.islands,
    required this.onStart,
    required this.onBack,
    super.key,
  });

  /// The provider or business name from step 2. The artboard greets on its
  /// first word — "You're all set, Hassan!" — and falls back to no name at
  /// all rather than to a placeholder.
  final String firstName;
  final List<Island> islands;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final first = firstName.trim().split(' ').first;

    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: colors.ctaGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: AppSpacing.xxxl + 2,
                color: colors.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            first.isEmpty ? "You're all set!" : "You're all set, $first!",
            textAlign: TextAlign.center,
            style: type.screenTitle,
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            'Your provider profile is ready. Next, add your first service so '
            'customers on ${_where(islands)} can find you.',
            textAlign: TextAlign.center,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            key: const Key('onboarding-start-service'),
            label: 'Start My First Service',
            expand: true,
            onPressed: onStart,
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          AppButton.text(
            label: 'Back to service area',
            expand: true,
            onPressed: onBack,
          ),
        ],
      ),
    );
  }

  /// The qualified display names — `Dh. Meedhoo` where the name is shared,
  /// `Kulhudhuffushi` where it is not. Never rebuilt from `nameAmbiguous`
  /// here; the server decides it once (§0.0 item 12) and this prints what it
  /// sent.
  static String _where(List<Island> islands) => switch (islands.length) {
    0 => 'your islands',
    1 => islands.first.displayName,
    2 => '${islands[0].displayName} and ${islands[1].displayName}',
    3 =>
      '${islands[0].displayName}, ${islands[1].displayName} and '
          '${islands[2].displayName}',
    _ => 'your ${islands.length} islands',
  };
}
