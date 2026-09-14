import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Every step opens the same way: a 24/800 title and a line of plain English
/// under it.
class StepIntro extends StatelessWidget {
  const StepIntro({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: type.screenTitle.copyWith(fontSize: 24)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: type.body.copyWith(
            fontSize: 14.5,
            height: 1.5,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// How a [WizardNote] reads.
enum NoteTone {
  /// White card, a green tick — a reassurance, not a warning.
  reassuring,

  /// Accent tint — context the provider should read but need not act on.
  informative,

  /// Warning tint — a consequence.
  cautionary,

  /// Neutral tint — the honesty notes (§1i's "RaajjePro doesn't check…").
  plain,
}

/// A line of explanation inside a step, in a tinted box.
///
/// Distinct from [NoticeBanner], which is the app's inline *warning*: several
/// of these are reassurances or plain statements of fact, and a screen where
/// every explanation is amber teaches a provider to ignore amber.
class WizardNote extends StatelessWidget {
  const WizardNote({
    required this.message,
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.tone = NoteTone.plain,
    this.trailing,
  });

  final String message;
  final IconData icon;
  final NoteTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final (background, border, foreground, iconColor) = switch (tone) {
      NoteTone.reassuring => (
        colors.surface,
        colors.borderCard,
        colors.textTertiary,
        colors.success,
      ),
      NoteTone.informative => (
        colors.accentTint,
        colors.accentBorder,
        colors.accentText,
        colors.primary,
      ),
      NoteTone.cautionary => (
        colors.warningTint,
        colors.warningBorder,
        colors.warningText,
        colors.warningText,
      ),
      NoteTone.plain => (
        colors.surfaceMuted,
        colors.surfaceMuted,
        colors.textTertiary,
        colors.textSecondary,
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg - 1,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.iconMd, color: iconColor),
          const SizedBox(width: AppSpacing.md - 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: type.secondary.copyWith(
                    height: 1.5,
                    color: foreground,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label row for a control that is not an [AppTextField] — a chooser, a
/// grid, a pair of pickers. Text fields draw their own through
/// `AppTextField.requirement`.
class ControlLabel extends StatelessWidget {
  const ControlLabel({required this.label, super.key, this.requirement});

  final String label;
  final FieldRequirement? requirement;

  @override
  Widget build(BuildContext context) {
    final style = context.type.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: context.colors.ink,
    );
    if (requirement == null) return Text(label, style: style);
    return Semantics(
      label: '$label, ${requirement!.label.toLowerCase()}',
      excludeSemantics: true,
      child: Row(
        children: [
          Flexible(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.sm),
          FieldRequirementPill(requirement!),
        ],
      ),
    );
  }
}

/// One of the white cards a step groups related controls into.
class WizardSection extends StatelessWidget {
  const WizardSection({
    required this.children,
    super.key,
    this.title,
    this.requirement,
    this.helper,
    this.borderColor,
  });

  final String? title;
  final FieldRequirement? requirement;
  final String? helper;
  final List<Widget> children;

  /// The callback guarantee's card is outlined in green, because §1h's
  /// promise is RaajjePro's own and must not sit in the same treatment as
  /// §1i's self-declared warranty.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final heading = title;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(
          color: borderColor ?? colors.borderCard,
          width: borderColor == null ? 1 : AppSizes.inputStroke,
        ),
        boxShadow: AppShadows.card(colors.ink),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg + 2,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null) ...[
            ControlLabel(label: heading, requirement: requirement),
            if (helper != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                helper!,
                style: type.secondary.copyWith(
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// A radio-style choice card — pricing models on step 3, booking modes on
/// step 5.
///
/// [disabledReason] renders **under the title, in the card**, rather than
/// hiding the option: §Phase 9 requires a blocked choice to say why, so a
/// provider can act on it. An option that simply vanished would leave them
/// looking for it.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
    this.disabledReason,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final String? disabledReason;

  bool get _disabled => disabledReason != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final reason = disabledReason;

    return Pressable(
      semanticLabel: _disabled ? '$title, unavailable. $reason' : title,
      toggled: selected,
      enabled: !_disabled,
      onTap: _disabled ? null : onTap,
      minSize: 0,
      focusRadius: AppRadius.button,
      builder: (context, state) => AnimatedContainer(
        duration: context.motion.fast,
        decoration: BoxDecoration(
          color: selected
              ? colors.accentTint
              : _disabled
              ? colors.surfaceMuted
              : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: selected ? colors.primary : colors.borderCard,
            width: AppSizes.inputStroke,
          ),
        ),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colors.primary : colors.surface,
                border: Border.all(
                  color: selected ? colors.primary : colors.neutralDot,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.onPrimary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md + 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: type.cardTitle.copyWith(
                            color: _disabled ? colors.disabledText : colors.ink,
                          ),
                        ),
                      ),
                      if (_disabled) ...[
                        const SizedBox(width: AppSpacing.xs + 1),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: colors.disabledText,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: type.secondary.copyWith(
                      height: 1.45,
                      color: _disabled
                          ? colors.placeholder
                          : colors.textSecondary,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      reason,
                      style: type.secondary.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: colors.warningText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
