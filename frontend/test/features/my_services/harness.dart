import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/my_services/presentation/my_services_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Everything a My Services test drives.
///
/// The four reads the dashboard opens with are scripted together, because the
/// screen fetches them together: the provider profile (the badge), the
/// entitlement (the cap the over-cap copy names), the listings, and the
/// catalogue (the card's category chip and which listings have a slot grid).
class MyServicesHarness {
  MyServicesHarness() : api = FakeApiClient();

  final FakeApiClient api;

  /// A fixed clock, so "Updated 2 days ago" is a fact rather than a race.
  static final DateTime now = DateTime.utc(2026, 9, 16, 6);

  void script({
    required List<Map<String, dynamic>> listings,
    required List<Map<String, dynamic>> categories,
    String verificationTier = 'none',
    String? businessName = "Hassan's Repairs",
    bool suspended = false,
    int? activeListingCap = 1,
  }) {
    api.on(
      'GET',
      '/v1/providers/me',
      (_) => providerJson(
        verificationTier: verificationTier,
        businessName: businessName,
        suspended: suspended,
      ),
    );
    api.on(
      'GET',
      '/v1/providers/me/subscription',
      (_) => subscriptionJson(activeListingCap: activeListingCap),
    );
    api.on(
      'GET',
      '/v1/providers/me/listings?limit=50',
      (_) => {'_list': listings, '_meta': <String, dynamic>{}},
    );
    api.on('GET', '/v1/categories', (_) => {'_list': categories});
  }

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const MyServicesScreen(),
    overrides: [
      apiClientProvider.overrideWithValue(api),
      clockProvider.overrideWithValue(() => now),
    ],
  );

  /// Calls made after the opening four — what a test asserting "no manual
  /// refresh" looks at.
  Iterable<({String method, String path, Object? body})> get listingCalls =>
      api.calls.where((c) => c.path.startsWith('/v1/providers/me/listings'));
}

/// `GET /v1/providers/me`, as much of `OwnProviderDto` as the dashboard reads.
///
/// **The tier and the subscription are separate fixtures on purpose.** §1e
/// makes them different axes, and a test that degraded both together would
/// pass while proving nothing about the badge surviving a lapse.
Map<String, dynamic> providerJson({
  String verificationTier = 'none',
  String? businessName = "Hassan's Repairs",
  bool suspended = false,
}) => {
  'id': 'provider-1',
  'userId': 'user-1',
  'businessName': businessName,
  'verificationTier': verificationTier,
  // The other axis entirely: the review state of a pending submission. Left
  // at its default so nothing in a test can accidentally read it as the
  // badge.
  'verificationStatus': 'unverified',
  'acceptingNewCustomers': true,
  'suspended': suspended,
  'suspendedReason': null,
  'serviceAreas': const <Map<String, dynamic>>[],
  'onboardingComplete': true,
};

/// `GET /v1/providers/me/subscription` — the free-tier shape by default, which
/// is what a provider who has never paid actually has.
Map<String, dynamic> subscriptionJson({
  int? activeListingCap = 1,
  String tier = 'free',
  String status = 'none',
  String? downgradedAt,
}) => {
  'tier': tier,
  'status': status,
  'entitlements': {
    'activeListingCap': activeListingCap,
    'analytics': activeListingCap == null,
    'priorityPlacement': activeListingCap == null,
  },
  'trial': {
    'startedAt': null,
    'endsAt': null,
    'daysRemaining': null,
    'available': true,
  },
  'billing': {
    'anchorAt': null,
    'currentPeriodEnd': null,
    'daysRemaining': null,
    'nextPaymentAmountLaari': 15000,
    'priceLaari': null,
    'introductory': true,
    'introductoryConvertsAt': null,
  },
  'pause': {
    'paused': false,
    'pausedAt': null,
    'cumulativePausedDays': 0,
    'remainingPauseAllowanceDays': 10,
    'forcedResumeDueAt': null,
  },
  'acceptingNewCustomers': true,
  'downgradedAt': downgradedAt,
  'latestSubmission': null,
};
