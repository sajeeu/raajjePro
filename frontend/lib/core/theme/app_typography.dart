import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_colors.dart';

/// Type roles, Inter throughout (see `docs/decisions/08-phase-1-design-system.md`
/// for why not Plus Jakarta Sans). The 34 sizes and five weights the
/// prototypes use (`frontend/CLAUDE.md` → Type) are rationalised to these
/// roles; nothing here is lighter than 500 and no UI label is lighter than
/// 600. **Weight 750 resolves to 700 everywhere** — Flutter has no `w750`,
/// and 700 keeps section headings visibly lighter than the 800 screen title
/// they sit under.
///
/// Sizes are logical pixels before scaling — `Text` applies
/// `MediaQuery.textScaler` itself, which is why no widget in this app puts a
/// fixed height around text.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.screenTitle,
    required this.sectionHeading,
    required this.cardTitle,
    required this.body,
    required this.bodyStrong,
    required this.secondary,
    required this.caption,
    required this.overline,
    required this.button,
    required this.buttonSmall,
    required this.price,
    required this.stat,
    required this.pill,
    required this.pillSmall,
    required this.navLabel,
    required this.badgeCount,
    required this.helper,
    required this.tierWords,
  });

  factory AppTypography.inter(AppColors c) {
    const family = 'Inter';
    // Tabular figures so a price or a rating does not jitter as it changes.
    const tabular = [FontFeature.tabularFigures()];
    return AppTypography(
      screenTitle: TextStyle(
        fontFamily: family,
        fontSize: 25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
        color: c.ink,
      ),
      sectionHeading: TextStyle(
        fontFamily: family,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.17,
        height: 1.3,
        color: c.ink,
      ),
      cardTitle: TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: c.ink,
      ),
      body: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
        color: c.textTertiary,
      ),
      bodyStrong: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: c.ink,
      ),
      secondary: TextStyle(
        fontFamily: family,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: c.textSecondary,
      ),
      caption: TextStyle(
        fontFamily: family,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: c.textSecondary,
      ),
      overline: TextStyle(
        fontFamily: family,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.66,
        height: 1.3,
        color: c.textSecondary,
      ),
      button: const TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      buttonSmall: const TextStyle(
        fontFamily: family,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      price: TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.16,
        height: 1.3,
        color: c.ink,
        fontFeatures: tabular,
      ),
      stat: TextStyle(
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.36,
        height: 1.3,
        color: c.ink,
        fontFeatures: tabular,
      ),
      pill: const TextStyle(
        fontFamily: family,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      pillSmall: const TextStyle(
        fontFamily: family,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      navLabel: TextStyle(
        fontFamily: family,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: c.textSecondary,
      ),
      badgeCount: TextStyle(
        fontFamily: family,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        height: 1,
        color: c.onPrimary,
        fontFeatures: tabular,
      ),
      helper: TextStyle(
        fontFamily: family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: c.textSecondary,
      ),
      tierWords: const TextStyle(
        fontFamily: family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    );
  }

  /// 25 / 800, tight. One per screen.
  final TextStyle screenTitle;

  /// 17 / 700. Section headings inside a screen.
  final TextStyle sectionHeading;

  /// 15 / 700. Card and row titles.
  final TextStyle cardTitle;

  /// 14 / 500. Running copy.
  final TextStyle body;

  /// 14 / 600, ink. Field values, emphasised copy.
  final TextStyle bodyStrong;

  /// 12.5 / 600, secondary colour. Helper and supporting lines.
  final TextStyle secondary;

  /// 11.5 / 600, secondary colour. Metadata and footnotes.
  final TextStyle caption;

  /// 11 / 800, +.06em. Uppercase section labels — apply `toUpperCase()`
  /// at the call site so screen readers still get the words.
  final TextStyle overline;

  /// 15 / 700. Primary, secondary and destructive buttons. No colour —
  /// the button supplies it.
  final TextStyle button;

  /// 13.5 / 700. Compact buttons (empty-state action, header CTA).
  final TextStyle buttonSmall;

  /// 16 / 800, tabular. Prices.
  final TextStyle price;

  /// 18 / 800, tabular. The number on a [StatMiniCard].
  final TextStyle stat;

  /// 11.5 / 800. Status pills and chips. No colour — the pill supplies it.
  final TextStyle pill;

  /// 9.5 / 800. The compact tier chip on a card. No colour.
  final TextStyle pillSmall;

  /// 10.5 / 700. Bottom-navigation labels.
  final TextStyle navLabel;

  /// 10 / 800, tabular, on primary. The unread count on a header action.
  final TextStyle badgeCount;

  /// 13 / 600, secondary. The message under an input — error or guidance.
  final TextStyle helper;

  /// 13 / 600. The tier's words in a full verification badge. No colour —
  /// the tier palette supplies it.
  final TextStyle tierWords;

  @override
  AppTypography copyWith() => this;

  @override
  AppTypography lerp(AppTypography? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
