import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';
import 'package:raajjepro/features/service_preview/presentation/preview_copy.dart';
import 'package:raajjepro/shared/shared.dart';

/// The sections of `Service Preview.dc.html`, one widget each so the screen
/// reads as the artboard's own outline and a test can find a section by type.
///
/// **Nothing here can show a phone number, an email or a bank detail** — the
/// models they read have no field for one — and nothing here dresses a
/// provider's own claim as a platform check: self-declared cover is printed as
/// "Provider states: …" and never beside the callback guarantee's treatment.

/// A white panel with the card geometry every section shares.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: padding ?? const EdgeInsetsDirectional.all(AppSpacing.lg),
    child: SizedBox(width: double.infinity, child: child),
  );
}

class TitleBlock extends StatelessWidget {
  const TitleBlock({required this.listing, super.key});

  final PublicListing listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final areas = listing.serviceAreas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(listing.name, style: type.screenTitle),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: AppSizes.iconMd,
                  color: colors.ratingStar,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(ratingLine(listing.rating), style: type.bodyStrong),
              ],
            ),
            if (areas.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: AppSizes.iconMd,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  // Every island travels with its atoll code where the name is
                  // shared, so this prints the server's own `displayName`.
                  Text(
                    areas.length == 1
                        ? areas.first.displayName
                        : '${areas.first.displayName} +${areas.length - 1}',
                    style: type.secondary,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The price, what kind of price it is, and — the part §1c cares about — how
/// the customer will book it, with the emergency door beside it when offered.
class PriceCard extends StatelessWidget {
  const PriceCard({
    required this.listing,
    required this.providerName,
    required this.onEmergency,
    super.key,
  });

  final PublicListing listing;
  final String providerName;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final price = priceCopy(listing.pricing, providerName);
    final slot = listing.bookingMode == BookingMode.slot;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  price.big,
                  style: type.screenTitle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (price.unit.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(price.unit, style: type.secondary),
              ],
              const Spacer(),
              AppChip.label(label: price.label),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(price.note, style: type.secondary),
          const SizedBox(height: AppSpacing.md),
          // The booking mode, stated before the customer taps anything:
          // "a customer must never be uncertain which kind of wait they are in".
          DecoratedBox(
            decoration: BoxDecoration(
              color: slot ? colors.accentTint : colors.neutralTint,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md2,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  _IconChip(
                    icon: slot
                        ? Icons.schedule_rounded
                        : Icons.event_note_outlined,
                    color: slot ? colors.accentText : colors.neutralText,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookingCta(listing.bookingMode),
                          style: type.bodyStrong.copyWith(
                            color: slot
                                ? colors.accentText
                                : colors.neutralText,
                          ),
                        ),
                        Text(
                          bookingModeSub(listing, providerName),
                          style: type.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (listing.emergency.available) ...[
            const SizedBox(height: AppSpacing.md),
            _EmergencyDoor(emergency: listing.emergency, onTap: onEmergency),
          ],
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color, this.fill});

  final IconData icon;
  final Color color;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
    width: AppSizes.avatarMedium,
    height: AppSizes.avatarMedium,
    decoration: BoxDecoration(
      color: fill ?? context.colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: AppSizes.iconLg, color: color),
  );
}

/// Emergency alongside the normal path, with its cost stated before anything
/// is sent (§Phase 12, §1c). It is a door to the ASAP request — which reaches
/// every eligible provider and shows up to three offers — not a claim that this
/// provider will come, and it says so.
class _EmergencyDoor extends StatelessWidget {
  const _EmergencyDoor({required this.emergency, required this.onTap});

  final PublicEmergency emergency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final fee = emergency.dispatchFeeLaari;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorTint,
        border: Border.all(color: colors.errorBorder),
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md2,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _IconChip(
              icon: Icons.bolt_rounded,
              color: colors.onError,
              fill: colors.error,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency call-out also available',
                    style: type.bodyStrong.copyWith(color: colors.errorText),
                  ),
                  Text(
                    'Offers arrive with each provider’s own callout fee and '
                    'arrival estimate. Choosing one adds RaajjePro’s '
                    '${fee == null ? 'dispatch fee' : mvr(fee)} '
                    '${fee == null ? '' : 'dispatch fee, '}settled later by '
                    'bank transfer.',
                    style: type.caption,
                  ),
                ],
              ),
            ),
            Pressable(
              semanticLabel: 'Get emergency help',
              onTap: onTap,
              focusRadius: AppRadius.pill,
              builder: (context, state) => Container(
                width: AppSizes.iconButtonSize,
                height: AppSizes.iconButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: AppSizes.iconLg,
                  color: colors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The provider's identity, badge and the mode's second signal. Whole-card tap
/// goes to their profile (§Phase 13); the card holds no control of its own, so
/// making it one tap target swallows nothing.
class ProviderCard extends StatelessWidget {
  const ProviderCard({
    required this.listing,
    required this.providerName,
    required this.now,
    required this.onTap,
    super.key,
  });

  final PublicListing listing;
  final String providerName;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final provider = listing.provider;
    return AppCard(
      onTap: onTap,
      semanticLabel: 'View $providerName’s profile',
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md2,
      ),
      child: Row(
        children: [
          AppAvatar(name: providerName, tier: provider.tier),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(providerName, style: type.cardTitle),
                const SizedBox(height: AppSpacing.xs),
                // The full form, so the tier's words are on screen: the chip alone
                // says "◆ Silver", which a customer can read as a track record
                // rather than an ID and trade check (§1e).
                VerificationBadge(
                  tier: provider.tier,
                  size: VerificationBadgeSize.full,
                ),
                if (provider.tier != VerificationTier.none)
                  const SizedBox(height: AppSpacing.xs),
                Text(providerLine(listing, now), style: type.caption),
                if (!provider.acceptingNewCustomers) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Not taking new customers right now',
                    style: type.caption.copyWith(color: colors.warningText),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.placeholder),
        ],
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({required this.listing, super.key});

  final PublicListing listing;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final about = listing.about;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About this service', style: type.sectionHeading),
          if (about != null && about.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(about, style: type.body),
          ],
          if (listing.whatsIncluded.isNotEmpty)
            _BulletGroup(
              heading: 'What’s included',
              lines: listing.whatsIncluded,
            ),
          if (listing.whatsNotIncluded.isNotEmpty)
            _BulletGroup(
              heading: 'What’s not included',
              lines: listing.whatsNotIncluded,
            ),
          if (listing.serviceAreas.isNotEmpty) ...[
            const _Rule(),
            Text('SERVICE AREAS', style: type.overline),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final island in listing.serviceAreas)
                  // Keyed by id: sixteen names are shared across atolls.
                  AppChip.label(
                    key: ValueKey(island.id),
                    label: island.displayName,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.md),
    child: Divider(height: 1, color: context.colors.divider),
  );
}

class _BulletGroup extends StatelessWidget {
  const _BulletGroup({required this.heading, required this.lines});

  final String heading;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Rule(),
        Text(heading.toUpperCase(), style: type.overline),
        const SizedBox(height: AppSpacing.sm),
        for (final line in lines)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: AppSpacing.n7,
                    end: AppSpacing.sm2,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                    child: const SizedBox(
                      width: AppSpacing.xs,
                      height: AppSpacing.xs,
                    ),
                  ),
                ),
                Expanded(child: Text(line, style: type.bodyStrong)),
              ],
            ),
          ),
      ],
    );
  }
}

/// §1i. **The provider's own words, attributed, with a plain statement that
/// RaajjePro has not checked them.** No check mark, no shield, and not inside
/// the callback guarantee's treatment — those belong to `verificationTier`,
/// which means something because a human looked.
class SelfDeclaredCard extends StatelessWidget {
  const SelfDeclaredCard({required this.statements, super.key});

  final List<String> statements;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From the provider', style: type.sectionHeading),
          for (final statement in statements) ...[
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Provider states: ',
                    style: type.bodyStrong.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  TextSpan(text: statement, style: type.bodyStrong),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'These are the provider’s own statements. RaajjePro has not '
            'checked them.',
            style: type.caption,
          ),
        ],
      ),
    );
  }
}

/// The one promise on this page RaajjePro itself keeps (§1h, Round 28) — which
/// is why it, unlike [SelfDeclaredCard], may say "enforced".
class CallbackCard extends StatelessWidget {
  const CallbackCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      color: colors.guaranteeTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChip(
            icon: Icons.verified_user_outlined,
            color: colors.onPrimary,
            fill: colors.guaranteeText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RaajjePro callback guarantee',
                  style: type.bodyStrong.copyWith(color: colors.guaranteeText),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Free return visit within 7 days if the same problem comes '
                  'back.',
                  style: type.secondary.copyWith(color: colors.guaranteeText),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Enforced by RaajjePro — request it from your booking.',
                  style: type.caption.copyWith(color: colors.guaranteeText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Common questions, and — below them, where the questions end — the way to ask
/// your own (§1c: "Message" restored, the pre-booking enquiry).
class FaqCard extends StatelessWidget {
  const FaqCard({
    required this.faqs,
    required this.openIndex,
    required this.onToggle,
    super.key,
  });

  final List<Faq> faqs;
  final int openIndex;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return _Panel(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: Text('Common questions', style: type.sectionHeading),
          ),
          for (final (index, faq) in faqs.indexed) ...[
            Divider(height: 1, color: colors.divider),
            Pressable(
              semanticLabel: faq.question,
              toggled: openIndex == index,
              onTap: () => onToggle(index),
              focusRadius: AppRadius.xs,
              builder: (context, state) => Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: AppSpacing.md2,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(faq.question, style: type.bodyStrong)),
                    AnimatedRotation(
                      turns: openIndex == index ? 0.5 : 0,
                      duration: context.motion.fast,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.placeholder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (openIndex == index)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: AppSpacing.md2,
                ),
                child: Text(
                  faq.answer,
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class ReviewsCard extends StatelessWidget {
  const ReviewsCard({
    required this.rating,
    required this.reviews,
    required this.now,
    super.key,
  });

  final RatingSummary rating;
  final List<PublicReview> reviews;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final average = rating.averageRating;
    final total = rating.reviewCount;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Reviews', style: type.sectionHeading),
              const Spacer(),
              if (average != null && total > 0)
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: AppSizes.iconMd,
                      color: colors.ratingStar,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(average.toStringAsFixed(1), style: type.stat),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('($total)', style: type.secondary),
                  ],
                ),
            ],
          ),
          if (total == 0) ...[
            const SizedBox(height: AppSpacing.md),
            // An empty state that says what happens next, not merely that
            // nothing is here. Reviews come from completed bookings only.
            Text(
              'No reviews yet. Reviews are written by customers after a '
              'completed booking, so the first ones appear once this '
              'service has been done.',
              style: type.secondary,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md2),
            for (var stars = 5; stars >= 1; stars--)
              _StarBar(
                stars: stars,
                count: rating.starBreakdown[stars] ?? 0,
                total: total,
              ),
            if (rating.tags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final tag in rating.tags)
                    AppChip.label(label: '${tag.label} (${tag.count})'),
                ],
              ),
            ],
            for (final review in reviews) _ReviewRow(review: review, now: now),
          ],
        ],
      ),
    );
  }
}

class _StarBar extends StatelessWidget {
  const _StarBar({
    required this.stars,
    required this.count,
    required this.total,
  });

  final int stars;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      label: '$stars star: $count of $total',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.sm2,
              child: Text('$stars', style: type.caption),
            ),
            const SizedBox(width: AppSpacing.n9),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : count / total,
                  minHeight: AppSpacing.n7,
                  backgroundColor: colors.divider,
                  color: colors.ratingStar,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.n9),
            SizedBox(
              width: AppSpacing.lg2,
              child: Text('$count', style: type.caption),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review, required this.now});

  final PublicReview review;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    // Null once the author's account is anonymised: a neutral placeholder, and
    // nothing about who they were.
    final name = review.authorDisplayName ?? 'A RaajjePro customer';
    final body = review.body;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.md2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: colors.divider),
          const SizedBox(height: AppSpacing.md2),
          Row(
            children: [
              AppAvatar(name: name, size: AppSizes.avatarMedium),
              const SizedBox(width: AppSpacing.sm2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: type.bodyStrong),
                    Text(reviewAge(review.createdAt, now), style: type.caption),
                  ],
                ),
              ),
              Icon(
                Icons.star_rounded,
                size: AppSizes.iconMd,
                color: colors.ratingStar,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text('${review.rating}', style: type.bodyStrong),
            ],
          ),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: type.body),
          ],
        ],
      ),
    );
  }
}

/// The category pill that sits on the hero, in the category's own accent.
class CategoryPill extends StatelessWidget {
  const CategoryPill({required this.category, super.key});

  final PublicCategory category;

  @override
  Widget build(BuildContext context) {
    final accent = CategoryAccents.resolve(category.colorToken);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          category.name,
          style: context.type.pill.copyWith(color: accent.text),
        ),
      ),
    );
  }
}
