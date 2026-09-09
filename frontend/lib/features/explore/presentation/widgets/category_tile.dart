import 'package:flutter/material.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/core/theme/category_icons.dart';
import 'package:raajjepro/shared/shared.dart';

/// One tile of the Explore grid (`Discovery.dc.html` → Explore).
///
/// Both the colour and the glyph come from tokens the seed wrote and this
/// widget resolves, each with a neutral fallback — which is what makes the
/// Done-when's thirteenth category render without a rebuild rather than
/// crash or leave a hole.
///
/// The tile carries the name only. It deliberately shows **no emergency
/// marker**: Round 23 removed that from cards and from search, because
/// dispatch broadcasts to every eligible provider and never targets one, so
/// the marker advertised an action that does not exist.
class CategoryTile extends StatelessWidget {
  const CategoryTile({required this.category, this.onTap, super.key});

  final ServiceCategory category;

  /// Null in this build: category results are Phase 15's surface.
  final VoidCallback? onTap;

  /// The prototype's icon chip: 56 dp, 16 dp radius, the accent's tint behind
  /// the accent's icon hue.
  static const double chip = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final accent = CategoryAccents.resolve(category.colorToken);

    return Pressable(
      onTap: onTap,
      semanticLabel: category.name,
      focusRadius: AppRadius.panel,
      // The grid cell is already taller than the 48 dp floor; without this the
      // Pressable's minimum would fight the cell's own height.
      minSize: 0,
      // `SizedBox.expand`, or the tile paints narrower than its cell. The grid
      // constrains each cell tightly to 116 dp, but `Pressable` wraps its
      // child in `Center(widthFactor: 1, heightFactor: 1)`, which passes
      // *loose* constraints down — so the surface shrink-wrapped its label and
      // "Appliance Repair" drew visibly wider than "Fitness". The prototype
      // never says the tile fills its cell because a block `<div>` already
      // does; Flutter has no such default. Same cause as the Register role
      // cards.
      builder: (context, s) => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(
              color: s.pressed || s.hovered
                  ? colors.accentBorder
                  : colors.borderCard,
            ),
            boxShadow: AppShadows.card(colors.ink),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.sm,
              AppSpacing.lg + 2,
              AppSpacing.sm,
              AppSpacing.md + 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.tint,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: SizedBox.square(
                    dimension: chip,
                    child: Center(
                      child: Icon(
                        CategoryIcons.resolve(category.iconIdentifier),
                        size: 22,
                        color: accent.icon,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                Flexible(
                  child: Text(
                    category.name,
                    textAlign: TextAlign.center,
                    style: type.secondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
