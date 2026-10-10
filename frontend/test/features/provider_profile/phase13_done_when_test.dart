import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/public/public_models.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/provider_profile/presentation/profile_copy.dart';
import 'package:raajjepro/features/provider_profile/presentation/provider_profile_screen.dart';
import 'package:raajjepro/features/service_preview/presentation/service_preview_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/provider_profile.dart';
import '../../helpers/public_listing.dart';
import '../../helpers/pump.dart';
import '../bookings/harness.dart' show FixedAuthController;

/// §Phase 13 — **Done when:** "renders for a visible provider; returns a
/// proper not-found state for a drafts-only provider's id; no contact data in
/// the response regardless of viewer."
///
/// The third clause is the backend's (`phase13-done-when.test.ts` scans the
/// raw bodies for every viewer); what this side owes it is that nothing here
/// can render a field the server should not have sent. Alongside, §1f's two
/// rules this page is the first to render publicly — numbers or nothing, and no
/// editorial label — and the artboard's geometry.
void main() {
  const providerId = 'prov-1';
  const path = '/v1/providers/$providerId/public';

  /// 2026-09-15, 08:00 Malé.
  final now = DateTime.utc(2026, 9, 15, 3);

  late FakeApiClient api;
  late Map<String, Object?> pushed;

  setUp(() {
    api = FakeApiClient();
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

  Map<String, WidgetBuilder> recorders() => {
    for (final name in [
      AppRoutes.listingPreview,
      AppRoutes.signIn,
      AppRoutes.verifyEmail,
      AppRoutes.providerProfile,
    ])
      name: (context) {
        pushed[name] = ModalRoute.of(context)?.settings.arguments;
        return Scaffold(body: Text('opened $name'));
      },
  };

  List<Override> overrides(AuthState? auth) => [
    apiClientProvider.overrideWithValue(api),
    clockProvider.overrideWithValue(() => now),
    authControllerProvider.overrideWith(
      () => FixedAuthController(auth ?? signedIn()),
    ),
  ];

  Future<void> pump(WidgetTester tester, {AuthState? auth}) => pumpScreen(
    tester,
    const ProviderProfileScreen(
      args: ProviderProfileArgs(providerId: providerId),
    ),
    overrides: overrides(auth),
    routes: recorders(),
  );

  void script(Map<String, dynamic> profile) =>
      api.on('GET', path, (_) => profile);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// The business name in the header — it also heads every card.
  Finder headerName() => find.descendant(
    of: find.byType(ProfileHeaderCard),
    matching: find.text('Rasheed Plumbing Services'),
  );

  /// Every string painted on screen, for the scans below.
  Iterable<String> paintedText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

  group('renders for a visible provider', () {
    testWidgets('a skeleton while it loads, never a spinner or a blank', (
      tester,
    ) async {
      final gate = Completer<void>();
      api.gate = gate;
      script(providerProfileJson());
      await pump(tester);

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(headerName(), findsNothing);
      // Save and Report act on a provider; there is none yet.
      expect(find.bySemanticsLabel('Report this provider'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(headerName(), findsOneWidget);
    });

    testWidgets('the header: name, the tier in its own words, §1g, tenure and '
        'the rating across every service', (tester) async {
      script(providerProfileJson());
      await pump(tester);

      expect(headerName(), findsOneWidget);
      // The full badge, with Gold's §1e words on screen — never bare "Verified".
      final badge = find.byWidgetPredicate(
        (w) =>
            w is VerificationBadge &&
            w.tier == VerificationTier.gold &&
            w.size == VerificationBadgeSize.full,
      );
      expect(badge, findsOneWidget);
      expect(find.text('ID checked, registered trade'), findsOneWidget);
      const bare = 'Verified'; // retired-ok: asserting its absence
      expect(paintedText(tester), isNot(contains(bare)));

      expect(find.text('Maldivian-owned business'), findsOneWidget);
      expect(find.text('Provider since Mar 2026'), findsOneWidget);
      expect(find.text('4.6'), findsWidgets);
      expect(find.text('31 reviews across all services'), findsOneWidget);
    });

    testWidgets('§1g is absent below Gold, and absent where Gold did not '
        'evidence it', (tester) async {
      script(providerProfileJson(tier: 'silver', maldivianOwned: true));
      await pump(tester);
      expect(find.text('Maldivian-owned business'), findsNothing);
      expect(find.text('ID checked, work verified'), findsOneWidget);
    });

    testWidgets('a provider at tier none shows no badge — and is still '
        'publicly visible', (tester) async {
      script(providerProfileJson(tier: 'none', maldivianOwned: null));
      await pump(tester);
      expect(find.byType(VerificationBadge), findsNothing);
      expect(headerName(), findsOneWidget);
    });

    testWidgets('the track record is six numbers and the response time', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);

      expect(find.text('Track record'), findsOneWidget);
      expect(find.text('Rolling last 90 days'), findsOneWidget);
      for (final (value, label) in [
        ('94%', 'completed'),
        ('3%', 'cancelled'),
        ('2%', 'no-show'),
        ('91%', 'on time'),
        ('97%', 'price honoured'),
        ('47', 'jobs completed'),
      ]) {
        expect(find.bySemanticsLabel('$label: $value'), findsOneWidget);
      }
      expect(
        find.descendant(
          of: find.byType(TrackRecordCard),
          matching: find.text('Usually replies in about 12 minutes'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rate with nothing measured reads "No data yet", never 0%', (
      tester,
    ) async {
      script(providerProfileJson(onTimeRate: null));
      await pump(tester);
      expect(find.bySemanticsLabel('on time: No data yet'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('tags print as counts, in the order the server sent', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);
      expect(find.text('What customers say'), findsOneWidget);
      expect(find.text('On time (26)'), findsOneWidget);
      // Negative tags are the point (§1f) — shown, not filtered.
      expect(find.text('Arrived late (4)'), findsOneWidget);
    });

    testWidgets('no tags, no section — never an empty heading', (tester) async {
      script(providerProfileJson(tags: const []));
      await pump(tester);
      expect(find.text('What customers say'), findsNothing);
    });

    testWidgets('every published service is a card stating its booking mode', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);

      expect(find.text('2 published services'), findsOneWidget);
      expect(find.byType(PublicServiceCard), findsNWidgets(2));
      expect(find.text('Request a time'), findsOneWidget);
      expect(find.text('Pick a time'), findsOneWidget);
      expect(find.text('From MVR 350'), findsOneWidget);
      expect(find.text('Usually replies in about 12 minutes'), findsWidgets);
      expect(find.text('Next: Tomorrow 09:00'), findsOneWidget);
      // The callback badge only where the server said so (Round 28) —
      // and no emergency marker on any card (Round 23).
      expect(find.text('Free callback · 7 days'), findsOneWidget);
      expect(paintedText(tester).where((t) => t.contains('mergency')), isEmpty);
    });

    testWidgets('tapping a card opens that listing', (tester) async {
      script(providerProfileJson());
      await pump(tester);
      await tapVisible(
        tester,
        find.bySemanticsLabel(RegExp('^Bathroom & Kitchen Plumbing')),
      );
      expect(pushed[AppRoutes.listingPreview], {'listingId': 'listing-2'});
    });

    // 🔧 §Phase 14 wired the hearts; this asserted them inert until then
    // (ledger P13-3). `phase14_done_when_test.dart` asserts what they do.
    testWidgets('the card is a container: its heart is not swallowed, and is '
        'live since §Phase 14', (tester) async {
      script(providerProfileJson());
      await pump(tester);
      expectNoSwallowedControls(tester);
      expect(find.byType(ListingSaveHeart), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is InertControl && w.owedBy == 'Phase 14',
        ),
        findsNothing,
      );
    });

    testWidgets('the Service Preview’s provider card now opens this page', (
      tester,
    ) async {
      api.on(
        'GET',
        '/v1/listings/listing-1/public',
        (_) => publicListingJson(),
      );
      api.on(
        'GET',
        '/v1/listings/listing-1/reviews?limit=3',
        (_) => {'_list': <dynamic>[], '_meta': <String, dynamic>{}},
      );
      await pumpScreen(
        tester,
        const ServicePreviewScreen(
          args: ServicePreviewArgs(listingId: 'listing-1'),
        ),
        overrides: overrides(null),
        routes: recorders(),
      );
      await tapVisible(
        tester,
        find.bySemanticsLabel('View Mariyam Shifa’s profile'),
      );
      expect(pushed[AppRoutes.providerProfile], {'providerId': 'prov-1'});
    });
  });

  group('§1f: numbers or nothing, and never a label', () {
    testWidgets('below the floor with few jobs: "New provider" and the count, '
        'no rates', (tester) async {
      script(providerProfileJson(metricsBelowFloor: true, jobsCompleted: 7));
      await pump(tester);

      expect(find.text('New provider · 7 jobs completed'), findsOneWidget);
      expect(find.text('Track record'), findsNothing);
      expect(paintedText(tester).where((t) => t.contains('%')), isEmpty);
      expect(find.textContaining('Usually replies'), findsNothing);
    });

    testWidgets('below the 90-day floor with 47 lifetime jobs: the count '
        'alone, never "New provider"', (tester) async {
      script(providerProfileJson(metricsBelowFloor: true, jobsCompleted: 47));
      await pump(tester);

      expect(find.text('47 jobs completed'), findsOneWidget);
      expect(find.textContaining('New provider'), findsNothing);
      expect(find.textContaining('in the last 90 days'), findsOneWidget);
      expect(paintedText(tester).where((t) => t.contains('%')), isEmpty);
    });

    testWidgets('no editorial label anywhere on the page', (tester) async {
      script(providerProfileJson(onTimeRate: 0.4));
      await pump(tester);
      final labels = RegExp(
        r'prone|hiking|unreliable|often late|frequently|warning|poor|avoid',
        caseSensitive: false,
      );
      expect(paintedText(tester).where(labels.hasMatch), isEmpty);
    });

    test('the copy functions emit numbers and counts only', () {
      const conduct = PublicConduct(
        jobsCompletedCount: 47,
        belowFloor: false,
        medianResponseSeconds: 720,
        completionRate: 0.94,
        cancellationRate: 0.03,
        noShowRate: 0.02,
        onTimeRate: null,
        priceAdherenceRate: 0.97,
      );
      expect(trackRecord(conduct).map((c) => c.value), [
        '94%',
        '3%',
        '2%',
        null,
        '97%',
        '47',
      ]);
      expect(
        jobsLine(
          const PublicConduct(
            jobsCompletedCount: 0,
            belowFloor: true,
            medianResponseSeconds: null,
          ),
        ),
        'New provider',
      );
      expect(
        reviewsAcross(const RatingTotals(reviewCount: 0, averageRating: null)),
        'No reviews yet',
      );
    });
  });

  group('a proper not-found state', () {
    testWidgets('a 404 — drafts only, suspended, or never existed — is the '
        'not-found page, not an empty profile', (tester) async {
      api.fail('GET', path, status: 404, code: 'NOT_FOUND');
      await pump(tester);

      expect(find.text('This provider isn’t here anymore'), findsOneWidget);
      expect(find.byType(PublicServiceCard), findsNothing);
      expect(find.text('Track record'), findsNothing);
      expect(find.bySemanticsLabel('Report this provider'), findsNothing);
      expect(find.bySemanticsLabel('Save this provider'), findsNothing);
      expect(find.text('Explore services'), findsOneWidget);
    });

    testWidgets('a dropped connection is an error with a retry, not a '
        'not-found', (tester) async {
      api.offline('GET', path);
      await pump(tester);
      expect(find.text('Couldn’t load this profile'), findsOneWidget);
      expect(find.text('This provider isn’t here anymore'), findsNothing);

      script(providerProfileJson());
      await tapVisible(tester, find.text('Try again'));
      expect(headerName(), findsOneWidget);
    });
  });

  group('no contact data, regardless of viewer', () {
    testWidgets('a phone, an email or a bank detail the server should never '
        'send has nowhere to land', (tester) async {
      final planted = providerProfileJson();
      (planted['provider'] as Map<String, dynamic>).addAll({
        'phone': '7771234',
        'phoneE164': '+9607771234',
        'email': 'ibrahim@example.mv',
        'fullName': 'Ibrahim Rasheed',
        'bankAccountNumber': '7700 1234 5678 9',
      });
      script(planted);

      for (final auth in [
        const AuthGuest(),
        signedIn(),
        signedIn(verified: false),
      ]) {
        await pump(tester, auth: auth);
        final text = paintedText(tester).join('\n');
        for (final secret in [
          '7771234',
          'ibrahim@example.mv',
          'Ibrahim Rasheed',
          '7700 1234 5678 9',
        ]) {
          expect(text, isNot(contains(secret)));
        }
      }
    });

    testWidgets('the footer promises private messaging, and keeps it', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);
      expect(
        find.textContaining('your phone number stays private'),
        findsOneWidget,
      );
      // No phone shape anywhere on the page.
      expect(
        paintedText(tester).where(RegExp(r'\+?960|\d{7}').hasMatch),
        isEmpty,
      );
    });
  });

  group('Message, Report and Save', () {
    testWidgets('a guest is sent to sign in', (tester) async {
      script(providerProfileJson());
      await pump(tester, auth: const AuthGuest());
      await tapVisible(tester, find.text('Message provider'));
      expect(pushed.containsKey(AppRoutes.signIn), isTrue);
    });

    testWidgets('an unverified user is sent to verify their email', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester, auth: signedIn(verified: false));
      await tapVisible(tester, find.text('Message provider'));
      expect(pushed[AppRoutes.verifyEmail], {
        'email': 'aishath@example.mv',
        'purpose': 'verifyEmail',
      });
    });

    testWidgets('a verified user reaches Message, which names the phase that '
        'owes the thread', (tester) async {
      script(providerProfileJson());
      await pump(tester);
      await tapVisible(tester, find.text('Message provider'));
      expect(find.text('Messages is not built yet'), findsOneWidget);
      expect(find.textContaining('Phase 18'), findsOneWidget);
    });

    testWidgets('Report lands on its owner; Save is live since §Phase 14', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);

      final save = tester.getSemantics(
        find.bySemanticsLabel('Save this provider'),
      );
      expect(
        save.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      // A toggle, so a screen reader hears whether it is saved.
      expect(
        save.getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
      );

      await tester.tap(find.bySemanticsLabel('Report this provider'));
      await settle(tester);
      expect(find.text('Report is not built yet'), findsOneWidget);
      expect(find.textContaining('Phase 22'), findsOneWidget);
    });

    testWidgets('a provider not taking new customers says so', (tester) async {
      script(providerProfileJson(acceptingNewCustomers: false));
      await pump(tester);
      expect(find.text('Not taking new customers right now'), findsOneWidget);
    });
  });

  group('geometry — measured against Provider Profile.dc.html at 412 dp', () {
    testWidgets('the header card: 20 dp gutters, radius 24, a 76 dp banner and '
        'a 76 dp avatar lifted 32 dp into it', (tester) async {
      script(providerProfileJson());
      await pump(tester);

      final card = find.byWidgetPredicate(
        (w) => w is AppCard && w.radius == AppRadius.feature,
      );
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.left, AppSpacing.xl);
      expect(412 - rect.right, AppSpacing.xl);

      final banner = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      );
      final bannerRect = tester.getRect(banner.first);
      expect(bannerRect.height, 76);
      // Inside the card's 1 dp border on each side.
      expect(bannerRect.width, rect.width - 2);

      final avatarRing = find.ancestor(
        of: find.byType(AppAvatar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
      );
      final ring = tester.getRect(avatarRing.first);
      expect(ring.width, 76);
      expect(ring.height, 76);
      expect(ring.top - bannerRect.top, 76 - 32);
      // 16 dp of padding inside the card's 1 dp border, as the CSS box draws it.
      expect(ring.left - rect.left, AppSpacing.lg + 1);
    });

    testWidgets('sections sit 16 dp apart; the service card is 14 dp padded '
        'with a 96 dp thumbnail', (tester) async {
      script(providerProfileJson());
      await pump(tester);

      final header = tester.getRect(find.byType(ProfileHeaderCard));
      final record = tester.getRect(find.byType(TrackRecordCard));
      expect(record.top - header.bottom, AppSpacing.lg);

      final firstCard = find.byType(PublicServiceCard).first;
      await tester.ensureVisible(firstCard);
      await tester.pump();
      final cardRect = tester.getRect(firstCard);
      expect(cardRect.width, 412 - AppSpacing.xl * 2);
      final thumb = find.descendant(
        of: firstCard,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppRadius.input),
        ),
      );
      final thumbRect = tester.getRect(thumb);
      expect(thumbRect.width, 96);
      expect(thumbRect.height, greaterThanOrEqualTo(112));
      expect(thumbRect.left - cardRect.left, AppSpacing.md2);
    });

    testWidgets('three metrics across at 100% text; the footer CTA is 54 dp', (
      tester,
    ) async {
      script(providerProfileJson());
      await pump(tester);

      final completed = tester.getRect(find.bySemanticsLabel('completed: 94%'));
      final cancelled = tester.getRect(find.bySemanticsLabel('cancelled: 3%'));
      final noShow = tester.getRect(find.bySemanticsLabel('no-show: 2%'));
      final onTime = tester.getRect(find.bySemanticsLabel('on time: 91%'));
      expect(cancelled.top, completed.top);
      expect(noShow.top, completed.top);
      expect(onTime.top, greaterThan(completed.bottom));

      final cta = find.ancestor(
        of: find.text('Message provider'),
        matching: find.byType(AppButton),
      );
      expect(tester.getSize(cta).height, AppSizes.ctaHeight);
    });

    testWidgets('at 200% text nothing overflows and the grid sheds columns', (
      tester,
    ) async {
      script(providerProfileJson());
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      expect(tester.takeException(), isNull);
      final completed = tester.getRect(find.bySemanticsLabel('completed: 94%'));
      final cancelled = tester.getRect(find.bySemanticsLabel('cancelled: 3%'));
      expect(cancelled.top, greaterThan(completed.top));
    });
  });
}
