import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/explore/presentation/tab_placeholder_screen.dart';
import 'package:raajjepro/features/explore/presentation/widgets/category_tile.dart';
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
    api.on('GET', '/v1/categories', (_) => {'data': seededTwelve()});
  });

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    const ExploreScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  /// Finds the [InertControl] wrapper for [label] and returns it.
  InertControl inert(WidgetTester tester, String label) {
    final matches = tester
        .widgetList<InertControl>(find.byType(InertControl))
        .where((c) => c.label == label);
    expect(matches, hasLength(1), reason: 'expected one inert "$label"');
    return matches.first;
  }

  group('present, and doing nothing', () {
    testWidgets('the island pill is drawn and owes Phase 7', (tester) async {
      await pump(tester);
      expect(inert(tester, 'Island').owedBy, 'Phase 7');

      final pressable = tester.widget<Pressable>(
        find.descendant(
          of: find.byWidget(inert(tester, 'Island')),
          matching: find.byType(Pressable),
        ),
      );
      expect(pressable.onTap, isNull);
    });

    testWidgets(
      'the search field is drawn, owes Phase 15, and takes no input',
      (tester) async {
        await pump(tester);
        expect(inert(tester, 'Search').owedBy, 'Phase 15');
        expect(find.text('What service do you need?'), findsOneWidget);
        // Not a real field: nothing can be typed into it and nothing submits.
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(EditableText), findsNothing);
      },
    );

    testWidgets('the Saved heart is drawn, owes Phase 14, and cannot toggle', (
      tester,
    ) async {
      await pump(tester);
      expect(inert(tester, 'Saved').owedBy, 'Phase 14');

      final heart = tester.widget<SaveHeartToggle>(
        find.byType(SaveHeartToggle),
      );
      expect(heart.onChanged, isNull);
      expect(heart.saved, isFalse);

      // Tapping it changes nothing — no navigation, no state.
      await tester.tap(find.byType(SaveHeartToggle));
      await settle(tester);
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(
        tester.widget<SaveHeartToggle>(find.byType(SaveHeartToggle)).saved,
        isFalse,
      );
    });

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

    testWidgets('a category tile is drawn but leads nowhere yet', (
      tester,
    ) async {
      await pump(tester);
      final tile = tester.widget<CategoryTile>(find.byType(CategoryTile).first);
      expect(tile.onTap, isNull);

      await tester.tap(find.byType(CategoryTile).first);
      await settle(tester);
      expect(find.byType(ExploreScreen), findsOneWidget);
    });
  });

  group('the account disc', () {
    testWidgets('shows a generic disc for a guest, never invented initials', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(AppAvatar), findsNothing);
      // Scoped to the header: the Profile nav tab carries the same glyph.
      final accountDisc = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is InertControl && w.label == 'Account',
        ),
        matching: find.byIcon(Icons.person_outline_rounded),
      );
      expect(accountDisc, findsOneWidget);
    });

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
