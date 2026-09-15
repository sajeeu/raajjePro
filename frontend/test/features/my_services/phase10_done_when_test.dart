import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';
import 'package:raajjepro/features/my_services/presentation/my_services_screen.dart';
import 'package:raajjepro/features/my_services/presentation/widgets/service_card.dart';
import 'package:raajjepro/features/onboarding/presentation/become_provider_screen.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/features/service_wizard/presentation/service_wizard_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import '../profile/helpers.dart';
import 'harness.dart';

/// §Phase 10's Done-when list, driven through the **real app and its real
/// route table**:
///
/// > every context-menu action performs a real mutation with no manual
/// > refresh; a drafts-only provider sees a correct zero state; the badge
/// > persists through a subscription lapse.
///
/// Plus the bullet that is a routing claim rather than a rendering one —
/// "reachable in one action from the Phase 6 role switcher" — which is also
/// ledger row **P6-1**'s remaining half, and which only the real route table
/// can prove: until this phase, `/provider/services` resolved to the
/// placeholder that owed it.
void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;
  var bootCount = 0;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': <Object>[]});
  });

  Map<String, dynamic> published({
    String id = 'listing-1',
    String name = 'AC Service & Repair',
    String visibility = 'active',
  }) =>
      publishableListingJson(
          id: id,
          categoryId: 'cat-ac',
          status: 'published',
        ).cast<String, dynamic>()
        ..['name'] = name
        ..['visibility'] = visibility
        ..['missingRequiredFields'] = const <Map<String, dynamic>>[];

  void scriptDashboard({
    required List<Map<String, dynamic>> listings,
    String verificationTier = 'none',
    int? activeListingCap = 1,
  }) {
    api.on(
      'GET',
      '/v1/providers/me',
      (_) => providerJson(verificationTier: verificationTier),
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
    api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
  }

  /// Boots the real app signed in and pushes Profile — the same entry
  /// §Phase 6a's Done-when test uses, because the role switcher lives there
  /// and is the way into provider mode that exists today.
  Future<NavigatorState> bootToProfile(
    WidgetTester tester, {
    required bool onboardingComplete,
  }) async {
    api.on(
      'GET',
      '/v1/users/me/profile-summary',
      (_) => profileSummaryJson(
        isProvider: true,
        providerOnboardingComplete: onboardingComplete,
      ),
    );
    await store.write(TokenPair.fromJson(tokensJson()));
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(bootCount++),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
          crashReporterProvider.overrideWithValue(NoopCrashReporter()),
          deviceNameProvider.overrideWith((_) async => 'Test'),
        ],
        child: const RaajjeProApp(),
      ),
    );
    await settle(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    // Not awaited: `pushNamed`'s future completes when the route is popped.
    unawaited(nav.pushNamed<void>(ProfileScreen.routeName));
    await settle(tester);
    return nav;
  }

  Future<void> switchToProviding(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Switch to providing'));
    await tester.tap(find.text('Switch to providing'));
    await settle(tester);
    await tester.tap(find.text('Provider'));
    await settle(tester);
  }

  Future<void> openCardMenu(WidgetTester tester) async {
    final menu = find.bySemanticsLabel(RegExp('More options for'));
    await tester.ensureVisible(menu.first);
    await settle(tester);
    await tester.tap(menu.first);
    await settle(tester);
  }

  group('reachable in one action from the role switcher', () {
    /// 🔧 **Closes ledger row P6-1.** Its remaining question was whether the
    /// switcher's later switch reaches a real dashboard; until today
    /// `/provider/services` was an `UnbuiltScreen` naming this phase. The row
    /// asks for both branches in one place, so both are here: a provider who
    /// finished onboarding lands on the dashboard, and one who did not is
    /// still taken back into the flow.
    testWidgets('a completed provider switches straight onto My Services', (
      tester,
    ) async {
      scriptDashboard(listings: [published()]);
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      expect(find.byType(MyServicesScreen), findsOneWidget);
      expect(find.text('My Services'), findsWidgets);
      // Not a placeholder standing in for the screen.
      expect(find.byType(UnbuiltScreen), findsNothing);
      expect(find.byType(ServiceCard), findsOneWidget);
    });

    testWidgets('a provider mid-onboarding still goes back into the flow', (
      tester,
    ) async {
      api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      await bootToProfile(tester, onboardingComplete: false);
      await switchToProviding(tester);

      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      expect(find.byType(MyServicesScreen), findsNothing);
    });
  });

  group('every context-menu action performs a real mutation, no manual '
      'refresh', () {
    testWidgets('Pause writes the visibility the provider owns and the card '
        'changes without re-listing', (tester) async {
      scriptDashboard(listings: [published()]);
      api.on(
        'PATCH',
        '/v1/providers/me/listings/listing-1/visibility',
        (_) => published(visibility: 'hidden_by_provider'),
      );
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      await openCardMenu(tester);
      await tester.tap(find.text('Pause — hide from customers'));
      await settle(tester);

      final patch = api.calls.last;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/v1/providers/me/listings/listing-1/visibility');
      // §1b: the provider's own value, never the entitlement system's.
      expect(patch.body, {'visibility': 'hidden_by_provider'});
      expect(find.text('Hidden'), findsWidgets);
      expect(
        api.calls
            .where(
              (c) =>
                  c.method == 'GET' &&
                  c.path == '/v1/providers/me/listings?limit=50',
            )
            .length,
        1,
      );
    });

    testWidgets('Remove confirms first, then soft-deletes, and the card '
        'leaves the list', (tester) async {
      scriptDashboard(
        listings: [
          published(),
          published(id: 'listing-2'),
        ],
      );
      api.on(
        'DELETE',
        '/v1/providers/me/listings/listing-1',
        (_) => published(),
      );
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);
      expect(find.byType(ServiceCard), findsNWidgets(2));

      await openCardMenu(tester);
      await tester.tap(find.text('Remove service'));
      await settle(tester);

      // Nothing has happened yet — the confirmation is the mutation's gate.
      expect(
        api.calls.where((c) => c.method == 'DELETE'),
        isEmpty,
        reason: 'opening the confirmation must not delete anything',
      );
      expect(find.textContaining('stay in your account'), findsOneWidget);

      await tester.tap(find.text('Remove service').last);
      await settle(tester);

      expect(api.calls.last.method, 'DELETE');
      expect(find.byType(ServiceCard), findsOneWidget);
      expect(
        api.calls
            .where(
              (c) =>
                  c.method == 'GET' &&
                  c.path == '/v1/providers/me/listings?limit=50',
            )
            .length,
        1,
      );
    });

    testWidgets('Edit opens the wizard on this listing, not a fresh draft', (
      tester,
    ) async {
      scriptDashboard(listings: [published()]);
      api.on('GET', '/v1/providers/me/listings/listing-1', (_) => published());
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      await openCardMenu(tester);
      await tester.tap(find.text('Edit service'));
      await settle(tester);

      expect(find.byType(ServiceWizardScreen), findsOneWidget);
      // Resumed: read by id, never a POST that would have made a second one.
      expect(
        api.calls.map((c) => '${c.method} ${c.path}'),
        contains('GET /v1/providers/me/listings/listing-1'),
      );
      expect(
        api.calls.where(
          (c) => c.method == 'POST' && c.path == '/v1/providers/me/listings',
        ),
        isEmpty,
      );
    });

    testWidgets('View as customer reaches the phase that owes the public '
        'page', (tester) async {
      scriptDashboard(listings: [published()]);
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      await openCardMenu(tester);
      await tester.tap(find.text('View as customer'));
      await settle(tester);

      expect(find.textContaining('Phase 12'), findsWidgets);
    });
  });

  group('a drafts-only provider sees a correct zero state', () {
    testWidgets('no live count, no measured zeros, and the reason they are '
        'not in search', (tester) async {
      scriptDashboard(
        listings: [listingJson(categoryId: 'cat-ac', name: 'Half-typed')],
      );
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      // The dashboard renders — a drafts-only provider is not an empty one.
      expect(find.byType(ServiceCard), findsOneWidget);
      expect(find.text('Draft'), findsWidgets);

      // Nothing is live, and the screen says what that costs them. Scoped to
      // the stats tile: the card's own view and booking counts are also zero,
      // and on a draft that is structurally true rather than a measurement.
      expect(
        find.descendant(
          of: find.byType(StatMiniCard),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('you don’t appear in search until you publish'),
        findsOneWidget,
      );

      // Views and bookings are **absent**, not zero: nothing has been
      // published, so nothing could have been counted
      // (`frontend/CLAUDE.md`: a metric with no data reads "No data yet").
      expect(find.text('No data yet'), findsNWidgets(2));

      // And the one action that moves them forward is on the card.
      expect(find.text('Finish & publish'), findsOneWidget);
    });
  });

  group('the badge persists through a subscription lapse', () {
    /// §1e, and §Phase 10's own bullet: the badge is gated by
    /// `verificationTier` **alone**.
    ///
    /// The two axes are set separately on purpose — the provider is `silver`
    /// *and* degraded to the free tier with a listing the entitlement system
    /// has hidden. Degrading both together would pass while proving nothing.
    testWidgets('a silver provider whose plan has lapsed keeps the badge and '
        'its §1e words', (tester) async {
      scriptDashboard(
        verificationTier: 'silver',
        activeListingCap: 1,
        listings: [
          published(),
          published(
            id: 'listing-2',
            name: 'Home Deep Cleaning',
            visibility: 'hidden_over_cap',
          ),
        ],
      );
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      // The lapse is real and visible on this very screen.
      expect(
        find.textContaining('Your free plan includes 1 live service'),
        findsOneWidget,
      );

      // And the badge is untouched, carrying §1e's copy verbatim — which
      // `VerificationBadge` owns, so a screen cannot drift from it.
      expect(find.byType(VerificationBadge), findsOneWidget);
      expect(find.text('ID checked, work verified'), findsOneWidget);
      expect(
        find.textContaining('it stays with you even if a subscription lapses'),
        findsOneWidget,
      );
      // The bare word is banned app-wide by `design_rules_test.dart`'s
      // source scan — which is also why this test cannot assert its absence
      // by writing it.
    });

    testWidgets('and a provider at none renders no badge at all, rather than '
        'an empty one', (tester) async {
      scriptDashboard(listings: [published()]);
      await bootToProfile(tester, onboardingComplete: true);
      await switchToProviding(tester);

      expect(find.byType(VerificationBadge), findsNothing);
    });
  });
}
