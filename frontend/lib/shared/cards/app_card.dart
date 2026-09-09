import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// The card (`Components.dc.html` → Card, "plain container"). White surface,
/// 1 px card border, 20 radius, the measured `0 1px 3px rgba(15,27,45,.05)`
/// shadow. Every panel in the app is this card; a listing card and a row
/// card are compositions on top of it, not separate surfaces.
///
/// With [onTap] the whole card is a 48 dp-floored, tap-scaling control and
/// needs a [semanticLabel]; without it the card is inert and its children
/// speak for themselves.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsetsDirectional.all(AppSpacing.lg),
    this.radius = AppRadius.panel,
    this.onTap,
    this.semanticLabel,
    this.selected = false,
    this.color,
    this.clip = false,
  }) : assert(
         onTap == null || semanticLabel != null,
         'A tappable card needs a semanticLabel.',
       );

  /// A row card with a leading icon chip — settings rows, list rows.
  static Widget row({
    required Widget leading,
    required String title,
    Key? key,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    String? semanticLabel,
  }) => _RowCard(
    key: key,
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onTap,
    semanticLabel: semanticLabel,
  );

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// A selectable card's chosen state: 2 px primary border.
  final bool selected;
  final Color? color;

  /// Clip children to the rounded corners (for a flush image).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;

    Widget paint(bool pressed) {
      final border = selected
          ? Border.all(color: colors.primary, width: AppSizes.selectedStroke)
          : Border.all(
              color: pressed ? colors.accentBorder : colors.borderCard,
              width: AppSizes.dividerStroke,
            );
      // **A card fills the width it is given.** Every prototype draws it as a
      // block element, which does that by default in CSS and never says so;
      // a Flutter box has no such default and sizes to its child. Until this
      // was explicit, a card landed full width only when something inside it
      // happened to be full width — the `expand: true` button on session
      // expired, the `Row` in a settings row — and the one card whose content
      // was all intrinsic (Explore's tile: a fixed 56 dp chip above a `Text`)
      // collapsed to its longest label and drew a visibly ragged grid.
      //
      // `LayoutBuilder` rather than `width: double.infinity`, because a card
      // in a horizontal carousel (Phase 16's Home rails) is handed an
      // unbounded width, where infinity is a layout error. There it keeps the
      // old shrink-wrap; the carousel gives it an explicit width, as those
      // prototypes already do, and that width is then what it fills.
      return LayoutBuilder(
        builder: (context, constraints) => AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.easeOut,
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          clipBehavior: clip ? Clip.antiAlias : Clip.none,
          decoration: BoxDecoration(
            color: color ?? colors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: border,
            boxShadow: AppShadows.card(colors.ink),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
    }

    if (onTap == null) return paint(false);

    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel!,
      focusRadius: radius,
      builder: (context, s) => paint(s.pressed),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.leading,
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      onTap: onTap,
      semanticLabel:
          semanticLabel ?? (subtitle == null ? title : '$title, $subtitle'),
      radius: AppRadius.card,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: AppSizes.avatarMedium,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.neutralTint,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Center(child: leading),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: type.cardTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: type.secondary),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ] else if (onTap != null)
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
