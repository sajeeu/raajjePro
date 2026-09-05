import 'package:flutter/material.dart';

/// The twelve category accents (style guide → Tokens → Category accents).
///
/// Keyed by a hue token, not by category: `Category` is seeded with a
/// `color token` (plan §Phase 4) and the client resolves it here, so a
/// thirteenth category added through the API gets a colour without a
/// rebuild. Which category carries which token is the seed's business —
/// the comments below record the pairing the prototypes used.
///
/// Each accent has three parts. `tint` is the ~8% wash behind an icon
/// chip; `icon` is the full hue for the glyph (asserted ≥ 3:1 on its tint);
/// `text` is the same hue one step darker for any label rendered in the
/// category colour (asserted ≥ 4.5:1 on white and on the tint). The
/// prototypes used the icon hue for labels too — several of those fall
/// under 4.5:1 (Electrical 3.19, Home Repairs 2.94), which is why `text`
/// exists. Never borrow an accent for a non-category meaning.
enum AccentToken {
  indigo, // Cleaning
  emerald, // Plumbing
  amber, // Electrical
  blue, // AC Repair
  pink, // Beauty
  orange, // Photography
  green, // Pest Control
  sky, // Appliance Repair
  burntOrange, // Moving
  violet, // Fitness
  yellow, // Home Repairs
  cyan, // Boat Charter
}

@immutable
class CategoryAccent {
  const CategoryAccent({
    required this.tint,
    required this.icon,
    required this.text,
  });

  final Color tint;
  final Color icon;
  final Color text;
}

abstract final class CategoryAccents {
  static const Map<AccentToken, CategoryAccent> byToken = {
    AccentToken.indigo: CategoryAccent(
      tint: Color(0xFFEEF2FF),
      icon: Color(0xFF4F46E5),
      text: Color(0xFF4338CA),
    ),
    AccentToken.emerald: CategoryAccent(
      tint: Color(0xFFECFDF5),
      icon: Color(0xFF059669),
      text: Color(0xFF047857),
    ),
    AccentToken.amber: CategoryAccent(
      tint: Color(0xFFFFFBEB),
      icon: Color(0xFFD97706),
      text: Color(0xFF92400E),
    ),
    AccentToken.blue: CategoryAccent(
      tint: Color(0xFFEFF6FF),
      icon: Color(0xFF2563EB),
      text: Color(0xFF1D4ED8),
    ),
    AccentToken.pink: CategoryAccent(
      tint: Color(0xFFFDF2F8),
      icon: Color(0xFFDB2777),
      text: Color(0xFFBE185D),
    ),
    AccentToken.orange: CategoryAccent(
      tint: Color(0xFFFFF7ED),
      icon: Color(0xFFEA580C),
      text: Color(0xFFC2410C),
    ),
    AccentToken.green: CategoryAccent(
      tint: Color(0xFFF0FDF4),
      icon: Color(0xFF16A34A),
      text: Color(0xFF15803D),
    ),
    AccentToken.sky: CategoryAccent(
      tint: Color(0xFFF0F9FF),
      icon: Color(0xFF0284C7),
      text: Color(0xFF0369A1),
    ),
    AccentToken.burntOrange: CategoryAccent(
      tint: Color(0xFFFFF7ED),
      icon: Color(0xFFC2410C),
      text: Color(0xFF9A3412),
    ),
    AccentToken.violet: CategoryAccent(
      tint: Color(0xFFF5F3FF),
      icon: Color(0xFF7C3AED),
      text: Color(0xFF6D28D9),
    ),
    // Measured icon #CA8A04 is 2.84:1 on its tint — the only accent whose
    // glyph failed the 3:1 graphics bar — so the icon steps to yellow-700.
    AccentToken.yellow: CategoryAccent(
      tint: Color(0xFFFEFCE8),
      icon: Color(0xFFA16207),
      text: Color(0xFF854D0E),
    ),
    AccentToken.cyan: CategoryAccent(
      tint: Color(0xFFECFEFF),
      icon: Color(0xFF0891B2),
      text: Color(0xFF0E7490),
    ),
  };

  /// For a category whose token the client does not know (a new one seeded
  /// after this build shipped). Neutral, so it never impersonates another.
  static const CategoryAccent fallback = CategoryAccent(
    tint: Color(0xFFEEF3FA),
    icon: Color(0xFF41526B),
    text: Color(0xFF41526B),
  );

  /// Resolves a seeded token name (`'emerald'`) to its accent, falling back
  /// to [fallback] for anything unknown.
  static CategoryAccent resolve(String? token) {
    for (final t in AccentToken.values) {
      if (t.name == token) return byToken[t]!;
    }
    return fallback;
  }
}
