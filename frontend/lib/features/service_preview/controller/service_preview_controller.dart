import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_api.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';

// `retry: null`. Riverpod 3 auto-retries a failed `build()` with exponential
// backoff for ~30s before the screen's own error branch is reached, which
// fights the explicit "Try again" this screen provides (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Everything the Service Preview renders: the listing and a sample of its
/// reviews, fetched together behind one skeleton.
class ServicePreview {
  const ServicePreview({required this.listing, required this.reviews});

  final PublicListing listing;
  final List<PublicReview> reviews;
}

final servicePreviewProvider =
    AsyncNotifierProvider.family<
      ServicePreviewController,
      ServicePreview,
      String
    >(ServicePreviewController.new, isAutoDispose: true, retry: _noRetry);

class ServicePreviewController extends AsyncNotifier<ServicePreview> {
  ServicePreviewController(this.listingId);

  final String listingId;

  @override
  Future<ServicePreview> build() async {
    final api = ref.read(publicListingApiProvider);
    // The listing is the page; the reviews are a sample beneath it. A page
    // whose reviews could not load is still a page — the summary above them
    // came with the listing — so only the listing's failure fails the screen.
    final reviewsFuture = api
        .latestReviews(listingId)
        .then<List<PublicReview>>((r) => r)
        .catchError((Object _) => const <PublicReview>[]);
    final listing = await api.read(listingId);
    return ServicePreview(listing: listing, reviews: await reviewsFuture);
  }

  /// The error state's retry.
  Future<void> reload() async {
    state = const AsyncLoading<ServicePreview>();
    state = await AsyncValue.guard(build);
  }
}

/// Whether [error] is the server saying this listing is not public — a draft,
/// a hidden one, a deleted one, or a suspended provider's, all the same 404 —
/// as distinct from the connection dropping.
bool isListingUnavailable(Object error) =>
    error is ApiException && error.status == 404;
