import 'package:flutter/material.dart';

/// Colour tokens, measured from `mockups/design-composer/` (see
/// `frontend/CLAUDE.md` → Design tokens). Reach them with
/// `context.colors` from `app_theme.dart`; never a literal in a widget.
///
/// Every text-on-surface pair here is asserted at WCAG AA (4.5:1) by
/// `test/core/theme/contrast_test.dart`. Seven measured values failed that
/// bar and were replaced — each is noted at its field with the value it
/// replaced, and `docs/decisions/08-phase-1-design-system.md` carries the
/// follow-up for the design project.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryPressed,
    required this.gradientStart,
    required this.onPrimary,
    required this.ink,
    required this.textSecondary,
    required this.textTertiary,
    required this.placeholder,
    required this.background,
    required this.frame,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderCard,
    required this.divider,
    required this.accentTint,
    required this.accentTintPressed,
    required this.accentBorder,
    required this.accentBorderPressed,
    required this.accentText,
    required this.neutralTint,
    required this.neutralBorder,
    required this.neutralText,
    required this.neutralDot,
    required this.success,
    required this.successTint,
    required this.successBorder,
    required this.successText,
    required this.error,
    required this.errorPressed,
    required this.errorTint,
    required this.errorBorder,
    required this.errorText,
    required this.onError,
    required this.warning,
    required this.warningTint,
    required this.warningBorder,
    required this.warningText,
    required this.disabledFill,
    required this.disabledText,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.ratingStar,
    required this.ratingStarStroke,
    required this.ratingStarEmpty,
    required this.guaranteeText,
    required this.guaranteeTint,
    required this.guaranteeBorder,
    required this.scrim,
    required this.bronze,
    required this.silver,
    required this.gold,
  });

  /// The one palette v1 ships. Dark mode is not specified by the plan.
  const AppColors.light()
    : primary = const Color(0xFF2563EB),
      primaryPressed = const Color(0xFF1D4ED8),
      gradientStart = const Color(0xFF5B8DF6),
      onPrimary = const Color(0xFFFFFFFF),
      ink = const Color(0xFF0F1B2D),
      textSecondary = const Color(0xFF5B6B84),
      textTertiary = const Color(0xFF41526B),
      // Measured #9AA9C0 is 2.38:1 on white; a placeholder is still text
      // (plan §Phase 1: AA on all text). #627187 is the lightest slate
      // that clears 4.5:1 on every surface an input sits on.
      placeholder = const Color(0xFF627187),
      background = const Color(0xFFF2F6FB),
      frame = const Color(0xFFDEE7F3),
      surface = const Color(0xFFFFFFFF),
      surfaceMuted = const Color(0xFFF7FAFD),
      border = const Color(0xFFE3EAF3),
      borderCard = const Color(0xFFE9EFF7),
      divider = const Color(0xFFEEF3FA),
      accentTint = const Color(0xFFE8F0FE),
      accentTintPressed = const Color(0xFFDDEAFE),
      accentBorder = const Color(0xFFCDDDFB),
      accentBorderPressed = const Color(0xFFB9CFF7),
      accentText = const Color(0xFF1D4ED8),
      neutralTint = const Color(0xFFEEF3FA),
      neutralBorder = const Color(0xFFE1EAF5),
      neutralText = const Color(0xFF41526B),
      neutralDot = const Color(0xFF8296B3),
      success = const Color(0xFF16A34A),
      successTint = const Color(0xFFE5F6EC),
      successBorder = const Color(0xFFA7DDBB),
      // #16A34A is 3.30:1 on white — an icon colour, never a text colour.
      successText = const Color(0xFF166534),
      error = const Color(0xFFDC2626),
      errorPressed = const Color(0xFFB91C1C),
      errorTint = const Color(0xFFFEF2F2),
      errorBorder = const Color(0xFFF5C6C6),
      errorText = const Color(0xFFB91C1C),
      onError = const Color(0xFFFFFFFF),
      warning = const Color(0xFFD97706),
      warningTint = const Color(0xFFFEF3DC),
      warningBorder = const Color(0xFFF3C77B),
      // The amber-on-white case the plan names: #D97706 is 3.19:1 on
      // white. Text in a warning context uses this, as StatusPill does.
      warningText = const Color(0xFFA15C00),
      disabledFill = const Color(0xFFC6D4EA),
      // 3.02:1 on white — permitted only on disabled controls (WCAG 1.4.3
      // exempts inactive components). Never for a live label.
      disabledText = const Color(0xFF8296B3),
      skeletonBase = const Color(0xFFE8EEF6),
      skeletonHighlight = const Color(0xFFF4F8FC),
      ratingStar = const Color(0xFFF3B23E),
      // Measured strokes #D99A1E (2.44:1) and #C6D4EA (1.60:1) do not
      // separate a filled star from an empty one at the 3:1 graphics bar.
      // The filled stroke takes the gold tier's amber, the empty stroke the
      // disabled grey — both clear 3:1 on white.
      ratingStarStroke = const Color(0xFFB45309),
      ratingStarEmpty = const Color(0xFF8296B3),
      guaranteeText = const Color(0xFF047857),
      guaranteeTint = const Color(0xFFECFDF5),
      guaranteeBorder = const Color(0xFFA7F3D0),
      scrim = const Color(0x8C0F1B2D),
      bronze = const TierPalette(
        fill: Color(0xFFFBEDE3),
        text: Color(0xFF9A5B2D),
        border: Color(0xFFE8C4A0),
        words: Color(0xFF7A4A26),
      ),
      silver = const TierPalette(
        fill: Color(0xFFF1F5F9),
        text: Color(0xFF475569),
        border: Color(0xFFCBD5E1),
        words: Color(0xFF3B4A5E),
      ),
      gold = const TierPalette(
        fill: Color(0xFFFEF3C7),
        text: Color(0xFFB45309),
        border: Color(0xFFFCD34D),
        words: Color(0xFF92400E),
      );

  // Brand
  final Color primary;
  final Color primaryPressed;
  final Color gradientStart;
  final Color onPrimary;

  // Text
  final Color ink;
  final Color textSecondary;
  final Color textTertiary;
  final Color placeholder;

  // Surfaces
  final Color background;
  final Color frame;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderCard;
  final Color divider;

  // Accent (primary tint) — secondary buttons, selected states, info pills
  final Color accentTint;
  final Color accentTintPressed;
  final Color accentBorder;
  final Color accentBorderPressed;
  final Color accentText;

  // Neutral pill
  final Color neutralTint;
  final Color neutralBorder;
  final Color neutralText;
  final Color neutralDot;

  // Semantic
  final Color success;
  final Color successTint;
  final Color successBorder;
  final Color successText;
  final Color error;
  final Color errorPressed;
  final Color errorTint;
  final Color errorBorder;
  final Color errorText;
  final Color onError;
  final Color warning;
  final Color warningTint;
  final Color warningBorder;
  final Color warningText;

  // States
  final Color disabledFill;
  final Color disabledText;
  final Color skeletonBase;
  final Color skeletonHighlight;

  // Rating (from `Rate This Job.dc.html`)
  final Color ratingStar;
  final Color ratingStarStroke;
  final Color ratingStarEmpty;

  // Callback guarantee badge (from `ServiceCard.dc.html`) — the platform's
  // promise, so it has its own green rather than borrowing a category's.
  final Color guaranteeText;
  final Color guaranteeTint;
  final Color guaranteeBorder;

  /// Behind bottom sheets and dialogs.
  final Color scrim;

  // Verification tiers (plan §1e). `none` has no palette: the badge is
  // absent, never a grey chip.
  final TierPalette bronze;
  final TierPalette silver;
  final TierPalette gold;

  /// The primary CTA gradient. The measured stops were 0 / 0.6 / 1.0; the
  /// middle stop moved to 0.4 so that white text anywhere a centred label
  /// can reach clears 4.5:1 (asserted in `contrast_test.dart`). Directional
  /// so the highlight mirrors under RTL.
  LinearGradient get ctaGradient => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [gradientStart, primary, primaryPressed],
    stops: const [0, 0.4, 1],
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Fill · text · border · words for one verification tier. `text` colours
/// the tier name, `words` the tier's fixed public copy beside it.
@immutable
class TierPalette {
  const TierPalette({
    required this.fill,
    required this.text,
    required this.border,
    required this.words,
  });

  final Color fill;
  final Color text;
  final Color border;
  final Color words;
}
