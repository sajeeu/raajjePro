import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/email_gate.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/core/favorites/save_action.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/public/public_models.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/provider_profile/controller/provider_profile_controller.dart';
import 'package:raajjepro/features/provider_profile/data/provider_profile_api.dart';
import 'package:raajjepro/features/provider_profile/presentation/profile_copy.dart';
import 'package:raajjepro/shared/shared.dart';

class ProviderProfileArgs {
  const ProviderProfileArgs({required this.providerId});

  /// Built from untyped route arguments so no feature has to import this one
  /// to push it — the shape `ServicePreviewArgs` established.
  factory ProviderProfileArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return ProviderProfileArgs(providerId: map['providerId'] as String? ?? '');
  }

  final String providerId;
}

/// The header card's measured frames (`Provider Profile.dc.html`): a 76 dp
/// banner, a 76 dp avatar ringed in 4 dp of white, lifted 32 dp into the
/// banner. Pictures' frames rather than rhythm steps, so not spacing tokens.
const double _bannerHeight = 76;
const double _avatarSize = 76;
const double _avatarRing = 4;
const double _avatarLift = 32;

/// Where the avatar row starts: the banner's height less the lift.
const double _avatarTop = _bannerHeight - _avatarLift;

/// The disc inside the ring.
const double _avatarInner = _avatarSize - _avatarRing * 2;

/// The below-floor card's icon tile (40 dp, radius 12).
const double _newProviderTile = 40;

/// **Provider Profile** — `Provider Profile.dc.html`, the provider's public
/// page (§Phase 13).
///
/// ## What it does
///
/// Reads `GET /v1/providers/:id/public` and renders the header (name, the
/// three-tier badge with its own words, §1g's Maldivian-owned attribute where
/// Gold evidenced it, the rating across every service), §1f's track record as
/// **numbers only** — or "New provider" and the job count below the floor —
/// the tags three different customers applied, and every published service as
/// a card.
///
/// ## The not-found state is the server's
///
/// A provider with no published listing, a suspended one and an id that never
/// existed are one 404 (§1a, `findVisibleProviders`), and this screen renders
/// that 404 as "This provider isn't here anymore" — never an empty profile.
///
/// ## Where it departs from the artboard
///
/// - **No personal name and no photo** (decision 34, the control session's
///   ruling on the owner's behalf): the headline is the business name, the
///   avatar is its initials, and the button is "Message provider". The
///   artboard draws a person's name over the business name and a photo slot;
///   the public provider shape carries neither, and Phase 12 already prints the
///   business name on the same provider.
/// - **The below-floor line** says "in the last 90 days", because that is what
///   §1f's floor measures.
///
/// ## What is not built here
///
/// Message (§Phase 18) and Report (§Phase 22) are drawn where the artboard
/// draws them and land on the phase that owes them. 🔧 Save is §Phase 14's
/// and is live: the header heart saves the provider (Round 15), and each
/// service card's heart saves that service.
class ProviderProfileScreen extends ConsumerWidget {
  const ProviderProfileScreen({required this.args, super.key});

  static const routeName = AppRoutes.providerProfile;

  final ProviderProfileArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerProfileProvider(args.providerId));
    final body = state is AsyncData<PublicProviderProfile>;
    final saved = ref.watch(
      favoritesProvider.select((s) => s.providerSaved(args.providerId)),
    );

    void report() => _openUnbuilt(context, 'Report', 'Phase 22');

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Provider profile',
            onBack: () => Navigator.of(context).maybePop(),
            // The artboard draws these only over a real profile: saving or
            // reporting a provider who is not there is not a thing.
            actions: body
                ? [
                    // §Phase 14, Round 15 — the on-platform substitute for
                    // taking their number. Optimistic, rolled back visibly.
                    AppHeaderAction(
                      icon: saved
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: 'Save this provider',
                      toggled: saved,
                      iconColor: saved ? context.colors.error : null,
                      onTap: () {
                        AppHaptics.selection();
                        unawaited(
                          setSaved(
                            context,
                            ref,
                            FavoriteKind.provider,
                            args.providerId,
                            saved: !saved,
                          ),
                        );
                      },
                    ),
                    AppHeaderAction(
                      icon: Icons.flag_outlined,
                      label: 'Report this provider',
                      onTap: report,
                    ),
                  ]
                : const [],
          ),
          Expanded(
            child: switch (state) {
              AsyncData(:final value) => _Body(
                profile: value,
                onMessage: () => _message(context, ref),
                onListing: (listingId) => Navigator.of(context).pushNamed(
                  AppRoutes.listingPreview,
                  arguments: <String, dynamic>{'listingId': listingId},
                ),
              ),
              AsyncError(:final error) =>
                isProviderUnavailable(error)
                    ? _NotFound(
                        onExplore: () =>
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                      )
                    : _LoadError(
                        onRetry: () => ref
                            .read(
                              providerProfileProvider(args.providerId).notifier,
                            )
                            .reload(),
                      ),
              _ => const _ProfileSkeleton(),
            },
          ),
        ],
      ),
    );
  }

  /// §1c: messaging needs a verified email. This routes to the screen that
  /// fixes it; it is not the check — the server refuses an unverified send on
  /// its own (invariant 4). Past the gate the enquiry thread is §Phase 18's.
  void _message(BuildContext context, WidgetRef ref) {
    if (!passEmailGate(context, ref)) return;
    _openUnbuilt(context, 'Messages', 'Phase 18');
  }

  /// A control the artboard draws whose destination a later phase owes lands
  /// on [UnbuiltScreen] naming that phase — the Service Preview's pattern.
  static void _openUnbuilt(BuildContext context, String title, String owedBy) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnbuiltScreen(title: title, owedBy: owedBy),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.profile,
    required this.onMessage,
    required this.onListing,
  });

  final PublicProviderProfile profile;
  final VoidCallback onMessage;
  final ValueChanged<String> onListing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final now = ref.watch(clockProvider)();
    final provider = profile.provider;
    final conduct = provider.conduct;
    final name = displayName(provider);

    // The rows a reader sees, each its own entrance step (frontend/CLAUDE.md).
    final rows = <Widget>[
      ProfileHeaderCard(profile: profile),
      if (conduct.belowFloor)
        BelowFloorCard(conduct: conduct)
      else
        TrackRecordCard(conduct: conduct),
      if (profile.tags.isNotEmpty) TagsSection(tags: profile.tags),
      Text(servicesHeading(profile.listings.length), style: type.cardTitle),
      for (final listing in profile.listings)
        PublicServiceCard(
          listing: listing,
          providerName: name,
          providerTier: provider.tier,
          providerConduct: conduct,
          now: now,
          onTap: () => onListing(listing.id),
        ),
    ];

    final spaced = <Widget>[];
    for (final (index, row) in rows.indexed) {
      if (index > 0) spaced.add(const SizedBox(height: AppSpacing.lg));
      spaced.add(row);
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxl2,
            ),
            child: FadeUpColumn(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spaced,
            ),
          ),
        ),
        _Footer(onMessage: onMessage),
      ],
    );
  }
}

/// Name, badge, §1g's attribute, tenure and the rating across every service.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({required this.profile, super.key});

  final PublicProviderProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final provider = profile.provider;
    final name = displayName(provider);
    final since = providerSince(provider);
    final average = averageText(profile.rating);
    // §1g: shown only where Gold review evidenced it. The server already sends
    // null below Gold; the tier check is the artboard's own and costs nothing.
    final maldivianOwned =
        provider.tier == VerificationTier.gold &&
        (provider.maldivianOwned ?? false);

    return AppCard(
      radius: AppRadius.feature,
      clip: true,
      padding: EdgeInsetsDirectional.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [colors.accentTint, colors.background],
                  ),
                ),
                child: const SizedBox(
                  height: _bannerHeight,
                  width: double.infinity,
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  _avatarTop,
                  AppSpacing.lg,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.surface,
                          width: _avatarRing,
                        ),
                        boxShadow: AppShadows.card(colors.ink),
                      ),
                      // A border paints inside its box, so the ring needs its
                      // own room: without this padding it covered the
                      // avatar's edge and the disc painted at 68, not 76.
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(_avatarRing),
                        child: AppAvatar(name: name, size: _avatarInner),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md2),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: AppSpacing.xxs,
                        ),
                        child: Semantics(
                          header: true,
                          // The artboard's 20/800 has no role; this is the
                          // nearest one that keeps the weight (decision 34).
                          child: Text(
                            name,
                            style: type.sectionHeading.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (provider.tier != VerificationTier.none ||
                    maldivianOwned) ...[
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // The full badge, so the tier's words are on screen
                      // (§1e) — never a bare "Verified".
                      if (provider.tier != VerificationTier.none)
                        VerificationBadge(
                          tier: provider.tier,
                          size: VerificationBadgeSize.full,
                        ),
                      if (maldivianOwned) const _MaldivianOwnedPill(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (since != null) Text(since, style: type.caption),
                if (!provider.acceptingNewCustomers) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Not taking new customers right now',
                    style: type.caption.copyWith(color: colors.warningText),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: colors.divider),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (average != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: AppSizes.iconMd,
                            color: colors.ratingStar,
                          ),
                          const SizedBox(width: AppSpacing.n5),
                          Text(average, style: type.price),
                        ],
                      ),
                    Text(reviewsAcross(profile.rating), style: type.secondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §1g's attribute — of the business, evidenced by Gold's registration
/// document, and never a statement about a person.
class _MaldivianOwnedPill extends StatelessWidget {
  const _MaldivianOwnedPill();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.accentBorder),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.n7,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: AppSizes.iconSm,
              color: colors.accentText,
            ),
            const SizedBox(width: AppSpacing.xs),
            // Flexible so that at large text the words wrap inside the pill
            // rather than push it past the screen edge.
            Flexible(
              child: Text(
                'Maldivian-owned business',
                style: context.type.pill.copyWith(color: colors.accentText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §1f's track record, above the floor: six numbers and the response time.
/// **Never a label** — the customer draws the conclusion.
class TrackRecordCard extends StatelessWidget {
  const TrackRecordCard({required this.conduct, super.key});

  final PublicConduct conduct;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final median = conduct.medianResponseSeconds;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text('Track record', style: type.cardTitle),
              Text('Rolling last 90 days', style: type.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.md2),
          // Three across at 100% text, fewer as it grows — a number is never
          // broken mid-digit (`StatMiniCardRow`'s rule, applied to bare cells).
          StatMiniCardRow(
            gap: AppSpacing.sm,
            minTileWidth: 88,
            children: [
              for (final cell in trackRecord(conduct)) _MetricTile(cell: cell),
            ],
          ),
          if (median != null) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: AppSpacing.n11),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: AppSizes.iconMd,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.n7),
                Expanded(
                  child: Text(
                    'Usually replies in ${responseTimePhrase(median)}',
                    style: type.secondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textTertiary,
                    ),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.cell});

  final MetricCell cell;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final value = cell.value;
    return Semantics(
      label: '${cell.label}: ${value ?? 'No data yet'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value != null)
            Text(value, style: type.stat, softWrap: false)
          else
            // "No data yet", never a zero (frontend/CLAUDE.md).
            Text(
              'No data yet',
              style: type.secondary.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(cell.label, style: type.caption),
        ],
      ),
    );
  }
}

/// Below §1f's floor: the job count and why there are no rates — no figure at
/// all, because one cancellation out of two is 50% and means nothing.
class BelowFloorCard extends StatelessWidget {
  const BelowFloorCard({required this.conduct, super.key});

  final PublicConduct conduct;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final copy = belowFloorCopy(conduct);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _newProviderTile,
            height: _newProviderTile,
            decoration: BoxDecoration(
              color: colors.neutralTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_outlined,
              size: AppSizes.iconLg,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.title,
                  style: type.bodyStrong.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(copy.body, style: type.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What customers say" — §1f's tags as counts. The server sends only tags
/// three different customers applied, so nothing here filters or relabels.
class TagsSection extends StatelessWidget {
  const TagsSection({required this.tags, super.key});

  final List<TagCount> tags;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What customers say', style: type.cardTitle),
        const SizedBox(height: AppSpacing.sm2),
        Wrap(
          spacing: AppSpacing.n7,
          runSpacing: AppSpacing.n7,
          children: [
            for (final tag in tags)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.neutralTint,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.staticChipHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Align(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        tagChip(tag),
                        style: type.pill.copyWith(color: colors.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onMessage});

  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton.primary(
                label: 'Message provider',
                icon: Icons.chat_bubble_outline_rounded,
                expand: true,
                onPressed: onMessage,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Private messaging — your phone number stays private, and '
                'you talk in the app.',
                style: context.type.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonLoader(
    label: 'Loading the provider',
    child: Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm2,
        AppSpacing.xl,
        AppSpacing.sm2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 64, height: 64, shape: BoxShape.circle),
              SizedBox(width: AppSpacing.md2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: AppSpacing.n17, width: 180),
                    SizedBox(height: AppSpacing.n9),
                    SkeletonBox(height: AppSpacing.md, width: 130),
                    SizedBox(height: AppSpacing.n9),
                    SkeletonBox(height: AppSpacing.xxl2, width: 220),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 150, radius: AppRadius.panel),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: AppSpacing.md2, width: 150),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 188, radius: AppRadius.panel),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 188, radius: AppRadius.panel),
        ],
      ),
    ),
  );
}

/// §1a's not-found: no published service, suspended, or never existed — one
/// answer, so the page never confirms that a hidden provider exists.
class _NotFound extends StatelessWidget {
  const _NotFound({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => _Centered(
    child: EmptyState(
      icon: Icons.search_off_rounded,
      title: 'This provider isn’t here anymore',
      body:
          'They have no services published on RaajjePro right now, so '
          'there’s no page to show. The link you followed may be old.',
      actionLabel: 'Explore services',
      onAction: onExplore,
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Centered(
    child: EmptyState.error(
      title: 'Couldn’t load this profile',
      body:
          'Your connection may have dropped — that happens. Nothing is '
          'lost; try again.',
      onRetry: onRetry,
    ),
  );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: AppSpacing.screenInsets,
      child: FadeUp(child: child),
    ),
  );
}
