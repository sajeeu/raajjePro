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

  /// `height: 124px` in `Register.dc.html`. Not on the size scale, so it
  /// stands as the prototype's measured value.
  static const _cardHeight = 124.0;

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
          // `width: double.infinity` and the explicit height are both
          // load-bearing. `Expanded` does give each card an equal 176 dp
          // slot, but `Pressable` centres its child in that slot and passes
          // loose constraints, so the card sized to its own text instead:
          // 146 dp for "Book local providers" against 128 dp for "List my
          // services", each centred, leaving two different cards with
          // uneven gaps. The prototype's are identical, and it sets
          // `height: 124px` explicitly rather than letting content decide.
          builder: (context, state) => AnimatedContainer(
            duration: context.motion.fast,
            width: double.infinity,
            height: _cardHeight,
            // `padding: 18px 12px` in the prototype. 18 is not on the
            // spacing scale (…12, 16, 20…), so it stands as a measured
            // value; the horizontal 12 is `AppSpacing.md`.
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: 18,
              horizontal: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.accentTint : colors.surface,
              // `border-radius: 18px` — `AppRadius.tile`, not `card` (16).
              borderRadius: AppRadius.circular(AppRadius.tile),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: selected
                    ? AppSizes.selectedStroke
                    : AppSizes.inputStroke,
              ),
            ),
            // `align-items: center` in the prototype: icon, title and
            // subtitle are centred in the card, not ranged left.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
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
                  textAlign: TextAlign.center,
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
