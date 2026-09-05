import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/buttons/app_button.dart';
import 'package:raajjepro/shared/cards/app_card.dart';

/// The empty and error states (`EmptyState.dc.html`; `My Services.dc.html`
/// error card). Icon in a 48 dp disc, a title, a body, and an action.
///
/// The action is part of the component, not decoration: **an empty state
/// names what to do next** (plan §3 convention) — "No bookings yet" plus a
/// route to Explore, never just an icon. An error state says what failed in
/// human terms and offers retry — never a raw code, never "Something went
/// wrong" alone.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
    this.actionLabel,
    this.onAction,
  }) : _error = false;

  /// Red disc, "Try again" as the default action label.
  const EmptyState.error({
    required this.title,
    required this.body,
    required VoidCallback onRetry,
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.actionLabel = 'Try again',
  }) : onAction = onRetry,
       _error = true;

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _error ? colors.errorTint : colors.neutralTint,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: AppSizes.touchTarget,
                child: Center(
                  child: Icon(
                    icon,
                    size: AppSizes.iconLg + 3,
                    color: _error ? colors.errorText : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 1),
          Semantics(
            header: true,
            child: Text(
              title,
              style: type.cardTitle,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              body,
              style: type.secondary,
              textAlign: TextAlign.center,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.sm + 3),
            AppButton.secondary(
              label: actionLabel!,
              onPressed: onAction,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}
