import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/location/browsing_island_controller.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/search/controller/search_controller.dart';
import 'package:raajjepro/features/search/data/search_api.dart';
import 'package:raajjepro/features/search/presentation/filters_sheet.dart';
import 'package:raajjepro/features/search/presentation/search_copy.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 15 — **Search results** and **Category results**, from
/// `Discovery.dc.html`. One screen, because the server answers both from one
/// endpoint and the artboard draws them as one layout with two headers.
///
/// - **Sort**: Distance, Rating, Price, in the plan's order (Round 12).
///   Distance is island-relative. It ranks listings that serve fewer
///   islands first, because the system knows islands and nothing finer
///   (decision 36), so nothing here prints kilometres.
/// - **Filters**: the island (the session's browsing island, shared with
///   Explore's pill), Category on a search, Price, Mode and §1g's
///   Maldivian-owned. The dropdown chips and the filters button open the one
///   Filters sheet the owner approved on 2026-10-10. There is **no emergency
///   filter** (Round 23) and **no tier filter**.
/// - **Every card states its booking mode** and the mode's second signal
///   ([PublicServiceCard]), and a result priority placement moved up says
///   `Sponsored`.
///
/// Four states, the artboard's own: skeleton cards; "Results didn't load",
/// which says nothing was filtered out; an empty state that names its reason
/// (filters, the query, or a category not yet on this island); and the
/// list, paged by "Show 12 more".
class SearchResultsScreen extends ConsumerWidget {
  const SearchResultsScreen({required this.args, super.key});

  static const routeName = AppRoutes.search;

  final SearchArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final filters = ref.watch(searchFiltersProvider(args));
    final results = ref.watch(searchResultsProvider(args));
    final island = ref.watch(browsingIslandProvider);
    final total = results.hasValue && !results.isLoading
        ? results.requireValue.total
        : null;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(args: args, total: total, island: island),
            if (!args.isCategory && total != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xl,
                  AppSpacing.xxs,
                  AppSpacing.xl,
                  0,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: serviceCount(total),
                        style: type.secondary.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                      ),
                      if (args.query.trim().isNotEmpty)
                        TextSpan(
                          text: ' for “${args.query.trim()}”',
                          style: type.secondary.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            _SortRow(args: args, sort: filters.sort),
            _FilterRow(args: args, filters: filters, island: island),
            Expanded(
              child: switch (results) {
                AsyncValue(isLoading: true) => const _ResultsSkeleton(),
                AsyncError(:final error) => _Centered(
                  child: EmptyState.error(
                    title: errorTitle,
                    body: error is ApiNetworkException
                        ? errorBodyOffline
                        : errorBodyServer,
                    onRetry: () =>
                        ref.read(searchResultsProvider(args).notifier).reload(),
                  ),
                ),
                AsyncData(:final value) when value.items.isEmpty => _Empty(
                  args: args,
                  filters: filters,
                  island: island,
                ),
                AsyncData(:final value) => _ResultList(
                  args: args,
                  results: value,
                ),
                _ => const _ResultsSkeleton(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Back, then the query (a search) or the category and its count (a
/// category's results), then Saved: the artboard's header row.
class _Header extends ConsumerWidget {
  const _Header({
    required this.args,
    required this.total,
    required this.island,
  });

  final SearchArgs args;
  final int? total;
  final Island? island;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.md2,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          CircleBackButton(
            semanticLabel: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpacing.sm2),
          Expanded(
            child: args.isCategory
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          args.categoryName ?? 'Services',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.sectionHeading.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        [
                          if (total != null) serviceCount(total!),
                          if (island != null) island!.displayName,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.secondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : _QueryPill(query: args.query),
          ),
          const SizedBox(width: AppSpacing.sm2),
          const _SavedButton(),
        ],
      ),
    );
  }
}

/// The search as typed. Tapping it goes back to Explore's field, holding the
/// same words, to change them: the artboard's `editSearch`.
class _QueryPill extends StatelessWidget {
  const _QueryPill({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final shown = query.trim().isEmpty ? 'All services' : query.trim();
    return Pressable(
      semanticLabel: 'Search: $shown. Edit search',
      onTap: () => Navigator.of(context).maybePop(query),
      focusRadius: AppRadius.input,
      builder: (context, s) => Container(
        height: AppSizes.iconButtonSize,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md2,
        ),
        decoration: BoxDecoration(
          color: s.pressed ? colors.surfaceMuted : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: AppSizes.iconMd,
              color: colors.placeholder,
            ),
            const SizedBox(width: AppSpacing.n9),
            Expanded(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.secondary.copyWith(color: colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saved, as on Explore: navigation, not a toggle. A guest is sent to sign
/// in, because saving needs an account (§1c: Registered).
class _SavedButton extends ConsumerWidget {
  const _SavedButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final signedIn = ref.watch(authControllerProvider) is AuthSignedIn;
    return Pressable(
      onTap: () =>
          Navigator.of(context)
              .pushNamed(signedIn ? AppRoutes.saved : AppRoutes.signIn),
      semanticLabel: 'Saved',
      tooltip: 'Saved',
      focusRadius: AppRadius.pill,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed ? colors.surfaceMuted : colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: SizedBox.square(
          dimension: AppSizes.iconButtonSize,
          child: Icon(
            Icons.favorite_border_rounded,
            size: AppSizes.iconLg,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _SortRow extends ConsumerWidget {
  const _SortRow({required this.args, required this.sort});

  final SearchArgs args;
  final SearchSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm2,
        AppSpacing.xl,
        0,
      ),
      child: Semantics(
        container: true,
        label: 'Sort',
        child: Row(
          children: [
            ExcludeSemantics(
              child: Text(
                'SORT',
                style: context.type.overline.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final option in SearchSort.values)
                    AppChip.filter(
                      label: option.label,
                      selected: option == sort,
                      onTap: () {
                        if (option == sort) return;
                        AppHaptics.selection();
                        ref
                            .read(searchFiltersProvider(args).notifier)
                            .sortBy(option);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The artboard's horizontally scrolling filter row: the filters button, a
/// divider, then Island, Category (a search only), Price, Mode and
/// Maldivian-owned.
class _FilterRow extends ConsumerWidget {
  const _FilterRow({
    required this.args,
    required this.filters,
    required this.island,
  });

  final SearchArgs args;
  final SearchFilters filters;
  final Island? island;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notifier = ref.read(searchFiltersProvider(args).notifier);

    Future<void> openSheet(FilterSection? focus) async {
      final next = await showFiltersSheet(
        context,
        current: filters,
        showCategory: !args.isCategory,
        islandId: island?.id,
        initial: notifier.initial,
        focus: focus,
      );
      if (next != null) notifier.apply(next);
    }

    final chips = <Widget>[
      _RowChip(
        label: island?.displayName ?? 'Island',
        semanticLabel: island == null
            ? 'Island: anywhere. Choose your island'
            : 'Island: ${island!.displayName}. Change island',
        on: island != null,
        dropdown: true,
        onTap: () => showIslandPicker(context),
      ),
      if (!args.isCategory)
        _RowChip(
          label: filters.categoryName ?? 'Category',
          semanticLabel: 'Category: ${filters.categoryName ?? 'any'}',
          on: filters.categoryId != null,
          dropdown: true,
          onTap: () => openSheet(FilterSection.category),
        ),
      _RowChip(
        label: priceLabel(filters),
        semanticLabel:
            'Price: ${filters.hasPrice ? priceLabel(filters) : 'any'}',
        on: filters.hasPrice,
        dropdown: true,
        onTap: () => openSheet(FilterSection.price),
      ),
      _RowChip(
        label: modeLabel(filters.mode),
        semanticLabel:
            'How you book: ${filters.mode == null ? 'any' : modeLabel(filters.mode)}',
        on: filters.mode != null,
        dropdown: true,
        onTap: () => openSheet(FilterSection.mode),
      ),
      _RowChip(
        label: maldivianOwnedLabel,
        semanticLabel: maldivianOwnedTitle,
        on: filters.maldivianOwned,
        check: filters.maldivianOwned,
        toggle: true,
        onTap: () {
          AppHaptics.selection();
          notifier.toggleMaldivianOwned();
        },
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm2,
        AppSpacing.xl,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          Pressable(
            semanticLabel: 'All filters',
            tooltip: 'All filters',
            onTap: () => openSheet(null),
            focusRadius: AppRadius.md,
            builder: (context, s) => DecoratedBox(
              decoration: BoxDecoration(
                color: s.pressed ? colors.surfaceMuted : colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colors.border,
                  width: AppSizes.inputStroke,
                ),
              ),
              child: SizedBox.square(
                dimension: AppSizes.chipHeight,
                child: Icon(
                  Icons.tune_rounded,
                  size: AppSizes.iconMd,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ExcludeSemantics(
            child: SizedBox(
              width: AppSizes.dividerStroke,
              height: AppSpacing.xl2,
              child: ColoredBox(color: colors.border),
            ),
          ),
          for (final chip in chips) ...[
            const SizedBox(width: AppSpacing.sm),
            chip,
          ],
        ],
      ),
    );
  }
}

/// A filter-row chip, drawn as the artboard draws it: 38 high, 12 radius,
/// the accent tint when it is narrowing something, a chevron when it opens a
/// choice and a check when it is a toggle that is on.
class _RowChip extends StatelessWidget {
  const _RowChip({
    required this.label,
    required this.semanticLabel,
    required this.on,
    required this.onTap,
    this.dropdown = false,
    this.toggle = false,
    this.check = false,
  });

  final String label;
  final String semanticLabel;
  final bool on;
  final bool dropdown;
  final bool toggle;
  final bool check;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = on ? colors.accentText : colors.textTertiary;
    return Semantics(
      toggled: toggle ? on : null,
      child: Pressable(
        semanticLabel: semanticLabel,
        onTap: onTap,
        focusRadius: AppRadius.md,
        builder: (context, s) => AnimatedContainer(
          duration: context.motion.fast,
          height: AppSizes.chipHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.n13,
          ),
          decoration: BoxDecoration(
            color: on ? colors.accentTint : colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: on ? colors.accentBorder : colors.border,
              width: AppSizes.inputStroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (check) ...[
                Icon(Icons.check_rounded, size: AppSizes.iconSm, color: fg),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: context.type.secondary.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: AppSizes.iconSm,
                  color: fg,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({required this.args, required this.results});

  final SearchArgs args;
  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final notifier = ref.read(searchResultsProvider(args).notifier);
    final colors = context.colors;

    final rows = <Widget>[
      for (final result in results.items)
        PublicServiceCard(
          listing: result.listing,
          providerName: displayName(result.provider),
          providerTier: result.provider.tier,
          providerConduct: result.provider.conduct,
          sponsored: result.sponsored,
          now: now,
          onTap: () => Navigator.of(context).pushNamed(
            AppRoutes.listingPreview,
            arguments: <String, dynamic>{'listingId': result.listing.id},
          ),
        ),
      if (results.loadMoreFailed)
        Text(
          loadMoreFailed,
          textAlign: TextAlign.center,
          style: context.type.secondary.copyWith(color: colors.error),
        ),
      if (results.hasMore)
        AppButton.secondary(
          label: results.loadMoreFailed
              ? 'Try again'
              : 'Show ${SearchApi.pageSize} more',
          loading: results.loadingMore,
          onPressed: () => unawaited(notifier.loadMore()),
        ),
    ];

    final spaced = <Widget>[];
    for (final (index, row) in rows.indexed) {
      if (index > 0) spaced.add(const SizedBox(height: AppSpacing.md));
      spaced.add(row);
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm2,
        AppSpacing.xl,
        AppSpacing.n28,
      ),
      children: fadeUpAll(spaced),
    );
  }
}

/// Three empty states, each naming its own reason, which is what the
/// artboard does. Filters are narrowing everything out, or the query
/// matched nothing, or a category has nobody on this island yet.
class _Empty extends ConsumerWidget {
  const _Empty({
    required this.args,
    required this.filters,
    required this.island,
  });

  final SearchArgs args;
  final SearchFilters filters;
  final Island? island;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchFiltersProvider(args).notifier);

    final active = <({String label, VoidCallback remove})>[
      if (!args.isCategory && filters.categoryId != null)
        (
          label: filters.categoryName ?? 'Category',
          remove: () =>
              notifier.apply(filters.copyWith(category: (null, null))),
        ),
      if (filters.hasPrice)
        (
          label: priceLabel(filters),
          remove: () => notifier.apply(filters.copyWith(price: (null, null))),
        ),
      if (filters.mode != null)
        (
          label: modeLabel(filters.mode),
          remove: () => notifier.apply(filters.copyWith(mode: (null,))),
        ),
      if (filters.maldivianOwned)
        (label: maldivianOwnedLabel, remove: notifier.toggleMaldivianOwned),
    ];

    if (active.isNotEmpty) {
      final named = [
        ...active.map((a) => a.label),
        if (island != null) island!.displayName,
      ];
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final a in active)
                  AppChip.input(label: a.label, onRemove: a.remove),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            EmptyState(
              icon: Icons.search_rounded,
              title: noMatchTitle,
              body: filteredOutBody(named),
              actionLabel: 'Clear filters',
              onAction: notifier.clear,
            ),
          ],
        ),
      );
    }

    if (args.isCategory) {
      final category = args.categoryName ?? 'service';
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              icon: Icons.location_on_outlined,
              title: categoryEmptyTitle(category, island?.displayName),
              body: categoryEmptyBody,
              actionLabel: island == null
                  ? 'Choose your island'
                  : 'Change island',
              onAction: () => showIslandPicker(context),
            ),
            AppButton.text(
              label: 'Browse all services',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      );
    }

    return _Centered(
      child: EmptyState(
        icon: Icons.search_rounded,
        title: noMatchTitle,
        body: unmatchedBody(args.query),
        actionLabel: 'Browse categories',
        onAction: () => Navigator.of(context).maybePop(),
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

/// Card-shaped bones in the list's own layout: the artboard's four
/// `SkeletonCard`s, not a spinner.
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonLoader(
    label: 'Loading results',
    child: Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm2,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
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
