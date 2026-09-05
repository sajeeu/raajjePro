import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/badges/verification_badge.dart';

/// The avatar (`Components.dc.html` → Avatar). Image when there is one,
/// initials on the accent tint when there is not, and an optional tier
/// badge overlay at the trailing-bottom corner.
///
/// The overlay carries the tier's fill and ◆ — it is a *pointer* to the
/// badge, not a substitute for it. Wherever an avatar shows a tier overlay,
/// the full [VerificationBadge] with its words must be reachable on the
/// same screen; the overlay alone never says "verified".
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    super.key,
    this.imageUrl,
    this.size = AppSizes.avatarLarge,
    this.tier = VerificationTier.none,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final VerificationTier tier;

  /// Up to two initials from the first two words. `Ibrahim Rasheed` → `IR`.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = VerificationBadge.paletteFor(colors, tier);
    final badgeSize = (size * 0.38).clamp(16.0, 24.0);

    Widget disc = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: imageUrl == null
            ? _Initials(name: name, size: size)
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _Initials(name: name, size: size),
              ),
      ),
    );

    if (palette != null) {
      disc = SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            disc,
            PositionedDirectional(
              end: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: SizedBox.square(
                  dimension: badgeSize,
                  child: Center(
                    child: Text(
                      '◆',
                      textScaler: TextScaler.noScaling,
                      style: context.type.pill.copyWith(
                        color: palette.text,
                        fontSize: badgeSize * 0.45,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final spoken = StringBuffer(imageUrl == null ? name : 'Photo of $name');
    if (palette != null) {
      spoken.write(', ${VerificationBadge.nameFor(tier)} tier');
    }
    return Semantics(
      label: spoken.toString(),
      image: imageUrl != null,
      excludeSemantics: true,
      child: disc,
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.accentTint),
      child: Center(
        // Initials are an identity glyph sized to the disc, not running
        // text: they do not follow the OS text scale (the name itself is in
        // the semantics label, and scales wherever it is written out).
        child: Text(
          AppAvatar.initialsOf(name),
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          softWrap: false,
          style: context.type.pill.copyWith(
            color: colors.accentText,
            fontSize: size * 0.31,
            height: 1,
          ),
        ),
      ),
    );
  }
}
