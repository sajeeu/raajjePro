import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/explore/presentation/tab_placeholder_screen.dart';
import 'package:raajjepro/features/explore/presentation/widgets/category_tile.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'helpers.dart';

/// Tripwires on the chrome Phase 4 renders but does not wire.
///
/// A comment naming the owning phase is documentation; these are the thing
/// that actually fails when someone wires a control and forgets that the
/// screen was built on the promise it was inert. **When Phase 15 attaches
/// search, the search test below fails and has to be deleted on purpose** —
/// which is the intended cost.
///
/// 🔧 **Three of them have now been paid.** Phase 6 built Profile, so the
/// header's account disc and the `Profile` nav tab have real destinations, and
/// Phase 7 built the island picker, so the header pill opens it. Their inert
/// assertions are gone — replaced by tests of where they go, which is the
/// state Phase 4 was holding the line for. 🔧 Phase 14 paid a fourth: the
/// Saved heart now opens Saved. 🔧 Phase 15 paid the search field and the
/// category tiles. The bell is still inert and still asserted.
///
/// The one control that is *absent* rather than inert is the emergency entry,
/// and it has its own test here for the same reason: it must not reappear as
/// a dead button.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient();
    api.on('GET', '/v1/categories', (_) => {'_list': seededTwelve()});
  });

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ExploreScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  /// The header's account control for a guest. Scoped by the `Pressable`:
  /// the Profile nav tab carries the same glyph but is not one of these.
  Finder accountDisc() => find
      .ancestor(
        of: find.byIcon(Icons.person_outline_rounded),
        matching: find.byType(Pressable),
      )
      .first;

  group('present, and doing nothing', () {
    testWidgets('the notification bell is drawn with no destination', (
      tester,
    ) async {
      await pump(tester);
      final header = tester.widget<AppHeader>(find.byType(AppHeader));
      final bell = header.actions.singleWhere(
        (a) => a.label == 'Notifications',
      );
      expect(bell.onTap, isNull);
    });
  });

  // 🔧 §Phase 15 paid the search field's and the tiles' debts. Their inert
  // tripwires are gone, replaced by where they go.
  group('search and the category tiles — Phase 15 owed these', () {
    Future<void> pumpWithResults(WidgetTester tester, List<Object?> seen) =>
        pumpScreen(
          tester,
          const ExploreScreen(),
          overrides: [apiClientProvider.overrideWithValue(api)],
          routes: {
            AppRoutes.search: (context) {
              seen.add(ModalRoute.of(context)?.settings.arguments);
              return const Scaffold(body: Text('results'));
            },
          },
        );

    testWidgets('the field takes a query and submits it to the results', (
      tester,
    ) async {
      final seen = <Object?>[];
      await pumpWithResults(tester, seen);
      expect(
        tester
            .widgetList<InertControl>(find.byType(InertControl))
            .where((c) => c.label == 'Search'),
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '  sofa clean ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('results'), findsOneWidget);
      expect(seen.single, {'query': 'sofa clean'});
    });

    testWidgets('the arrow submits too', (tester) async {
      final seen = <Object?>[];
      await pumpWithResults(tester, seen);
      await tester.enterText(find.byType(TextField), 'plumber');
      await tester.tap(find.bySemanticsLabel('Search'));
      await settle(tester);
      expect(seen.single, {'query': 'plumber'});
    });

    testWidgets("a category tile opens that category's results", (
      tester,
    ) async {
      final seen = <Object?>[];
      await pumpWithResults(tester, seen);
      final tile = tester.widget<CategoryTile>(find.byType(CategoryTile).first);
      await tester.tap(find.byType(CategoryTile).first);
      await settle(tester);
      expect(seen.single, {
        'categoryId': tile.category.id,
        'categoryName': tile.category.name,
      });
    });
  });

  group('the account disc', () {
    testWidgets('shows a generic disc for a guest, never invented initials', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(AppAvatar), findsNothing);
      // Two on the screen now: the header disc and the Profile nav tab carry
      // the same glyph, and neither may invent a name.
      expect(find.byIcon(Icons.person_outline_rounded), findsNWidgets(2));
    });

    testWidgets(
      'takes a guest to Sign in, not to a profile they have none of',
      (tester) async {
        await pumpScreen(
          tester,
          const ExploreScreen(),
          overrides: [apiClientProvider.overrideWithValue(api)],
          routes: {
            SignInScreen.routeName: (_) => const SignInScreen(),
            ProfileScreen.routeName: (_) => const ProfileScreen(),
          },
        );
        await tester.tap(accountDisc());
        await settle(tester);
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(ProfileScreen), findsNothing);
      },
    );

    testWidgets('shows the signed-in account’s own initials', (tester) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(
              AuthSignedIn(UserAccount.fromJson(userJson())),
            ),
          ),
        ],
      );
      final avatar = tester.widget<AppAvatar>(find.byType(AppAvatar));
      expect(avatar.name, isNotEmpty);
      expect(avatar.name, isNot('Guest'));
      // No tier overlay: the badge's words must be reachable on the same
      // screen wherever the overlay appears, and Explore has nowhere for them.
      expect(avatar.tier, VerificationTier.none);
    });

    testWidgets('takes a signed-in user to Profile — Phase 6 owed this', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(
              AuthSignedIn(UserAccount.fromJson(userJson())),
            ),
          ),
        ],
        routes: {ProfileScreen.routeName: (_) => const ProfileScreen()},
      );
      await tester.tap(find.byType(AppAvatar));
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('the Profile TAB routes a guest to Sign in, like the avatar', (
      tester,
    ) async {
      // Found on a device: the avatar checked for an account and the nav tab
      // did not, so a guest tapping the tab reached Profile, took a 401 on
      // `/v1/users/me/profile-summary` and read "Couldn't load your profile —
      // your account is safe, try again". An error state for something that is
      // not an error, about an account that does not exist.
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        routes: {
          SignInScreen.routeName: (_) => const SignInScreen(),
          ProfileScreen.routeName: (_) => const ProfileScreen(),
        },
      );

      await tester.tap(find.text('Profile').last);
      await settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
    });

    testWidgets('the Profile tab takes a signed-in user to Profile', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(
              AuthSignedIn(UserAccount.fromJson(userJson())),
            ),
          ),
        ],
        routes: {
          SignInScreen.routeName: (_) => const SignInScreen(),
          ProfileScreen.routeName: (_) => const ProfileScreen(),
        },
      );

      await tester.tap(find.text('Profile').last);
      await settle(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('has a tap target that is really 48 dp, not just 48 dp wide', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [apiClientProvider.overrideWithValue(api)],
        routes: {SignInScreen.routeName: (_) => const SignInScreen()},
      );
      // Tapped 20 dp off centre: inside a 48 dp target, outside the 36 dp
      // disc it paints. Asserted by tapping rather than by measuring, because
      // a box can lay out at 48 while hit-testing at 36 — which is what an
      // `OverflowBox` does, and why this screen does not use one.
      final centre = tester.getCenter(accountDisc());
      await tester.tapAt(centre + const Offset(20, 0));
      await settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('announces itself, since it is now a control', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(find.bySemanticsLabel('Sign in'), findsWidgets);
      handle.dispose();
    });

    testWidgets('the brand row survives 200% text with it wired', (
      tester,
    ) async {
      // Wiring this control widened the header's trailing slot from a 36 dp
      // avatar to a 48 dp target, and the brand row overflowed by 5.5 px at
      // 200% text. `AppHeader`'s wordmark is `Flexible` because of it.
      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ExploreScreen(),
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AppHeader), findsOneWidget);
    });
  });

  // 🔧 §Phase 14 paid the Saved heart's debt: its inert tripwire is gone,
  // replaced by where it goes.
  group('the Saved heart — Phase 14 owed this', () {
    Finder savedButton() => find.bySemanticsLabel('Saved');

    testWidgets(
      'is navigation, not a toggle: there is nothing on Explore to save',
      (tester) async {
        await pump(tester);
        expect(
          tester
              .widgetList<InertControl>(find.byType(InertControl))
              .where((c) => c.label == 'Saved'),
          isEmpty,
        );
        expect(find.byType(SaveHeartToggle), findsNothing);
        expect(
          tester.getSemantics(savedButton()),
          matchesSemantics(
            label: 'Saved',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      },
    );

    testWidgets('takes a signed-in user to Saved', (tester) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authControllerProvider.overrideWith(
            () => _FixedAuthController(
              AuthSignedIn(UserAccount.fromJson(userJson())),
            ),
          ),
        ],
        routes: {AppRoutes.saved: (_) => const Text('saved-screen')},
      );
      await tester.tap(savedButton());
      await settle(tester);
      expect(find.text('saved-screen'), findsOneWidget);
    });

    testWidgets('takes a guest to Sign in — saving needs an account (§1c)', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [apiClientProvider.overrideWithValue(api)],
        routes: {
          SignInScreen.routeName: (_) => const SignInScreen(),
          AppRoutes.saved: (_) => const Text('saved-screen'),
        },
      );
      await tester.tap(savedButton());
      await settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('saved-screen'), findsNothing);
    });
  });

  group('absent, not dead', () {
    testWidgets('there is no emergency entry on this screen at all', (
      tester,
    ) async {
      await pump(tester);
      // Round 23's reasoning applied to an unbuilt flow: a marker for an
      // action that does not exist is worse than no marker. §Phase 16 owes
      // the entry; Phase 17.3 owes the dispatch behind it.
      expect(find.textContaining('urgent'), findsNothing);
      expect(find.textContaining('Get help now'), findsNothing);
      expect(find.byIcon(Icons.bolt), findsNothing);
    });
  });

  group('the bottom nav', () {
    testWidgets('shows the five customer tabs with Explore selected', (
      tester,
    ) async {
      await pump(tester);
      final nav = tester.widget<AnimatedBottomNav>(
        find.byType(AnimatedBottomNav),
      );
      expect(nav.items.map((i) => i.label), [
        'Home',
        'Explore',
        'Bookings',
        'Messages',
        'Profile',
      ]);
      expect(nav.currentIndex, 1);
    });

    testWidgets('the Profile tab is not a placeholder — Phase 6 owed this too', (
      tester,
    ) async {
      // 🔧 This asserted that a *guest* tapping the tab reaches Profile, which
      // is the defect a device pass found: Profile then 401s and draws an
      // error card about an account the guest does not have. What Phase 6 owed
      // was that the tab stop being a placeholder; where it goes depends on
      // whether there is an account, and the two tests above cover both.
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        routes: {
          SignInScreen.routeName: (_) => const SignInScreen(),
          ProfileScreen.routeName: (_) => const ProfileScreen(),
        },
      );
      await tester.tap(find.text('Profile').last);
      await settle(tester);
      expect(find.byType(TabPlaceholderScreen), findsNothing);
    });

    testWidgets(
      'a tab whose screen is unbuilt says so rather than doing nothing',
      (tester) async {
        await pump(tester);
        await tester.tap(find.text('Bookings'));
        await settle(tester);

        expect(find.byType(TabPlaceholderScreen), findsOneWidget);
        expect(find.text('Bookings is not built yet'), findsOneWidget);

        await tester.tap(find.text('Back to Explore'));
        await settle(tester);
        expect(find.byType(ExploreScreen), findsOneWidget);
      },
    );

    testWidgets('tapping Explore while on Explore does not push anything', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Explore'));
      await settle(tester);
      expect(find.byType(TabPlaceholderScreen), findsNothing);
    });
  });
}
