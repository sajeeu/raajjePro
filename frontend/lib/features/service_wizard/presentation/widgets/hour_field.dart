import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The working-window hours step 5 offers, 06:00–22:00 (`Create
/// Service.dc.html`). The API accepts any valid clock time; this is the list
/// the wizard puts in front of a provider.
const List<String> wizardWorkingHours = [
  '06:00',
  '07:00',
  '08:00',
  '09:00',
  '10:00',
  '11:00',
  '12:00',
  '13:00',
  '14:00',
  '15:00',
  '16:00',
  '17:00',
  '18:00',
  '19:00',
  '20:00',
  '21:00',
  '22:00',
];

/// A From/To hour control.
///
/// A tap opens a sheet rather than a platform dropdown: the app's own sheet
/// is the idiom every other chooser here uses, it scales with the OS text
/// size, and it keeps the focus ring and 48 dp target [Pressable] gives
/// everything else.
class HourField extends StatelessWidget {
  const HourField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;

  /// `HH:MM`, or null where the provider has not set one.
  final String? value;
  final ValueChanged<String> onChanged;

  Future<void> _choose(BuildContext context) async {
    final chosen = await showAppBottomSheet<String>(
      context: context,
      builder: (sheetContext) => AppBottomSheet(
        title: label,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final hour in wizardWorkingHours)
              _HourRow(
                hour: hour,
                selected: hour == value,
                onTap: () => Navigator.of(sheetContext).pop(hour),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final shown = value ?? 'Not set';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: type.secondary.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.n7),
        Pressable(
          semanticLabel: '$label, $shown',
          onTap: () => _choose(context),
          focusRadius: AppRadius.input,
          builder: (context, state) => Container(
            constraints: const BoxConstraints(minHeight: 50),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: state.focused ? colors.primary : colors.border,
                width: AppSizes.inputStroke,
              ),
            ),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.n15,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shown,
                    style: type.bodyStrong.copyWith(
                      fontWeight: FontWeight.w700,
                      color: value == null ? colors.placeholder : colors.ink,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: AppSizes.iconMd,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.hour,
    required this.selected,
    required this.onTap,
  });

  final String hour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel: hour,
      selected: selected,
      onTap: onTap,
      focusRadius: AppRadius.md,
      builder: (context, state) => Container(
        color: state.pressed ? colors.surfaceMuted : colors.surface,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hour,
                style: context.type.bodyStrong.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: colors.ink,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: AppSizes.iconLg,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
