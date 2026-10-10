import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/email_gate.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/core/favorites/save_action.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/saved/controller/saved_controller.dart';
import 'package:raajjepro/features/saved/data/saved_api.dart';
import 'package:raajjepro/features/saved/presentation/saved_copy.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 14 — **Saved**: the services and (Round 15) the providers a
/// customer kept, from `Discovery.dc.html`'s Saved screen. Reached from
/// Profile's Saved row and Explore's heart.
///
/// Four states, the artboard's own: skeleton cards, "Saved items didn't
/// load" with a retry, "Nothing saved yet" naming what to do next, and the two
/// sections.
///
/// **What is shown is what the app's one saved state says is saved.** An
/// unsave anywhere — this screen's own hearts, a card's, the listing page's —
/// removes the row on the next frame, and a failed one puts it back with the
/// artboard's sentence. That is §Phase 14's "reflects it immediately".
///
/// ## Where it departs from the artboard
///
/// - **A saved provider's headline is the business name**, with its initials
///   and what they offer beneath — no personal name (decision 34, the
///   provider profile's ruling, applied to the same provider here).
/// - **Tapping the provider's name and avatar opens their profile.** The
///   artboard draws no destination for the row; a saved person you cannot
///   look at again is a dead end. The two buttons stay their own targets.
/// - **No bottom navigation.** This is a pushed screen with a back control,
///   like Saved preferences.
///
/// Message is §Phase 18's: it passes the email gate (§1c) and lands on the
/// screen naming that phase (ledger P14-1).
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  static const routeName = AppRoutes.saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final lists = ref.watch(savedProvider);
    final favorites = ref.watch(favoritesProvider);

    final shown = switch (lists) {
      AsyncData(:final value) => (
        services: value.services
            .where((s) => favorites.listingSaved(s.listing.id))
            .toList(),
        providers: value.providers
            .where((p) => favorites.providerSaved(p.provider.id))
            .toList(),
      ),
      _ => null,
    };

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Saved',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          if (shown != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  savedSubtitle(
                    services: shown.services.length,
                    providers: shown.providers.length,
                  ),
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
          Expanded(
            child: switch (lists) {
              AsyncError() => _Centered(
                child: EmptyState.error(
                  title: errorTitle,
                  body: errorBody,
                  onRetry: () => ref.read(savedProvider.notifier).reload(),
                ),
              ),
              AsyncData() when shown != null =>
                shown.services.isEmpty && shown.providers.isEmpty
                    ? _Centered(
                        child: EmptyState(
                          icon: Icons.favorite_border_rounded,
                          title: emptyTitle,
                          body: emptyBody,
                          actionLabel: 'Browse services',
                          onAction: () =>
                              Navigator.of(context)
                                  .pushNamed(AppRoutes.explore),
                        ),
                      )
                    : _Populated(
                        services: shown.services,
                        providers: shown.providers,
                      ),
              _ => const _SavedSkeleton(),
            },
          ),
        ],
      ),
    );
  }
}

class _Populated extends ConsumerWidget {
  const _Populated({required this.services, required this.providers});

  final List<SavedService> services;
  final List<SavedProvider> providers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final now = ref.watch(clockProvider)();

    final rows = <Widget>[
      if (services.isNotEmpty) ...[
        Semantics(
          header: true,
          child: Text('Saved services', style: type.cardTitle),
        ),
        for (final saved in services)
          PublicServiceCard(
            listing: saved.listing,
            providerName: displayName(saved.provider),
            providerTier: saved.provider.tier,
            providerConduct: saved.provider.conduct,
            now: now,
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.listingPreview,
              arguments: <String, dynamic>{'listingId': saved.listing.id},
            ),
          ),
      ],
      if (providers.isNotEmpty) ...[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Saved providers', style: type.cardTitle),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              providersIntro,
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        for (final saved in providers) _ProviderRow(saved: saved),
      ],
    ];

    final spaced = <Widget>[];
    for (final (index, row) in rows.indexed) {
      if (index > 0) spaced.add(const SizedBox(height: AppSpacing.md));
      spaced.add(row);
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl2,
      ),
      children: fadeUpAll(spaced),
    );
  }
}

/// `Discovery.dc.html`'s saved-provider row: initials, the name and the chip
/// badge, what they offer, the rating, then Message and the filled heart.
///
/// A container, not a button (`frontend/CLAUDE.md`): it holds two controls,
/// so the identity half is its own tap target beside them rather than the
/// whole card wrapping them.
class _ProviderRow extends ConsumerWidget {
  const _ProviderRow({required this.saved});

  final SavedProvider saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final provider = saved.provider;
    final name = displayName(provider);
    final offers = offersLine(saved);
    final rating = ratingLine(saved);

    Future<void> unsave() async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final ok = await setSaved(
        context,
        ref,
        FavoriteKind.provider,
        provider.id,
        saved: false,
      );
      if (ok) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(removedCopy)));
      }
    }

    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md2,
        AppSpacing.n13,
        AppSpacing.md2,
        AppSpacing.n13,
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              semanticLabel: [
                name,
                // `Pressable` hides the badge's own semantics, so its words
                // are spoken here — never a bare "Verified" (§1e).
                if (provider.tier != VerificationTier.none)
                  '${VerificationBadge.nameFor(provider.tier)}, '
                      '${VerificationBadge.wordsFor(provider.tier)}',
                if (offers.isNotEmpty) offers,
                if (rating != null) 'rated $rating',
                'open profile',
              ].join(', '),
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.providerProfile,
                arguments: <String, dynamic>{'providerId': provider.id},
              ),
              focusRadius: AppRadius.input,
              builder: (context, state) => Row(
                children: [
                  AppAvatar(name: name, size: AppSizes.avatarMedium),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.bodyStrong,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            VerificationBadge(tier: provider.tier),
                          ],
                        ),
                        if (offers.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            offers,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.secondary.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        if (rating != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: AppSizes.iconSm,
                                color: colors.ratingStar,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(
                                rating,
                                style: type.secondary.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _RoundButton(
            icon: Icons.chat_bubble_outline_rounded,
            semanticLabel: 'Message $name',
            accent: true,
            onTap: () {
              if (!passEmailGate(context, ref)) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const UnbuiltScreen(
                    title: 'Messages',
                    owedBy: 'Phase 18',
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.sm),
          _RoundButton(
            icon: Icons.favorite_rounded,
            semanticLabel: 'Remove $name from saved',
            iconColor: colors.error,
            onTap: () {
              AppHaptics.selection();
              unawaited(unsave());
            },
          ),
        ],
      ),
    );
  }
}

/// The row's two 40 dp discs. The tap area is 48 dp via [Pressable].
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.accent = false,
    this.iconColor,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool accent;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      focusRadius: AppRadius.pill,
      builder: (context, state) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent ? colors.accentTint : colors.surface,
          border: Border.all(
            color: accent ? colors.accentBorder : colors.border,
          ),
        ),
        child: SizedBox.square(
          dimension: 40,
          child: Icon(
            icon,
            size: AppSizes.iconMd,
            color: iconColor ?? colors.primary,
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: AppSpacing.screenInsets,
    child: Center(child: child),
  );
}

class _SavedSkeleton extends StatelessWidget {
  const _SavedSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonLoader(
    label: 'Loading what you saved',
    child: Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: AppSpacing.md2, width: 150),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 140, radius: AppRadius.panel),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 140, radius: AppRadius.panel),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 140, radius: AppRadius.panel),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 140, radius: AppRadius.panel),
        ],
      ),
    ),
  );
}
