import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/my_bookings_screen.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/provider_receipt_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 17.1's screens, against the artboards and §1c's copy rules.
///
/// The assertions that matter most here are the **negative** ones: that no
/// screen says "verified" about a payment, and that no screen anywhere in the
/// feature renders a phone number. Both are rules the plan states in the
/// strongest terms, and both are the kind of thing that only ever breaks by
/// somebody adding a field.
void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  String allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  Future<String> allTextScrolled(WidgetTester tester) async {
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      seen.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? t.textSpan?.toPlainText() ?? ''),
      );
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -320));
      await settle(tester);
    }
    return seen.join(' | ');
  }

  group('My Bookings', () {
    testWidgets('renders a skeleton while the list is loading', (tester) async {
      h.api.gate = Completer<void>();
      h.scriptList([bookingJson()]);

      await pumpScreen(
        tester,
        const MyBookingsScreen(),
        overrides: h.overrides(),
      );

      expect(find.byType(SkeletonLoader), findsOneWidget);
      h.api.gate?.complete();
    });

    testWidgets(
      'a genuinely empty account reads differently from an empty pill',
      (tester) async {
        h.scriptList(const []);
        await pumpScreen(
          tester,
          const MyBookingsScreen(),
          overrides: h.overrides(),
        );

        // The empty state names what would put something in it — never a bare
        // "nothing here" (screen-state completeness).
        expect(find.text('No bookings yet'), findsOneWidget);
        expect(allText(tester), contains('When you book a service'));
      },
    );

    testWidgets('the pills filter what is loaded rather than re-fetching', (
      tester,
    ) async {
      h.scriptList([
        bookingJson(status: 'awaiting_payment'),
        bookingJson(id: 'booking-2', status: 'completed'),
      ]);
      await pumpScreen(
        tester,
        const MyBookingsScreen(),
        overrides: h.overrides(),
      );

      final before = h.api.calls.length;
      expect(find.text('2 bookings'), findsOneWidget);

      // Scoped to the pill: the completed booking's own status badge carries
      // the same word, which is the copy working rather than a clash.
      await tester.tap(find.widgetWithText(AppChip, 'Completed'));
      await settle(tester);

      // No second GET: the count above the list can never disagree with the
      // list under it, which is why §Phase 10's dashboard made this choice.
      expect(h.api.calls.length, before);
      expect(find.text('2 bookings'), findsOneWidget);
    });

    testWidgets('an offline list offers a retry rather than a blank screen', (
      tester,
    ) async {
      h.api.offline('GET', '/v1/users/me/bookings?role=customer&limit=50');
      await pumpScreen(
        tester,
        const MyBookingsScreen(),
        overrides: h.overrides(),
      );

      expect(find.text('Couldn’t load your bookings'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(allText(tester), contains('Nothing has changed'));
    });
  });

  group('Booking detail', () {
    Future<void> pumpDetail(
      WidgetTester tester, {
      required Map<String, dynamic> booking,
      String viewerId = 'customer-1',
    }) async {
      h.scriptDetail(booking);
      await pumpScreen(
        tester,
        BookingDetailScreen(
          args: BookingDetailArgs(bookingId: booking['id'] as String),
        ),
        overrides: h.overrides(viewerId: viewerId),
      );
    }

    testWidgets('renders the status timeline with who caused each transition', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        booking: bookingJson(
          statusHistory: [
            eventJson('create', 'requested'),
            eventJson('accept', 'accepted', actorRole: 'provider'),
            eventJson('amount-set', 'awaiting_payment', actorRole: 'provider'),
          ],
        ),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('Requested'));
      expect(text, contains('Accepted — terms locked'));
      // The customer reads their own action as "you" and the provider's by
      // name — which is what makes an auto-decline legible as *automatic*.
      expect(text, contains('you'));
      expect(text, contains('Mariyam Shifa'));
    });

    testWidgets(
      'an auto-decline reads as automatic, not as the provider refusing',
      (tester) async {
        await pumpDetail(
          tester,
          booking: bookingJson(
            status: 'declined',
            statusHistory: [
              eventJson('create', 'requested'),
              eventJson('accept-timeout', 'declined', actorRole: 'system'),
            ],
          ),
        );

        final text = await allTextScrolled(tester);
        expect(text, contains('No answer in time — closed'));
        expect(text, contains('automatically'));
      },
    );

    testWidgets(
      '§1h: an open amendment is a decision for the counterparty only',
      (tester) async {
        await pumpDetail(
          tester,
          booking: bookingJson(amendments: [amendmentJson()]),
        );

        final text = await allTextScrolled(tester);
        expect(text, contains('Change proposed — your decision'));
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        // The live terms have not moved — that is the whole of "neither party
        // can alter them unilaterally".
        expect(text, contains('MVR 450'));
      },
    );

    testWidgets(
      'the proposer sees their own proposal as waiting, with no accept',
      (tester) async {
        await pumpDetail(
          tester,
          booking: bookingJson(amendments: [amendmentJson()]),
          viewerId: 'provider-user-1',
        );

        final text = await allTextScrolled(tester);
        expect(text, contains('Your proposal · on the record'));
        expect(find.text('Accept'), findsNothing);
        expect(find.text('Withdraw this proposal'), findsOneWidget);
      },
    );

    testWidgets('§1h: a provider cancellation offers the customer a prefill', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        booking: bookingJson(
          status: 'cancelled',
          cancelledByRole: 'provider',
          replacement: {
            'listingId': 'listing-1',
            'bookingMode': 'slot',
            'scheduledFor': '2026-09-25T09:00:00.000Z',
            'jobNotes': 'Two bedrooms and kitchen',
            'islandId': 'island-1',
            'addressDetail': 'H. Faiha, 2nd floor',
          },
        ),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('Your booking, ready to send again'));
      // §1h: "normal bookings do not broadcast" — the copy says so, because a
      // customer expecting other providers to be contacted would wait.
      expect(text, contains('isn’t sent out to other providers'));
    });

    testWidgets('offers no way to contact the counterparty, and no number', (
      tester,
    ) async {
      await pumpDetail(tester, booking: bookingJson());

      final text = await allTextScrolled(tester);
      // §1c: coordination is the chat, and the chat is §Phase 18's. A dead
      // "Message" button would advertise an action with a person on the other
      // end of it, which `InertControl`'s own note says belongs absent.
      expect(find.widgetWithText(AppButton, 'Message'), findsNothing);
      expect(text.toLowerCase(), isNot(contains('call ')));
      expect(RegExp(r'\b7\d{6}\b').hasMatch(text), isFalse);
      expect(RegExp(r'\+960').hasMatch(text), isFalse);
    });

    testWidgets('no card swallows the controls inside it', (tester) async {
      await pumpDetail(
        tester,
        booking: bookingJson(amendments: [amendmentJson()]),
      );
      expectNoSwallowedControls(tester);
    });
  });

  group('Payment step — §1c’s honesty rule', () {
    testWidgets('shows the bank details and says what they are not', (
      tester,
    ) async {
      final booking = bookingJson(paymentDetails: bankDetails);
      h.scriptDetail(booking);

      await pumpScreen(
        tester,
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('Bank of Maldives'));
      expect(text, contains('7701234567890'));
      expect(text, contains('aren’t a way to contact'));
      expect(text, contains('This payment never touches RaajjePro'));
    });

    testWidgets('never says verified, and never implies RaajjePro checked it', (
      tester,
    ) async {
      h.scriptDetail(
        bookingJson(
          status: 'payment_claimed',
          paymentClaimedAt: '2026-09-15T02:00:00.000Z',
        ),
      );

      await pumpScreen(
        tester,
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      final text = (await allTextScrolled(tester)).toLowerCase();
      // The forbidden claim is the affirmative one. The screen may — and
      // does — use the word to *deny* it, which is the copy §1c asks for.
      expect(text.contains('payment verified'), isFalse);
      expect(text.contains('verified by raajjepro'), isFalse);
      expect(RegExp('(?<!hasn’t )\\bverified\\b').hasMatch(text), isFalse);
      // What it says instead.
      expect(text, contains('that’s your word, not a check'));
      expect(text, contains('raajjepro hasn’t verified anything'));
    });

    testWidgets('Round 24: the withdrawal is offered once and then explained', (
      tester,
    ) async {
      h.scriptDetail(
        bookingJson(
          status: 'payment_claimed',
          paymentClaimedAt: '2026-09-15T02:00:00.000Z',
        ),
      );
      await pumpScreen(
        tester,
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('I haven’t actually paid yet — undo'), findsOneWidget);

      // Already used: the control is gone, and the screen says why rather
      // than offering a button that will certainly be refused.
      h.api.on(
        'GET',
        '/v1/bookings/booking-1',
        (_) => bookingJson(
          status: 'payment_claimed',
          paymentClaimedAt: '2026-09-15T02:00:00.000Z',
          paymentClaimWithdrawnAt: '2026-09-15T01:00:00.000Z',
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      final text = await allTextScrolled(tester);
      expect(find.text('I haven’t actually paid yet — undo'), findsNothing);
      expect(text, contains('already taken a payment claim back'));
    });

    testWidgets('a provider with no bank details is explained, not blank', (
      tester,
    ) async {
      h.scriptDetail(bookingJson());

      await pumpScreen(
        tester,
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('No transfer details yet'));
      expect(text, contains('the booking stays exactly where it is'));
    });
  });

  group('Provider receipt — three distinct actions', () {
    testWidgets('decline and dispute are separate, and neither says verified', (
      tester,
    ) async {
      h.scriptDetail(
        bookingJson(
          status: 'payment_claimed',
          paymentClaimedAt: '2026-09-15T02:00:00.000Z',
        ),
      );

      await pumpScreen(
        tester,
        const ProviderReceiptScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      final text = await allTextScrolled(tester);
      // §Phase 17 frontend item 5, and §1c's "decline ≠ dispute".
      expect(find.text('Payment received'), findsOneWidget);
      expect(find.text('Payment not received'), findsOneWidget);
      expect(find.text('Cancel this booking instead'), findsOneWidget);
      expect(text.toLowerCase().contains('verified'), isFalse);
      expect(text, contains('your own statement'));
      // §1c step 9: seven days is a review, not a confirmation.
      expect(text, contains('a review, not a confirmation'));
    });
  });

  group('Raise a dispute', () {
    testWidgets(
      'offers §Phase 22’s four booking reasons and no free-text-only path',
      (tester) async {
        h.scriptDetail(bookingJson());

        await pumpScreen(
          tester,
          const RaiseDisputeScreen(
            args: BookingActionArgs(bookingId: 'booking-1'),
          ),
          overrides: h.overrides(),
        );

        final text = await allTextScrolled(tester);
        expect(text, contains('The work wasn’t done'));
        expect(text, contains('The price changed on site'));
        expect(text, contains('The work was unsafe'));
        expect(text, contains('The payment doesn’t match'));
        // The honest limit, stated where somebody is about to expect otherwise.
        expect(text, contains('can’t be refunded or reversed from here'));
      },
    );

    testWidgets('a completed booking is told the report does not reopen it', (
      tester,
    ) async {
      h.scriptDetail(bookingJson(status: 'completed'));

      await pumpScreen(
        tester,
        const RaiseDisputeScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      expect(
        await allTextScrolled(tester),
        contains('The booking stays completed'),
      );
    });
  });

  group('Mark complete', () {
    testWidgets('an emergency booking requires the final amount and says why', (
      tester,
    ) async {
      h.scriptDetail(
        bookingJson(
          bookingMode: 'emergency',
          status: 'confirmed',
          amountKind: 'callout_fee',
        ),
      );

      await pumpScreen(
        tester,
        const MarkCompleteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('Final amount — required'));
      expect(text, contains('this is the number that settles it'));

      // Submitting without it is refused before the request is made.
      // Scoped to the button: the header carries the same words.
      await tester.tap(find.widgetWithText(AppButton, 'Mark complete'));
      await settle(tester);
      expect(
        await allTextScrolled(tester),
        contains('An emergency job needs its final amount'),
      );
    });

    testWidgets('a slot booking makes it optional and names the consequence', (
      tester,
    ) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));

      await pumpScreen(
        tester,
        const MarkCompleteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('Final amount charged'));
      expect(text, contains('price-adherence'));
      // The reassurance that stops a provider feeling trapped by the button.
      expect(text, contains('Not marking it complete doesn’t bury it'));
    });
  });

  group('Did this happen', () {
    testWidgets(
      'says plainly that "no" opens a report, and what silence does',
      (tester) async {
        h.scriptDetail(
          bookingJson(
            status: 'confirmed',
            completionPromptedAt: '2026-09-15T01:00:00.000Z',
          ),
        );

        await pumpScreen(
          tester,
          const DidThisHappenScreen(
            args: BookingActionArgs(bookingId: 'booking-1'),
          ),
          overrides: h.overrides(),
        );

        final text = await allTextScrolled(tester);
        expect(find.text('Yes — the job was done'), findsOneWidget);
        expect(find.text('No — it didn’t happen'), findsOneWidget);
        expect(text, contains('opens a report an admin reviews'));
        expect(text, contains('closes on its own in three days'));
      },
    );
  });

  group('Cancel', () {
    testWidgets('tells a customer nothing goes on anyone’s record', (
      tester,
    ) async {
      h.scriptDetail(bookingJson());

      await pumpScreen(
        tester,
        const CancelBookingScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      final text = await allTextScrolled(tester);
      expect(text, contains('goes back into the calendar'));
      expect(text, contains('nothing here to refund'));
      expect(text, contains('never appears on anyone’s public profile'));
    });
  });
}
