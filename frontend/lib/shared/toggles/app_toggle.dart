import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// The toggle (style guide → Toggle): on · off · **disabled-with-reason**.
///
/// A disabled toggle must be able to say why. The wizard's emergency toggle
/// is the case that forced this: it is gated by the category's
/// `emergencyMinimumTier` (plan §1c), and a greyed switch with no
/// explanation reads as broken. Pass [disabledReason] and it renders under
/// the label and is spoken with it.
///
/// The row is the control: label, description and switch are one 48 dp-
/// floored target, announced as a toggle with its state.
class AppToggle extends StatelessWidget {
  const AppToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
    this.description,
    this.disabledReason,
  });

  final bool value;

  /// Null disables the toggle; pair it with [disabledReason].
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? description;

  /// Why the toggle cannot be changed right now. Shown when [onChanged] is
  /// null.
  final String? disabledReason;

  bool get _enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final motion = context.motion;

    final spoken = StringBuffer(label);
    if (description != null) spoken.write(', $description');
    if (!_enabled && disabledReason != null) {
      spoken.write(', unavailable: $disabledReason');
    }

    return Pressable(
      onTap: _enabled ? () => onChanged!(!value) : null,
      enabled: _enabled,
      toggled: value,
      semanticLabel: spoken.toString(),
      focusRadius: AppRadius.md,
      builder: (context, s) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: type.bodyStrong.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _enabled ? colors.ink : colors.textTertiary,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!, style: type.secondary),
                  ],
                  if (!_enabled && disabledReason != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: colors.warningText,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            disabledReason!,
                            style: type.secondary.copyWith(
                              color: colors.warningText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _Switch(
              on: value,
              enabled: _enabled,
              pressed: s.pressed,
              motion: motion,
            ),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.on,
    required this.enabled,
    required this.pressed,
    required this.motion,
  });

  final bool on;
  final bool enabled;
  final bool pressed;
  final ResolvedMotion motion;

  static const double _w = 46;
  static const double _h = AppSizes.checkbox;
  static const double _thumb = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final track = !enabled
        ? colors.disabledFill
        : on
        ? (pressed ? colors.primaryPressed : colors.primary)
        : (pressed ? colors.border : colors.neutralTint);
    return AnimatedContainer(
      duration: motion.fast,
      curve: AppMotion.easeOut,
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: on || !enabled
            ? null
            : Border.all(color: colors.border, width: AppSizes.inputStroke),
      ),
      child: AnimatedAlign(
        duration: motion.fast,
        curve: AppMotion.easeOut,
        alignment: on
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.ink.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const SizedBox.square(dimension: _thumb),
          ),
        ),
      ),
    );
  }
}
