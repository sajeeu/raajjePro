import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';

/// §Phase 14's writes and the status lookup — every heart in the app goes
/// through these.
///
/// Save is `PUT` and unsave is `DELETE`, and both are idempotent on the
/// server, so a retry after a lost response lands on the state the customer
/// asked for rather than toggling it back. **Nothing here is queued offline**:
/// §0.0 item 14 limits the queue to three surfaces and a heart is not one of
/// them. A failed tap rolls back visibly instead (`FavoritesController`).
class FavoritesApi {
  const FavoritesApi(this._api);

  final ApiClient _api;

  static const _base = '/v1/users/me/favorites';

  Future<void> setListing(String listingId, {required bool saved}) async {
    final path = '$_base/listings/$listingId';
    await (saved ? _api.put(path) : _api.delete(path));
  }

  Future<void> setProvider(String providerId, {required bool saved}) async {
    final path = '$_base/providers/$providerId';
    await (saved ? _api.put(path) : _api.delete(path));
  }

  /// Which of these ids the caller has saved. The server takes at most
  /// [statusBatch] of each per call.
  Future<({Set<String> listingIds, Set<String> providerIds})> status({
    Iterable<String> listingIds = const [],
    Iterable<String> providerIds = const [],
  }) async {
    final query = <String>[
      if (listingIds.isNotEmpty) 'listingIds=${listingIds.join(',')}',
      if (providerIds.isNotEmpty) 'providerIds=${providerIds.join(',')}',
    ].join('&');
    final response = await _api.get('$_base/status?$query');
    Set<String> ids(String key) =>
        ((response[key] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toSet();
    return (listingIds: ids('listingIds'), providerIds: ids('providerIds'));
  }

  static const statusBatch = 100;
}

final favoritesApiProvider = Provider<FavoritesApi>(
  (ref) => FavoritesApi(ref.watch(apiClientProvider)),
);
