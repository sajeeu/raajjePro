import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// One settings row (`Account Settings.dc.html`): a 46 dp icon disc, title,
/// subtitle, chevron, in a card. [destructive] paints the delete row.
///
/// Brief-vs-code: the brief wrapped `AppCard` in a bare `Pressable(child: …)`,
/// but `Pressable` has no `child` parameter (only `builder`) — it would not
/// compile. `AppCard` already becomes a 48 dp-floored, tap-scaling,
/// semantics-carrying [Pressable] whenever `onTap` is given, so this uses
/// that built-in path instead of double-wrapping.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: destructive ? colors.errorTint : colors.accentTint,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: destructive ? colors.error : colors.primary,
              size: AppSizes.iconLg,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: type.cardTitle.copyWith(
                    color: destructive ? colors.errorText : colors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.placeholder),
        ],
      ),
    );
  }
}
