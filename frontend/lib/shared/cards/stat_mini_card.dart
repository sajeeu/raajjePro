import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/cards/app_card.dart';

/// The small metric tile (`My Services.dc.html` stats row): an icon in a
/// 32 dp tinted circle, the number at 18/800, the label at 11/600. Three
/// sit in a row on the provider dashboard.
///
/// [value] `null` renders **"No data yet"** — never a blank, and never a
/// zero that reads worse than no metric (screen-state rule). Pass `'0'`
/// only when zero is the true, meaningful count.
class StatMiniCard extends StatelessWidget {
  const StatMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
    this.iconColor,
    this.iconTint,
    this.noDataLabel = 'No data yet',
  });

  final IconData icon;
  final String label;
  final String? value;

  /// Defaults to the primary accent pair. Category accents are for
  /// categories — a metric uses a system role.
  final Color? iconColor;
  final Color? iconTint;
  final String noDataLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final hasValue = value != null;

    return Semantics(
      label: hasValue ? '$label: $value' : '$label: $noDataLabel',
      excludeSemantics: true,
      child: AppCard(
        radius: AppRadius.tile,
        padding: const EdgeInsetsDirectional.fromSTEB(13, 13, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconTint ?? colors.accentTint,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: Icon(
                    icon,
                    size: 15,
                    color: iconColor ?? colors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 1),
            if (hasValue)
              // A number never breaks across lines; the row reflows instead.
              Text(
                value!,
                style: type.stat,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                noDataLabel,
                style: type.secondary.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            const SizedBox(height: 1),
            Text(label, style: type.caption),
          ],
        ),
      ),
    );
  }
}

/// Lays [StatMiniCard]s out in a row that gives up columns as the OS text
/// size grows, so a number is never broken mid-digit: three across at 100%
/// on a phone, two at ~150%, one at 200%. Use this rather than a bare `Row`
/// of `Expanded` tiles.
class StatMiniCardRow extends StatelessWidget {
  const StatMiniCardRow({
    required this.children,
    super.key,
    this.gap = AppSpacing.sm + 2,
    this.minTileWidth = 110,
  });

  final List<Widget> children;
  final double gap;

  /// The narrowest a tile can be at 100% text and still hold `1,284` and a
  /// one-word label. Scales with the text.
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    final scaledMin = MediaQuery.textScalerOf(context).scale(minTileWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + gap) / (scaledMin + gap)).floor().clamp(
          1,
          children.length,
        );
        final tileWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}
