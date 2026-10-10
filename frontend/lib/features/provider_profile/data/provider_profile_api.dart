import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/public/public_models.dart';

/// `GET /v1/providers/:id/public` as the client holds it (§Phase 13).
///
/// **Nothing here can hold a phone number, an email or a bank detail** — it is
/// built from `core/public/` shapes that parse only the fields they name, so a
/// value the server should never send has nowhere to land (§1c).
@immutable
class PublicProviderProfile {
  const PublicProviderProfile({
    required this.provider,
    required this.rating,
    required this.tags,
    required this.listings,
  });

  factory PublicProviderProfile.fromJson(Map<String, dynamic> json) =>
      PublicProviderProfile(
        provider: PublicProvider.fromJson(
          json['provider'] as Map<String, dynamic>,
        ),
        rating: RatingTotals.fromJson(
          json['rating'] as Map<String, dynamic>? ?? const {},
        ),
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TagCount.fromJson)
            .toList(),
        listings: (json['listings'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PublicListingCard.fromJson)
            .toList(),
      );

  final PublicProvider provider;

  /// Across every service, deleted ones included.
  final RatingTotals rating;

  /// One per tag, only those three different customers applied (§1f).
  final List<TagCount> tags;

  /// Newest published first. Never empty — a provider with none is a 404.
  final List<PublicListingCard> listings;
}

/// Open to a guest. `ApiClient` attaches a token when there is one, but the
/// server reads nothing from it: the profile is the same for every viewer.
///
/// **Nothing here is queued offline** (§0.0 item 14) — a page read is retried
/// by hand.
class ProviderProfileApi {
  const ProviderProfileApi(this._api);

  final ApiClient _api;

  Future<PublicProviderProfile> read(String providerId) async =>
      PublicProviderProfile.fromJson(
        await _api.get('/v1/providers/$providerId/public'),
      );
}

final providerProfileApiProvider = Provider<ProviderProfileApi>(
  (ref) => ProviderProfileApi(ref.watch(apiClientProvider)),
);
