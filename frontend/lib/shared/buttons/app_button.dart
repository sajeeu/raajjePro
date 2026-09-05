import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/feedback/app_spinner.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

enum AppButtonVariant {
  /// Gradient fill, 54 high. One per screen — the thing to do next.
  primary,

  /// Accent tint with a 1.5 border, 52 high. Retry, secondary actions.
  secondary,

  /// No fill, 44 high. "See all", inline links.
  text,

  /// Error red, 54 high. Cancel, delete, decline.
  destructive,
}

enum AppButtonSize {
  /// The measured height for the variant.
  regular,

  /// 44 high with the small label — empty-state action, header CTA.
  compact,
}

/// The button (`Components.dc.html` → Button). Four variants, each with
/// default, pressed, disabled and loading. **Loading keeps the label** and
/// adds a spinner; the button stops accepting taps but does not grey out,
/// because the user needs to see what is still happening.
///
/// A button that triggers a network call shows its own loading state — pass
/// `loading: true`; never cover the screen with a spinner for a local action.
///
/// Heights are minimums: the label scales with the OS text size and the
/// button grows rather than clipping.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticLabel,
  });

  const AppButton.primary({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = AppButtonSize.regular,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = AppButtonSize.regular,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.text({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = AppButtonSize.regular,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.text;

  const AppButton.destructive({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = AppButtonSize.regular,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.destructive;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final IconData? icon;

  /// Fill the available width.
  final bool expand;

  /// Overrides the spoken label when the visible one is not enough.
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final motion = context.motion;

    final compact = size == AppButtonSize.compact;
    final minHeight = compact
        ? AppSizes.compactButtonHeight
        : switch (variant) {
            AppButtonVariant.primary ||
            AppButtonVariant.destructive => AppSizes.ctaHeight,
            AppButtonVariant.secondary => AppSizes.secondaryButtonHeight,
            AppButtonVariant.text => AppSizes.compactButtonHeight,
          };
    final radius = variant == AppButtonVariant.text
        ? AppRadius.md
        : (compact ? AppRadius.compact : AppRadius.button);
    final labelStyle = compact ? type.buttonSmall : type.button;
    final horizontal = switch (variant) {
      AppButtonVariant.text => AppSpacing.sm,
      _ => compact ? AppSpacing.xl : AppSpacing.xxl,
    };

    final spoken = loading
        ? '${semanticLabel ?? label}, loading'
        : (semanticLabel ?? label);

    return Pressable(
      onTap: _enabled ? onPressed : null,
      enabled: _enabled || loading,
      semanticLabel: spoken,
      focusRadius: radius,
      builder: (context, s) {
        final look = _Look.resolve(
          variant: variant,
          colors: colors,
          pressed: s.pressed,
          disabled: onPressed == null,
        );
        final fg = look.foreground;

        Widget content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              AppSpinner(color: fg, size: compact ? 14 : 16),
              const SizedBox(width: AppSpacing.sm + 1),
            ] else if (icon != null) ...[
              Icon(icon, size: compact ? 16 : 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                style: labelStyle.copyWith(color: fg),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );

        content = Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: horizontal,
            vertical: AppSpacing.sm,
          ),
          child: content,
        );

        return AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.easeOut,
          constraints: BoxConstraints(minHeight: minHeight),
          width: expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: look.fill,
            gradient: look.gradient,
            borderRadius: BorderRadius.circular(radius),
            border: look.border,
            boxShadow: look.shadow,
          ),
          // No `alignment:` — it would make a Container fill its
          // constraints; [expand] is the only thing that widens a button.
          child: content,
        );
      },
    );
  }
}

/// The resolved paint for one variant in one state.
class _Look {
  const _Look({
    required this.foreground,
    this.fill,
    this.gradient,
    this.border,
    this.shadow,
  });

  final Color foreground;
  final Color? fill;
  final Gradient? gradient;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  static _Look resolve({
    required AppButtonVariant variant,
    required AppColors colors,
    required bool pressed,
    required bool disabled,
  }) {
    switch (variant) {
      case AppButtonVariant.primary:
        if (disabled) {
          return _Look(
            fill: colors.disabledFill,
            foreground: colors.disabledText,
          );
        }
        if (pressed) {
          return _Look(
            fill: colors.primaryPressed,
            foreground: colors.onPrimary,
          );
        }
        return _Look(
          gradient: colors.ctaGradient,
          foreground: colors.onPrimary,
          shadow: AppShadows.cta(colors.primary),
        );
      case AppButtonVariant.destructive:
        if (disabled) {
          return _Look(
            fill: colors.disabledFill,
            foreground: colors.disabledText,
          );
        }
        if (pressed) {
          return _Look(fill: colors.errorPressed, foreground: colors.onError);
        }
        return _Look(
          fill: colors.error,
          foreground: colors.onError,
          shadow: AppShadows.cta(colors.error, alpha: 0.28),
        );
      case AppButtonVariant.secondary:
        if (disabled) {
          return _Look(
            fill: colors.background,
            foreground: colors.disabledText,
            border: Border.all(
              color: colors.border,
              width: AppSizes.inputStroke,
            ),
          );
        }
        if (pressed) {
          return _Look(
            fill: colors.accentTintPressed,
            foreground: colors.accentText,
            border: Border.all(
              color: colors.accentBorderPressed,
              width: AppSizes.inputStroke,
            ),
          );
        }
        return _Look(
          fill: colors.accentTint,
          foreground: colors.accentText,
          border: Border.all(
            color: colors.accentBorder,
            width: AppSizes.inputStroke,
          ),
        );
      case AppButtonVariant.text:
        if (disabled) return _Look(foreground: colors.disabledText);
        if (pressed) {
          return _Look(
            fill: colors.ink.withValues(alpha: 0.05),
            foreground: colors.accentText,
          );
        }
        return _Look(foreground: colors.primary);
    }
  }
}
