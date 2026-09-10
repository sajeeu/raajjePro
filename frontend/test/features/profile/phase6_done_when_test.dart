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
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/features/legal/presentation/legal_index_screen.dart';
import 'package:raajjepro/features/onboarding/presentation/become_provider_screen.dart';
import 'package:raajjepro/features/profile/controller/role_switch.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'helpers.dart';

/// §Phase 6's own Done-when list, one group per line:
///
/// > Profile reflects live data; every row navigates; switching to provider
/// > mode for the first time reaches the onboarding flow, and reaches My
/// > Services Dashboard directly on every subsequent switch.
///
/// Driven through the **real app and its real route table**, not a screen in
/// isolation, because two of the three lines are about routing: a row that
/// pushes a name nothing registered throws here rather than passing.
///
/// 🔧 **One of the two destinations behind the role switcher is now real.**
/// §Phase 6a built `BecomeProviderScreen`, so the first-switch assertion below
/// lands on the intro step rather than on a placeholder — which is the half of
/// ledger row **P6-1** that Phase 6a closes. §Phase 10's dashboard is still a
/// placeholder, and the signal itself moved from `isProvider` to onboarding
/// completeness in the same phase (`role_switch.dart` says why).
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

  /// Boots the real app signed in, then pushes Profile by its route name.
  Future<NavigatorState> bootToProfile(
    WidgetTester tester, {
    bool isProvider = false,
    bool onboardingComplete = false,
    String fullName = 'Aishath Naeema',
    String memberSince = '2026-01-14T08:30:00.000Z',
  }) async {
    api.on(
      'GET',
      '/v1/users/me/profile-summary',
      (_) => profileSummaryJson(
        fullName: fullName,
        memberSince: memberSince,
        isProvider: isProvider,
        providerOnboardingComplete: onboardingComplete,
      ),
    );
    await store.write(TokenPair.fromJson(tokensJson()));
    // A mobile viewport, as `pumpScreen` sets for every other screen test —
    // the 800 × 600 default is landscape-shaped and too short for a full
    // scrolling screen, so a row below the fold is untappable even though a
    // real phone would reach it.
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
    // Not awaited: `pushNamed`'s future completes when the route is *popped*,
    // so awaiting it here hangs the test forever.
    unawaited(nav.pushNamed<void>(ProfileScreen.routeName));
    await settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
    return nav;
  }

  group('Profile reflects live data', () {
    testWidgets('the name and join date are the ones the endpoint returned', (
      tester,
    ) async {
      await bootToProfile(
        tester,
        fullName: 'Ibrahim Rasheed',
        memberSince: '2026-03-02T11:00:00.000Z',
      );
      expect(find.text('Ibrahim Rasheed'), findsOneWidget);
      expect(find.text('Member since Mar 2026'), findsOneWidget);
      // The initials are derived from that same live name, not from the auth
      // state or a placeholder.
      expect(
        tester.widget<AppAvatar>(find.byType(AppAvatar)).name,
        'Ibrahim Rasheed',
      );
    });

    testWidgets('it is one call, and it is the one §Phase 6 names', (
      tester,
    ) async {
      await bootToProfile(tester);
      final profileReads = api.calls.where(
        (c) => c.path == '/v1/users/me/profile-summary',
      );
      expect(profileReads, hasLength(1));
    });

    testWidgets('a different account gets its own data, not the last one’s', (
      tester,
    ) async {
      await bootToProfile(tester, fullName: 'Aishath Naeema');
      expect(find.text('Aishath Naeema'), findsOneWidget);
      await bootToProfile(tester, fullName: 'Mariyam Hussain');
      expect(find.text('Mariyam Hussain'), findsOneWidget);
      expect(find.text('Aishath Naeema'), findsNothing);
    });
  });

  group('every row navigates', () {
    // The two that have a real screen today, and the three that name the
    // phase which owes them one. All five navigate; none is inert.
    testWidgets('Account settings reaches Phase 3’s real screen', (
      tester,
    ) async {
      await bootToProfile(tester);
      await tester.ensureVisible(find.text('Account settings'));
      await tester.tap(find.text('Account settings'));
      await settle(tester);
      expect(find.byType(AccountSettingsScreen), findsOneWidget);
    });

    testWidgets('Legal reaches the document index, marked as placeholder', (
      tester,
    ) async {
      await bootToProfile(tester);
      await tester.ensureVisible(find.text('Legal'));
      await tester.tap(find.text('Legal'));
      await settle(tester);
      expect(find.byType(LegalIndexScreen), findsOneWidget);
      expect(
        find.text('Placeholder — legal text pending review'),
        findsOneWidget,
      );
      // No invented binding text anywhere on the path (root CLAUDE.md 1d).
      expect(find.textContaining('hereby'), findsNothing);
      await tester.tap(find.text('Terms of Service'));
      await settle(tester);
      expect(find.text('1. Scope'), findsOneWidget);
    });

    testWidgets('the three unbuilt rows each name the phase that owes them', (
      tester,
    ) async {
      const owed = {
        'Saved': 'Phase 14',
        // 🔧 Was Phase 7 until 2026-09-10. Phase 7 seeded `Island` and
        // built the picker but does not own this screen — §1h's "carried
        // forward by Book Again" puts it in 17.4
        // (`docs/decisions/19-phase-7-service-areas.md`, decision 1).
        'Saved preferences': 'Phase 17.4',
        'Help & support': 'Phase 19b',
      };
      await bootToProfile(tester);
      for (final entry in owed.entries) {
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await settle(tester);
        final screen = tester.widget<UnbuiltScreen>(find.byType(UnbuiltScreen));
        expect(screen.title, entry.key, reason: entry.key);
        expect(screen.owedBy, entry.value, reason: entry.key);
        // It says so rather than doing nothing — the point of the screen.
        expect(find.text('${entry.key} is not built yet'), findsOneWidget);
        await tester.tap(find.text('Go back'));
        await settle(tester);
        expect(find.byType(ProfileScreen), findsOneWidget);
      }
    });
  });

  group('the role switcher routes on onboarding completeness', () {
    /// Opens the sheet and chooses Provider.
    Future<void> switchToProviding(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Switch to providing'));
      await tester.tap(find.text('Switch to providing'));
      await settle(tester);
      // The sheet states the rule before acting on it.
      expect(find.text("How you're using RaajjePro"), findsOneWidget);
      expect(find.text("You're here now"), findsOneWidget);
      await tester.tap(find.text('Provider'));
      await settle(tester);
    }

    testWidgets('a first switch reaches onboarding, never the wizard', (
      tester,
    ) async {
      // §Phase 6a's own first Done-when line, from the Profile side: the
      // intro step, not `/services/new`.
      api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      await bootToProfile(tester, isProvider: false);
      await switchToProviding(tester);
      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      expect(find.text('Offer your services on RaajjePro'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.byType(UnbuiltScreen), findsNothing);
    });

    testWidgets('a returning provider reaches the dashboard directly', (
      tester,
    ) async {
      await bootToProfile(tester, isProvider: true, onboardingComplete: true);
      await switchToProviding(tester);
      final screen = tester.widget<UnbuiltScreen>(find.byType(UnbuiltScreen));
      expect(screen.title, 'My Services');
      expect(screen.owedBy, 'Phase 10');
      // §Phase 6a's Done-when: a provider who has completed it never sees the
      // flow again.
      expect(find.byType(BecomeProviderScreen), findsNothing);
    });

    testWidgets('a provider mid-onboarding is sent back into it, not on', (
      tester,
    ) async {
      // The case `isProvider` alone could not see. Step 2 has landed — so a
      // profile exists and `isProvider` is true — and step 3 has not.
      api.on(
        'GET',
        '/v1/providers/me',
        (_) => {
          'businessName': "Hassan's Repairs",
          'providerType': 'individual',
          'paymentDetails': {
            'bankName': 'Bank of Maldives (BML)',
            'bankAccountName': 'Hassan Ibrahim',
            'bankAccountNumber': '7730000123456',
          },
          'serviceAreas': <Object>[],
          'onboardingComplete': false,
        },
      );
      api.on('GET', '/v1/islands', (_) => {'_list': <Object>[]});
      await bootToProfile(tester, isProvider: true, onboardingComplete: false);
      await switchToProviding(tester);
      expect(find.byType(BecomeProviderScreen), findsOneWidget);
      // Resumed at the step they stopped on, not restarted at the intro.
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Where do you usually work?'), findsOneWidget);
    });

    testWidgets('the sheet closes, so Back from the destination is Profile', (
      tester,
    ) async {
      api.fail(
        'GET',
        '/v1/providers/me',
        status: 404,
        code: 'PROVIDER_PROFILE_NOT_FOUND',
      );
      await bootToProfile(tester, isProvider: false);
      await switchToProviding(tester);
      // §Phase 6a's "Not right now" — back to customer mode, nothing saved.
      await tester.tap(find.text('Not right now'));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text("How you're using RaajjePro"), findsNothing);
    });

    testWidgets('"Not now" leaves the sheet and changes nothing', (
      tester,
    ) async {
      await bootToProfile(tester, isProvider: false);
      await tester.ensureVisible(find.text('Switch to providing'));
      await tester.tap(find.text('Switch to providing'));
      await settle(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(find.text("How you're using RaajjePro"), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(UnbuiltScreen), findsNothing);
    });

    testWidgets('the decision itself, without a screen in the way', (
      tester,
    ) async {
      // The rule as one expression, so it cannot drift from the UI test above
      // and so §Phase 6a and §Phase 10 have something to read.
      //
      // 🔧 **Phase 6a changed the input from `isProvider` to onboarding
      // completeness.** The two are not the same moment: onboarding's step 2
      // creates the provider profile, so `isProvider` flips one step early
      // and a provider who stopped on step 3 was being sent to the dashboard
      // instead of back to the step they left. §Phase 6a's own Done-when says
      // it is a provider who "already completed onboarding" who never sees
      // the flow again. `role_switch.dart` carries the full note.
      expect(
        RoleSwitch.destinationFor(onboardingComplete: false),
        RoleSwitch.onboardingRoute,
      );
      expect(
        RoleSwitch.destinationFor(onboardingComplete: true),
        RoleSwitch.dashboardRoute,
      );
    });
  });

  group('signing out', () {
    testWidgets('leaves Profile, rather than showing a signed-out name', (
      tester,
    ) async {
      // Needs a real stack: `signOut()` clears the session and `AuthGate`
      // swaps to the guest home *underneath*, so a Profile left on top would
      // sit there still showing the name of the account that just signed out.
      // `app.dart`'s listener pops only for a session expiry, not for this.
      api.on('POST', '/v1/auth/logout', (_) => {'loggedOut': true});
      await bootToProfile(tester, fullName: 'Aishath Naeema');
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await settle(tester);

      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.text('Aishath Naeema'), findsNothing);
      // Back on the guest home: the account is signed out, not just hidden.
      expect(find.text('Sign in'), findsOneWidget);
      expect(await store.read(), isNull);
    });

    testWidgets('a second account does not inherit the first one’s summary', (
      tester,
    ) async {
      // The provider is `isAutoDispose`, so nothing survives the account it
      // describes. Without it the previous person's name renders and the role
      // switcher routes on their `isProvider` — and it would not show up in
      // the tests above, which rebuild the ProviderScope on every boot.
      api.on('POST', '/v1/auth/logout', (_) => {'loggedOut': true});
      await bootToProfile(tester, fullName: 'Aishath Naeema');
      expect(find.text('Aishath Naeema'), findsOneWidget);

      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await settle(tester);

      // Same app instance, same ProviderScope — a different account signs in.
      api.on(
        'GET',
        '/v1/users/me/profile-summary',
        (_) => profileSummaryJson(
          id: 'user-2',
          fullName: 'Mariyam Hussain',
          isProvider: true,
        ),
      );
      await store.write(TokenPair.fromJson(tokensJson()));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.pushNamed<void>(ProfileScreen.routeName));
      await settle(tester);

      expect(find.text('Mariyam Hussain'), findsOneWidget);
      expect(find.text('Aishath Naeema'), findsNothing);
    });
  });
}
