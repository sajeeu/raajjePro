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
  static const double sm2 = 10;
  static const double md = 12;
  static const double md2 = 14;
  static const double lg = 16;
  static const double lg2 = 18;
  static const double xl = 20;
  static const double xl2 = 22;
  static const double xxl = 24;
  static const double xxl2 = 26;
  static const double xxxl = 32;

  // 🔧 **The half-steps, named 2026-09-14.** The scale above was the 4-ish
  // one; the app's real rhythm is a 2 dp step from 8 to 26, and 121 call
  // sites across 44 files were reaching the unnamed halves by arithmetic —
  // `AppSpacing.sm + 2` fifty-four times, `lg + 2` twenty-seven, `md + 2`
  // thirty, `xxl - 2` ten. Every one of those resolved to a value this scale
  // simply had no name for.
  //
  // That is the same failure Round 51 fixed in motion, in spacing form: a
  // literal sitting between two tokens, where a reader cannot tell whether it
  // is a considered value or a nudge. Naming them changes no pixel — the
  // numbers are identical — and it removes the arithmetic, which is what let
  // ±1 drift in beside ±2 (there are still 46 odd-valued sites; they are
  // off-grid rather than half-steps, and belong to a design round rather than
  // a rename).

  /// 🔧 **Traced, not chosen — 2026-09-14.** The nine values below are not on
  /// the scale and are not meant to be. They come from the artboards, which
  /// were drawn on a 1 dp grid and never had a spacing system: 13 px appears
  /// 172 times across the 61 prototypes, 11 px 159 times, 9 px 112. Flutter
  /// reproduced them faithfully, then hid them behind arithmetic —
  /// `AppSpacing.md + 1` — where they read as a considered half-step rather
  /// than a traced measurement.
  ///
  /// The `n` prefix is the whole point: a call site now says *this number was
  /// measured off an artboard*, which is a different claim from `md`. Naming
  /// them changes no pixel and removes the last arithmetic; it does not make
  /// them part of the vocabulary.
  ///
  /// **Rationalising them is a design round's job, not a rename's** — it
  /// means moving ~750 values across 61 artboards, and the app would have to
  /// follow rather than lead. When that lands, this group is deleted.
  static const double n5 = 5;
  static const double n7 = 7;
  static const double n9 = 9;
  static const double n11 = 11;
  static const double n13 = 13;
  static const double n15 = 15;
  static const double n17 = 17;
  static const double n28 = 28;
  static const double n34 = 34;

  /// 🔧 **Added 2026-09-15**, with the same provenance as the rest of this
  /// group: 56 px appears 25 times across the artboards and 28 px is the most
  /// common bottom padding in them, at 53. Eight call sites reached those two
  /// values as `AppSpacing.xxl + AppSpacing.xxs` and `xxl + xxxl` — arithmetic
  /// the ratchet did not catch, because it looked for a token plus a *number*
  /// and these are a token plus a token. Same defect: a reader cannot tell 28
  /// traced off an artboard from 24 with a nudge on it.
  static const double n56 = 56;

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

  /// The numbered step bullet in a "what happens next" list
  /// (`Request a Time.dc.html`, 22 dp). Added by §Phase 17.2 — the scale had
  /// no 22 outside [avatarSmall], and a step number is not an avatar.
  static const double stepBullet = 22;

  /// The icon disc atop a settings/confirmation card (`Account Settings.dc.html`).
  static const double iconDisc = 46;

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
