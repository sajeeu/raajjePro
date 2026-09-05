import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';

/// Spacing scale, in logical pixels. Use these — never a bare number in a
/// widget. Every inset in this app is an `EdgeInsetsDirectional` (plan
/// §Phase 1, RTL-ready): `test/core/rtl_lint_test.dart` fails the build on
/// the absolute `EdgeInsets` constructors and friends.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal screen padding — 20, consistently.
  static const double screen = xl;

  static const EdgeInsetsDirectional screenInsets =
      EdgeInsetsDirectional.symmetric(horizontal: screen);
}

/// Corner radii, by use across all 61 prototypes (`frontend/CLAUDE.md` →
/// Geometry): 20 cards · 16 buttons and small cards · 999 pills · 14 inputs ·
/// 12 · 13 compact buttons · 24 feature cards · 18 tiles · 8 and 10 · 28 sheets.
abstract final class AppRadius {
  /// Text-line skeleton bones.
  static const double xxs = 6;
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 12;
  static const double compact = 13;
  static const double input = 14;
  static const double button = 16;
  static const double card = 16;
  static const double tile = 18;
  static const double panel = 20;
  static const double feature = 24;
  static const double sheet = 28;

  /// Pills, avatars, dots.
  static const double pill = 999;

  static BorderRadius circular(double r) => BorderRadius.circular(r);
}

/// Fixed dimensions. Heights here are *minimums* — text scales, and a
/// control grows with it rather than clipping.
abstract final class AppSizes {
  /// The accessibility floor for anything tappable (plan §Phase 1).
  static const double touchTarget = 48;

  static const double inputHeight = 52;
  static const double ctaHeight = 54;
  static const double secondaryButtonHeight = 52;
  static const double compactButtonHeight = 44;
  static const double iconButtonSize = 44;
  static const double chipHeight = 38;
  static const double staticChipHeight = 28;
  static const double checkbox = 26;

  static const double navPillWidth = 52;
  static const double navPillHeight = 30;
  static const double navIcon = 19;

  static const double avatarLarge = 52;
  static const double avatarMedium = 36;
  static const double avatarSmall = 22;

  static const double dividerStroke = 1;
  static const double inputStroke = 1.5;
  static const double selectedStroke = 2;

  /// Glyph sizes. `sm` inside pills and chips, `md` in rows and inputs,
  /// `lg` in headers and buttons.
  static const double iconSm = 12;
  static const double iconMd = 16;
  static const double iconLg = 18;
}

/// The three shadows the prototypes use. Colours are taken from the ink and
/// the brand colours so they stay coherent if a palette ever changes.
abstract final class AppShadows {
  /// `0 1px 3px rgba(15,27,45,.05)` — every card.
  static List<BoxShadow> card(Color ink) => [
    BoxShadow(
      color: ink.withValues(alpha: 0.05),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  /// `0 10px 24px rgba(37,99,235,.32)` — the primary CTA (and the
  /// destructive one, in its own colour at .28).
  static List<BoxShadow> cta(Color color, {double alpha = 0.32}) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  /// `0 2px 6px rgba(15,27,45,.12)` — a control floating over an image.
  static List<BoxShadow> overlay(Color ink) => [
    BoxShadow(
      color: ink.withValues(alpha: 0.12),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}
