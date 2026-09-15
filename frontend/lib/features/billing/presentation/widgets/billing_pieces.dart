import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The small vocabulary the three billing screens share: a labelled card
/// section, an overline, a copy-to-clipboard affordance and a quoted line.

/// `AMOUNT TO TRANSFER` — the uppercase label above a card's content.
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.type.overline.copyWith(color: context.colors.textSecondary),
  );
}

/// A card with an [Overline] and its content beneath.
class LabelledCard extends StatelessWidget {
  const LabelledCard({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Overline(label),
        const SizedBox(height: AppSpacing.sm2),
        child,
      ],
    ),
  );
}

/// A 44 dp copy button. [onCopied] fires after the text is on the clipboard.
class CopyButton extends StatelessWidget {
  const CopyButton({
    required this.value,
    required this.what,
    required this.onCopied,
    super.key,
    this.withLabel = false,
  });

  /// What goes on the clipboard.
  final String value;

  /// "Account number" — for the spoken label and the confirmation.
  final String what;
  final void Function(String what) onCopied;

  /// Draws `Copy` beside the icon, the reference code's variant.
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      semanticLabel: 'Copy $what',
      focusRadius: AppRadius.sm,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        onCopied(what);
      },
      builder: (context, s) => Container(
        height: AppSizes.iconButtonSize,
        constraints: const BoxConstraints(minWidth: AppSizes.iconButtonSize),
        padding: withLabel
            ? const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: s.pressed ? colors.accentTintPressed : colors.accentTint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.accentBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.copy_rounded,
              size: AppSizes.iconMd,
              color: colors.accentText,
            ),
            if (withLabel) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Copy',
                style: type.buttonSmall.copyWith(color: colors.accentText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A label over a value — one bank-detail row.
class FactRow extends StatelessWidget {
  const FactRow({
    required this.label,
    required this.value,
    super.key,
    this.trailing,
    this.mono = false,
  });

  final String label;
  final String value;
  final Widget? trailing;

  /// Tabular, spaced figures for an account number.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                value,
                style: mono
                    ? type.price.copyWith(letterSpacing: 0.5)
                    : type.bodyStrong,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

/// The admin's rejection reason, set off from the screen's own voice.
class QuotedLine extends StatelessWidget {
  const QuotedLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(AppSpacing.md2),
      decoration: BoxDecoration(
        color: colors.errorTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: BorderDirectional(
          start: BorderSide(color: colors.error, width: AppSpacing.xxs),
        ),
      ),
      child: Text(
        '“$text”',
        style: context.type.body.copyWith(color: colors.ink),
      ),
    );
  }
}
