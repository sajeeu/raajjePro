import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// One of the four tiles under "My bookings" (`Profile.dc.html`, Round 48 §2).
class BookingTile {
  const BookingTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.glyph,
  });

  /// The tab this tile names on §Phase 17's My Bookings — All · Upcoming ·
  /// Active · Completed, and nothing else. Round 48 §2 removed `Cancelled`
  /// and renamed `Waiting`, because the grid was naming two views the app
  /// does not have; and whether `Cancelled` should exist at all was flagged
  /// there as a product question, not answered.
  final String label;
  final IconData icon;

  /// The disc fill and the glyph on it. Round 48 §3 aligned these with
  /// `StatusPill`'s own colour for each state, so a customer seeing a tile
  /// and then a pill on the next screen reads the same colour twice.
  final Color Function(AppColors) tint;
  final Color Function(AppColors) glyph;
}

/// The four tiles, in the prototype's order.
///
/// `All` takes the system grey because it is not a state at all; `Upcoming`
/// is green because its bookings are `confirmed`; `Active` amber because it
/// holds `awaiting_payment`; `Completed` blue because that is `completed`.
/// Every one of the eight colours is an existing token — none was added.
const bookingTiles = <BookingTile>[
  BookingTile(
    label: 'All',
    icon: Icons.format_list_bulleted_rounded,
    tint: _neutralTint,
    glyph: _neutralGlyph,
  ),
  BookingTile(
    label: 'Upcoming',
    icon: Icons.event_available_outlined,
    tint: _successTint,
    glyph: _successGlyph,
  ),
  BookingTile(
    label: 'Active',
    icon: Icons.schedule_rounded,
    tint: _warningTint,
    glyph: _warningGlyph,
  ),
  BookingTile(
    label: 'Completed',
    icon: Icons.check_circle_outline_rounded,
    tint: _accentTint,
    glyph: _primaryGlyph,
  ),
];

Color _neutralTint(AppColors c) => c.neutralTint;
Color _neutralGlyph(AppColors c) => c.neutralDot;
Color _successTint(AppColors c) => c.successTint;
Color _successGlyph(AppColors c) => c.success;
Color _warningTint(AppColors c) => c.warningTint;
Color _warningGlyph(AppColors c) => c.warning;
Color _accentTint(AppColors c) => c.accentTint;
Color _primaryGlyph(AppColors c) => c.primary;

/// The 2 × 2 block of booking shortcuts.
///
/// Two columns, not three: four tiles in a three-across grid leave an orphan,
/// and a four-across row does not survive the 200% text-scale rule (Round 48
/// §2). Each tile keeps its own destination — Round 48's whole point was that
/// four labels sharing one destination is a defect — so until §Phase 17
/// builds My Bookings, each lands on a placeholder that names *its* tab
/// rather than a generic one.
class BookingTilesCard extends StatelessWidget {
  const BookingTilesCard({required this.onSelected, super.key});

  final void Function(BookingTile tile) onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadius.feature,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg + 2,
      ),
      child: Column(
        children: [
          for (var row = 0; row < 2; row += 1) ...[
            if (row > 0) const SizedBox(height: AppSpacing.lg + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 2; col += 1)
                  Expanded(
                    child: _Tile(
                      tile: bookingTiles[row * 2 + col],
                      onTap: () => onSelected(bookingTiles[row * 2 + col]),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.onTap});

  final BookingTile tile;
  final VoidCallback onTap;

  static const disc = 52.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      onTap: onTap,
      semanticLabel: '${tile.label} bookings',
      focusRadius: AppRadius.tile,
      builder: (context, s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              color: tile.tint(colors),
              borderRadius: AppRadius.circular(AppRadius.tile),
            ),
            alignment: Alignment.center,
            child: Icon(tile.icon, size: 22, color: tile.glyph(colors)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tile.label,
            textAlign: TextAlign.center,
            style: type.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
