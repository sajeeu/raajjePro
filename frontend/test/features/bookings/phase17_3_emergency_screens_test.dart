import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/dispatch_fee_screen.dart';
import 'package:raajjepro/features/bookings/presentation/emergency_request_screen.dart';
import 'package:raajjepro/features/bookings/presentation/provider_emergency_screen.dart';
import 'package:raajjepro/features/bookings/presentation/reveal_contact_screen.dart';

import '../../helpers/a11y.dart';
import '../../helpers/islands.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';
import '../billing/harness.dart' show FakeReceiptPicker, FakeReceiptUploader;
import 'harness.dart';

/// §Phase 17.3's four screens — `Emergency Flow`, `Provider Emergency`,
/// `Reveal Contact` and `Dispatch Fee` — and the emergency block on `Booking
/// Detail`.
///
/// What these assert beyond the usual states:
///
///  * the emergency is raised by **trade and island**, and the trade's own
///    tier bar and answer window are rendered, never derived (owner's
///    decision 2026-09-28; invariant 13's posture);
///  * the offers are the server's three, in the server's order, with the
///    provider's **own** estimate labelled as such — and no distance and no
///    invented rating;
///  * **no arrival preset is preselected**, and the offer cannot be sent
///    without one (Round 22);
///  * the emergency accept is **never queued** (§0.0 item 14);
///  * a pass **does not claim to count** against the provider (owner's
///    decision);
///  * no screen renders a phone number **except** `Reveal Contact`, after the
///    customer starts it, and it never calls the number "verified".

Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Map<String, dynamic> requestJson({
  String id = 'req-1',
  String status = 'requested',
  String phase = 'waiting',
  List<Map<String, dynamic>> offers = const [],
  int offersReceived = 0,
  String? bookingId,
  Map<String, dynamic>? dispatchFee,
}) => {
  'id': id,
  'status': status,
  'phase': phase,
  'categoryId': 'cat-plumbing',
  'categoryName': 'Plumbing',
  'minimumTier': 'gold',
  'windowMinutes': 30,
  'islandId': 'i-kulhudhuffushi',
  'islandDisplayName': 'Kulhudhuffushi',
  'jobNotes': 'Pipe burst under the kitchen sink',
  'addressDetail': 'Fehivina, 2nd floor',
  'windowEndsAt': '2026-09-15T03:30:00.000Z',
  'collectionClosesAt': phase == 'collecting' || phase == 'choosing'
      ? '2026-09-15T03:01:30.000Z'
      : null,
  'choiceEndsAt': phase == 'choosing' ? '2026-09-15T03:06:30.000Z' : null,
  'broadcastCount': 4,
  'offersReceived': offersReceived,
  'offers': offers,
  'bookingId': bookingId,
  'dispatchFee': dispatchFee,
  'createdAt': '2026-09-15T03:00:00.000Z',
};

Map<String, dynamic> offerJson(
  String id,
  String name,
  int fee,
  int eta, {
  String tier = 'gold',
}) => {
  'id': id,
  'providerName': name,
  'verificationTier': tier,
  'ratingAverage': null,
  'calloutFeeLaari': fee,
  'etaMinutes': eta,
  'state': 'open',
  'createdAt': '2026-09-15T03:00:40.000Z',
};

Map<String, dynamic> broadcastJson({
  bool canOffer = true,
  bool passed = false,
  Map<String, dynamic>? myOffer,
}) => {
  'requestId': 'req-1',
  'categoryName': 'Plumbing',
  'customerFirstName': 'Aishath',
  'jobNotes': 'Pipe burst under the kitchen sink',
  'islandDisplayName': 'Kulhudhuffushi',
  'createdAt': '2026-09-15T03:00:00.000Z',
  'windowEndsAt': '2026-09-15T03:30:00.000Z',
  'collectionClosesAt': null,
  'choiceEndsAt': null,
  'etaPresetsMinutes': [15, 30, 45, 60],
  'myOffer': myOffer,
  'passed': passed,
  'canOffer': canOffer,
};

void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  group('Emergency request — the customer', () {
    void scriptCatalogue() {
      h.api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
      h.api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
    }

    testWidgets(
      'offers only emergency trades and states the trade’s own bar and window',
      (tester) async {
        scriptCatalogue();
        await pumpScreen(
          tester,
          const EmergencyRequestScreen(args: EmergencyRequestArgs()),
          overrides: h.overrides(),
        );

        expect(find.text('Electrical'), findsOneWidget);
        // Not capable, so not offered.
        expect(find.text('Cleaning'), findsNothing);

        await tester.tap(find.text('Electrical'));
        await settle(tester);
        // Both numbers are the category row's — gold, 30 — not this screen's.
        expect(
          find.textContaining(
            'Goes to every Gold-verified Electrical provider on your island at '
            'the same time — they have 30 minutes to respond.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('MVR 200, charged only when you pick a provider'),
          findsOneWidget,
        );
        expectNoSwallowedControls(tester);
      },
    );

    testWidgets(
      'sends the trade, the island by id and the words — and refuses without an island',
      (tester) async {
        scriptCatalogue();
        Map<String, dynamic>? sent;
        h.api.on('POST', '/v1/emergency-requests', (body) {
          sent = body as Map<String, dynamic>;
          return requestJson();
        });
        h.api.on('GET', '/v1/emergency-requests/req-1', (_) => requestJson());

        await pumpScreen(
          tester,
          const EmergencyRequestScreen(
            args: EmergencyRequestArgs(categoryId: 'cat-electrical'),
          ),
          overrides: h.overrides(),
        );
        await tester.enterText(
          find.byType(TextField).first,
          'Sparks from the fuse box',
        );

        await scrollTo(tester, find.text('Send emergency request'));
        await tester.tap(find.text('Send emergency request'));
        await settle(tester);
        expect(sent, isNull);
        await scrollTo(
          tester,
          find.text('Choose the island it’s on.'),
          delta: -200,
        );
        expect(find.text('Choose the island it’s on.'), findsOneWidget);

        await tester.tap(find.text('Choose the island'));
        await settle(tester);
        await tester.tap(find.text('Kulhudhuffushi').last);
        await settle(tester);

        await scrollTo(tester, find.text('Send emergency request'));
        await tester.tap(find.text('Send emergency request'));
        await settle(tester);

        expect(sent?['categoryId'], 'cat-electrical');
        expect(sent?['islandId'], 'i-kulhudhuffushi');
        expect(sent?['jobNotes'], 'Sparks from the fuse box');
        // Never a listing: dispatch targets nobody.
        expect(sent?.containsKey('listingId'), isFalse);
        expect(find.text('Sent to 4 providers'), findsOneWidget);
      },
    );

    testWidgets('shows the limit with the server’s own numbers', (
      tester,
    ) async {
      scriptCatalogue();
      h.api.on('GET', '/v1/islands', (_) => {'_list': sampleIslands()});
      h.api.fail(
        'POST',
        '/v1/emergency-requests',
        status: 422,
        code: 'EMERGENCY_RATE_LIMITED',
        details: {
          'usedLast24Hours': 3,
          'limitPer24Hours': 3,
          'usedLast7Days': 7,
          'limitPer7Days': 10,
          'nextAvailableAt': '2026-09-15T09:00:00.000Z',
        },
      );
      await pumpScreen(
        tester,
        const EmergencyRequestScreen(
          args: EmergencyRequestArgs(categoryId: 'cat-electrical'),
        ),
        overrides: h.overrides(),
      );
      await tester.enterText(find.byType(TextField).first, 'Again');
      await tester.tap(find.text('Choose the island'));
      await settle(tester);
      await tester.tap(find.text('Kulhudhuffushi').last);
      await settle(tester);
      await scrollTo(tester, find.text('Send emergency request'));
      await tester.tap(find.text('Send emergency request'));
      await settle(tester);

      expect(find.text('You’ve reached the emergency limit'), findsOneWidget);
      expect(find.text('Last 24 hours · 3 of 3 used'), findsOneWidget);
      expect(find.text('Last 7 days · 7 of 10 used'), findsOneWidget);
    });

    testWidgets('keeps the form when the request did not send', (tester) async {
      scriptCatalogue();
      h.api.offline('POST', '/v1/emergency-requests');
      await pumpScreen(
        tester,
        const EmergencyRequestScreen(
          args: EmergencyRequestArgs(categoryId: 'cat-electrical'),
        ),
        overrides: h.overrides(),
      );
      await tester.enterText(find.byType(TextField).first, 'Sparks');
      await tester.tap(find.text('Choose the island'));
      await settle(tester);
      await tester.tap(find.text('Kulhudhuffushi').last);
      await settle(tester);
      await scrollTo(tester, find.text('Send emergency request'));
      await tester.tap(find.text('Send emergency request'));
      await settle(tester);

      expect(find.text('Retry — send request'), findsOneWidget);
      await scrollTo(
        tester,
        find.textContaining('Your request didn’t send'),
        delta: -200,
      );
      expect(
        find.textContaining('nothing was sent and nothing was charged'),
        findsOneWidget,
      );
      expect(find.text('Sparks'), findsOneWidget);
    });

    testWidgets(
      'shows the server’s three offers, the provider’s own estimate, and sends the choice',
      (tester) async {
        Object? chosen;
        h.api.on(
          'GET',
          '/v1/emergency-requests/req-1',
          (_) => requestJson(
            status: 'emergency_offered',
            phase: 'choosing',
            offersReceived: 4,
            offers: [
              offerJson('o1', 'Hassan Waheed', 30000, 20),
              offerJson('o2', 'Rasheed Plumbing', 30000, 45),
              offerJson('o3', 'Ahmed Shakir', 40000, 30, tier: 'silver'),
            ],
          ),
        );
        h.api.on(
          'PATCH',
          '/v1/emergency-requests/req-1/emergency-offer-response',
          (body) {
            chosen = body;
            return requestJson(
              status: 'matched',
              phase: 'matched',
              bookingId: 'booking-1',
            );
          },
        );
        await pumpScreen(
          tester,
          const EmergencyRequestScreen(
            args: EmergencyRequestArgs(requestId: 'req-1'),
          ),
          overrides: h.overrides(),
        );

        expect(find.text('Pick one'), findsOneWidget);
        expect(
          find.textContaining('4 providers answered — these are the 3'),
          findsOneWidget,
        );
        expect(
          find.textContaining('~20 min to arrive — their own estimate'),
          findsOneWidget,
        );
        // No distance (the system has islands, not metres) and no invented rating.
        expect(find.textContaining('km'), findsNothing);
        expect(find.text('No ratings yet'), findsNWidgets(3));

        await tester.tap(find.text('Hassan Waheed'));
        await settle(tester);
        await scrollTo(tester, find.text('Confirm Hassan Waheed — MVR 300'));
        await tester.tap(find.text('Confirm Hassan Waheed — MVR 300'));
        await settle(tester);
        expect(chosen, {'offerId': 'o1'});
      },
    );

    testWidgets('says nobody answered, and that nothing was charged', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/emergency-requests/req-1',
        (_) => requestJson(status: 'declined', phase: 'closed'),
      );
      await pumpScreen(
        tester,
        const EmergencyRequestScreen(
          args: EmergencyRequestArgs(requestId: 'req-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('No one accepted in time'), findsOneWidget);
      expect(find.textContaining('Nothing has been charged'), findsOneWidget);
      expect(find.text('Try again now'), findsOneWidget);
    });
  });

  group('Emergency near you — the provider', () {
    testWidgets('preselects no arrival and will not send without one', (
      tester,
    ) async {
      var patched = 0;
      h.api.on(
        'GET',
        '/v1/providers/me/emergency-requests/req-1',
        (_) => broadcastJson(),
      );
      h.api.on('PATCH', '/v1/emergency-requests/req-1/emergency-accept', (_) {
        patched += 1;
        return broadcastJson(canOffer: false);
      });
      await pumpScreen(
        tester,
        const ProviderEmergencyScreen(
          args: ProviderEmergencyArgs(requestId: 'req-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      // "This is a bid, not a race."
      expect(
        find.textContaining('answering first doesn’t win it'),
        findsOneWidget,
      );
      // The category's presets, none of them selected.
      for (final m in [15, 30, 45, 60]) {
        expect(find.text('$m min'), findsOneWidget);
      }
      // No address before being chosen.
      expect(find.textContaining('Fehivina'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '350');
      await scrollTo(tester, find.text('Send offer'));
      await tester.tap(find.text('Send offer'));
      await settle(tester);
      expect(patched, 0);
      await scrollTo(
        tester,
        find.text('Choose when you can get there.'),
        delta: -200,
      );
      expect(find.text('Choose when you can get there.'), findsOneWidget);
    });

    testWidgets(
      'sends the fee in laari with the chosen estimate, in one call',
      (tester) async {
        Object? sent;
        h.api.on(
          'GET',
          '/v1/providers/me/emergency-requests/req-1',
          (_) => broadcastJson(),
        );
        h.api.on('PATCH', '/v1/emergency-requests/req-1/emergency-accept', (
          body,
        ) {
          sent = body;
          return broadcastJson(canOffer: false);
        });
        await pumpScreen(
          tester,
          const ProviderEmergencyScreen(
            args: ProviderEmergencyArgs(requestId: 'req-1'),
          ),
          overrides: h.overrides(viewerId: 'provider-user-1'),
        );
        await tester.enterText(find.byType(TextField).first, '350');
        await tester.tap(find.text('30 min'));
        await settle(tester);
        await scrollTo(tester, find.text('Send offer — MVR 350, 30 min'));
        await tester.tap(find.text('Send offer — MVR 350, 30 min'));
        await settle(tester);
        expect(sent, {'calloutFeeLaari': 35000, 'etaMinutes': 30});
      },
    );

    testWidgets('offline, says the offer did not send — it is never queued', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/emergency-requests/req-1',
        (_) => broadcastJson(),
      );
      h.api.offline('PATCH', '/v1/emergency-requests/req-1/emergency-accept');
      await pumpScreen(
        tester,
        const ProviderEmergencyScreen(
          args: ProviderEmergencyArgs(requestId: 'req-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      await tester.enterText(find.byType(TextField).first, '350');
      await tester.tap(find.text('15 min'));
      await settle(tester);
      await scrollTo(tester, find.text('Send offer — MVR 350, 15 min'));
      await tester.tap(find.text('Send offer — MVR 350, 15 min'));
      await settle(tester);

      await scrollTo(tester, find.textContaining('Your offer did not send'));
      expect(find.textContaining('Your offer did not send'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // One attempt, and nothing parked for replay.
      expect(h.api.calls.where((c) => c.method == 'PATCH').length, 1);
    });

    testWidgets('a pass does not claim to count against the provider', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/emergency-requests/req-1',
        (_) => broadcastJson(),
      );
      await pumpScreen(
        tester,
        const ProviderEmergencyScreen(
          args: ProviderEmergencyArgs(requestId: 'req-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      await scrollTo(tester, find.text('Pass on this request'));
      await tester.tap(find.text('Pass on this request'));
      await settle(tester);
      expect(
        find.textContaining('doesn’t count against your record'),
        findsOneWidget,
      );
      expect(find.textContaining('acceptance rate'), findsNothing);
    });

    testWidgets('is released at once when the customer chose someone else', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/providers/me/emergency-requests/req-1',
        (_) => broadcastJson(
          canOffer: false,
          myOffer: {
            'id': 'o1',
            'state': 'not_selected',
            'calloutFeeLaari': 35000,
            'etaMinutes': 30,
            'bookingId': null,
            'createdAt': '2026-09-15T03:00:40.000Z',
          },
        ),
      );
      await pumpScreen(
        tester,
        const ProviderEmergencyScreen(
          args: ProviderEmergencyArgs(requestId: 'req-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      expect(find.text('Aishath chose another offer'), findsOneWidget);
    });
  });

  group('Contact numbers — the one exception', () {
    Map<String, dynamic> emergencyBooking(String reveal) {
      final b = bookingJson(
        bookingMode: 'emergency',
        amountKind: 'callout_fee',
        agreedAmountLaari: 35000,
      );
      b['emergency'] = {
        'requestId': 'req-1',
        'etaMinutes': 30,
        'dispatchFee': null,
        'notArrivedAvailableAt': null,
        'contactReveal': reveal,
      };
      return b;
    }

    testWidgets(
      'the customer starts it and sees both numbers — never called "verified"',
      (tester) async {
        h.scriptDetail(emergencyBooking('available'));
        h.api.on(
          'POST',
          '/v1/bookings/booking-1/reveal-contact',
          (_) => {
            'bookingId': 'booking-1',
            'customer': {'name': 'Aishath Naeema', 'phone': '+9607792140'},
            'provider': {
              'name': 'Mariyam Shifa',
              'phone': '+9607718455',
              'verificationTier': 'gold',
            },
            'revealedAt': '2026-09-15T03:10:00.000Z',
            'expiresAt': null,
          },
        );
        await pumpScreen(
          tester,
          const RevealContactScreen(
            args: BookingActionArgs(bookingId: 'booking-1'),
          ),
          overrides: h.overrides(),
        );
        // No number before the tap.
        expect(find.textContaining('+960'), findsNothing);

        await scrollTo(tester, find.text('Share numbers both ways'));
        await tester.tap(find.text('Share numbers both ways'));
        await settle(tester);

        expect(find.text('+9607718455'), findsOneWidget);
        expect(find.textContaining('+9607792140'), findsOneWidget);
        expect(find.textContaining('confirmed by an admin'), findsOneWidget);
        expect(find.textContaining('isn’t checked live'), findsOneWidget);
        expect(
          find.textContaining(RegExp('verified number', caseSensitive: false)),
          findsNothing,
        );
      },
    );

    testWidgets('the kill switch reads as paused, not as an error', (
      tester,
    ) async {
      h.scriptDetail(emergencyBooking('paused'));
      await pumpScreen(
        tester,
        const RevealContactScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('Number sharing is paused right now'), findsOneWidget);
      expect(find.textContaining('it isn’t an error'), findsOneWidget);
    });

    testWidgets('the provider cannot start it', (tester) async {
      h.scriptDetail(emergencyBooking('available'));
      await pumpScreen(
        tester,
        const RevealContactScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      expect(find.text('Share numbers both ways'), findsNothing);
      await scrollTo(tester, find.textContaining('can start sharing numbers'));
      expect(
        find.textContaining('Only Aishath Naeema can start sharing numbers'),
        findsOneWidget,
      );
    });
  });

  group('Dispatch fee', () {
    testWidgets('submitting proof lifts the hold — no admin needed first', (
      tester,
    ) async {
      final picker = FakeReceiptPicker()..result = FakeReceiptPicker.picked();
      final uploader = FakeReceiptUploader();
      var submitted = false;
      h.api.on(
        'GET',
        '/v1/users/me/dispatch-fees',
        (_) => {
          'fees': [
            {
              'id': 'fee-1',
              'requestId': 'req-1',
              'amountLaari': 20000,
              'referenceCode': 'RP-4471-EMGX',
              'state': 'owed',
              'submittedAt': null,
              'rejectionReason': null,
              'proofUploaded': false,
              'createdAt': '2026-09-15T03:02:00.000Z',
            },
          ],
          'bankTransfer': {
            'bankName': 'Bank of Maldives',
            'accountName': 'RaajjePro Pvt Ltd',
            'accountNumber': '7701200000415',
          },
        },
      );
      h.api.on(
        'POST',
        '/v1/users/me/dispatch-fees/fee-1/proof',
        (_) => {
          'submission': <String, dynamic>{},
          'upload': {'url': 'http://store/put', 'headers': <String, dynamic>{}},
        },
      );
      h.api.on('POST', '/v1/users/me/dispatch-fees/fee-1/submit', (_) {
        submitted = true;
        return <String, dynamic>{};
      });

      await pumpScreen(
        tester,
        const DispatchFeeScreen(args: DispatchFeeArgs(blocked: true)),
        overrides: [
          ...h.overrides(),
          mediaPickerProvider.overrideWithValue(picker),
          mediaUploaderProvider.overrideWithValue(uploader),
        ],
      );
      expect(find.textContaining('New bookings are on hold'), findsOneWidget);
      expect(find.text('RaajjePro Pvt Ltd'), findsOneWidget);
      expect(find.text('RP-4471-EMGX'), findsOneWidget);

      await scrollTo(tester, find.text('Add your transfer receipt'));
      await tester.tap(find.text('Add your transfer receipt'));
      await settle(tester);
      await scrollTo(tester, find.text('Submit proof — lifts the hold now'));
      await tester.tap(find.text('Submit proof — lifts the hold now'));
      await settle(tester);

      expect(submitted, isTrue);
      expect(uploader.calls, 1);
      await scrollTo(
        tester,
        find.text('New bookings are unblocked'),
        delta: -200,
      );
      expect(find.text('New bookings are unblocked'), findsOneWidget);
      expect(find.textContaining('doesn’t hold you up'), findsOneWidget);
    });
  });

  group('Booking detail — the emergency block', () {
    testWidgets(
      'offers the fee, says when "not arrived" opens, and carries no number',
      (tester) async {
        final b = bookingJson(
          bookingMode: 'emergency',
          amountKind: 'callout_fee',
          agreedAmountLaari: 35000,
        );
        b['emergency'] = {
          'requestId': 'req-1',
          'etaMinutes': 30,
          'dispatchFee': {
            'submissionId': 'fee-1',
            'amountLaari': 20000,
            'referenceCode': 'RP-4471-EMGX',
            'state': 'owed',
          },
          // Later than the harness clock: not yet reportable.
          'notArrivedAvailableAt': '2026-09-15T03:30:00.000Z',
          'contactReveal': 'available',
        };
        h.scriptDetail(b);
        await pumpScreen(
          tester,
          const BookingDetailScreen(
            args: BookingDetailArgs(bookingId: 'booking-1'),
          ),
          overrides: h.overrides(),
        );
        await scrollTo(tester, find.text('Settle MVR 200 now'));
        expect(find.text('Settle MVR 200 now'), findsOneWidget);
        expect(find.text('Contact numbers'), findsOneWidget);
        expect(
          find.textContaining('their own estimate, not a guarantee'),
          findsOneWidget,
        );
        expect(find.textContaining('you can report it from'), findsOneWidget);
        // The button itself is not offered yet — only the sentence saying when.
        expect(find.text('Mariyam Shifa hasn’t arrived'), findsNothing);
        expect(find.textContaining('+960'), findsNothing);
        expectNoSwallowedControls(tester);
      },
    );
  });
}
