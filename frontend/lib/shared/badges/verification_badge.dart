import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/verification_tier.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

export 'package:raajjepro/core/domain/verification_tier.dart';

enum VerificationBadgeSize {
  /// The compact pill on cards: `◆ Gold`.
  chip,

  /// The pill with the tier's words: `◆ Gold  ID checked, registered trade`.
  full,
}

/// The verification badge (`VerificationBadge.dc.html`; plan §1e). Three
/// tiers, each with its own fixed public copy — **the copy lives here and
/// nowhere else**, so it can never drift between screens. A bare "Verified"
/// is never rendered: a customer would read it as a track record, not as an
/// ID check.
///
/// [VerificationTier.none] renders **nothing** — not an empty pill, not a
/// grey "unverified" chip, no reserved space. Absence is the signal, and a
/// provider at `none` is still fully listed and bookable.
///
/// The tier reflects verification checks, not payment: it is untouched by
/// subscription state.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({
    required this.tier,
    super.key,
    this.size = VerificationBadgeSize.chip,
  });

  final VerificationTier tier;
  final VerificationBadgeSize size;

  /// The tier's public copy, verbatim from plan §1e. `none` has none.
  static String? wordsFor(VerificationTier tier) => switch (tier) {
    VerificationTier.bronze => 'ID checked by RaajjePro',
    VerificationTier.silver => 'ID checked, work verified',
    VerificationTier.gold => 'ID checked, registered trade',
    VerificationTier.none => null,
  };

  static String nameFor(VerificationTier tier) => switch (tier) {
    VerificationTier.bronze => 'Bronze',
    VerificationTier.silver => 'Silver',
    VerificationTier.gold => 'Gold',
    VerificationTier.none => '',
  };

  static TierPalette? paletteFor(AppColors colors, VerificationTier tier) =>
      switch (tier) {
        VerificationTier.bronze => colors.bronze,
        VerificationTier.silver => colors.silver,
        VerificationTier.gold => colors.gold,
        VerificationTier.none => null,
      };

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(context.colors, tier);
    if (palette == null) return const SizedBox.shrink();

    final name = nameFor(tier);
    final words = wordsFor(tier)!;
    final type = context.type;

    final full = size == VerificationBadgeSize.full;
    final nameStyle = full
        ? type.tierWords.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w700,
          )
        : type.pillSmall.copyWith(color: palette.text);

    return Semantics(
      label: '$name — $words',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fill,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(
            full ? AppRadius.md : AppRadius.pill,
          ),
        ),
        child: Padding(
          padding: full
              ? const EdgeInsetsDirectional.symmetric(
                  horizontal: 14,
                  vertical: AppSpacing.sm,
                )
              : const EdgeInsetsDirectional.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('◆ $name', style: nameStyle),
              if (full) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    words,
                    style: type.tierWords.copyWith(color: palette.words),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
