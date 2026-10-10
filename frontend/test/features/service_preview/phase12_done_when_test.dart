import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/bookings/presentation/book_slot_screen.dart';
import 'package:raajjepro/features/bookings/presentation/request_time_screen.dart';
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';
import 'package:raajjepro/features/service_preview/presentation/preview_copy.dart';
import 'package:raajjepro/features/service_preview/presentation/service_preview_screen.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/publish_sheets.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/listings.dart';
import '../../helpers/public_listing.dart';
import '../../helpers/pump.dart';
import '../bookings/harness.dart' show FixedAuthController;

/// §Phase 12 — **Done when:** "live data renders end-to-end; the Edit control
/// appears only for the owner; the raw API response contains no contact or
/// payment data under any circumstance; each booking mode routes to the
/// correct entry point."
///
/// The third clause is the backend's (`phase12-done-when.test.ts` scans the raw
/// bodies); what this side owes it is that nothing here can render a field the
/// server should not have sent, which the last group asserts.
void main() {
  const listingId = 'listing-1';
  const path = '/v1/listings/$listingId/public';
  const reviewsPath = '/v1/listings/$listingId/reviews?limit=3';

  /// 2026-09-15, 08:00 Malé. The scripted next-open time is 09:00 the next day.
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

  void script(
    Map<String, dynamic> listing, {
    List<Map<String, dynamic>> reviews = const [],
  }) {
    api.on('GET', path, (_) => listing);
    api.on(
      'GET',
      reviewsPath,
      (_) => {'_list': reviews, '_meta': <String, dynamic>{}},
    );
  }

  /// A route that records the arguments it was opened with and says so.
  Map<String, WidgetBuilder> recorders() => {
    for (final name in [
      AppRoutes.bookSlot,
      AppRoutes.requestTime,
      AppRoutes.emergency,
      AppRoutes.signIn,
      AppRoutes.verifyEmail,
      AppRoutes.createService,
    ])
      name: (context) {
        pushed[name] = ModalRoute.of(context)?.settings.arguments;
        return Scaffold(body: Text('opened $name'));
      },
  };

  Future<void> pump(WidgetTester tester, {AuthState? auth}) async {
    final overrides = <Override>[
      apiClientProvider.overrideWithValue(api),
      clockProvider.overrideWithValue(() => now),
      authControllerProvider.overrideWith(
        () => FixedAuthController(auth ?? signedIn()),
      ),
    ];
    await pumpScreen(
      tester,
      const ServicePreviewScreen(
        args: ServicePreviewArgs(listingId: listingId),
      ),
      overrides: overrides,
      routes: recorders(),
    );
  }

  /// The LAST match: a booking CTA's words also head the mode box above it,
  /// which is a statement and not a control.
  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  group('live data renders end to end', () {
    testWidgets('a skeleton while it loads, never a spinner or a blank', (
      tester,
    ) async {
      final gate = Completer<void>();
      api.gate = gate;
      script(publicListingJson());
      await pump(tester);

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.text('Home Deep Cleaning'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(find.text('Home Deep Cleaning'), findsOneWidget);
    });

    testWidgets('the page carries the listing, the provider and the reviews', (
      tester,
    ) async {
      script(publicListingJson(), reviews: [reviewJson()]);
      await pump(tester);

      expect(find.text('Home Deep Cleaning'), findsOneWidget);
      expect(find.text('MVR 450'), findsWidgets);
      expect(find.text('/session'), findsOneWidget);
      expect(find.text('Flat rate'), findsOneWidget);
      expect(find.text('4.8 (24 reviews)'), findsOneWidget);
      expect(find.text('Mariyam Shifa'), findsOneWidget);
      // The badge's own copy, never a bare "Verified".
      expect(find.text('ID checked, work verified'), findsOneWidget);
      expect(find.text('86 jobs completed'), findsNothing);
      expect(
        find.textContaining('86 jobs completed', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Spotless, and on time.'), findsOneWidget);
      expect(find.text('Aishath N.'), findsOneWidget);
      expect(find.text('On time (19)'), findsOneWidget);
      // What's included is the provider's lines, one bullet each.
      expect(find.text('Kitchen deep clean'), findsOneWidget);
      // An island keyed by id and printed as the server's own display name.
      expect(find.text('Dh. Meedhoo'), findsOneWidget);
    });

    testWidgets('no flat star row of zeros for a listing with no reviews', (
      tester,
    ) async {
      script(
        publicListingJson(
          rating: {
            'reviewCount': 0,
            'averageRating': null,
            'starBreakdown': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
            'tags': <Map<String, dynamic>>[],
          },
        ),
      );
      await pump(tester);

      expect(find.text('No reviews yet'), findsOneWidget);
      expect(
        find.textContaining('No reviews yet. Reviews are written'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a controls-bearing page swallows none of them', (
      tester,
    ) async {
      script(publicListingJson(emergencyAvailable: true));
      await pump(tester);
      expectNoSwallowedControls(tester);
    });
  });

  group('the Edit control appears only for the owner', () {
    testWidgets('a customer sees Book and Message, and no Edit', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester);

      expect(find.text('Edit service'), findsNothing);
      expect(find.text('Pick a time'), findsWidgets);
      expect(find.bySemanticsLabel('Message Mariyam Shifa'), findsOneWidget);
    });

    testWidgets('the owner sees Edit — and nothing that acts on their own '
        'listing', (tester) async {
      script(publicListingJson(viewerIsOwner: true));
      await pump(tester);

      expect(find.text('Edit service'), findsOneWidget);
      // The mode box still states how the service books; there is no control.
      expect(find.widgetWithText(AppButton, 'Pick a time'), findsNothing);
      expect(find.bySemanticsLabel('Message Mariyam Shifa'), findsNothing);
      expect(find.textContaining('Ask Mariyam Shifa'), findsNothing);
      expect(find.text('Report this listing'), findsNothing);

      await tapText(tester, 'Edit service');
      expect(pushed[AppRoutes.createService], {'listingId': listingId});
    });
  });

  group('each booking mode routes to the correct entry point', () {
    testWidgets('slot → the time picker, carrying the listing', (tester) async {
      script(publicListingJson());
      await pump(tester);

      await tapText(tester, 'Pick a time');

      expect(pushed[AppRoutes.bookSlot], {
        'listingId': listingId,
        'serviceName': 'Home Deep Cleaning',
      });
      expect(pushed.containsKey(AppRoutes.requestTime), isFalse);
    });

    testWidgets('request → the request form, carrying the category', (
      tester,
    ) async {
      script(
        publicListingJson(
          bookingMode: 'request',
          pricingModel: 'range',
          priceLaari: null,
          priceMinLaari: 35000,
          priceMaxLaari: 90000,
          priceUnit: null,
        ),
      );
      await pump(tester);

      await tapText(tester, 'Request a time');

      expect(pushed[AppRoutes.requestTime], {
        'listingId': listingId,
        'serviceName': 'Home Deep Cleaning',
        'providerName': 'Mariyam Shifa',
        'categoryId': 'cat-1',
      });
      expect(pushed.containsKey(AppRoutes.bookSlot), isFalse);
    });

    testWidgets('the emergency door sits beside the normal path, with its fee '
        'stated up front', (tester) async {
      script(
        publicListingJson(
          bookingMode: 'request',
          pricingModel: 'range',
          priceLaari: null,
          priceMinLaari: 35000,
          priceUnit: null,
          categoryName: 'Plumbing',
          emergencyAvailable: true,
        ),
      );
      await pump(tester);

      // The ordinary path is still there.
      expect(find.text('Request a time'), findsWidgets);
      expect(find.text('Emergency call-out also available'), findsOneWidget);
      // The cost is stated before anything is sent, from the server's figure.
      expect(
        find.textContaining('MVR 200 dispatch fee', findRichText: true),
        findsOneWidget,
      );

      await tester.ensureVisible(find.bySemanticsLabel('Get emergency help'));
      await tester.tap(find.bySemanticsLabel('Get emergency help'));
      await settle(tester);

      // Raised against a category, never a provider or a listing.
      expect(pushed[AppRoutes.emergency], {'categoryId': 'cat-1'});
    });

    testWidgets('no emergency door where the server did not offer one', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester);
      expect(find.text('Emergency call-out also available'), findsNothing);
    });

    test('the route names agree with the screens that own them', () {
      expect(AppRoutes.bookSlot, BookSlotScreen.routeName);
      expect(AppRoutes.requestTime, RequestTimeScreen.routeName);
      expect(ServicePreviewScreen.routeName, AppRoutes.listingPreview);
    });
  });

  group('who may proceed', () {
    testWidgets('a guest is sent to sign in, not into a booking', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester, auth: const AuthGuest());

      await tapText(tester, 'Pick a time');

      expect(pushed.containsKey(AppRoutes.signIn), isTrue);
      expect(pushed.containsKey(AppRoutes.bookSlot), isFalse);
    });

    testWidgets('an unverified user is sent to verify their email first', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester, auth: signedIn(verified: false));

      await tapText(tester, 'Pick a time');

      expect(pushed[AppRoutes.verifyEmail], {
        'email': 'aishath@example.mv',
        'purpose': 'verifyEmail',
      });
      expect(pushed.containsKey(AppRoutes.bookSlot), isFalse);
    });

    testWidgets('the same gate guards the emergency door and Message', (
      tester,
    ) async {
      script(publicListingJson(emergencyAvailable: true));
      await pump(tester, auth: signedIn(verified: false));

      await tester.tap(find.bySemanticsLabel('Message Mariyam Shifa'));
      await settle(tester);
      expect(pushed.containsKey(AppRoutes.verifyEmail), isTrue);
      expect(find.text('Messages is not built yet'), findsNothing);
    });

    testWidgets('a verified user reaches Message, which names the phase that '
        'owes the thread', (tester) async {
      script(publicListingJson());
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Message Mariyam Shifa'));
      await settle(tester);

      expect(find.text('Messages is not built yet'), findsOneWidget);
      expect(find.textContaining('Phase 18'), findsOneWidget);
    });

    testWidgets('Report is reachable from the overlay and lands on its owner', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Report this listing').first);
      await settle(tester);

      expect(find.text('Report is not built yet'), findsOneWidget);
      expect(find.textContaining('Phase 22'), findsOneWidget);
    });

    testWidgets('a provider not taking new customers cannot be booked', (
      tester,
    ) async {
      script(publicListingJson(acceptingNewCustomers: false));
      await pump(tester);

      expect(find.text('Not taking new customers right now'), findsOneWidget);
      await tester.tap(find.text('Pick a time').last);
      await settle(tester);
      expect(pushed.containsKey(AppRoutes.bookSlot), isFalse);
    });
  });

  group('honest copy', () {
    testWidgets('the provider’s own claims are attributed and unchecked', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester);

      expect(find.text('From the provider'), findsOneWidget);
      expect(
        find.textContaining('Provider states: ', findRichText: true),
        findsNWidgets(2),
      );
      expect(
        find.text(
          'These are the provider’s own statements. RaajjePro has not '
          'checked them.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the callback guarantee shows only where the server says so, '
        'and is not the provider’s claim', (tester) async {
      script(publicListingJson(callbackGuarantee: true));
      await pump(tester);
      expect(find.text('RaajjePro callback guarantee'), findsOneWidget);
      expect(
        find.text('Enforced by RaajjePro — request it from your booking.'),
        findsOneWidget,
      );
    });

    testWidgets('no callback card where the category is not eligible', (
      tester,
    ) async {
      script(publicListingJson());
      await pump(tester);
      expect(find.text('RaajjePro callback guarantee'), findsNothing);
    });

    testWidgets('below the floor: "New provider" and the job count, no rates, '
        'no response time', (tester) async {
      script(
        publicListingJson(
          bookingMode: 'request',
          pricingModel: 'quote',
          priceLaari: null,
          priceUnit: null,
          metricsBelowFloor: true,
          jobsCompleted: 4,
        ),
      );
      await pump(tester);

      expect(
        find.textContaining(
          'New provider · 4 jobs completed',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Usually replies'), findsNothing);
      expect(find.text('Price on request'), findsWidgets);
    });

    testWidgets('above the floor a request listing states the provider’s '
        'response time', (tester) async {
      script(
        publicListingJson(
          bookingMode: 'request',
          pricingModel: 'quote',
          priceLaari: null,
          priceUnit: null,
        ),
      );
      await pump(tester);

      expect(
        find.textContaining('Usually replies in about 12 minutes'),
        findsOneWidget,
      );
    });

    testWidgets('a slot listing states its next open time, not a response '
        'time', (tester) async {
      script(publicListingJson());
      await pump(tester);

      expect(
        find.textContaining('Next available: Tomorrow 09:00'),
        findsOneWidget,
      );
      expect(find.textContaining('Usually replies'), findsNothing);
    });

    testWidgets('no editorial label anywhere on the page', (tester) async {
      script(publicListingJson(), reviews: [reviewJson()]);
      await pump(tester);

      for (final label in const [
        'Prone to cancel', // retired-ok: asserts absence
        'Price hiking', // retired-ok: asserts absence
        'Unreliable', // retired-ok: asserts absence
        'Book instantly', // retired-ok: asserts absence
        'Emergency available', // retired-ok: asserts absence
      ]) {
        expect(find.textContaining(label), findsNothing, reason: label);
      }
      const bare = 'Verified'; // retired-ok: asserts absence
      expect(find.text(bare), findsNothing);
    });
  });

  group('the other states', () {
    testWidgets('a listing that is not public says so and offers a way on', (
      tester,
    ) async {
      api.fail('GET', path, status: 404, code: 'NOT_FOUND');
      api.on(
        'GET',
        reviewsPath,
        (_) => {
          '_list': <Map<String, dynamic>>[],
          '_meta': <String, dynamic>{},
        },
      );
      await pump(tester);

      expect(find.text('This listing is unavailable'), findsOneWidget);
      expect(find.text('Browse services'), findsOneWidget);
      expect(find.text('Pick a time'), findsNothing);
    });

    testWidgets('a dropped connection offers Try again, and it works', (
      tester,
    ) async {
      var attempts = 0;
      api.on('GET', path, (_) {
        attempts += 1;
        if (attempts == 1) throw const ApiNetworkException();
        return publicListingJson();
      });
      api.on(
        'GET',
        reviewsPath,
        (_) => {
          '_list': <Map<String, dynamic>>[],
          '_meta': <String, dynamic>{},
        },
      );
      await pump(tester);

      expect(find.text('Couldn’t load this service'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('Home Deep Cleaning'), findsOneWidget);
      expect(attempts, 2);
    });

    testWidgets('reviews failing to load does not fail the page', (
      tester,
    ) async {
      api.on('GET', path, (_) => publicListingJson());
      api.offline('GET', reviewsPath);
      await pump(tester);

      expect(find.text('Home Deep Cleaning'), findsOneWidget);
      expect(find.text('Couldn’t load this service'), findsNothing);
    });
  });

  group('nothing here can render contact or payment data', () {
    testWidgets('a field the server should never send has nowhere to land', (
      tester,
    ) async {
      final json = publicListingJson();
      // Planted at the depths the models read, to prove the parse is by name.
      json['phone'] = '+9607771234';
      (json['provider'] as Map<String, dynamic>)
        ..['phone'] = '+9607779999'
        ..['email'] = 'secret@example.test'
        ..['bankAccountNumber'] = '7700123456789';
      script(json);
      await pump(tester);

      for (final secret in ['7771234', '7779999', 'secret@', '7700123456789']) {
        expect(find.textContaining(secret), findsNothing, reason: secret);
      }
    });

    test('the models have no field that could hold one', () {
      final listing = PublicListing.fromJson(publicListingJson());
      final names = [listing.toString(), listing.provider.toString()].join();
      expect(names, isNot(contains('phone')));
    });
  });

  group('priceCopy — the one place a price becomes words', () {
    PublicPricing pricing(
      String model, {
      int? price,
      int? min,
      int? max,
      String? unit,
    }) => PublicPricing.fromJson({
      'model': model,
      'priceLaari': price,
      'priceMinLaari': min,
      'priceMaxLaari': max,
      'unit': unit,
    });

    test('fixed, hourly and daily carry their unit', () {
      expect(
        priceCopy(pricing('fixed', price: 45000, unit: 'visit'), 'A').footPrice,
        'MVR 450 /visit',
      );
      expect(
        priceCopy(pricing('hourly', price: 15000, unit: 'hour'), 'A').unit,
        '/hr',
      );
      expect(
        priceCopy(pricing('daily', price: 90000, unit: 'day'), 'A').label,
        'Daily rate',
      );
    });

    test('a range is a starting price, never a final one', () {
      final copy = priceCopy(
        pricing('range', min: 35000, max: 90000),
        'Ibrahim',
      );
      expect(copy.big, 'From MVR 350');
      expect(copy.note, contains('not the final amount'));
      expect(copy.note, contains('Ibrahim quotes your actual price'));
    });

    test('a quote names no amount at all', () {
      final copy = priceCopy(pricing('quote'), 'Ibrahim');
      expect(copy.big, 'Price on request');
      expect(copy.big, isNot(contains('MVR')));
    });

    test('an unknown model reads as "price on request"', () {
      expect(priceCopy(pricing('mystery'), 'A').big, 'Price on request');
    });
  });

  group('the wizard’s "View listing" is back', () {
    testWidgets('it opens the public page for the listing just published', (
      tester,
    ) async {
      final listing = ServiceListing.fromJson(
        publishableListingJson(id: listingId, categoryId: 'cat-1'),
      );
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => PublishedSheet(
              listing: listing,
              categoryName: 'Cleaning',
              onDone: () {},
            ),
          ),
        ),
        routes: {
          AppRoutes.listingPreview: (context) {
            pushed[AppRoutes.listingPreview] = ModalRoute.of(context)
                ?.settings
                .arguments;
            return const Scaffold(body: Text('preview opened'));
          },
        },
      );

      await tester.tap(find.text('View listing'));
      await settle(tester);

      expect(pushed[AppRoutes.listingPreview], {'listingId': listingId});
      expect(find.text('preview opened'), findsOneWidget);
    });
  });
}
