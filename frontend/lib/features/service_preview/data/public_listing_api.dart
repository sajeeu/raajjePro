import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';

/// §Phase 12's reads: `GET /v1/listings/:id/public` and the first page of
/// `GET /v1/listings/:id/reviews`.
///
/// Both are open to a guest, and `ApiClient` attaches the bearer token when one
/// exists — which is how the server knows to set `viewerIsOwner`. There is no
/// owner check on this side to get wrong: the Edit control reads that one field.
///
/// **Nothing here is queued offline** (§0.0 item 14 keeps the queue to three
/// surfaces, and a page read is not one). A failed read is retried by hand.
///
/// **No response carries a phone number** — the models parse only named fields,
/// none of which could hold one (§1c).
class PublicListingApi {
  const PublicListingApi(this._api);

  final ApiClient _api;

  Future<PublicListing> read(String listingId) async =>
      PublicListing.fromJson(await _api.get('/v1/listings/$listingId/public'));

  /// The newest few. The page shows what the prototype shows — a sample under
  /// the summary — rather than paging the whole history inline.
  Future<List<PublicReview>> latestReviews(
    String listingId, {
    int limit = 3,
  }) async {
    final response = await _api.get(
      '/v1/listings/$listingId/reviews?limit=$limit',
    );
    final items = response['_list'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(PublicReview.fromJson)
        .toList();
  }
}

final publicListingApiProvider = Provider<PublicListingApi>(
  (ref) => PublicListingApi(ref.watch(apiClientProvider)),
);
