import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/categories/categories_controller.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/listings/listing_api.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/features/my_services/data/provider_workspace_api.dart';

// `retry: null`, for the reason every controller here passes it: Riverpod 3
// retries a failed `build()` with exponential backoff for ~30s before the
// screen's own error branch is reached, which fights the explicit "Try again"
// the error state offers (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Which of the three filter pills is selected. The wire values are §Phase 8's
/// `status` enum plus "everything", because that is what the pills mean.
enum ServiceFilter {
  all('All'),
  published('Published'),
  draft('Draft');

  const ServiceFilter(this.label);
  final String label;
}

/// List or grid. A display preference, held for the session and nowhere else
/// — §Phase 10 asks for the toggle, and no part of the plan says the choice
/// is remembered across launches.
enum ServiceLayout { list, grid }

/// Everything the dashboard renders, fetched together.
///
/// The categories travel with the listings because the card needs a category
/// *name* and §Phase 8's own-listing shape carries only `categoryId` — which
/// is correct, since the catalogue is admin-editable from §Phase 10b and a
/// name copied onto a listing would go stale the moment it is renamed.
class MyServicesState {
  const MyServicesState({
    required this.provider,
    required this.cap,
    required this.listings,
    required this.categories,
  });

  final ProviderWorkspace provider;
  final EntitlementCap cap;
  final List<ServiceListing> listings;
  final List<ServiceCategory> categories;

  ServiceCategory? categoryOf(ServiceListing listing) {
    for (final category in categories) {
      if (category.id == listing.categoryId) return category;
    }
    return null;
  }

  /// Listings a customer can actually find: published **and** `active`
  /// (§1b, Round 17). Deliberately not "published", which is the other axis
  /// and is what the filter pills switch on.
  int get liveCount => listings.where((l) => l.isLive).length;

  bool get hasPublished =>
      listings.any((l) => l.status == ListingStatus.published);

  bool get hasDrafts => listings.any((l) => l.status == ListingStatus.draft);

  /// Rolled up from §Phase 8's event log. Null where nothing could have been
  /// counted yet — a provider with no published listing has never been seen
  /// by anybody, and `0` there reads as a measured failure rather than as an
  /// absence (`frontend/CLAUDE.md`: a metric with no data reads "No data
  /// yet", never a zero).
  int? get totalViews => hasPublished
      ? listings.fold<int>(0, (sum, l) => sum + l.viewCount)
      : null;

  int? get totalBookings => hasPublished
      ? listings.fold<int>(0, (sum, l) => sum + l.bookingCount)
      : null;

  /// The listings §Phase 9a's Availability screen has anything to say about.
  /// A `request` listing has no slot grid, so an entry point into one would
  /// open a screen with nothing on it.
  List<ServiceListing> get slotListings => listings
      .where((l) => categoryOf(l)?.bookingMode == BookingMode.slot)
      .toList(growable: false);

  List<ServiceListing> where(ServiceFilter filter) => switch (filter) {
    ServiceFilter.all => listings,
    ServiceFilter.published =>
      listings
          .where((l) => l.status == ListingStatus.published)
          .toList(growable: false),
    ServiceFilter.draft =>
      listings
          .where((l) => l.status == ListingStatus.draft)
          .toList(growable: false),
  };

  MyServicesState withListings(List<ServiceListing> listings) =>
      MyServicesState(
        provider: provider,
        cap: cap,
        listings: List.unmodifiable(listings),
        categories: categories,
      );
}

final myServicesControllerProvider =
    AsyncNotifierProvider<MyServicesController, MyServicesState>(
      MyServicesController.new,
      retry: _noRetry,
    );

/// §Phase 10's dashboard, and the four mutations its context menu and live
/// toggle perform.
///
/// **Every mutation writes through the server and adopts what comes back.**
/// §Phase 10's Done-when is "every context-menu action performs a real
/// mutation with no manual refresh", and the two halves of that sentence pull
/// in opposite directions unless the response is used: the screen must not
/// re-fetch, and it must not draw a state the server did not confirm. So the
/// live toggle flips optimistically for the tap to feel immediate, and the
/// server's own listing replaces it a moment later — or the previous one is
/// put back and the refusal is said out loud, which is the case that actually
/// happens (toggling a second listing live on the free tier is refused by the
/// cap).
class MyServicesController extends AsyncNotifier<MyServicesState> {
  @override
  Future<MyServicesState> build() => _load();

  Future<MyServicesState> _load() async {
    final workspace = ref.read(providerWorkspaceApiProvider);
    final listings = ref.read(listingApiProvider);
    // Together rather than in sequence: four independent reads behind one
    // skeleton, so the dashboard does not appear in four stages.
    final results = await Future.wait<Object>([
      workspace.read(),
      workspace.cap(),
      listings.listOwn(),
      ref.read(categoriesControllerProvider.future),
    ]);
    return MyServicesState(
      provider: results[0] as ProviderWorkspace,
      cap: results[1] as EntitlementCap,
      listings: List.unmodifiable(results[2] as List<ServiceListing>),
      categories: results[3] as List<ServiceCategory>,
    );
  }

  Future<void> reload() async {
    state = const AsyncLoading<MyServicesState>();
    state = await AsyncValue.guard(_load);
  }

  /// Called when a screen this one pushed comes back — the wizard, most of
  /// all, which can have published, renamed or deleted a listing while it was
  /// gone. Silent: no skeleton, because the dashboard is already on screen
  /// and replacing it with a loading state would read as a bug.
  Future<void> refreshQuietly() async {
    final current = state.value;
    if (current == null) return;
    try {
      state = AsyncData(await _load());
    } on ApiException {
      // Keep what is on screen. A failed background refresh is not worth
      // taking a working dashboard away from a provider.
    } on ApiNetworkException {
      // Same.
    }
  }

  /// The live toggle and the menu's Pause / Resume — one mutation behind two
  /// controls, because they are one thing (§1b: `active` ⇄
  /// `hidden_by_provider`, the only two values the provider owns).
  ///
  /// Returns null on success, or the message to show when the server refused.
  Future<String?> setLive(ServiceListing listing, {required bool live}) async {
    final current = state.value;
    if (current == null) return null;
    final previous = current.listings;
    final target = live
        ? ListingVisibility.active
        : ListingVisibility.hiddenByProvider;

    state = AsyncData(
      current.withListings(
        _replacing(previous, listing.copyWith(visibility: target)),
      ),
    );
    try {
      final saved = await ref
          .read(listingApiProvider)
          .setVisibility(listing.id, target);
      state = AsyncData(current.withListings(_replacing(previous, saved)));
      return null;
    } on ApiException catch (e) {
      state = AsyncData(current.withListings(previous));
      return e.message;
    } on ApiNetworkException {
      state = AsyncData(current.withListings(previous));
      return 'No connection — nothing was changed.';
    }
  }

  /// §1b's override: keep *this* one visible when the entitlement cap cannot
  /// hold them all (§Phase 10, "the provider can override the choice from the
  /// dashboard").
  ///
  /// **This is the one mutation that re-reads**, and it re-reads for a reason
  /// rather than for convenience: the server sets a pin and re-runs its own
  /// reconcile, so a second listing has changed too — which one is §1b's
  /// ranking to decide, and recomputing that here would be a second copy of
  /// the rule the plan is emphatic about keeping in one place. Still no
  /// *manual* refresh: the provider taps once and the screen is right.
  Future<String?> keepVisible(ServiceListing listing) async {
    try {
      await ref.read(listingApiProvider).keepVisible(listing.id);
      state = AsyncData(await _load());
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiNetworkException {
      return 'No connection — nothing was changed.';
    }
  }

  /// Invariant 8's soft delete. The listing leaves this screen because the
  /// server will not return it again; its bookings, reviews and event log
  /// stay exactly where they are.
  Future<String?> remove(ServiceListing listing) async {
    final current = state.value;
    if (current == null) return null;
    try {
      await ref.read(listingApiProvider).remove(listing.id);
      state = AsyncData(
        current.withListings(
          current.listings.where((l) => l.id != listing.id).toList(),
        ),
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on ApiNetworkException {
      return 'No connection — nothing was removed.';
    }
  }

  static List<ServiceListing> _replacing(
    List<ServiceListing> listings,
    ServiceListing replacement,
  ) => [
    for (final listing in listings)
      if (listing.id == replacement.id) replacement else listing,
  ];
}

/// The two display choices, kept out of the async state so that changing a
/// filter never touches the data and a reload never resets the view.
class MyServicesView {
  const MyServicesView({
    this.filter = ServiceFilter.all,
    this.layout = ServiceLayout.list,
  });

  final ServiceFilter filter;
  final ServiceLayout layout;

  MyServicesView copyWith({ServiceFilter? filter, ServiceLayout? layout}) =>
      MyServicesView(
        filter: filter ?? this.filter,
        layout: layout ?? this.layout,
      );
}

class MyServicesViewController extends Notifier<MyServicesView> {
  @override
  MyServicesView build() => const MyServicesView();

  void filter(ServiceFilter filter) => state = state.copyWith(filter: filter);

  void layout(ServiceLayout layout) => state = state.copyWith(layout: layout);
}

final myServicesViewProvider =
    NotifierProvider<MyServicesViewController, MyServicesView>(
      MyServicesViewController.new,
    );
