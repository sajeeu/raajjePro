import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/motion/pressable.dart';

/// An icon-only action in the header's trailing slot: a 40 dp bordered disc
/// with an optional count badge. Always labelled — it is icon-only.
class AppHeaderAction {
  const AppHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Unread count. Renders as a primary pill; spoken as part of the label.
  final int? badgeCount;
}

/// The screen header (`Home.dc.html`, `My Services.dc.html` top bars).
///
/// * [AppHeader.brand] — the logo mark and wordmark, with trailing actions:
///   the top of a tab root.
/// * [AppHeader.page] — a back control and a title: the top of a pushed
///   screen. The back arrow mirrors under RTL (Flutter's `arrow_back` is
///   direction-aware).
///
/// Sits on the page background with no elevation; a [surface] variant
/// draws white with a bottom divider for provider screens.
///
/// **Place it at the top of the body, not in `Scaffold.appBar`.** A
/// `PreferredSizeWidget` is given a fixed height, and at 200% text a title
/// that wraps would be clipped — `test/features/gallery/` caught exactly
/// that. In the body the header sizes to its content; it handles the status
/// bar inset itself.
class AppHeader extends StatelessWidget {
  const AppHeader.brand({
    super.key,
    this.actions = const [],
    this.leadingSlot,
    this.surface = false,
  }) : title = null,
       onBack = null,
       backLabel = 'Back';

  const AppHeader.page({
    required String this.title,
    super.key,
    this.onBack,
    this.backLabel = 'Back',
    this.actions = const [],
    this.surface = false,
  }) : leadingSlot = null;

  final String? title;
  final VoidCallback? onBack;
  final String backLabel;
  final List<AppHeaderAction> actions;

  /// A widget between the wordmark and the actions (the island selector on
  /// Home). Constrained to what is left of the row.
  final Widget? leadingSlot;
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final brand = title == null;

    return Material(
      color: surface ? colors.surface : colors.background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: surface
              ? Border(
                  bottom: BorderSide(
                    color: colors.borderCard,
                    width: AppSizes.dividerStroke,
                  ),
                )
              : null,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.md + 2,
              AppSpacing.xl,
              AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                if (brand) ...[
                  const _LogoMark(),
                  const SizedBox(width: AppSpacing.sm + 2),
                  const _Wordmark(),
                ] else ...[
                  if (onBack != null)
                    _RoundAction(
                      icon: Icons.arrow_back,
                      label: backLabel,
                      onTap: onBack!,
                    ),
                  if (onBack != null) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title!, style: type.sectionHeading),
                    ),
                  ),
                ],
                if (brand)
                  Expanded(
                    child: leadingSlot == null
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: leadingSlot,
                          ),
                  ),
                for (final a in actions) ...[
                  const SizedBox(width: AppSpacing.sm + 2),
                  _RoundAction(
                    icon: a.icon,
                    label: a.badgeCount == null || a.badgeCount == 0
                        ? a.label
                        : '${a.label}, ${a.badgeCount} new',
                    onTap: a.onTap,
                    badgeCount: a.badgeCount,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.ctaGradient,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: SizedBox.square(
          dimension: AppSizes.avatarMedium,
          child: Center(
            child: Icon(
              Icons.location_on_outlined,
              size: AppSizes.iconLg,
              color: colors.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final style = type.sectionHeading.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.34,
    );
    return Semantics(
      header: true,
      label: 'RaajjePro',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: 'Raajje',
          style: style,
          children: [
            TextSpan(
              text: 'Pro',
              style: style.copyWith(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final showBadge = badgeCount != null && badgeCount! > 0;

    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      focusRadius: AppRadius.pill,
      builder: (context, s) => SizedBox.square(
        dimension: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: s.pressed ? colors.surfaceMuted : colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: Icon(
                    icon,
                    size: AppSizes.iconLg,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
            if (showBadge)
              PositionedDirectional(
                top: -2,
                end: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: colors.background, width: 2),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: Center(
                        child: Text(
                          badgeCount! > 99 ? '99+' : '$badgeCount',
                          style: type.badgeCount,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
