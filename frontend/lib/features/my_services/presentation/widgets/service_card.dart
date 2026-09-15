import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/listings/listing_money.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// One of the provider's own services, as `My Services.dc.html` draws it.
///
/// ## What the card says about a listing, and what it does not
///
/// The status pill is [StatusBadge]'s, so "Draft" / "Published" / "Hidden"
/// read identically here and everywhere else (`frontend/CLAUDE.md`:
/// duplicating that mapping into a screen is a defect). The price string is
/// [customerPricePreview] — the same one §Phase 9's step 3 shows the provider
/// as a preview of what a customer will read, which is only a promise if both
/// screens compute it in one place.
///
/// **There is no rating on this card**, though the artboard draws one. A
/// `Review` does not exist until §Phase 11 and §Phase 8's own-listing shape
/// carries no rating field, so the star would be either invented or blank —
/// and a blank star on a provider's own listing reads as "nobody rated you".
/// §Phase 11 adds it to the shape and to this card together.
///
/// **And no emergency marker**, which the artboard also omits: Round 23
/// removed it from every card because dispatch never targets a provider.
///
/// ## The card is not itself a button, and that is deliberate
///
/// The artboard's card is a container whose *rows* are interactive — the
/// overflow menu, the live toggle, "Finish & publish" — and nothing happens
/// when the body between them is tapped. Making the whole card tappable was
/// tried and is an accessibility regression rather than a convenience:
/// `Pressable` wraps its child with `excludeSemantics: true`, so a tappable
/// card **erases every control inside it** from the semantics tree, and a
/// screen-reader user would lose the menu, the toggle and the publish button
/// in exchange for one summary. Editing is reached from the menu, which is
/// where the artboard puts it.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    required this.listing,
    required this.category,
    required this.now,
    required this.onFinishDraft,
    required this.onMenu,
    required this.onSetLive,
    required this.onUpgrade,
    required this.onKeepVisible,
    this.capLabel,
    super.key,
  });

  /// The list variant's cover, measured off the artboard.
  static const double coverWidth = 104;

  /// The grid variant's, likewise.
  static const double gridCoverHeight = 92;

  final ServiceListing listing;

  /// Null where the catalogue has no such id — an admin retiring a category
  /// (§Phase 10b) must not blank a provider's card.
  final ServiceCategory? category;

  final DateTime now;

  /// A draft's "Finish & publish" — the one action on the card body itself,
  /// because a draft has nothing to toggle and finishing it is the only thing
  /// a provider opens the dashboard to do.
  final VoidCallback onFinishDraft;
  final VoidCallback onMenu;
  final ValueChanged<bool> onSetLive;
  final VoidCallback onUpgrade;

  /// §1b's override — "keep this one instead". Only ever reachable from an
  /// over-cap card.
  final VoidCallback onKeepVisible;

  /// "1 live service" — §1b's cap in words, supplied by the screen because
  /// the number is the entitlement endpoint's and not this widget's to guess.
  final String? capLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.panel,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: coverWidth,
              child: _Cover(listing: listing, colors: colors),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md2,
                  AppSpacing.md,
                  AppSpacing.md2,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TitleRow(listing: listing, onMenu: onMenu),
                    const SizedBox(height: AppSpacing.sm),
                    _ChipRow(listing: listing, category: category),
                    const SizedBox(height: AppSpacing.sm),
                    _Numbers(listing: listing),
                    if (listing.isOverCap)
                      _OverCapFooter(
                        capLabel: capLabel,
                        onUpgrade: onUpgrade,
                        onKeepVisible: onKeepVisible,
                      )
                    else
                      _Footer(
                        listing: listing,
                        now: now,
                        onFinishDraft: onFinishDraft,
                        onSetLive: onSetLive,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grid variant: cover, name, price, status. Deliberately less than the
/// row — the grid is for scanning a list of names, and every action on it is
/// one tap away in the same menu.
class ServiceGridCard extends StatelessWidget {
  const ServiceGridCard({
    required this.listing,
    required this.onMenu,
    super.key,
  });

  final ServiceListing listing;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: ServiceCard.gridCoverHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(listing: listing, colors: colors),
                PositionedDirectional(
                  top: AppSpacing.xxs,
                  end: AppSpacing.xxs,
                  child: _MenuButton(listing: listing, onMenu: onMenu),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listing.name ?? 'Untitled service',
                  style: type.cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  customerPricePreview(listing),
                  style: type.price.copyWith(color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusBadge(_statusFor(listing)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three listing states this screen can show, mapped onto the shared
/// badge. `hidden_by_admin` maps to the same word a provider already
/// understands — it is not this phase's job to explain a moderation action
/// that §Phase 22 has not built yet, and inventing copy for it here would
/// put words in an admin's mouth.
BadgeStatus _statusFor(ServiceListing listing) {
  if (listing.status == ListingStatus.draft) return BadgeStatus.draft;
  return listing.isLive ? BadgeStatus.published : BadgeStatus.hidden;
}

class _Cover extends StatelessWidget {
  const _Cover({required this.listing, required this.colors});

  final ServiceListing listing;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final url = listing.coverMedia?.isStored ?? false
        ? listing.coverMedia?.url
        : null;
    return ColoredBox(
      color: colors.surfaceMuted,
      child: url == null
          ? Center(
              child: Icon(
                Icons.image_outlined,
                color: colors.placeholder,
                size: AppSizes.iconLg,
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              // A grey wash rather than a broken-image glyph: the listing is
              // fine, the signed URL has simply expired or the connection
              // dropped.
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.image_outlined,
                  color: colors.placeholder,
                  size: AppSizes.iconLg,
                ),
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : SkeletonLoader(
                      child: ColoredBox(color: colors.skeletonBase),
                    ),
            ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.listing, required this.onMenu});

  final ServiceListing listing;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            listing.name ?? 'Untitled service',
            style: context.type.cardTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _MenuButton(listing: listing, onMenu: onMenu),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.listing, required this.onMenu});

  final ServiceListing listing;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onMenu,
      // Named for the listing, because a screen reader moving through a list
      // of cards otherwise meets four controls all called "More options".
      semanticLabel: 'More options for ${listing.name ?? 'this service'}',
      focusRadius: AppRadius.pill,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed || s.hovered ? colors.surfaceMuted : null,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.more_vert_rounded,
          size: AppSizes.iconMd,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.listing, required this.category});

  final ServiceListing listing;
  final ServiceCategory? category;

  @override
  Widget build(BuildContext context) {
    final accent = CategoryAccents.resolve(category?.colorToken);
    final type = context.type;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (category != null)
          Container(
            height: AppSizes.staticChipHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.sm,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.tint,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              category!.name,
              style: type.pill.copyWith(color: accent.text),
            ),
          ),
        StatusBadge(_statusFor(listing)),
      ],
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.listing});

  final ServiceListing listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Row(
      children: [
        Expanded(
          child: Text(
            customerPricePreview(listing),
            style: type.price.copyWith(color: colors.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Rolled up by §Phase 8's job, so they are counts of what happened,
        // not a live meter — which is why nothing here animates.
        _Count(
          icon: Icons.visibility_outlined,
          value: listing.viewCount,
          spoken: 'views',
        ),
        const SizedBox(width: AppSpacing.sm2),
        _Count(
          icon: Icons.calendar_today_outlined,
          value: listing.bookingCount,
          spoken: 'bookings',
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.value, required this.spoken});

  final IconData icon;
  final int value;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$value $spoken',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconSm, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '$value',
              style: context.type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.listing,
    required this.now,
    required this.onFinishDraft,
    required this.onSetLive,
  });

  final ServiceListing listing;
  final DateTime now;
  final VoidCallback onFinishDraft;
  final ValueChanged<bool> onSetLive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final updated = listing.updatedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Divider(height: AppSizes.dividerStroke, color: colors.divider),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                updated == null ? '' : 'Updated ${relativeEdit(updated, now)}',
                style: type.caption.copyWith(color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (listing.status == ListingStatus.draft)
              AppButton.secondary(
                label: 'Finish & publish',
                size: AppButtonSize.compact,
                onPressed: onFinishDraft,
              )
            else
              IntrinsicWidth(
                child: AppToggle(
                  // The word stays "Live" whichever way the switch is set.
                  // The artboard flips it to "Off", which reads correctly on
                  // screen and wrongly to a screen reader — "Off, off" — and
                  // the switch already announces its own state.
                  label: 'Live',
                  value: listing.isLive,
                  onChanged: onSetLive,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// §1b: hidden because the provider is over their entitlement cap.
///
/// Two ways out, and neither is a visibility the provider writes. Upgrade
/// raises the cap; "Make this one live instead" sets §1b's override — "the
/// provider can override the choice from the dashboard" — which the server
/// honours by re-ranking, staying the only writer of `hidden_over_cap`.
class _OverCapFooter extends StatelessWidget {
  const _OverCapFooter({
    required this.capLabel,
    required this.onUpgrade,
    required this.onKeepVisible,
  });

  final String? capLabel;
  final VoidCallback onUpgrade;
  final VoidCallback onKeepVisible;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Divider(height: AppSizes.dividerStroke, color: colors.divider),
        const SizedBox(height: AppSpacing.sm),
        Text(
          capLabel == null
              ? 'This one is hidden from customers while you are over your '
                    'plan’s limit — nothing is lost, and its numbers stay.'
              : 'Your free plan includes $capLabel. This one is hidden from '
                    'customers — nothing is lost, and its numbers stay.',
          style: type.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton.primary(
              label: 'Upgrade',
              size: AppButtonSize.compact,
              onPressed: onUpgrade,
            ),
            AppButton.secondary(
              label: 'Make this one live instead',
              size: AppButtonSize.compact,
              onPressed: onKeepVisible,
            ),
          ],
        ),
      ],
    );
  }
}
