import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The banks §Phase 6a's "Getting paid" section offers, exactly as
/// `Become a Provider.dc.html` lists them.
///
/// 🔧 **Flagged, not resolved: there is no "Other" and no free-text escape.**
/// The artboard's `<select>` has none, the plan names no bank register, and
/// §Phase 6a says the three payment fields are all required — so a provider
/// banking somewhere unlisted cannot finish this step. Inventing an option
/// would be inventing product, and `ProviderProfile.transferInstructions`
/// (§Phase 5's "and/or other transfer instructions") is the field a design
/// round would most likely reach for. Recorded in
/// `docs/decisions/20-phase-6a-become-a-provider.md` rather than guessed at.
///
/// The stored value is the bank's display name, because `bankName` is free
/// text on the server (§Phase 5) and a customer at a booking's payment step
/// reads it as-is.
const maldivianBanks = [
  'Bank of Maldives (BML)',
  'Maldives Islamic Bank (MIB)',
  'State Bank of India — Malé',
  'Habib Bank Limited',
  'Mauritius Commercial Bank (MCB)',
  'Commercial Bank of Maldives (CBM)',
  'Bank of Ceylon',
];

/// The bank chooser. Drawn as the artboard's 52 dp select — label, value,
/// chevron — and opened as a bottom sheet rather than a dropdown, which is
/// what a web `<select>` becomes on a phone anyway and what every other
/// choice in this app already uses.
///
/// **This is not an island control and the §0.0 item 12 rule does not reach
/// it.** That rule bans a picker over a browsable list *for islands*, where
/// 192 entries make search the only workable control. Seven banks is a list.
class BankField extends StatelessWidget {
  const BankField({
    required this.value,
    required this.onChanged,
    super.key,
    this.errorText,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final chosen = value;
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Bank', style: type.bodyStrong),
            const SizedBox(width: AppSpacing.sm),
            const FieldRequirementPill(FieldRequirement.mandatory),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Pressable(
          onTap: () => _open(context),
          semanticLabel: chosen == null
              ? 'Bank, required. Select your bank'
              : 'Bank, $chosen',
          focusRadius: AppRadius.input,
          builder: (context, states) => Container(
            constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.circular(AppRadius.input),
              border: Border.all(
                color: hasError
                    ? colors.error
                    : states.focused
                    ? colors.primary
                    : colors.border,
                width: AppSizes.inputStroke,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chosen ?? 'Select your bank',
                    style: chosen == null
                        ? type.body.copyWith(color: colors.placeholder)
                        : type.bodyStrong,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: AppSizes.iconLg,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: type.secondary.copyWith(color: colors.errorText),
          ),
        ],
      ],
    );
  }

  void _open(BuildContext context) {
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Select your bank',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final bank in maldivianBanks)
              _BankRow(
                name: bank,
                selected: bank == value,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onChanged(bank);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: name,
      builder: (context, states) => Container(
        color: states.pressed || states.hovered
            ? colors.background
            : Colors.transparent,
        padding: const EdgeInsetsDirectional.symmetric(
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            Expanded(child: Text(name, style: type.cardTitle)),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: AppSizes.iconLg + 2,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
