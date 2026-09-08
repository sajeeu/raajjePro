import 'package:flutter/material.dart';

import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// `I want to…` — two selectable cards (`Register.dc.html`). Selecting Offer
/// Services adds one field; it does not make anyone a provider.
class RoleToggle extends StatelessWidget {
  const RoleToggle({required this.value, required this.onChanged, super.key});
  final AccountRole value;
  final ValueChanged<AccountRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    Widget card(AccountRole role, IconData icon, String title, String sub) {
      final selected = role == value;
      return Expanded(
        child: Pressable(
          semanticLabel: '$title, $sub${selected ? ', selected' : ''}',
          onTap: () => onChanged(role),
          selected: selected,
          builder: (context, state) => AnimatedContainer(
            duration: context.motion.fast,
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? colors.accentTint : colors.surface,
              borderRadius: AppRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: selected
                    ? AppSizes.selectedStroke
                    : AppSizes.inputStroke,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected ? colors.primary : colors.textSecondary,
                  size: AppSizes.iconLg,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  style: type.bodyStrong.copyWith(
                    color: selected ? colors.primaryPressed : colors.ink,
                  ),
                ),
                Text(
                  sub,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(
          AccountRole.customer,
          Icons.search_rounded,
          'Find Services',
          'Book local providers',
        ),
        const SizedBox(width: AppSpacing.md),
        card(
          AccountRole.provider,
          Icons.handyman_outlined,
          'Offer Services',
          'List my services',
        ),
      ],
    );
  }
}
