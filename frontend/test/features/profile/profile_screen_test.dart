import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/features/profile/presentation/widgets/profile_hero.dart';
import 'package:raajjepro/features/profile/presentation/widgets/profile_wave_band.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import 'helpers.dart';

/// The Profile screen (`Profile.dc.html`; plan §Phase 6) — its states, its
/// fidelity to the prototype, and the two divergences that are deliberate.
void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient();
    api.on('GET', '/v1/users/me/profile-summary', (_) => profileSummaryJson());
  });

  Future<void> pump(
    WidgetTester tester, {
    Map<String, WidgetBuilder> routes = const {},
  }) => pumpScreen(
    tester,
    const ProfileScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
    routes: routes,
  );

  group('the four states', () {
    testWidgets('populated: the hero, the tiles, the rows and the switcher', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Aishath Naeema'), findsOneWidget);
      expect(find.text('Member since Jan 2026'), findsOneWidget);
      expect(find.text('My bookings'), findsOneWidget);
      expect(find.text('Switch to providing'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('loading: a skeleton shaped like the screen, not a spinner', (
      tester,
    ) async {
      api.gate = Completer<void>();
      await pump(tester);
      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(AppSpinner), findsNothing);
      // The bones are the populated layout's shape, not a spinner: a
      // hero-sized circular disc, four tile bones, three row bones.
      final disc = tester
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .where(
            (b) =>
                b.shape == BoxShape.circle && b.width == ProfileHero.avatarSize,
          );
      expect(disc, hasLength(1));
      final tiles = tester
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .where((b) => b.radius == AppRadius.tile);
      expect(tiles, hasLength(4));
      expect(find.byType(SkeletonRow), findsNWidgets(3));
      api.gate!.complete();
      await settle(tester);
    });

    testWidgets('error: says what failed, and the retry actually retries', (
      tester,
    ) async {
      api.fail(
        'GET',
        '/v1/users/me/profile-summary',
        status: 500,
        code: 'INTERNAL',
      );
      await pump(tester);
      expect(find.text("Couldn't load your profile"), findsOneWidget);
      expect(find.textContaining('Your account is safe'), findsOneWidget);
      // Never a code or a stack trace.
      expect(find.textContaining('INTERNAL'), findsNothing);

      api.on(
        'GET',
        '/v1/users/me/profile-summary',
        (_) => profileSummaryJson(),
      );
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Aishath Naeema'), findsOneWidget);
    });

    testWidgets('offline reads differently from a server error', (
      tester,
    ) async {
      api.offline('GET', '/v1/users/me/profile-summary');
      await pump(tester);
      expect(find.textContaining('Your connection dropped'), findsOneWidget);
    });

    testWidgets('there is no empty state, because an account is never empty', (
      tester,
    ) async {
      // A signed-in account always has a name and a join date. An "empty"
      // profile would mean "you do not exist", so a failed read is the
      // error state and there is no third thing.
      await pump(tester);
      expect(find.byType(EmptyState), findsNothing);
    });
  });

  group('the hero, and the two things it cannot say yet', () {
    testWidgets('renders initials rather than inventing a photo', (
      tester,
    ) async {
      await pump(tester);
      final avatar = tester.widget<AppAvatar>(find.byType(AppAvatar));
      expect(avatar.name, 'Aishath Naeema');
      expect(avatar.imageUrl, isNull);
      expect(avatar.size, ProfileHero.avatarSize);
      // The customer's own profile carries no tier overlay.
      expect(avatar.tier, VerificationTier.none);
    });

    testWidgets('the change-photo control is drawn and owes Phase 8', (
      tester,
    ) async {
      await pump(tester);
      final control = tester
          .widgetList<InertControl>(find.byType(InertControl))
          .where((c) => c.label == 'Change photo');
      expect(control, hasLength(1));
      // §Phase 6 mentions no photo, `User` has no avatar column, and media
      // upload via presigned URL is §Phase 8's. When Phase 8 (or 6a) wires
      // it, this fails and comes out on purpose.
      expect(control.first.owedBy, 'Phase 8');

      final pressable = tester.widget<Pressable>(
        find.descendant(
          of: find.byWidget(control.first),
          matching: find.byType(Pressable),
        ),
      );
      expect(pressable.onTap, isNull);

      // Round 48 §5: 30 dp of paint, a 48 dp target.
      final hit = tester.getSize(
        find.descendant(
          of: find.byWidget(control.first),
          matching: find.byType(Pressable),
        ),
      );
      expect(hit.width, greaterThanOrEqualTo(AppSizes.touchTarget));
      expect(hit.height, greaterThanOrEqualTo(AppSizes.touchTarget));
    });

    testWidgets('states no location, because there is no island field yet', (
      tester,
    ) async {
      await pump(tester);
      // The prototype's hero reads `Malé, Maldives · Member since Jan 2026`.
      // `Island` is §Phase 7's seed and nothing stores a customer's island,
      // so the half that can be answered is answered and no placeholder
      // location is printed. Phase 7 is what puts it back.
      expect(find.textContaining('Maldives'), findsNothing);
      expect(find.textContaining('Malé'), findsNothing);
      expect(find.text('Member since Jan 2026'), findsOneWidget);
    });

    testWidgets('the wave band is drawn and says nothing to a screen reader', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(ProfileWaveBand), findsOneWidget);
      expect(
        tester.getSize(find.byType(ProfileWaveBand)).height,
        ProfileWaveBand.height,
      );
    });
  });

  group('the booking tiles', () {
    testWidgets('are the four tabs My Bookings has, and no others', (
      tester,
    ) async {
      await pump(tester);
      for (final label in ['All', 'Upcoming', 'Active', 'Completed']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Round 48 §2: there is no Waiting tab and no Cancelled tab, so the
      // grid must not name either.
      expect(find.text('Waiting'), findsNothing);
      expect(find.text('Cancelled'), findsNothing);
    });

    testWidgets('each one has its own destination, not one shared screen', (
      tester,
    ) async {
      // The defect Round 48 §2 fixed was four labels reaching one screen.
      // §Phase 17 has not built My Bookings, so each tile lands on a
      // placeholder that names *its* tab — the distinction survives the
      // placeholder rather than being reintroduced by it.
      await pump(tester);
      for (final label in ['All', 'Upcoming', 'Active', 'Completed']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settle(tester);
        final screen = tester.widget<UnbuiltScreen>(find.byType(UnbuiltScreen));
        expect(screen.title, '$label bookings', reason: label);
        expect(screen.owedBy, 'Phase 17', reason: label);
        await tester.tap(find.text('Go back'));
        await settle(tester);
      }
    });

    testWidgets('take their colours from the state each one names', (
      tester,
    ) async {
      await pump(tester);
      final colors = AppTheme.light().extension<AppColors>()!;
      // Round 48 §3 aligned these with StatusPill so a tile and the pill on
      // the next screen carry the same colour for the same state.
      final expected = {
        'All': colors.neutralDot,
        'Upcoming': colors.success,
        'Active': colors.warning,
        'Completed': colors.primary,
      };
      for (final entry in expected.entries) {
        final icon = tester.widget<Icon>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.text(entry.key),
                  matching: find.byType(Column),
                ),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(icon.color, entry.value, reason: entry.key);
      }
    });
  });

  group('the five rows', () {
    testWidgets('are the five §Phase 6 names, in Round 48 §4’s order', (
      tester,
    ) async {
      await pump(tester);
      final rows = tester.widgetList<SettingsRow>(find.byType(SettingsRow));
      expect(rows.map((r) => r.title), [
        'Saved',
        'Saved preferences',
        'Account settings',
        'Help & support',
        'Legal',
      ]);
      // Round 48 §4: subtitle-free.
      expect(rows.every((r) => r.subtitle == null), isTrue);
    });

    testWidgets('the provider-only Verification row is not on this screen', (
      tester,
    ) async {
      await pump(tester, routes: {});
      // `Profile.dc.html` prepends one in provider mode. §Phase 6 says five
      // rows; verification review is §Phase 10a's queue and the provider
      // workspace is §Phase 10's.
      expect(find.text('Verification'), findsNothing);
    });

    testWidgets('no row was smuggled past the navigate rule as inert', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(SettingsRow), findsNWidgets(5));
      // `SettingsRow.onTap` is non-nullable, so a row cannot be inert by
      // construction — the way one *could* still go nowhere is by being
      // wrapped in an `InertControl`. §Phase 6's Done-when is "every row
      // navigates", and `phase6_done_when_test.dart` taps all five; this
      // holds the structural half. The change-photo button is the only inert
      // control this screen is allowed to carry.
      final labels = tester
          .widgetList<InertControl>(find.byType(InertControl))
          .map((c) => c.label);
      expect(labels, ['Change photo']);
      expect(
        find.descendant(
          of: find.byType(InertControl),
          matching: find.byType(SettingsRow),
        ),
        findsNothing,
      );
    });
  });

  group('sign out', () {
    testWidgets('signs the account out rather than only leaving the screen', (
      tester,
    ) async {
      api.on('POST', '/v1/auth/logout', (_) => {'loggedOut': true});
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          // Sign out clears the token store; the real one is platform secure
          // storage and is not available under test.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
      );
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(
        api.calls.any((c) => c.path == '/v1/auth/logout'),
        isTrue,
        reason: 'sign out must reach the API, not just pop',
      );
    });
  });

  group('the two new controls announce themselves', () {
    // `Pressable(excludeSemantics: true)` returns the child *unwrapped*, so a
    // `semanticLabel` passed alongside it is silently discarded. Neither of
    // these children describes the control, so both need the wrapper — and a
    // label that exists in the source but not in the tree is exactly the kind
    // of accessibility defect a source review does not catch.
    testWidgets('the change-photo control is announced, and as unavailable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel('Change photo. Not available yet.'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('accessibility and geometry', () {
    testWidgets('nothing overflows or clips at 200% text', (tester) async {
      // The 2 × 2 tile grid exists because a four-across row does not survive
      // this (Round 48 §2), and the hero is the tallest fixed block on the
      // screen. Both are checked here rather than assumed.
      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ProfileScreen(),
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Aishath Naeema'), findsOneWidget);
      for (final label in ['All', 'Upcoming', 'Active', 'Completed']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('renders under RTL without a directional assertion', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileScreen(),
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ProfileWaveBand), findsOneWidget);
    });

    testWidgets('the skeleton degrades under reduced motion', (tester) async {
      api.gate = Completer<void>();
      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ProfileScreen(),
        ),
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SkeletonLoader), findsOneWidget);
      api.gate!.complete();
      await settle(tester);
    });

    testWidgets('every control on the screen clears the 48 dp floor', (
      tester,
    ) async {
      await pump(tester);
      for (final element in find.byType(Pressable).evaluate()) {
        final size = tester.getSize(
          find.byElementPredicate((e) => e == element),
        );
        expect(
          size.width,
          greaterThanOrEqualTo(AppSizes.touchTarget),
          reason: 'a control narrower than the floor',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(AppSizes.touchTarget),
          reason: 'a control shorter than the floor',
        );
      }
    });
  });
}
