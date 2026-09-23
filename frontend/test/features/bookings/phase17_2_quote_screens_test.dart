import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/propose_quote_screen.dart';
import 'package:raajjepro/features/bookings/presentation/provider_accept_screen.dart';
import 'package:raajjepro/features/bookings/presentation/quote_received_screen.dart';
import 'package:raajjepro/features/bookings/presentation/request_time_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 17.2's three screens — `Request a Time`, `Propose Time and Price`
/// and `Quote Received`.
///
/// What these assert beyond the usual four states:
///
///  * the two quote clocks are **rendered, never derived** — invariant 13 puts
///    them on the category, and a screen that computed 4 hours or 72 would be
///    the copy that drifts;
///  * a `request` booking's provider prompt offers a **quote**, not an accept
///    — §1c, and the server refuses a bare accept by name;
///  * the chat is reachable from `quote_offered`, which is the state §0.0
///    item 7 moved it to;
///  * **no screen renders a phone number** (the rule standing over all four
///    slices), re-checked over the three added here.

/// Scrolls the screen's list until [finder] is built and on screen.
///
/// These screens are taller than the 412×915 test frame and `ListView` builds
/// lazily, so a bottom CTA is genuinely absent from the tree until it is
/// scrolled to — not merely off screen.
/// [delta] is negative to search **upward** — an error banner sits at the top
/// of a form the tap that produced it had already scrolled away from.
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

void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  group('Request a time — the customer asks', () {
    testWidgets('leads with the window chips and sends what was tapped', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      h.api.on('POST', '/v1/listings/listing-1/bookings', (body) {
        sent = body as Map<String, dynamic>;
        return bookingJson(status: 'awaiting_quote', bookingMode: 'request');
      });
      h.scriptDetail(bookingJson(status: 'awaiting_quote'));

      await pumpScreen(
        tester,
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
        overrides: h.overrides(),
        routes: {'/bookings/detail': (_) => const SizedBox.shrink()},
      );

      // §1c: the chips lead, and all four of the plan's windows are offered.
      for (final chip in WindowChip.values) {
        expect(find.text(chip.label), findsOneWidget);
      }

      // Nothing can be sent until a window exists — the request *is* a window.
      await scrollTo(tester, find.text('Add a window to send'));
      expect(find.text('Add a window to send'), findsOneWidget);

      // Back up to the chips, which the scroll to the CTA left behind.
      await scrollTo(tester, find.text('Tomorrow morning'));
      await tester.tap(find.text('Tomorrow morning'));
      await settle(tester);

      await scrollTo(tester, find.text('Send request'));
      expect(find.text('Send request'), findsOneWidget);
      await tester.tap(find.text('Send request'));
      await settle(tester);

      expect(sent?['preferredWindowChip'], 'tomorrow_morning');
      // The chip's *range* is the server's to resolve — the client sends which
      // chip was tapped and nothing it worked out itself.
      expect(sent?.containsKey('preferredWindowFrom'), isFalse);
    });

    testWidgets('says the window is a preference, not a slot', (tester) async {
      await pumpScreen(
        tester,
        const RequestTimeScreen(
          args: RequestTimeArgs(
            listingId: 'listing-1',
            providerName: 'Ibrahim Rasheed',
          ),
        ),
        overrides: h.overrides(),
      );

      // The sentence that separates this mode from `Pick a Time`.
      expect(
        find.textContaining('This is a preference, not a slot'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'not a slot — Ibrahim Rasheed replies with a concrete time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('states no window it cannot read from the category', (
      tester,
    ) async {
      // No `categoryId`, so the catalogue is never consulted and the screen
      // has no clock to quote. Invariant 13: it says so qualitatively rather
      // than inventing 2 hours.
      await pumpScreen(
        tester,
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
        overrides: h.overrides(),
      );

      expect(
        find.textContaining('within the window their category sets'),
        findsOneWidget,
      );
      expect(find.textContaining('2 hours'), findsNothing);
      expect(find.textContaining('4 hours'), findsNothing);
      expect(find.textContaining('24 hours'), findsNothing);
      expect(find.textContaining('72 hours'), findsNothing);
    });

    testWidgets('blocks sending until the email is verified, and says why', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
        overrides: h.overrides(emailVerified: false),
      );

      await tester.tap(find.text('This week'));
      await settle(tester);

      await scrollTo(tester, find.text('Verify your email to send this'));
      expect(find.text('Verify your email to send this'), findsOneWidget);
      await scrollTo(tester, find.text('Send request'));
      final cta = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Send request'),
      );
      expect(cta.onPressed, isNull);
    });

    testWidgets('keeps what was typed when the network refuses', (
      tester,
    ) async {
      h.api.offline('POST', '/v1/listings/listing-1/bookings');

      await pumpScreen(
        tester,
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
        overrides: h.overrides(),
      );

      await tester.tap(find.text('Tomorrow afternoon'));
      await settle(tester);
      await scrollTo(tester, find.text('Send request'));
      await tester.tap(find.text('Send request'));
      await settle(tester);

      // The banner is at the top of the form, above where the tap left us.
      await scrollTo(
        tester,
        find.textContaining('nothing was sent'),
        delta: -200,
      );
      expect(find.textContaining('nothing was sent'), findsOneWidget);
      // Still sendable — the form is not thrown away on a failure.
      await scrollTo(tester, find.text('Send request'));
      expect(find.text('Send request'), findsOneWidget);
    });
  });

  group('Propose a time and price — the provider answers', () {
    testWidgets('sends the time and the price together, in laari', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      h.scriptDetail(
        bookingJson(
          status: 'awaiting_quote',
          bookingMode: 'request',
          agreedAmountLaari: null,
          amountKind: null,
          quotedAmountLaari: null,
          scheduledFor: null,
          preferredWindowText: 'Tomorrow morning',
        ),
      );
      h.api.on('PATCH', '/v1/bookings/booking-1/quote', (body) {
        sent = body as Map<String, dynamic>;
        return quotedBookingJson();
      });

      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      // What the customer asked for is on the screen, and nothing that could
      // reach them is.
      expect(find.text('Tomorrow morning'), findsOneWidget);
      expect(find.text('Aishath Naeema asked for'), findsOneWidget);

      await tester.tap(find.text('Tomorrow'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Your price'),
        '650',
      );
      await settle(tester);

      await scrollTo(tester, find.textContaining('Send quote'));
      await tester.tap(find.textContaining('Send quote'));
      await settle(tester);

      // Invariant 7: MVR 650 is 65000 laari, and the conversion happens once.
      expect(sent?['amountLaari'], 65000);
      expect(sent?['scheduledFor'], isA<String>());
    });

    testWidgets('refuses to send without a price, inline under the field', (
      tester,
    ) async {
      h.scriptDetail(
        bookingJson(
          status: 'awaiting_quote',
          bookingMode: 'request',
          scheduledFor: null,
        ),
      );

      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      await tester.tap(find.text('Tomorrow'));
      await settle(tester);
      await scrollTo(tester, find.textContaining('Send quote'));
      await tester.tap(find.textContaining('Send quote'));
      await settle(tester);

      expect(find.textContaining('accepts this exact number'), findsWidgets);
    });

    testWidgets(
      'tells the provider that sending holds the time and opens chat',
      (tester) async {
        h.scriptDetail(
          bookingJson(
            status: 'awaiting_quote',
            bookingMode: 'request',
            scheduledFor: null,
          ),
        );

        await pumpScreen(
          tester,
          const ProposeQuoteScreen(
            args: BookingActionArgs(bookingId: 'booking-1'),
          ),
          overrides: h.overrides(viewerId: 'provider-user-1'),
        );

        // §1c's two consequences of offering a quote, both stated before the tap.
        await scrollTo(
          tester,
          find.textContaining('holds that time in your calendar'),
        );
        expect(
          find.textContaining('holds that time in your calendar'),
          findsOneWidget,
        );
        expect(find.textContaining('opens the chat'), findsOneWidget);
      },
    );

    testWidgets('opens on the live quote when revising one', (tester) async {
      h.scriptDetail(quotedBookingJson());

      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      // A revision is an edit, not a re-entry: the price already on the table
      // is in the field, and the CTA says which it is.
      expect(find.text('650'), findsOneWidget);
      await scrollTo(tester, find.textContaining('Send revised quote'));
      expect(find.textContaining('Send revised quote'), findsOneWidget);
    });

    testWidgets('renders loading and error states', (tester) async {
      // A held response, so the screen is genuinely mid-fetch rather than
      // failing on an unscripted call.
      h.api.gate = Completer<void>();
      h.scriptDetail(quotedBookingJson());
      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );
      expect(find.byType(SkeletonLoader), findsOneWidget);
      h.api.gate?.complete();
      await settle(tester);

      final failing = BookingHarness();
      failing.api.offline('GET', '/v1/bookings/booking-1');
      await pumpScreen(
        tester,
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: failing.overrides(viewerId: 'provider-user-1'),
      );
      expect(find.text('Couldn’t load this request'), findsOneWidget);
    });
  });

  group('Quote received — the customer decides', () {
    testWidgets('counts down to the deadline the server gave it', (
      tester,
    ) async {
      h.scriptDetail(quotedBookingJson());

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      // The fixture's deadline is four hours after the harness clock, which is
      // what the server computed from Plumbing's `quoteApprovalMinutes`. The
      // screen renders that distance and never a category constant.
      expect(find.text('4h 0m left'), findsOneWidget);
      expect(
        find.textContaining('the window your service’s category sets'),
        findsOneWidget,
      );
    });

    testWidgets('shows the offered time, the price and the note', (
      tester,
    ) async {
      h.scriptDetail(quotedBookingJson());

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      expect(find.text('Quote from Mariyam Shifa'), findsOneWidget);
      // §1c's honest framing, and the actor the quote path actually has: the
      // **customer** accepts a quote, where a slot booking's provider accepts
      // a listed price.
      expect(find.text('MVR 650'), findsOneWidget);
      expect(
        find.text('Replace joint, reseal line — parts included'),
        findsOneWidget,
      );
      // §1h, before the button rather than after it.
      expect(find.text('What accepting means'), findsOneWidget);
    });

    testWidgets('accepting sends approve-quote and moves to payment', (
      tester,
    ) async {
      var approved = false;
      h.scriptDetail(quotedBookingJson());
      h.api.on('PATCH', '/v1/bookings/booking-1/approve-quote', (_) {
        approved = true;
        return quotedBookingJson(status: 'awaiting_payment');
      });

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
        routes: {PaymentStepScreen.routeName: (_) => const SizedBox.shrink()},
      );

      await scrollTo(tester, find.text('Accept quote'));
      await tester.tap(find.text('Accept quote'));
      await settle(tester);
      expect(approved, isTrue);
    });

    testWidgets('offers the chat above the decline, and never below it', (
      tester,
    ) async {
      h.scriptDetail(quotedBookingJson());

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      // §0.0 item 7: the thread is open at `quote_offered`, which is why the
      // artboard puts "say so in chat" above declining — the provider can
      // still revise, and a decline closes the booking.
      await scrollTo(tester, find.text('Decline this quote'));
      final chat = tester.getTopLeft(find.textContaining('Nearly right?'));
      final decline = tester.getTopLeft(find.text('Decline this quote'));
      expect(chat.dy, lessThan(decline.dy));
    });

    testWidgets('an expired quote cannot be accepted', (tester) async {
      // The sweep runs every five minutes, so a customer really can be looking
      // at a quote whose deadline has just passed.
      h.scriptDetail(
        quotedBookingJson(quoteExpiresAt: '2026-09-15T02:00:00.000Z'),
      );

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      expect(find.text('Expired'), findsOneWidget);
      await scrollTo(tester, find.text('This quote expired'));
      final cta = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'This quote expired'),
      );
      expect(cta.onPressed, isNull);
    });

    testWidgets('an answered quote is a record, not a decision', (
      tester,
    ) async {
      h.scriptDetail(quotedBookingJson(status: 'awaiting_payment'));

      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      expect(find.text('It’s agreed'), findsOneWidget);
      expect(find.text('Accept quote'), findsNothing);
    });
  });

  group('the provider prompt routes a request to a quote', () {
    testWidgets('offers a quote instead of a bare accept', (tester) async {
      h.scriptDetail(
        bookingJson(
          status: 'awaiting_quote',
          bookingMode: 'request',
          scheduledFor: null,
        ),
      );

      await pumpScreen(
        tester,
        const ProviderAcceptScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
        routes: {ProposeQuoteScreen.routeName: (_) => const SizedBox.shrink()},
      );

      // §1c: a request-based provider answers with a time and a price. The
      // server refuses a bare accept by name, and the screen must not offer
      // the tap that would earn that refusal.
      await scrollTo(tester, find.text('Propose a time & price'));
      expect(find.text('Propose a time & price'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Accept'), findsNothing);
    });

    testWidgets('still offers a plain accept on a slot booking', (
      tester,
    ) async {
      h.scriptDetail(bookingJson(status: 'requested'));

      await pumpScreen(
        tester,
        const ProviderAcceptScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(viewerId: 'provider-user-1'),
      );

      await scrollTo(tester, find.widgetWithText(AppButton, 'Accept'));
      expect(find.widgetWithText(AppButton, 'Accept'), findsOneWidget);
      expect(find.text('Propose a time & price'), findsNothing);
    });
  });

  group('the standing rule — no screen renders a phone number', () {
    testWidgets('across all three of this slice’s screens', (tester) async {
      // The counterparty's number is in the harness's own auth fixture, so a
      // screen that leaked one would have something to leak.
      const number = '7771234';

      h.scriptDetail(quotedBookingJson());
      for (final screen in <Widget>[
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        const ProposeQuoteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
      ]) {
        await pumpScreen(
          tester,
          screen,
          overrides: h.overrides(viewerId: 'provider-user-1'),
        );
        expect(find.textContaining(number), findsNothing);
        expect(find.textContaining('WhatsApp'), findsNothing);
        expect(find.textContaining('Viber'), findsNothing);
      }
    });
  });

  group('accessibility', () {
    testWidgets('no card swallows the controls inside it', (tester) async {
      h.scriptDetail(quotedBookingJson());
      await pumpScreen(
        tester,
        const QuoteReceivedScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expectNoSwallowedControls(tester);

      await pumpScreen(
        tester,
        const RequestTimeScreen(args: RequestTimeArgs(listingId: 'listing-1')),
        overrides: h.overrides(),
      );
      expectNoSwallowedControls(tester);
    });
  });
}
