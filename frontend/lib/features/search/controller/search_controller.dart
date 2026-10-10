import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/location/browsing_island_controller.dart';
import 'package:raajjepro/features/search/data/search_api.dart';

// `retry: null` (frontend/CLAUDE.md): the screen has its own retry.
Duration? _noRetry(int retryCount, Object error) => null;

/// What one results screen was opened with. It is a search (a query, which
/// may be empty) or a category's results. Results screens are keyed by it,
/// so two of them in the stack never share filters.
@immutable
class SearchArgs {
  const SearchArgs({this.query = '', this.categoryId, this.categoryName});

  /// The untyped route arguments, read the way the other public screens
  /// read theirs, so Explore and Home can open results without importing
  /// this feature.
  factory SearchArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    return SearchArgs(
      query: map['query'] as String? ?? '',
      categoryId: map['categoryId'] as String?,
      categoryName: map['categoryName'] as String?,
    );
  }

  final String query;
  final String? categoryId;
  final String? categoryName;

  /// A category's own results, as opposed to a search.
  bool get isCategory => categoryId != null;

  @override
  bool operator ==(Object other) =>
      other is SearchArgs &&
      other.query == query &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(query, categoryId);
}

/// The filters a results screen is showing. They start from its [SearchArgs]
/// and change through the sort chips, the filter chips and the Filters sheet.
final searchFiltersProvider =
    NotifierProvider.family<SearchFiltersController, SearchFilters, SearchArgs>(
      SearchFiltersController.new,
      isAutoDispose: true,
    );

class SearchFiltersController extends Notifier<SearchFilters> {
  SearchFiltersController(this.args);

  final SearchArgs args;

  /// What this screen started with, so "Clear filters" returns to it rather
  /// than to nothing. A category screen keeps its category.
  SearchFilters get initial => SearchFilters(
    query: args.query,
    categoryId: args.categoryId,
    categoryName: args.categoryName,
  );

  @override
  SearchFilters build() => initial;

  void sortBy(SearchSort sort) => state = state.copyWith(sort: sort);

  void toggleMaldivianOwned() =>
      state = state.copyWith(maldivianOwned: !state.maldivianOwned);

  /// The Filters sheet's Apply.
  void apply(SearchFilters next) => state = next;

  /// Everything but the sort, back to how the screen opened.
  void clear() => state = SearchFilters(
    query: args.query,
    categoryId: args.categoryId,
    categoryName: args.categoryName,
    sort: state.sort,
  );
}

/// What a results screen shows: every page loaded so far, and how "Show 12
/// more" stands.
@immutable
class SearchResults {
  const SearchResults({
    required this.total,
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final int total;
  final List<SearchResult> items;
  final String? nextCursor;
  final bool loadingMore;

  /// The last "Show 12 more" failed. Shown inline under the list, where
  /// the customer can try again (frontend/CLAUDE.md).
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;

  SearchResults copyWith({
    List<SearchResult>? items,
    (String?,)? nextCursor,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => SearchResults(
    total: total,
    items: items ?? this.items,
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor.$1,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// §Phase 15's results. A changed filter, sort or island reads from the first
/// page again: the filters and the island are watched, so changing either
/// rebuilds this.
final searchResultsProvider =
    AsyncNotifierProvider.family<
      SearchResultsController,
      SearchResults,
      SearchArgs
    >(SearchResultsController.new, isAutoDispose: true, retry: _noRetry);

class SearchResultsController extends AsyncNotifier<SearchResults> {
  SearchResultsController(this.args);

  final SearchArgs args;

  @override
  Future<SearchResults> build() async {
    final filters = ref.watch(searchFiltersProvider(args));
    final island = ref.watch(browsingIslandProvider);
    final page = await ref
        .read(searchApiProvider)
        .page(filters, islandId: island?.id);
    return SearchResults(
      total: page.total,
      items: page.items,
      nextCursor: page.nextCursor,
    );
  }

  /// The error state's retry.
  void reload() => ref.invalidateSelf();

  /// "Show 12 more". The next page comes from the cursor the server issued,
  /// so nothing repeats or goes missing across the boundary, including the
  /// one between sponsored and unsponsored results.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreFailed: false),
    );
    final filters = ref.read(searchFiltersProvider(args));
    final island = ref.read(browsingIslandProvider);
    try {
      final page = await ref
          .read(searchApiProvider)
          .page(filters, islandId: island?.id, cursor: current.nextCursor);
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          nextCursor: (page.nextCursor,),
          loadingMore: false,
          // `current` is the snapshot from before this attempt, which may
          // carry the last attempt's failure.
          loadMoreFailed: false,
        ),
      );
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }
}
