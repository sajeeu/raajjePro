import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/public/public_models.dart';

/// One saved service (`GET /v1/users/me/favorites/listings`): the card, and
/// the provider it belongs to — the Saved list mixes many providers, and the
/// card names each one and draws their badge.
///
/// **Nothing here can hold a phone number, an email or a bank detail**: both
/// halves are `core/public/` shapes, which parse only the fields they name.
@immutable
class SavedService {
  const SavedService({required this.listing, required this.provider});

  factory SavedService.fromJson(Map<String, dynamic> json) => SavedService(
    listing: PublicListingCard.fromJson(
      json['listing'] as Map<String, dynamic>,
    ),
    provider: PublicProvider.fromJson(json['provider'] as Map<String, dynamic>),
  );

  final PublicListingCard listing;
  final PublicProvider provider;
}

/// One saved provider (`GET /v1/users/me/favorites/providers`) —
/// `Discovery.dc.html`'s "Saved providers" row.
@immutable
class SavedProvider {
  const SavedProvider({
    required this.provider,
    required this.rating,
    required this.categories,
  });

  factory SavedProvider.fromJson(Map<String, dynamic> json) => SavedProvider(
    provider: PublicProvider.fromJson(json['provider'] as Map<String, dynamic>),
    rating: RatingTotals.fromJson(
      json['rating'] as Map<String, dynamic>? ?? const {},
    ),
    categories: (json['categories'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PublicCategory.fromJson)
        .toList(),
  );

  final PublicProvider provider;
  final RatingTotals rating;

  /// What they offer, from their published services.
  final List<PublicCategory> categories;
}

/// The Saved screen's two reads, each paged to the end the way
/// `BookingApi.list` is — the screen shows everything saved, and the server
/// keeps every page bounded.
class SavedApi {
  const SavedApi(this._api);

  final ApiClient _api;

  /// A runaway-cursor guard, not a product limit: 20 pages of 50.
  static const _maxPages = 20;

  Future<List<SavedService>> services() =>
      _all('/v1/users/me/favorites/listings', SavedService.fromJson);

  Future<List<SavedProvider>> providers() =>
      _all('/v1/users/me/favorites/providers', SavedProvider.fromJson);

  Future<List<T>> _all<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final all = <T>[];
    String? cursor;
    for (var page = 0; page < _maxPages; page += 1) {
      final query = StringBuffer('?limit=50');
      if (cursor != null) query.write('&cursor=${Uri.encodeComponent(cursor)}');
      final response = await _api.get('$path$query');
      // `ApiClient` unwraps a list payload as `_list` and the envelope's meta
      // as `_meta` (`BookingApi.list` records the same).
      all.addAll(
        ((response['_list'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(parse),
      );
      final meta = response['_meta'];
      cursor = meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null;
      if (cursor == null) break;
    }
    return all;
  }
}

final savedApiProvider = Provider<SavedApi>(
  (ref) => SavedApi(ref.watch(apiClientProvider)),
);
