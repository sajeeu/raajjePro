import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/cards/app_card.dart';

/// One navigation row (`Account Settings.dc.html`, `Profile.dc.html`): a
/// 46 dp icon disc, title, an optional subtitle, chevron, in a card.
/// [destructive] paints the delete row.
///
/// Shared rather than feature-owned because two features draw it: Phase 3's
/// Account settings, with a subtitle under every row, and Phase 6's Profile,
/// whose five rows are subtitle-free by design (Round 48 §4 — "keep the rows
/// subtitle-free"). `lib/README.md`: a widget a second feature needs moves
/// here, it is not copied.
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
    required this.onTap,
    super.key,
    this.subtitle,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconDisc,
            height: AppSizes.iconDisc,
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
                if (subtitle != null)
                  Text(
                    subtitle!,
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
