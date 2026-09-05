import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

enum AppChipKind {
  /// Selectable; inverts to primary when selected. 38 high.
  filter,

  /// Removable, with an ×. 38 high.
  input,

  /// A static label with no interaction. 28 high.
  label,
}

/// The chip (`Chip.dc.html`). The visual pill is 38 dp (28 for a label);
/// the tap area is floored to 48 dp by [Pressable], so a row of chips is
/// 48 tall with the pills centred — the price of the accessibility floor,
/// paid once here.
class AppChip extends StatelessWidget {
  const AppChip.filter({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.icon,
  }) : kind = AppChipKind.filter,
       onRemove = null;

  const AppChip.input({
    required this.label,
    required this.onRemove,
    super.key,
    this.icon,
  }) : kind = AppChipKind.input,
       selected = false,
       onTap = null;

  const AppChip.label({required this.label, super.key, this.icon})
    : kind = AppChipKind.label,
      selected = false,
      onTap = null,
      onRemove = null;

  final String label;
  final AppChipKind kind;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      AppChipKind.filter => _filter(context),
      AppChipKind.input => _input(context),
      AppChipKind.label => _label(context),
    };
  }

  Widget _filter(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      focusRadius: AppRadius.pill,
      builder: (context, s) {
        final fg = selected ? colors.onPrimary : colors.textTertiary;
        return AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.easeOut,
          constraints: const BoxConstraints(minHeight: AppSizes.chipHeight),
          decoration: BoxDecoration(
            color: selected
                ? (s.pressed ? colors.primaryPressed : colors.primary)
                : (s.pressed ? colors.background : colors.surface),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
              width: AppSizes.inputStroke,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: AppSpacing.xs,
          ),
          // No `alignment:` — a Container with one expands to fill its
          // constraints, and a chip must hug its label.
          child: _content(context, fg),
        );
      },
    );
  }

  Widget _input(BuildContext context) {
    final colors = context.colors;
    // The whole pill is the remove control: a separate 48 dp × inside a
    // 38 dp pill cannot exist, and "tap the chip to remove it" is the
    // pattern users already know. The × is the affordance, not the target.
    return Pressable(
      onTap: onRemove,
      semanticLabel: 'Remove $label',
      focusRadius: AppRadius.pill,
      builder: (context, s) {
        final fg = s.pressed ? colors.primaryPressed : colors.accentText;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: s.pressed ? colors.accentTintPressed : colors.accentTint,
            border: Border.all(
              color: colors.accentBorder,
              width: AppSizes.inputStroke,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.chipHeight),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 14,
                end: AppSpacing.sm + 2,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _content(context, fg),
                  const SizedBox(width: 7),
                  Icon(Icons.close, size: 14, color: fg),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _label(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.neutralTint,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.staticChipHeight,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 11,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: colors.neutralText),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  label,
                  style: context.type.pill.copyWith(color: colors.neutralText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color fg) {
    final style = context.type.secondary.copyWith(
      color: fg,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    // Flexible so a long island name in a tight slot ellipsizes rather
    // than overflowing the pill.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
