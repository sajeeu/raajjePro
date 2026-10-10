import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/public/public_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/core/theme/category_icons.dart';
import 'package:raajjepro/shared/badges/verification_badge.dart';
import 'package:raajjepro/shared/motion/pressable.dart';
import 'package:raajjepro/shared/toggles/listing_save_heart.dart';
import 'package:raajjepro/shared/toggles/save_heart_toggle.dart';

/// The thumbnail column of the full card (`ServiceCard.dc.html`, variant
/// `full`): 96 wide, never shorter than 112. A picture's frame, not a rhythm
/// step, so neither is a spacing token.
const double _thumbWidth = 96;
const double _thumbMinHeight = 112;

/// The customer-facing service card — `ServiceCard.dc.html`, the **full**
/// variant (a horizontal row: thumbnail, then the text). Built by §Phase 13 for
/// the provider profile's listings grid, which is its first consumer; §Phase
/// 15's results and §Phase 16's Home rows are the next, which is why it lives
/// in `shared/` rather than in the profile feature. Not to be confused with
/// `features/my_services/…/service_card.dart`, the provider's own card.
///
/// ## What it promises, and what it will not
///
/// - **The booking mode on every card** — "Pick a time" / "Request a time"
///   (§1c, Round 44), so a customer is never unsure which wait they are in.
/// - **The mode's second signal** (Round 23): the next open time for `slot`,
///   the median response time for `request` — and below §1f's floor, "New
///   provider" rather than a figure. There is **no emergency marker** on any
///   card, ever.
/// - **The callback badge only where the server said so** —
///   [PublicListingCard.callbackGuarantee] is already `offered &&
///   category.callbackEligible` (Round 28). The prototype re-derives it from a
///   category-name table; this does not, because a hardcoded list drifts.
///
/// ## Why the heart is not inside the tap target
///
/// `Pressable` excludes its child's semantics (`frontend/CLAUDE.md`), so a
/// heart *inside* a tappable card would vanish from the semantics tree. The
/// card's tap is laid **under** the heart instead, as a sibling. 🔧 **§Phase
/// 14 wired it**: the heart is a [ListingSaveHeart], which reads and writes
/// the app's one saved state, so this card needs nothing passed in for it.
///
/// 🔧 **§Phase 15 adds [sponsored]**, which draws the prototype's `Sponsored`
/// pill on the thumbnail: "any paid influence on ordering carries a visible
/// 'Sponsored' label". It is the server's fact about this result, so the card
/// never decides it. It is also spoken, because a label only a sighted reader
/// gets is not a visible label for everyone.
class PublicServiceCard extends StatelessWidget {
  const PublicServiceCard({
    required this.listing,
    required this.providerName,
    required this.providerTier,
    required this.providerConduct,
    required this.now,
    required this.onTap,
    this.sponsored = false,
    super.key,
  });

  final PublicListingCard listing;

  /// Priority placement moved this result up (§Phase 15). Only search sets it.
  final bool sponsored;
  final String providerName;
  final VerificationTier providerTier;

  /// Read only for the "New provider" wording below §1f's floor.
  final PublicConduct providerConduct;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final price = priceHeadline(listing.pricing);
    final mode = bookingCta(listing.bookingMode);
    final summary = [
      if (sponsored) 'Sponsored',
      listing.name,
      'by $providerName',
      '${price.big}${price.unit}',
      mode,
    ].join(', ');

    return Stack(
      children: [
        Pressable(
          semanticLabel: summary,
          onTap: onTap,
          focusRadius: AppRadius.panel,
          builder: (context, state) => DecoratedBox(
            decoration: BoxDecoration(
              color: state.pressed ? colors.surfaceMuted : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              border: Border.all(color: colors.borderCard),
              boxShadow: AppShadows.card(colors.ink),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md2),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Thumb(listing: listing, sponsored: sponsored),
                    const SizedBox(width: AppSpacing.md2),
                    Expanded(
                      child: _Text(
                        listing: listing,
                        providerName: providerName,
                        providerTier: providerTier,
                        providerConduct: providerConduct,
                        now: now,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: AppSpacing.md2,
          end: AppSpacing.md2,
          child: ListingSaveHeart(
            listingId: listing.id,
            listingName: listing.name,
            style: SaveHeartStyle.flat,
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.listing, required this.sponsored});

  final PublicListingCard listing;
  final bool sponsored;

  @override
  Widget build(BuildContext context) {
    final accent = CategoryAccents.resolve(listing.category.colorToken);
    final glyph = Icon(
      CategoryIcons.resolve(listing.category.iconIdentifier),
      size: AppSpacing.n34,
      color: accent.icon,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _thumbMinHeight),
      child: Container(
        width: _thumbWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: accent.tint,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: listing.coverUrl == null
                  ? glyph
                  : Image.network(
                      listing.coverUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      // An expired signed URL is a wash, not a broken-image glyph.
                      errorBuilder: (context, error, stack) => glyph,
                    ),
            ),
            if (sponsored)
              const PositionedDirectional(
                top: AppSpacing.xs,
                start: AppSpacing.xs,
                child: _SponsoredPill(),
              ),
          ],
        ),
      ),
    );
  }
}

/// `ServiceCard.dc.html`'s full-variant `Sponsored` pill, drawn on the photo
/// beside the platform's other marker. The card's own semantic label already
/// says it, so the pill adds no second announcement.
class _SponsoredPill extends StatelessWidget {
  const _SponsoredPill();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.n7,
            vertical: AppSpacing.xxs,
          ),
          child: Text(
            'Sponsored',
            style: context.type.pillSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({
    required this.listing,
    required this.providerName,
    required this.providerTier,
    required this.providerConduct,
    required this.now,
  });

  final PublicListingCard listing;
  final String providerName;
  final VerificationTier providerTier;
  final PublicConduct providerConduct;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final accent = CategoryAccents.resolve(listing.category.colorToken);
    final price = priceHeadline(listing.pricing);
    final average = averageText(listing.rating);
    final areas = listing.serviceAreas;
    final signal = _signal();
    final slot = listing.bookingMode == BookingMode.slot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The heart sits over this row's trailing edge (see the card); this
        // keeps the title from running under it.
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpacing.n34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                listing.name,
                style: type.cardTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      providerName,
                      style: type.secondary.copyWith(
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (providerTier != VerificationTier.none) ...[
                    const SizedBox(width: AppSpacing.n7),
                    VerificationBadge(tier: providerTier),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.n7),
        Wrap(
          spacing: AppSpacing.sm2,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (average != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: AppSizes.iconSm,
                    color: colors.ratingStar,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    '$average (${listing.rating.reviewCount})',
                    style: type.secondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            if (areas.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: AppSizes.iconSm,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  // The server's own `displayName`: an ambiguous island
                  // carries its atoll code, and nothing here rebuilds that.
                  Text(
                    areas.length == 1
                        ? areas.first.displayName
                        : '${areas.first.displayName} +${areas.length - 1}',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            Text(
              listing.category.name.toUpperCase(),
              style: type.overline.copyWith(color: accent.text),
            ),
          ],
        ),
        const Spacer(),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: colors.divider),
        const SizedBox(height: AppSpacing.n9),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: price.big,
                  style: type.price,
                  children: [
                    if (price.unit.isNotEmpty)
                      TextSpan(
                        text: price.unit,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ModeChip(label: bookingCta(listing.bookingMode), slot: slot),
          ],
        ),
        if (signal != null || listing.callbackGuarantee) ...[
          const SizedBox(height: AppSpacing.n7),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (signal != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: AppSizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.n5),
                    Flexible(
                      child: Text(
                        signal,
                        style: type.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              if (listing.callbackGuarantee) const _CallbackBadge(),
            ],
          ),
        ],
      ],
    );
  }

  /// The mode-appropriate second signal (Round 23), or null where there is
  /// nothing true to say. Never a zero, never a label.
  String? _signal() => switch (listing.secondSignal) {
    NextOpen(:final at) =>
      at == null ? null : 'Next: ${nextOpenPhrase(at, now)}',
    ResponseTime(:final medianSeconds) =>
      medianSeconds != null
          ? 'Usually replies in ${responseTimePhrase(medianSeconds)}'
          // Below the floor there is no figure. "New provider" is said only
          // where it is true — see `jobsLine`.
          : providerConduct.jobsCompletedCount < conductFloor
          ? 'New provider'
          : null,
  };
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.slot});

  final String label;
  final bool slot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = slot ? colors.accentText : colors.textTertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: slot ? colors.accentTint : colors.neutralTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.n9,
          vertical: AppSpacing.n5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              slot ? Icons.schedule_rounded : Icons.calendar_month_outlined,
              size: AppSizes.iconSm,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.n5),
            Flexible(
              child: Text(
                label,
                style: context.type.pill.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The callback guarantee's card badge (§1h, Round 23). RaajjePro enforces
/// this one, so — unlike a provider's own claim — it may carry the shield.
class _CallbackBadge extends StatelessWidget {
  const _CallbackBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.guaranteeTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.guaranteeBorder),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.n9,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: AppSizes.iconSm,
              color: colors.guaranteeText,
            ),
            const SizedBox(width: AppSpacing.n5),
            Flexible(
              child: Text(
                'Free callback · 7 days',
                style: context.type.pill.copyWith(color: colors.guaranteeText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
