import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/features/provider_profile/presentation/provider_profile_screen.dart';
import 'package:raajjepro/features/saved/presentation/saved_copy.dart';
import 'package:raajjepro/features/saved/presentation/saved_screen.dart';
import 'package:raajjepro/features/service_preview/presentation/service_preview_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/provider_profile.dart';
import '../../helpers/public_listing.dart';
import '../../helpers/pump.dart';
import '../../helpers/saved.dart';
import '../bookings/harness.dart' show FixedAuthController;
import '../profile/helpers.dart';

/// §Phase 14 — **Done when:** "tapping the heart anywhere persists via API;
/// the Saved Services screen reflects it immediately; Profile's count
/// updates."
///
/// "Anywhere" is every heart the app draws today: a service card's (the
/// provider profile's grid, the Saved list), the listing page's hero, the
/// provider page's header (Round 15: saving a provider), and the Saved
/// screen's own. The server half of each clause is
/// `backend/test/phase14-done-when.test.ts`.
void main() {
  final now = DateTime.utc(2026, 9, 15, 3);
  late FavoritesFakeApi api;
  late Map<String, Object?> pushed;

  setUp(() {
    api = FavoritesFakeApi();
    pushed = {};
  });

  AuthState signedIn({bool verified = true}) => AuthSignedIn(
    UserAccount.fromJson({
      'id': 'customer-1',
      'fullName': 'Aishath Naeema',
      'email': 'aishath@example.mv',
      'emailVerified': verified,
      'phone': {'dialCode': '+960', 'number': '7771234'},
      'status': 'active',
      'deletionDeadlineAt': null,
      'isProvider': false,
      'createdAt': '2026-09-06T10:00:00.000Z',
    }),
  );

  List<Override> overrides(AuthState? auth) => [
    apiClientProvider.overrideWithValue(api),
    clockProvider.overrideWithValue(() => now),
    authControllerProvider.overrideWith(
      () => FixedAuthController(auth ?? signedIn()),
    ),
  ];

  Map<String, WidgetBuilder> recorders() => {
    for (final name in [
      AppRoutes.listingPreview,
      AppRoutes.signIn,
      AppRoutes.verifyEmail,
      AppRoutes.providerProfile,
      AppRoutes.explore,
    ])
      name: (context) {
        pushed[name] = ModalRoute.of(context)?.settings.arguments;
        return Scaffold(body: Text('opened $name'));
      },
  };

  Future<void> pumpProfilePage(WidgetTester tester, {AuthState? auth}) {
    api.on('GET', '/v1/providers/prov-1/public', (_) => providerProfileJson());
    return pumpScreen(
      tester,
      const ProviderProfileScreen(
        args: ProviderProfileArgs(providerId: 'prov-1'),
      ),
      overrides: overrides(auth),
      routes: recorders(),
    );
  }

  Future<void> pumpPreview(WidgetTester tester, {AuthState? auth}) {
    api
      ..on('GET', '/v1/listings/listing-1/public', (_) => publicListingJson())
      ..on(
        'GET',
        '/v1/listings/listing-1/reviews?limit=3',
        (_) => {'_list': <dynamic>[], '_meta': <String, dynamic>{}},
      );
    return pumpScreen(
      tester,
      const ServicePreviewScreen(
        args: ServicePreviewArgs(listingId: 'listing-1'),
      ),
      overrides: overrides(auth),
      routes: recorders(),
    );
  }

  Future<void> pumpSaved(WidgetTester tester, {AuthState? auth}) => pumpScreen(
    tester,
    const SavedScreen(),
    overrides: overrides(auth),
    routes: recorders(),
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  bool heartSaved(WidgetTester tester, Finder heart) => tester
      .widget<SaveHeartToggle>(
        find.descendant(of: heart, matching: find.byType(SaveHeartToggle)),
      )
      .saved;

  Finder cardHeart(String listingId) => find.byWidgetPredicate(
    (w) => w is ListingSaveHeart && w.listingId == listingId,
  );

  // ---------------------------------------------------------------------------
  group('1. tapping the heart anywhere persists via the API', () {
    testWidgets('a service card’s heart saves, then unsaves, the service', (
      tester,
    ) async {
      await pumpProfilePage(tester);
      expect(heartSaved(tester, cardHeart('listing-1')), isFalse);

      await tapVisible(tester, cardHeart('listing-1'));
      expect(api.writes, ['PUT listings/listing-1']);
      expect(heartSaved(tester, cardHeart('listing-1')), isTrue);

      await tapVisible(tester, cardHeart('listing-1'));
      expect(api.writes, [
        'PUT listings/listing-1',
        'DELETE listings/listing-1',
      ]);
      expect(heartSaved(tester, cardHeart('listing-1')), isFalse);
    });

    testWidgets('the listing page’s hero heart saves the service', (
      tester,
    ) async {
      await pumpPreview(tester);
      await tapVisible(tester, cardHeart('listing-1'));
      expect(api.writes, ['PUT listings/listing-1']);
      expect(heartSaved(tester, cardHeart('listing-1')), isTrue);
    });

    testWidgets('the provider page’s header heart saves the provider '
        '(Round 15), and says so as a toggle', (tester) async {
      await pumpProfilePage(tester);
      final save = find.bySemanticsLabel('Save this provider');
      expect(
        tester.getSemantics(save).getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
      );

      await tapVisible(tester, save);
      expect(api.writes, ['PUT providers/prov-1']);
      expect(
        tester.getSemantics(save).getSemanticsData().flagsCollection.isToggled,
        Tristate.isTrue,
      );
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('a heart already saved on the server reads saved on arrival', (
      tester,
    ) async {
      api.savedListings.add('listing-2');
      api.savedProviders.add('prov-1');
      await pumpProfilePage(tester);
      await settle(tester);
      expect(heartSaved(tester, cardHeart('listing-1')), isFalse);
      expect(heartSaved(tester, cardHeart('listing-2')), isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Save this provider'))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
    });

    testWidgets('a refused save turns the heart back and says so', (
      tester,
    ) async {
      api.offline('PUT', '/v1/users/me/favorites/listings/listing-1');
      await pumpProfilePage(tester);
      await tapVisible(tester, cardHeart('listing-1'));
      expect(heartSaved(tester, cardHeart('listing-1')), isFalse);
      expect(find.text(saveFailedCopyForTest(saved: true)), findsOneWidget);
    });

    testWidgets('a guest is sent to sign in, and nothing is sent', (
      tester,
    ) async {
      await pumpProfilePage(tester, auth: const AuthGuest());
      await tapVisible(tester, cardHeart('listing-1'));
      expect(find.text('opened ${AppRoutes.signIn}'), findsOneWidget);
      expect(api.writes, isEmpty);
    });

    testWidgets('one saved state: the same service’s heart agrees everywhere', (
      tester,
    ) async {
      await pumpProfilePage(tester);
      await tapVisible(tester, cardHeart('listing-1'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProviderProfileScreen)),
      );
      expect(
        container.read(favoritesProvider).listingSaved('listing-1'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('2. the Saved screen reflects it immediately', () {
    testWidgets('lists saved services and providers, with the counts', (
      tester,
    ) async {
      scriptSaved(
        api,
        services: [savedServiceJson()],
        providers: [savedProviderJson()],
      );
      await pumpSaved(tester);

      expect(find.text('1 service · 1 provider'), findsOneWidget);
      expect(find.text('Saved services'), findsOneWidget);
      expect(find.byType(PublicServiceCard), findsOneWidget);
      expect(find.text('Saved providers'), findsOneWidget);
      expect(find.text(providersIntro), findsOneWidget);
      // The business name heads the row (decision 34); what they offer beneath.
      expect(find.text('Lens & Light Studio'), findsOneWidget);
      expect(find.text('Photography'), findsOneWidget);
      expect(find.text('4.9 (58)'), findsOneWidget);
      // Both hearts are red without a second lookup.
      expect(heartSaved(tester, cardHeart('listing-1')), isTrue);
      expectNoSwallowedControls(tester);
    });

    testWidgets('unsaving a provider removes the row at once and persists', (
      tester,
    ) async {
      scriptSaved(api, providers: [savedProviderJson()]);
      api.savedProviders.add('prov-2');
      await pumpSaved(tester);

      await tapVisible(
        tester,
        find.bySemanticsLabel('Remove Lens & Light Studio from saved'),
      );
      expect(api.writes, ['DELETE providers/prov-2']);
      expect(find.text('Lens & Light Studio'), findsNothing);
      expect(find.text(removedCopy), findsOneWidget);
    });

    testWidgets('unsaving a service from its card removes it at once', (
      tester,
    ) async {
      scriptSaved(api, services: [savedServiceJson()]);
      await pumpSaved(tester);
      await tapVisible(tester, cardHeart('listing-1'));
      expect(api.writes, ['DELETE listings/listing-1']);
      expect(find.byType(PublicServiceCard), findsNothing);
      // The last thing gone: the screen says what to do next.
      expect(find.text(emptyTitle), findsOneWidget);
    });

    testWidgets('a refused unsave puts the row back and says so', (
      tester,
    ) async {
      scriptSaved(api, providers: [savedProviderJson()]);
      api.offline('DELETE', '/v1/users/me/favorites/providers/prov-2');
      await pumpSaved(tester);
      await tapVisible(
        tester,
        find.bySemanticsLabel('Remove Lens & Light Studio from saved'),
      );
      expect(find.text('Lens & Light Studio'), findsOneWidget);
      expect(find.text(saveFailedCopyForTest(saved: false)), findsOneWidget);
    });

    testWidgets('empty: names what to do next', (tester) async {
      scriptSaved(api);
      await pumpSaved(tester);
      expect(find.text(emptyTitle), findsOneWidget);
      await tapVisible(tester, find.text('Browse services'));
      expect(find.text('opened ${AppRoutes.explore}'), findsOneWidget);
    });

    testWidgets('error: says nothing is lost, and Try again loads it', (
      tester,
    ) async {
      api
        ..offline('GET', '/v1/users/me/favorites/listings?limit=50')
        ..on(
          'GET',
          '/v1/users/me/favorites/providers?limit=50',
          (_) => {'_list': <Object>[]},
        );
      await pumpSaved(tester);
      expect(find.text(errorTitle), findsOneWidget);
      expect(find.text(errorBody), findsOneWidget);

      scriptSaved(api, services: [savedServiceJson()]);
      await tapVisible(tester, find.text('Try again'));
      expect(find.byType(PublicServiceCard), findsOneWidget);
    });

    testWidgets('loading: skeleton, not a spinner', (tester) async {
      scriptSaved(api);
      api.gate = Completer<void>();
      await pumpScreen(tester, const SavedScreen(), overrides: overrides(null));
      expect(find.byType(SkeletonLoader), findsOneWidget);
      api.gate!.complete();
      await settle(tester);
      expect(find.byType(SkeletonLoader), findsNothing);
    });

    testWidgets('the provider’s name opens their profile; Message passes the '
        'email gate to §Phase 18', (tester) async {
      scriptSaved(api, providers: [savedProviderJson()]);
      await pumpSaved(tester, auth: signedIn(verified: false));

      await tapVisible(tester, find.text('Lens & Light Studio'));
      expect(pushed[AppRoutes.providerProfile], {'providerId': 'prov-2'});
      Navigator.of(
        tester.element(find.text('opened ${AppRoutes.providerProfile}')),
      ).pop();
      await settle(tester);

      await tapVisible(
        tester,
        find.bySemanticsLabel('Message Lens & Light Studio'),
      );
      expect(find.text('opened ${AppRoutes.verifyEmail}'), findsOneWidget);
    });

    testWidgets(
      'a verified customer’s Message lands on the phase that owes it',
      (tester) async {
        scriptSaved(api, providers: [savedProviderJson()]);
        await pumpSaved(tester);
        await tapVisible(
          tester,
          find.bySemanticsLabel('Message Lens & Light Studio'),
        );
        expect(find.text('Messages is not built yet'), findsOneWidget);
        expect(find.textContaining('Phase 18'), findsOneWidget);
      },
    );

    testWidgets('nothing on the screen is a phone number or a person’s name', (
      tester,
    ) async {
      scriptSaved(
        api,
        services: [savedServiceJson()],
        providers: [savedProviderJson()],
      );
      await pumpSaved(tester);
      final painted = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' | ');
      expect(painted, isNot(contains('7771234')));
      expect(painted, isNot(contains('@')));
    });
  });

  // ---------------------------------------------------------------------------
  group("3. Profile's count updates", () {
    testWidgets('the Saved row carries the count, and a save moves it', (
      tester,
    ) async {
      var services = 2;
      api.on(
        'GET',
        '/v1/users/me/profile-summary',
        (_) => profileSummaryJson(savedServices: services, savedProviders: 1),
      );
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: overrides(null),
      );
      final row = find.widgetWithText(SettingsRow, 'Saved');
      expect(
        find.descendant(of: row, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(row),
        matchesSemantics(
          label: 'Saved, 3',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      // A save accepted anywhere — here, through the one saved state.
      services = 3;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
      );
      await container
          .read(favoritesProvider.notifier)
          .set(FavoriteKind.listing, 'listing-9', saved: true);
      await settle(tester);
      expect(
        find.descendant(of: row, matching: find.text('4')),
        findsOneWidget,
      );
    });

    testWidgets('nothing saved draws no number', (tester) async {
      api.on(
        'GET',
        '/v1/users/me/profile-summary',
        (_) => profileSummaryJson(),
      );
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: overrides(null),
      );
      final row = find.widgetWithText(SettingsRow, 'Saved');
      expect(find.descendant(of: row, matching: find.text('0')), findsNothing);
    });
  });
}

/// The rollback sentences, restated rather than imported: the test pins the
/// words the artboard uses, so a change to them is a decision, not a refactor.
String saveFailedCopyForTest({required bool saved}) => saved
    ? 'Couldn’t save — check your connection.'
    : 'Couldn’t remove — restored. Check your connection.';
