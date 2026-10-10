import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/public/public_models.dart';

/// §Phase 15's three sorts, in the plan's order (Round 12): distance, then
/// rating, then price.
enum SearchSort {
  distance('Distance'),
  rating('Rating'),
  price('Price');

  const SearchSort(this.label);

  /// The prototype's chip label.
  final String label;
}

/// What a result list is asked for, apart from the island. The island is
/// the session's one browsing island ([browsingIslandProvider]), shared with
/// the Explore header, so it is not a second copy kept here.
///
/// There is **no emergency field and no verification-tier field** (Round 23;
/// "no visibility difference between verified and unverified providers").
/// Nothing on this screen can narrow by either.
@immutable
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.categoryId,
    this.categoryName,
    this.mode,
    this.priceMinMvr,
    this.priceMaxMvr,
    this.maldivianOwned = false,
    this.sort = SearchSort.distance,
  });

  final String query;
  final String? categoryId;

  /// For the chips and the empty state's sentence. Never sent to the server.
  final String? categoryName;
  final BookingMode? mode;

  /// Whole rufiyaa, as a customer types them. Sent as laari (invariant 7).
  final int? priceMinMvr;
  final int? priceMaxMvr;

  /// §1g. Only `true` narrows.
  final bool maldivianOwned;
  final SearchSort sort;

  bool get hasPrice => priceMinMvr != null || priceMaxMvr != null;

  /// Fields are replaced, never merged. A `null` clears, which is what a
  /// filter sheet's "Any" means.
  SearchFilters copyWith({
    String? query,
    (String?, String?)? category,
    (BookingMode?,)? mode,
    (int?, int?)? price,
    bool? maldivianOwned,
    SearchSort? sort,
  }) => SearchFilters(
    query: query ?? this.query,
    categoryId: category == null ? categoryId : category.$1,
    categoryName: category == null ? categoryName : category.$2,
    mode: mode == null ? this.mode : mode.$1,
    priceMinMvr: price == null ? priceMinMvr : price.$1,
    priceMaxMvr: price == null ? priceMaxMvr : price.$2,
    maldivianOwned: maldivianOwned ?? this.maldivianOwned,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.query == query &&
      other.categoryId == categoryId &&
      other.mode == mode &&
      other.priceMinMvr == priceMinMvr &&
      other.priceMaxMvr == priceMaxMvr &&
      other.maldivianOwned == maldivianOwned &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    query,
    categoryId,
    mode,
    priceMinMvr,
    priceMaxMvr,
    maldivianOwned,
    sort,
  );
}

/// One result card. Both halves are `core/public/` shapes, which parse only
/// the fields they name, so **nothing here can hold a phone number, an email
/// or a bank detail**.
@immutable
class SearchResult {
  const SearchResult({
    required this.listing,
    required this.provider,
    required this.sponsored,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    listing: PublicListingCard.fromJson(
      json['listing'] as Map<String, dynamic>,
    ),
    provider: PublicProvider.fromJson(json['provider'] as Map<String, dynamic>),
    sponsored: json['sponsored'] as bool? ?? false,
  );

  final PublicListingCard listing;
  final PublicProvider provider;

  /// Priority placement moved it up. The server's fact, drawn as `Sponsored`.
  final bool sponsored;
}

@immutable
class SearchPage {
  const SearchPage({
    required this.total,
    required this.items,
    required this.nextCursor,
  });

  final int total;
  final List<SearchResult> items;
  final String? nextCursor;
}

/// `GET /v1/search/listings`. Open to a guest. Search and category results
/// both come from it.
class SearchApi {
  const SearchApi(this._api);

  final ApiClient _api;

  /// The prototype's "Show 12 more".
  static const pageSize = 12;

  Future<SearchPage> page(
    SearchFilters filters, {
    String? islandId,
    String? cursor,
    int limit = pageSize,
  }) async {
    final params = <String, String>{
      if (filters.query.trim().isNotEmpty) 'q': filters.query.trim(),
      'islandId': ?islandId,
      'categoryId': ?filters.categoryId,
      if (filters.mode != null) 'mode': filters.mode!.name,
      if (filters.priceMinMvr != null)
        'priceMinLaari': '${filters.priceMinMvr! * 100}',
      if (filters.priceMaxMvr != null)
        'priceMaxLaari': '${filters.priceMaxMvr! * 100}',
      if (filters.maldivianOwned) 'maldivianOwned': 'true',
      'sort': filters.sort.name,
      'limit': '$limit',
      'cursor': ?cursor,
    };
    final response = await _api.get(
      Uri(path: '/v1/search/listings', queryParameters: params).toString(),
    );
    final meta = response['_meta'];
    return SearchPage(
      total: response['total'] as int? ?? 0,
      items: (response['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SearchResult.fromJson)
          .toList(),
      nextCursor: meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null,
    );
  }
}

final searchApiProvider = Provider<SearchApi>(
  (ref) => SearchApi(ref.watch(apiClientProvider)),
);
