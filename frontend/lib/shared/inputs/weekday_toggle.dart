import 'package:flutter/material.dart';

import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// One day of a Monday-first row of seven — `M T W T F S S`, ISO 1–7
/// (Round 58). Announced by its full name, because two Ts and two Ss are
/// ambiguous out loud.
///
/// 🔧 Moved here from the availability rule editor on its second consumer,
/// Saved Preferences' time-window sheet (`lib/README.md`).
class WeekdayToggle extends StatelessWidget {
  const WeekdayToggle({
    required this.label,
    required this.day,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      // The initial alone is ambiguous out loud — two Ts and two Ss.
      semanticLabel: weekdayRangeLabel([day]),
      toggled: selected,
      onTap: onTap,
      focusRadius: AppRadius.input,
      builder: (context, state) => Container(
        height: AppSizes.compactButtonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? AppSizes.selectedStroke : AppSizes.inputStroke,
          ),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Text(
          label,
          style: context.type.bodyStrong.copyWith(
            color: selected ? colors.onPrimary : colors.ink,
          ),
        ),
      ),
    );
  }
}

/// A labelled single-choice dropdown at input height — the From/To menus of
/// the availability rule editor and the time-window sheet.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.caption),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSizes.inputHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(
              color: colors.border,
              width: AppSizes.inputStroke,
            ),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              style: context.type.body.copyWith(color: colors.ink),
              onChanged: (next) {
                if (next == null) return;
                AppHaptics.selection();
                onChanged(next);
              },
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
