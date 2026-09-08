import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// The inline warning notice from the prototypes (`Provider Emergency.dc.html`,
/// `Verification.dc.html`): warning tint, warning border, a 16 dp icon and a
/// line of 12.5/600 warning text.
///
/// It is a notice, not a dialog: it sits in the flow of a screen and does not
/// interrupt. The optional action is a plain text button rather than a filled
/// one, because a notice that competes with the screen's real CTA is a
/// distraction rather than a warning.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.message,
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.actionLabel,
    this.onAction,
    this.semanticLabel,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'an action needs both a label and a callback',
       );

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Announced instead of [message] when the visible wording reads oddly out
  /// of context. Defaults to the message itself.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final label = actionLabel;
    final action = onAction;

    return Semantics(
      liveRegion: true,
      label: semanticLabel ?? message,
      excludeSemantics: action == null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warningTint,
          border: Border.all(color: colors.warningBorder),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 2),
                  child: Icon(icon, size: 16, color: colors.warning),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: type.secondary.copyWith(
                        color: colors.warningText,
                        height: 1.55,
                      ),
                    ),
                    if (label != null && action != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Pressable(
                        onTap: action,
                        semanticLabel: label,
                        minSize: AppSizes.touchTarget,
                        focusRadius: AppRadius.xs,
                        builder: (context, _) => Text(
                          label,
                          style: type.buttonSmall.copyWith(
                            color: colors.warningText,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.warningText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
