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
import 'package:raajjepro/features/onboarding/presentation/become_provider_screen.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/features/service_wizard/presentation/service_wizard_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/islands.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import '../profile/helpers.dart';

/// §Phase 6a's Done-when list, driven through the **real app and its real
/// route table**:
///
/// > a brand-new user going through Home's "Become a Provider" CTA or
/// > Phase 6's role switcher lands on the intro screen, not the wizard
/// > directly; completing account details persists phone and payment details
/// > onto the Provider Profile via the existing Phase 5 update endpoint; the
/// > flow hands off into a fresh wizard draft; a provider who already
/// > completed onboarding never sees it again, going straight to the
/// > dashboard or a resumed draft instead.
///
/// Line 2's *endpoint* half is the backend's and is asserted in
/// `backend/test/phase6a-onboarding.test.ts`; what is asserted here is which
/// call the app makes. The rest are routing lines, and routing is exactly what
/// a screen test in isolation cannot prove — a push to a name nothing
/// registered throws here rather than passing.
///
/// **Home's "Become a Provider" CTA does not exist yet.** §Phase 16 builds the
/// Home feed; the role switcher is the entry that exists today, and ledger row
/// **P6A-1** carries the other one.
void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;
  var bootCount = 0;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': <Object>[]});
    api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
  });

  Map<String, dynamic> profileJson({
    List<Map<String, dynamic>> serviceAreas = const [],
    bool onboardingComplete = false,
  }) => {
    'businessName': "Hassan's Repairs",
    'providerType': 'individual',
    'bio': null,
    'acceptingNewCustomers': true,
    'paymentDetails': {
      'bankName': 'Bank of Maldives (BML)',
      'bankAccountName': 'Hassan Ibrahim',
      'bankAccountNumber': '7730000123456',
      'transferInstructions': null,
    },
    'serviceAreas': serviceAreas,
    'onboardingComplete': onboardingComplete,
  };

  /// Boots the real app signed in and pushes Profile, exactly as
  /// `phase6_done_when_test.dart` does — the role switcher lives there and is
  /// the only entry into this flow that exists today.
  Future<NavigatorState> bootToProfile(
    WidgetTester tester, {
    required bool isProvider,
    required bool onboardingComplete,
  }) async {
    api.on(
      'GET',
      '/v1/users/me/profile-summary',
      (_) => profileSummaryJson(
        isProvider: isProvider,
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

  group('lands on the intro screen, not the wizard directly', () {
    testWidgets('a brand-new user reaches step 1 through the role switcher', (
      tester,
    ) async {
      api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      await bootToProfile(tester, isProvider: false, onboardingComplete: false);
      await switchToProviding(tester);

      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      // Not the wizard, and not a placeholder standing in for this flow.
      expect(find.byType(UnbuiltScreen), findsNothing);
    });
  });

  group('the flow hands off into a fresh wizard draft', () {
    /// 🔧 **Closes ledger row P6A-2.** Until §Phase 9 existed this asserted
    /// that `/services/new` resolved to the placeholder that owed the wizard —
    /// the handoff was real but what it opened onto could not be checked,
    /// because there was no wizard and no `Listing` table. Both exist now, so
    /// the assertion is the one the row actually asked for.
    testWidgets('step 1 opens a genuinely fresh draft, not the last one', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      api.on('POST', '/v1/providers/me/listings', (_) => listingJson());
      api.on(
        'PATCH',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(serviceAreas: [sampleIslands().first]),
      );

      await bootToProfile(tester, isProvider: true, onboardingComplete: false);
      await switchToProviding(tester);

      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('onboarding-start-service')));
      await settle(tester);

      // The real route table's answer for `/services/new` is now the wizard,
      // opened on step 1.
      expect(find.byType(ServiceWizardScreen), findsOneWidget);
      expect(find.text('Step 1 of 7 · Details'), findsOneWidget);
      expect(find.byType(BecomeProviderScreen), findsNothing);

      // **Fresh, not resumed.** The only listing call is the creation: nothing
      // listed the provider's drafts and nothing read one by id, so there was
      // no most-recent draft for it to reopen. The name field is empty for the
      // same reason.
      final listingCalls = api.calls
          .where((c) => c.path.startsWith('/v1/providers/me/listings'))
          .toList();
      expect(listingCalls.first.method, 'POST');
      expect(listingCalls.map((c) => c.method), isNot(contains('GET')));
      final nameField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('wizard-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(nameField.controller!.text, isEmpty);
      // Five, not six: the progress framing §Phase 9 asks for, counting the
      // island the pre-fill just satisfied.
      expect(find.text('5 required fields left to publish'), findsOneWidget);
    });

    testWidgets('step 2 pre-fills from the account-level service areas', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      api.on('POST', '/v1/providers/me/listings', (_) => listingJson());
      api.on(
        'PATCH',
        '/v1/providers/me/listings/listing-1',
        (_) => listingJson(serviceAreas: [sampleIslands().first]),
      );

      await bootToProfile(tester, isProvider: true, onboardingComplete: false);
      await switchToProviding(tester);
      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('onboarding-start-service')));
      await settle(tester);

      // Copied across once, at creation, by **island id** — never by name
      // (§0.0 item 12), and never by sharing the account-level rows: what is
      // written is the listing's own set (ledger P7-3), which is what
      // discovery will match on.
      final patch = api.calls.firstWhere((c) => c.method == 'PATCH');
      expect(patch.path, '/v1/providers/me/listings/listing-1');
      expect((patch.body! as Map)['serviceAreaIslandIds'], [
        sampleIslands().first['id'],
      ]);

      await tester.tap(find.text('Location'));
      await settle(tester);
      expect(find.text('Location & service area'), findsOneWidget);
      expect(
        find.text(sampleIslands().first['displayName']! as String),
        findsWidgets,
      );
    });
  });

  group('a provider who already completed onboarding never sees it again', () {
    /// 🔧 **Updated by §Phase 10, 2026-09-15.** This asserted the
    /// `UnbuiltScreen` that owed My Services, and the screen now exists — the
    /// tripwire goes with the wiring, which is what those placeholders are
    /// for. It also asserted that the switch *did not read the provider
    /// profile*, which was a claim about the routing decision rather than
    /// about the destination: the dashboard reads `/v1/providers/me` itself,
    /// for §1e's badge. That claim still has a home — `RoleSwitch
    /// .destinationFor` is a pure function of `onboardingComplete` and
    /// `phase6_done_when_test.dart` asserts it directly.
    testWidgets('goes straight to the dashboard', (tester) async {
      api.on('GET', '/v1/providers/me', (_) => profileJson());
      api.on(
        'GET',
        '/v1/providers/me/subscription',
        (_) => {
          'tier': 'free',
          'status': 'none',
          'entitlements': {'activeListingCap': 1},
        },
      );
      api.on(
        'GET',
        '/v1/providers/me/listings?limit=50',
        (_) => {'_list': <Object>[], '_meta': <String, dynamic>{}},
      );
      api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});

      await bootToProfile(tester, isProvider: true, onboardingComplete: true);
      await switchToProviding(tester);

      expect(find.byType(MyServicesScreen), findsOneWidget);
      expect(find.byType(UnbuiltScreen), findsNothing);
      expect(find.byType(BecomeProviderScreen), findsNothing);
    });

    testWidgets('but one who stopped mid-flow resumes where they left off', (
      tester,
    ) async {
      // The distinction `isProvider` could not draw: this account HAS a
      // provider profile (step 2 created it) and has not finished.
      api.on('GET', '/v1/providers/me', (_) => profileJson());
      await bootToProfile(tester, isProvider: true, onboardingComplete: false);
      await switchToProviding(tester);

      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      // Not restarted from the intro — §Phase 6a's resume rule, not a replay.
      expect(find.text('Offer your services on RaajjePro'), findsNothing);
    });

    testWidgets('a provider-variant registration is not onboarded either', (
      tester,
    ) async {
      // §Phase 3 creates a minimal profile for the provider registration
      // variant: a business name and nothing else. It must reach onboarding,
      // not a dashboard it never set up.
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => {
          'businessName': 'Test Trade',
          'providerType': null,
          'bio': null,
          'acceptingNewCustomers': true,
          'paymentDetails': {
            'bankName': null,
            'bankAccountName': null,
            'bankAccountNumber': null,
            'transferInstructions': null,
          },
          'serviceAreas': <Object>[],
          'onboardingComplete': false,
        },
      );
      await bootToProfile(tester, isProvider: true, onboardingComplete: false);
      await switchToProviding(tester);

      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      // Step 2, because that is what is unfinished — and pre-filled with the
      // name Phase 3 already captured.
      expect(find.text('Step 2 of 3'), findsOneWidget);
      final name = tester.widget<AppTextField>(
        find.byKey(const Key('onboarding-name')),
      );
      expect(name.controller!.text, 'Test Trade');
    });
  });

  group('completing account details, from the app’s side', () {
    testWidgets('sends the payment details to the Phase 5 endpoint', (
      tester,
    ) async {
      // The endpoint's behaviour is `backend/test/phase6a-onboarding.test.ts`;
      // this asserts the app calls it rather than a parallel one §Phase 6a
      // told it not to create.
      api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      api.on(
        'PATCH',
        '/v1/providers/me',
        (_) => profileJson(serviceAreas: [sampleIslands().first]),
      );
      await bootToProfile(tester, isProvider: false, onboardingComplete: false);
      await switchToProviding(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('onboarding-name')),
        "Hassan's Repairs",
      );
      await tester.ensureVisible(find.text('Individual'));
      await tester.tap(find.text('Individual'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('onboarding-holder')));
      await tester.enterText(
        find.byKey(const Key('onboarding-holder')),
        'Hassan Ibrahim',
      );
      await tester.enterText(
        find.byKey(const Key('onboarding-account')),
        '7730000123456',
      );
      await tester.ensureVisible(find.text('Select your bank'));
      await tester.tap(find.text('Select your bank'));
      await settle(tester);
      await tester.tap(find.text('Bank of Maldives (BML)').last);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await settle(tester);

      final writes = api.calls
          .where((c) => c.method == 'PATCH' || c.method == 'POST')
          .toList();
      expect(writes.map((c) => c.path), ['/v1/providers/me']);
      // No endpoint §Phase 6a was told not to create.
      expect(
        api.calls.map((c) => c.path),
        isNot(contains('/v1/providers/me/onboarding')),
      );
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });
  });
}
