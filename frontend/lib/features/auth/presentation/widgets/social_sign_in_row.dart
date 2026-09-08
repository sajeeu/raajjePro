import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The four third-party buttons (`Sign In.dc.html`). Apple is present because
/// App Review requires it wherever another sign-in is offered (the Round 16
/// mockup audit amended the plan's three-stub list to four). Glyphs are
/// letters, never hotlinked brand assets. Every provider is a stub in v1: the
/// tap surfaces the API's own "not available yet" notice inline (plan §6 —
/// real social auth is post-v1).
///
/// **Layout, measured from the prototype rather than inferred:** a two-column
/// grid — `grid-template-columns: 177px 177px; gap: 10px` — of 50 dp pills,
/// each carrying its glyph disc *and the provider's name*. An earlier version
/// rendered a single row of four bare 48 dp circles showing only `G`, `A`,
/// `f`, `V`; the names were already in [providers] and were used for the
/// semantic label while being dropped from the screen. Two of those glyphs
/// are not guessable — `A` reads as neither Apple nor anything else, and a
/// lower-case `f` is only Facebook if you already knew.
///
/// The columns are [Expanded] rather than fixed at 177 dp: the prototype's
/// number is what 177 works out to inside a 412 dp frame at 24 dp page
/// padding, and hardcoding it would break on any other width.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({required this.onTap, super.key});
  final void Function(String provider) onTap;

  /// Id, name, glyph, and the glyph's colour — each provider's own brand
  /// colour, taken from the prototype's computed styles. These are literals
  /// rather than palette tokens on purpose: they belong to Google, Meta and
  /// Rakuten, not to this design system, so they must not become part of a
  /// palette that a future theme change would sweep. A `null` means the
  /// glyph takes `colors.ink`, which is what the prototype uses for Apple
  /// (`#0F1B2D`, the same value as the token).
  static const providers = <(String, String, String, Color?)>[
    ('google', 'Google', 'G', Color(0xFF4285F4)),
    ('apple', 'Apple', 'A', null),
    ('facebook', 'Facebook', 'f', Color(0xFF1877F2)),
    ('viber', 'Viber', 'V', Color(0xFF7360F2)),
  ];

  /// `gap: 10px` in the prototype's grid, on both axes.
  static const _gap = 10.0;

  /// The pill's own height, from the prototype. Between
  /// `AppSizes.compactButtonHeight` (44) and `secondaryButtonHeight` (52), so
  /// neither token fits and the measured value stands.
  static const _pillHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < providers.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
      rows.add(
        Row(
          children: [
            Expanded(
              child: _SocialButton(provider: providers[i], onTap: onTap),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: i + 1 < providers.length
                  ? _SocialButton(provider: providers[i + 1], onTap: onTap)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.provider, required this.onTap});

  final (String, String, String, Color?) provider;
  final void Function(String provider) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final (id, name, glyph, brand) = provider;

    return Pressable(
      semanticLabel: 'Continue with $name',
      onTap: () => onTap(id),
      focusRadius: AppRadius.input,
      builder: (context, state) => Container(
        height: SocialSignInRow._pillHeight,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: colors.border,
            width: AppSizes.dividerStroke,
          ),
          boxShadow: AppShadows.card(colors.ink),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The 24 dp glyph disc, page-coloured, from the prototype.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.background,
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: type.tierWords.copyWith(
                  color: brand ?? colors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 9),
            // The prototype sets this label at weight 400, which is outside
            // this app's type scale (Inter 500–800, §Phase 1). `helper` is
            // the scale's 13 dp entry and is used instead.
            Text(name, style: type.helper.copyWith(color: colors.ink)),
          ],
        ),
      ),
    );
  }
}
