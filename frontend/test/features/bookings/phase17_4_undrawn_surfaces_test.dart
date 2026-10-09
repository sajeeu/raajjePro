import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/files/share_file.dart';
import 'package:raajjepro/features/availability/presentation/slot_picker_screen.dart';
import 'package:raajjepro/features/bookings/presentation/book_again_screen.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/propose_quote_screen.dart';
import 'package:raajjepro/features/bookings/presentation/quote_received_screen.dart';
import 'package:raajjepro/features/saved_preferences/data/saved_preferences_api.dart';
import 'package:raajjepro/features/saved_preferences/presentation/saved_preferences_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 17.4's five undrawn pieces, built against the proposals the owner
/// approved on 2026-10-09 (decision 31 §6): Change the time, the callback
/// claim, Add to calendar, Book again, and the time-window editor.
///
/// The callback tests hold the owner's four binding rules: nothing shared
/// with a provider warranty (§1i), nothing that reads as a dispute, absent
/// rather than disabled where it does not apply, and MVR 0 with no payment
/// step on the return visit.

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Map<String, dynamic> callbackJson({
  bool guaranteed = true,
  bool canClaim = true,
  String? claimBookingId,
  String? claimableUntil = '2026-09-20T09:00:00.000Z',
}) => {
  'guaranteed': guaranteed,
  'claimableUntil': claimableUntil,
  'claimBookingId': claimBookingId,
  'canClaim': canClaim,
};

/// A completed request job, as the callback card sees it.
Map<String, dynamic> completedJob({
  String id = 'booking-1',
  Map<String, dynamic>? callback,
}) => bookingJson(
  id: id,
  status: 'completed',
  bookingMode: 'request',
  completedAt: '2026-09-13T09:00:00.000Z',
  callback: callback,
);

/// The return visit a claim creates: a request at `awaiting_quote`, linked to
/// the job, with no amount of any kind yet.
Map<String, dynamic> returnVisit({String status = 'awaiting_quote'}) =>
    bookingJson(
      id: 'booking-2',
      status: status,
      bookingMode: 'request',
      agreedAmountLaari: null,
      amountKind: null,
      quotedAmountLaari: null,
      scheduledFor: null,
      preferredWindowText: 'Tomorrow morning',
      callbackForBookingId: 'booking-1',
    );

/// A placeholder route that records what it was pushed with.
WidgetBuilder recordRoute(String marker, List<Object?> pushed) => (context) {
  pushed.add(ModalRoute.of(context)?.settings.arguments);
  return Scaffold(body: Text(marker));
};

void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  Future<void> pumpDetail(
    WidgetTester tester, {
    String bookingId = 'booking-1',
    String viewerId = 'customer-1',
    Map<String, WidgetBuilder> routes = const {},
  }) => pumpScreen(
    tester,
    BookingDetailScreen(args: BookingDetailArgs(bookingId: bookingId)),
    overrides: [
      ...h.overrides(viewerId: viewerId),
      tempDirProvider.overrideWithValue(() async => Directory.systemTemp),
    ],
    routes: routes,
  );

  // ===========================================================================
  // 2. The callback claim
  // ===========================================================================

  group('Callback guarantee on a completed job', () {
    testWidgets('offers the claim plainly — no tick, shield, lock or '
        '"verified", and nothing borrowed from Report a problem', (
      tester,
    ) async {
      final pushed = <Object?>[];
      h.scriptDetail(completedJob(callback: callbackJson()));
      await pumpDetail(
        tester,
        routes: {
          CallbackClaimScreen.routeName: recordRoute('claim-screen', pushed),
        },
      );

      await scrollTo(tester, find.text('The same problem is back'));
      expect(find.text('Callback guarantee'), findsOneWidget);
      expect(
        find.textContaining('Free return visit if the same problem comes back'),
        findsOneWidget,
      );
      // §1i: the platform's promise shares no treatment with a warranty.
      final card = find.ancestor(
        of: find.text('Callback guarantee'),
        matching: find.byType(AppCard),
      );
      for (final icon in [
        Icons.check,
        Icons.check_rounded,
        Icons.check_circle,
        Icons.check_circle_outline,
        Icons.verified,
        Icons.verified_outlined,
        Icons.verified_user,
        Icons.verified_user_outlined,
        Icons.shield,
        Icons.shield_outlined,
        Icons.lock,
        Icons.lock_outline,
      ]) {
        expect(
          find.descendant(of: card, matching: find.byIcon(icon)),
          findsNothing,
        );
      }
      expect(
        find.textContaining(RegExp('verified', caseSensitive: false)),
        findsNothing,
      );
      // Taking up an offer, not raising a problem: the card holds no report
      // affordance and its button is not the destructive one.
      expect(
        find.descendant(of: card, matching: find.textContaining('Report')),
        findsNothing,
      );
      final button = tester.widget<AppButton>(
        find.ancestor(
          of: find.text('The same problem is back'),
          matching: find.byType(AppButton),
        ),
      );
      expect(button.variant, isNot(AppButtonVariant.destructive));
      expectNoSwallowedControls(tester);

      await tester.tap(find.text('The same problem is back'));
      await settle(tester);
      expect(find.text('claim-screen'), findsOneWidget);
      expect(pushed.single, {'bookingId': 'booking-1'});
    });

    testWidgets('absent — not disabled — where the listing did not offer it', (
      tester,
    ) async {
      h.scriptDetail(
        completedJob(
          callback: callbackJson(guaranteed: false, canClaim: false),
        ),
      );
      await pumpDetail(tester);
      await scrollTo(tester, find.text('Report a problem'));
      expect(find.text('Callback guarantee'), findsNothing);
      expect(find.text('The same problem is back'), findsNothing);

      // An older server that sends no callback block at all reads the same.
      h.scriptDetail(completedJob(id: 'booking-3'));
      await pumpDetail(tester, bookingId: 'booking-3');
      expect(find.text('Callback guarantee'), findsNothing);
    });

    testWidgets('absent once the seven days have passed', (tester) async {
      h.scriptDetail(completedJob(callback: callbackJson(canClaim: false)));
      await pumpDetail(tester);
      await scrollTo(tester, find.text('Report a problem'));
      expect(find.text('Callback guarantee'), findsNothing);
    });

    testWidgets('once claimed, it leads to the return visit', (tester) async {
      final pushed = <Object?>[];
      h.scriptDetail(
        completedJob(
          callback: callbackJson(canClaim: false, claimBookingId: 'booking-2'),
        ),
      );
      await pumpDetail(
        tester,
        routes: {
          BookingDetailScreen.routeName: recordRoute('return-visit', pushed),
        },
      );
      await scrollTo(tester, find.text('Open the return visit'));
      expect(find.text('The same problem is back'), findsNothing);
      await tester.tap(find.text('Open the return visit'));
      await settle(tester);
      expect(pushed.single, {'bookingId': 'booking-2'});
    });

    testWidgets('the provider is not offered the customer’s claim', (
      tester,
    ) async {
      h.scriptDetail(completedJob(callback: callbackJson()));
      await pumpDetail(tester, viewerId: 'provider-user-1');
      await scrollTo(tester, find.text('Report a problem'));
      expect(find.text('The same problem is back'), findsNothing);
    });
  });

  group('Callback claim form', () {
    testWidgets('asks what came back and when, then opens the new booking', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      final pushed = <Object?>[];
      h.scriptDetail(completedJob(callback: callbackJson()));
      h.api.on('POST', '/v1/bookings/booking-1/callback', (body) {
        sent = body as Map<String, dynamic>;
        return returnVisit();
      });

      await pumpScreen(
        tester,
        const CallbackClaimScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
        routes: {
          BookingDetailScreen.routeName: recordRoute('return-visit', pushed),
        },
      );

      expect(find.text('Ask Mariyam to come back'), findsWidgets);
      expect(find.text('What came back?'), findsOneWidget);
      // Not a dispute: no reasons to cite, no "problem" framing.
      expect(find.textContaining('dispute'), findsNothing);

      Future<void> tapSend() async {
        final send = find.widgetWithText(AppButton, 'Ask Mariyam to come back');
        await scrollTo(tester, send);
        await tester.tap(send);
        await settle(tester);
      }

      // Both answers are needed — nothing is sent without them.
      await tapSend();
      expect(sent, isNull);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'What came back?'),
        'The kitchen tap is dripping again',
      );
      await scrollTo(tester, find.text('Tomorrow morning'));
      await tester.tap(find.text('Tomorrow morning'));
      await settle(tester);
      expect(find.textContaining('at MVR 0'), findsOneWidget);
      expect(find.textContaining('no payment step'), findsOneWidget);

      await tapSend();
      expect(sent, {
        'jobNotes': 'The kitchen tap is dripping again',
        'preferredWindowChip': 'tomorrow_morning',
      });
      expect(find.text('return-visit'), findsOneWidget);
      expect(pushed.single, {'bookingId': 'booking-2'});
    });

    testWidgets('a claim already made says so instead of a second form', (
      tester,
    ) async {
      h.scriptDetail(
        completedJob(
          callback: callbackJson(canClaim: false, claimBookingId: 'booking-2'),
        ),
      );
      await pumpScreen(
        tester,
        const CallbackClaimScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(
        find.text('You’ve already asked Mariyam to come back'),
        findsOneWidget,
      );
      expect(find.text('What came back?'), findsNothing);
    });

    testWidgets('loading error offers a retry', (tester) async {
      h.api.offline('GET', '/v1/bookings/booking-1');
      await pumpScreen(
        tester,
        const CallbackClaimScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('Couldn’t load the booking'), findsOneWidget);
    });
  });

  group('The return visit — MVR 0, and no payment step', () {
    testWidgets('its detail reads MVR 0 from the start', (tester) async {
      h.scriptDetail(returnVisit());
      await pumpDetail(tester, bookingId: 'booking-2');
      expect(find.text('Callback — free return visit'), findsOneWidget);
      expect(find.text('MVR 0'), findsOneWidget);
      expect(find.text('No price yet'), findsNothing);
      expect(find.text('Continue to payment'), findsNothing);
    });

    testWidgets('accepting the provider’s time goes nowhere near payment', (
      tester,
    ) async {
      var approved = false;
      final quoted = {
        ...quotedBookingJson(quotedAmountLaari: 0),
        'callbackForBookingId': 'booking-1',
      };
      h.scriptDetail(quoted);
      h.api.on('PATCH', '/v1/bookings/booking-1/approve-quote', (_) {
        approved = true;
        return {...quoted, 'status': 'confirmed'};
      });
      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
        routes: {
          PaymentStepScreen.routeName: (_) => const Text('payment-step'),
        },
      );
      expect(find.text('MVR 0 · free return visit'), findsOneWidget);
      expect(find.textContaining('bank transfer'), findsNothing);
      expect(find.textContaining('nothing to pay'), findsOneWidget);

      await scrollTo(tester, find.text('Accept this time'));
      await tester.tap(find.text('Accept this time'));
      await settle(tester);
      expect(approved, isTrue);
      expect(find.text('payment-step'), findsNothing);
    });

    testWidgets('the provider proposes a time and is never asked for a price', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      h.scriptDetail({...returnVisit(), 'id': 'booking-1'});
      h.api.on('PATCH', '/v1/bookings/booking-1/quote', (body) {
        sent = body as Map<String, dynamic>;
        return {
          ...quotedBookingJson(quotedAmountLaari: 0),
          'callbackForBookingId': 'booking-0',
        };
      });
      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      expect(find.widgetWithText(AppTextField, 'Your price'), findsNothing);
      expect(find.text('MVR 0 · free return visit'), findsOneWidget);

      await tester.tap(find.text('Tomorrow'));
      await settle(tester);
      await scrollTo(tester, find.text('Propose this time'));
      await tester.tap(find.text('Propose this time'));
      await settle(tester);
      // §1h "at zero cost"; the server refuses anything else (CALLBACK_IS_FREE).
      expect(sent?['amountLaari'], 0);
    });
  });

  // ===========================================================================
  // 4. Book again
  // ===========================================================================

  group('Book again', () {
    testWidgets(
      'a completed booking opens Book Again — above Report a problem',
      (tester) async {
        final pushed = <Object?>[];
        h.scriptDetail(bookingJson(status: 'completed'));
        await pumpDetail(
          tester,
          routes: {
            BookAgainScreen.routeName: recordRoute('book-again', pushed),
          },
        );
        await scrollTo(tester, find.text('Report a problem'));
        final bookAgain = find.text('Book again');
        expect(bookAgain, findsOneWidget);
        expect(
          tester.getTopLeft(bookAgain).dy,
          lessThan(tester.getTopLeft(find.text('Report a problem')).dy),
        );
        final button = tester.widget<AppButton>(
          find.ancestor(of: bookAgain, matching: find.byType(AppButton)),
        );
        expect(button.variant, AppButtonVariant.primary);

        await tester.tap(bookAgain);
        await settle(tester);
        // Book Again's own screen — never straight to Pick a Time.
        expect(find.text('book-again'), findsOneWidget);
        expect(pushed.single, {'bookingId': 'booking-1'});
      },
    );

    testWidgets('not offered before the job is done', (tester) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));
      await pumpDetail(tester);
      await scrollTo(tester, find.text('Report a problem'));
      expect(find.text('Book again'), findsNothing);
    });
  });

  // ===========================================================================
  // 3. Add to calendar
  // ===========================================================================

  group('Add to calendar', () {
    testWidgets('writes the server’s ICS and hands it to the share sheet', (
      tester,
    ) async {
      final shared = <({String path, String subject})>[];
      h.scriptDetail(bookingJson(status: 'confirmed'));
      h.api.on(
        'GET',
        '/v1/bookings/booking-1/calendar',
        (_) => {
          'filename': 'raajjepro-RP-7K4M2QXB.ics',
          'contentType': 'text/calendar',
          'ics': 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
        },
      );
      await pumpScreen(
        tester,
        const BookingDetailScreen(
          args: BookingDetailArgs(bookingId: 'booking-1'),
        ),
        overrides: [
          ...h.overrides(),
          tempDirProvider.overrideWithValue(() async => Directory.systemTemp),
          shareDocumentProvider.overrideWithValue((file, subject) async {
            shared.add((path: file.path, subject: subject));
          }),
        ],
      );

      // In the agreement card, with the terms it records.
      final card = find.ancestor(
        of: find.text('The agreement'),
        matching: find.byType(AppCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('Add to calendar')),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Add to calendar'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);

      expect(shared, hasLength(1));
      expect(shared.single.path, endsWith('raajjepro-RP-7K4M2QXB.ics'));
      expect(
        File(shared.single.path).readAsStringSync(),
        'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
      );
    });

    testWidgets('only once the time is agreed', (tester) async {
      for (final (index, status) in [
        'requested',
        'completed',
        'cancelled',
      ].indexed) {
        h.scriptDetail(bookingJson(id: 'booking-$index', status: status));
        await pumpDetail(tester, bookingId: 'booking-$index');
        expect(find.text('Add to calendar'), findsNothing, reason: status);
      }
      h.scriptDetail(bookingJson(id: 'booking-9', status: 'accepted'));
      await pumpDetail(tester, bookingId: 'booking-9');
      expect(find.text('Add to calendar'), findsOneWidget);
    });

    testWidgets('a failure says so under the button', (tester) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));
      h.api.offline('GET', '/v1/bookings/booking-1/calendar');
      await pumpDetail(tester);
      await tester.tap(find.text('Add to calendar'));
      await settle(tester);
      expect(find.textContaining('No connection'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 1. Change the time
  // ===========================================================================

  group('Change the time', () {
    testWidgets(
      'shown where the endpoint has a picker to feed, and only there',
      (tester) async {
        final cases = <(Map<String, dynamic>, String, bool)>[
          // The customer's unanswered slot booking: moved at once.
          (bookingJson(id: 'b1', status: 'requested'), 'customer-1', true),
          // The provider cannot move a request they have not answered.
          (
            bookingJson(id: 'b2', status: 'requested'),
            'provider-user-1',
            false,
          ),
          // The customer's unanswered request: new window, moved at once.
          (
            bookingJson(
              id: 'b3',
              status: 'awaiting_quote',
              bookingMode: 'request',
              scheduledFor: null,
            ),
            'customer-1',
            true,
          ),
          // An agreed slot booking: either party, filed as an amendment.
          (bookingJson(id: 'b4', status: 'confirmed'), 'customer-1', true),
          (bookingJson(id: 'b5', status: 'accepted'), 'provider-user-1', true),
          // An agreed request: "Propose a change" already does this.
          (
            bookingJson(id: 'b6', status: 'confirmed', bookingMode: 'request'),
            'customer-1',
            false,
          ),
          // An amendment already waiting: one at a time.
          (
            bookingJson(
              id: 'b7',
              status: 'confirmed',
              amendments: [amendmentJson()],
            ),
            'customer-1',
            false,
          ),
          (bookingJson(id: 'b8', status: 'completed'), 'customer-1', false),
        ];
        for (final (booking, viewer, shown) in cases) {
          // A fresh tree per case: a reused ProviderScope keeps the first
          // viewer's auth override.
          await tester.pumpWidget(const SizedBox.shrink());
          h.scriptDetail(booking);
          await pumpDetail(
            tester,
            bookingId: booking['id'] as String,
            viewerId: viewer,
          );
          await tester.scrollUntilVisible(
            find.text('What has happened'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -2000),
          );
          await settle(tester);
          expect(
            find.text('Change the time'),
            shown ? findsOneWidget : findsNothing,
            reason: '${booking['status']} ${booking['bookingMode']} as $viewer',
          );
        }
      },
    );

    testWidgets('a slot booking goes through the picker and sends the slot', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      h.scriptDetail(bookingJson(status: 'requested'));
      h.api.on('PATCH', '/v1/bookings/booking-1/reschedule', (body) {
        sent = body as Map<String, dynamic>;
        return bookingJson(status: 'requested');
      });
      await pumpDetail(
        tester,
        routes: {
          SlotPickerScreen.routeName: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).pop(
                PickedSlot(
                  slotId: 'slot-9',
                  startsAt: DateTime.utc(2026, 9, 26, 9),
                  endsAt: DateTime.utc(2026, 9, 26, 11),
                ),
              ),
              child: const Text('pick-slot-9'),
            ),
          ),
        },
      );
      await scrollTo(tester, find.text('Change the time'));
      await tester.tap(find.text('Change the time'));
      await settle(tester);
      await tester.tap(find.text('pick-slot-9'));
      await settle(tester);
      expect(sent, {'timeSlotId': 'slot-9'});
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      h.scriptDetail(bookingJson(status: 'requested'));
      await pumpDetail(
        tester,
        routes: {
          SlotPickerScreen.routeName: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('back'),
            ),
          ),
        },
      );
      await scrollTo(tester, find.text('Change the time'));
      await tester.tap(find.text('Change the time'));
      await settle(tester);
      await tester.tap(find.text('back'));
      await settle(tester);
      expect(h.api.calls.where((c) => c.method == 'PATCH'), isEmpty);
    });

    testWidgets('a request takes a new window from the same chips', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      final request = bookingJson(
        status: 'awaiting_quote',
        bookingMode: 'request',
        scheduledFor: null,
        preferredWindowText: 'Tomorrow morning',
      );
      h.scriptDetail(request);
      h.api.on('PATCH', '/v1/bookings/booking-1/reschedule', (body) {
        sent = body as Map<String, dynamic>;
        return request;
      });
      await pumpScreen(
        tester,
        const RescheduleWindowScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('You asked for: Tomorrow morning'), findsOneWidget);
      // Nothing to send until a window is chosen.
      await scrollTo(tester, find.text('Send the new time'));
      await tester.tap(find.text('Send the new time'));
      await settle(tester);
      expect(sent, isNull);

      await scrollTo(tester, find.text('This week'));
      await tester.tap(find.text('This week'));
      await settle(tester);
      await scrollTo(tester, find.text('Send the new time'));
      await tester.tap(find.text('Send the new time'));
      await settle(tester);
      expect(sent, {'preferredWindowChip': 'this_week'});
    });

    testWidgets('a request already answered cannot be moved from here', (
      tester,
    ) async {
      h.scriptDetail(quotedBookingJson());
      await pumpScreen(
        tester,
        const RescheduleWindowScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('This request has moved on'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. The time-window editor
  // ===========================================================================

  group('Time-window editor', () {
    Map<String, dynamic> prefs() => {
      'addresses': [
        {
          'id': 'address-1',
          'label': 'Home',
          'islandId': 'island-1',
          'islandDisplayName': 'Malé',
          'addressLine': 'H. Faiha',
          'createdAt': '2026-09-15T03:00:00.000Z',
        },
      ],
      'timeWindows': <Object>[],
      'standingInstructions': null,
    };

    Future<void> openSheet(WidgetTester tester) async {
      h.api.on('GET', '/v1/users/me/saved-preferences', (_) => prefs());
      await pumpScreen(
        tester,
        const SavedPreferencesScreen(),
        overrides: h.overrides(),
      );
      await tester.tap(find.bySemanticsLabel('Add — Preferred time windows'));
      await settle(tester);
    }

    testWidgets('day toggles alone, Monday first — no preset chips', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.text('Add a time window'), findsOneWidget);
      // The owner's amendment: no Weekdays/Weekend chips.
      expect(
        find.descendant(
          of: find.byType(AppBottomSheet),
          matching: find.byType(AppChip),
        ),
        findsNothing,
      );
      expect(find.text('Weekdays'), findsNothing);
      expect(find.text('Weekend'), findsNothing);

      final toggles = tester
          .widgetList<WeekdayToggle>(find.byType(WeekdayToggle))
          .toList();
      expect(toggles.map((t) => t.day), [1, 2, 3, 4, 5, 6, 7]);
      expect(toggles.map((t) => t.label), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);

      // Save waits for a day.
      expect(find.text('Choose at least one day.'), findsOneWidget);
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save window'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('previews the saved form and sends ISO weekdays', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      h.api.on('POST', '/v1/users/me/saved-preferences/time-windows', (body) {
        sent = body as Map<String, dynamic>;
        return {
          'id': 'window-1',
          'weekdays': [6],
          'startTime': '09:00',
          'endTime': '12:00',
          'label': 'Saturday · 9:00–12:00',
          'createdAt': '2026-09-15T03:00:00.000Z',
        };
      });
      await openSheet(tester);

      await tester.tap(find.bySemanticsLabel('Sat'));
      await settle(tester);
      expect(find.text('Saves as Saturday · 9:00–12:00'), findsOneWidget);

      await tester.tap(find.text('Save window'));
      await settle(tester);
      expect(sent, {
        'weekdays': [6],
        'startTime': '09:00',
        'endTime': '12:00',
      });
    });

    testWidgets('Sunday to Thursday previews as the server will label it', (
      tester,
    ) async {
      await openSheet(tester);
      for (final day in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu']) {
        await tester.tap(find.bySemanticsLabel(day));
        await settle(tester);
      }
      expect(find.text('Saves as Weekdays · 9:00–12:00'), findsOneWidget);
    });

    testWidgets('a refusal stays on the sheet with the choice intact', (
      tester,
    ) async {
      h.api.fail(
        'POST',
        '/v1/users/me/saved-preferences/time-windows',
        status: 422,
        code: 'SAVED_PREFERENCE_LIMIT_REACHED',
        message: 'You can save up to 20 time windows',
      );
      await openSheet(tester);
      await tester.tap(find.bySemanticsLabel('Mon'));
      await settle(tester);
      await tester.tap(find.text('Save window'));
      await settle(tester);
      expect(find.text('You can save up to 20 time windows'), findsOneWidget);
      expect(find.text('Saves as Monday · 9:00–12:00'), findsOneWidget);
    });
  });

  group('previewTimeWindowLabel mirrors the server', () {
    // The cases in backend/test/bookings-ics-and-labels.test.ts — change both
    // or neither.
    test('weekday sets', () {
      String days(List<int> d) =>
          previewTimeWindowLabel(d, '09:00', '12:00').split(' · ').first;
      expect(days([1, 2, 3, 4, 7]), 'Weekdays');
      expect(days([5, 6]), 'Weekend');
      expect(days([1, 3, 5]), 'Mon, Wed, Fri');
      expect(days([6]), 'Saturday');
      expect(days([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(days([2, 7]), 'Sun, Tue');
    });

    test('times', () {
      expect(
        previewTimeWindowLabel([7, 1, 2, 3, 4], '09:00', '12:00'),
        'Weekdays · 9:00–12:00',
      );
      expect(
        previewTimeWindowLabel([6], '14:00', '18:00'),
        'Saturday · 14:00–18:00',
      );
    });
  });
}
