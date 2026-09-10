import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/onboarding/data/provider_onboarding_api.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a's "How will you offer services?" — the two `providerType` cards
/// (`Become a Provider.dc.html`, step 2).
///
/// **The copy on each card states the consequence**, which is the artboard's
/// and the plan's: §1e reads this field to decide whether Gold verification
/// asks for personal ID or business registration documents, so a provider
/// choosing here is choosing what they will later be asked to produce. A
/// label reading only "Individual / Business" would hide that.
///
/// **It announces itself as one choice of two.** Two cards that look like
/// buttons but behave like a single selection have to say so, or a
/// screen-reader user has no way to know that picking the second unpicks the
/// first — so each card's spoken label ends "1 of 2" and [Pressable] carries
/// the selected state.
class ProviderTypeChoice extends StatelessWidget {
  const ProviderTypeChoice({
    required this.value,
    required this.onChanged,
    super.key,
    this.errorText,
  });

  final ProviderType? value;
  final ValueChanged<ProviderType> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'How will you offer services?',
                style: type.bodyStrong,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const FieldRequirementPill(FieldRequirement.mandatory),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // `IntrinsicHeight` so the two cards match height even though their
        // descriptions are different lengths. `CrossAxisAlignment.stretch`
        // alone cannot do it: this Row sits in a scrolling column, so its
        // cross axis is unbounded and stretching to infinity throws.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TypeCard(
                  icon: Icons.person_outline_rounded,
                  label: 'Individual',
                  description: 'Just me — verified later with my personal ID',
                  selected: value == ProviderType.individual,
                  position: 1,
                  onTap: () => onChanged(ProviderType.individual),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TypeCard(
                  icon: Icons.storefront_outlined,
                  label: 'Business',
                  description:
                      'Registered company or team — verified later with '
                      'business documents',
                  selected: value == ProviderType.business,
                  position: 2,
                  onTap: () => onChanged(ProviderType.business),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: type.secondary.copyWith(color: colors.errorText),
          ),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.position,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;

  /// 1-based, spoken as "1 of 2" so the pair reads as one choice.
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: '$label, $position of 2. $description',
      focusRadius: AppRadius.card,
      builder: (context, states) => AnimatedContainer(
        duration: context.motion.fast,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg - 2,
          AppSpacing.lg - 2,
          AppSpacing.lg - 2,
          AppSpacing.md + 1,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentTint : colors.surface,
          borderRadius: AppRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: AppSizes.inputStroke,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: AppSizes.iconLg + 4, color: colors.primary),
                if (selected)
                  Container(
                    width: AppSpacing.xl,
                    height: AppSpacing.xl,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: AppSizes.iconSm,
                      color: colors.onPrimary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: type.cardTitle),
            const SizedBox(height: AppSpacing.xxs / 2),
            Text(
              description,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
