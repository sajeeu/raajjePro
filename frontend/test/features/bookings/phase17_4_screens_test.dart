import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/bookings/presentation/book_again_screen.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/recurring_booking_screen.dart';
import 'package:raajjepro/features/saved_preferences/presentation/saved_preferences_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/a11y.dart';
import '../../helpers/pump.dart';
import 'harness.dart';

/// §Phase 17.4's drawn screens — `Recurring Booking`, `Book Again` and
/// `Saved Preferences` — plus Booking Detail's "Make this recurring".
///
/// Beyond the four states each screen owes, these hold the rules the slice
/// exists for: a series is **a weekly ask, never a subscription**; Book Again
/// routes by the listing's mode **now** and carries the saved details
/// forward; an island is **chosen, never defaulted**; and no screen here
/// renders a phone number.

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Map<String, dynamic> seriesJson({
  String status = 'active',
  int consecutiveMisses = 0,
  List<Map<String, dynamic>> occurrences = const [],
  String? nextOccurrenceAt = '2026-10-06T09:00:00.000Z',
  String? nextAskAt = '2026-09-29T09:00:00.000Z',
}) => {
  'id': 'series-1',
  'status': status,
  'listingId': 'listing-1',
  'listingName': 'Home Deep Cleaning',
  'customer': {'userId': 'customer-1', 'name': 'Aishath Naeema'},
  'provider': {'userId': 'provider-user-1', 'name': 'Mariyam Shifa'},
  'durationMinutes': 120,
  'pricePerVisitLaari': 45000,
  'nextOccurrenceAt': nextOccurrenceAt,
  'nextAskAt': nextAskAt,
  'nextOccurrenceSkipped': false,
  'consecutiveMisses': consecutiveMisses,
  'pausedAt': status == 'paused' ? '2026-09-29T09:00:00.000Z' : null,
  'endedAt': status == 'ended' ? '2026-09-29T09:00:00.000Z' : null,
  'createdAt': '2026-09-15T03:00:00.000Z',
  'occurrences': occurrences,
};

Map<String, dynamic> weekJson(
  String occursAt,
  String state, {
  String? missReason,
  String? bookingStatus,
  String? bookingId,
}) => {
  'id': 'week-$occursAt',
  'occursAt': occursAt,
  'state': state,
  'missReason': missReason,
  'bookingId': bookingId,
  'bookingStatus': bookingStatus,
};

Map<String, dynamic> bookAgainJson({
  bool available = true,
  String? bookingMode = 'slot',
  bool modeChanged = false,
}) => {
  'fromBookingId': 'booking-1',
  'listingId': 'listing-1',
  'listingName': 'Home Deep Cleaning',
  'categoryName': 'Cleaning',
  'providerName': 'Mariyam Shifa',
  'providerVerificationTier': 'silver',
  'available': available,
  'bookingMode': bookingMode,
  'modeChanged': modeChanged,
  'pricingModel': 'fixed',
  'priceLaari': 45000,
  'lastDoneAt': '2026-09-08T09:00:00.000Z',
  'jobNotes': 'Two bedrooms and kitchen',
  'islandId': 'island-1',
  'islandDisplayName': 'Malé',
  'addressDetail': 'H. Faiha, 2nd floor',
  'occasion': null,
  'standingInstructions': 'Gate code 4471',
  'preferredWindowLabel': 'Tuesday · 13:00–17:00',
};

void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  group('Booking Detail — "Make this recurring"', () {
    testWidgets('offered on a confirmed slot booking, not on a request', (
      tester,
    ) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));
      await pumpScreen(
        tester,
        const BookingDetailScreen(
          args: BookingDetailArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      await scrollTo(tester, find.text('Make this recurring'));
      expect(find.text('Make this recurring'), findsOneWidget);

      h.scriptDetail(
        bookingJson(
          id: 'booking-2',
          status: 'confirmed',
          bookingMode: 'request',
        ),
      );
      await pumpScreen(
        tester,
        const BookingDetailScreen(
          args: BookingDetailArgs(bookingId: 'booking-2'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('Make this recurring'), findsNothing);
    });
  });

  group('Recurring booking — the offer', () {
    testWidgets('states it is a weekly ask, asks, and confirms what it did', (
      tester,
    ) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));
      h.api.on(
        'POST',
        '/v1/recurring-series',
        (_) => seriesJson(
          occurrences: [
            weekJson(
              '2026-10-02T09:00:00.000Z',
              'asked',
              bookingStatus: 'requested',
              bookingId: 'booking-9',
            ),
          ],
        ),
      );
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );

      expect(find.text('Same time next week?'), findsOneWidget);
      // §1c: "Recurrence is a convenience, not a standing pre-authorization."
      expect(find.textContaining('not a subscription'), findsOneWidget);
      // 25 Sep 14:00 Malé + 7 days.
      expect(find.textContaining('Fri 2 Oct · 14:00'), findsOneWidget);

      await tester.tap(find.text('Ask Mariyam for next Friday'));
      await settle(tester);
      expect(h.api.calls.last.path, '/v1/recurring-series');
      expect(h.api.calls.last.body, {'bookingId': 'booking-1'});
      expect(find.text('Asked — Fridays are now a series'), findsOneWidget);
      expect(find.text('Waiting for provider'), findsOneWidget);
      expectNoSwallowedControls(tester);
    });

    testWidgets('an existing series opens instead of failing', (tester) async {
      h.scriptDetail(bookingJson(status: 'confirmed'));
      h.api.fail(
        'POST',
        '/v1/recurring-series',
        status: 409,
        code: 'RECURRING_SERIES_EXISTS',
        details: {'seriesId': 'series-1'},
      );
      h.api.on('GET', '/v1/recurring-series/series-1', (_) => seriesJson());
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      await tester.tap(find.text('Ask Mariyam for next Friday'));
      await settle(tester);
      expect(
        find.textContaining('a weekly ask, not a standing booking'),
        findsOneWidget,
      );
    });

    testWidgets('loading, then an error with a retry', (tester) async {
      h.api.offline('GET', '/v1/bookings/booking-1');
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(bookingId: 'booking-1'),
        ),
        overrides: h.overrides(),
      );
      expect(find.text('Couldn’t load the series'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Recurring booking — the series', () {
    testWidgets('a missed week reads as skipped, and the series carries on', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/recurring-series/series-1',
        (_) => seriesJson(
          consecutiveMisses: 1,
          occurrences: [
            weekJson(
              '2026-09-22T09:00:00.000Z',
              'accepted',
              bookingStatus: 'completed',
            ),
            weekJson(
              '2026-09-29T09:00:00.000Z',
              'missed',
              missReason: 'timed_out',
            ),
          ],
        ),
      );
      h.api.on(
        'PATCH',
        '/v1/recurring-series/series-1/skip',
        (_) => seriesJson(),
      );
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(seriesId: 'series-1'),
        ),
        overrides: h.overrides(),
      );

      expect(find.text('Tuesdays · 14:00'), findsOneWidget);
      // §1c's own words: "this week was not confirmed; your series continues
      // next week".
      expect(
        find.text(
          'This week was not confirmed; your series continues next week',
        ),
        findsOneWidget,
      );
      expect(find.text('Not confirmed'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // The next, not-yet-asked week is skippable ahead of time.
      await scrollTo(tester, find.text('Skip'));
      await tester.tap(find.text('Skip'));
      await settle(tester);
      final skip = h.api.calls.firstWhere((c) => c.method == 'PATCH');
      expect(skip.path, '/v1/recurring-series/series-1/skip');
      expect(skip.body, {'occursAt': '2026-10-06T09:00:00.000Z'});
    });

    testWidgets('paused after three: reconfirm or end, nothing charged', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/recurring-series/series-1',
        (_) =>
            seriesJson(status: 'paused', consecutiveMisses: 3, nextAskAt: null),
      );
      h.api.on(
        'PATCH',
        '/v1/recurring-series/series-1/resume',
        (_) => seriesJson(),
      );
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(seriesId: 'series-1'),
        ),
        overrides: h.overrides(),
      );
      expect(
        find.text('Series paused — three weeks weren’t confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('nothing is charged'), findsOneWidget);
      // A paused series offers no skip — nothing is being asked.
      expect(find.text('Skip'), findsNothing);
      await tester.tap(find.text('Keep asking weekly'));
      await settle(tester);
      expect(
        h.api.calls.any(
          (c) =>
              c.method == 'PATCH' &&
              c.path == '/v1/recurring-series/series-1/resume',
        ),
        isTrue,
      );
    });

    testWidgets('ending asks first, and says what it leaves alone', (
      tester,
    ) async {
      h.api.on('GET', '/v1/recurring-series/series-1', (_) => seriesJson());
      h.api.on(
        'PATCH',
        '/v1/recurring-series/series-1/end',
        (_) => seriesJson(status: 'ended'),
      );
      await pumpScreen(
        tester,
        const RecurringBookingScreen(
          args: RecurringBookingArgs(seriesId: 'series-1'),
        ),
        overrides: h.overrides(),
      );
      await scrollTo(tester, find.text('End the series'));
      await tester.tap(find.text('End the series'));
      await settle(tester);
      expect(
        find.textContaining('Confirmed and past weeks are untouched'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Yes, end it'));
      await tester.tap(find.text('Yes, end it'));
      await settle(tester);
      expect(
        h.api.calls.any(
          (c) =>
              c.method == 'PATCH' &&
              c.path == '/v1/recurring-series/series-1/end',
        ),
        isTrue,
      );
    });
  });

  group('Book again', () {
    testWidgets('routes a slot listing to Pick a time, carrying the details', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/bookings/booking-1/book-again',
        (_) => bookAgainJson(),
      );
      Object? pushed;
      await pumpScreen(
        tester,
        const BookAgainScreen(args: BookAgainArgs(bookingId: 'booking-1')),
        overrides: h.overrides(),
        routes: {
          '/book': (context) {
            pushed = ModalRoute.of(context)?.settings.arguments;
            return const SizedBox.shrink();
          },
        },
      );
      expect(find.text('Everything is carried over'), findsOneWidget);
      expect(find.text('Gate code 4471'), findsOneWidget);
      expect(find.text('Tuesday · 13:00–17:00'), findsOneWidget);
      // The tier, rendered by `VerificationBadge` — never a bare "Verified".
      expect(find.byType(VerificationBadge), findsOneWidget);
      expect(
        tester.widget<VerificationBadge>(find.byType(VerificationBadge)).tier,
        VerificationTier.silver,
      );

      await tester.tap(find.text('Pick a time'));
      await settle(tester);
      final args = pushed as Map<String, dynamic>;
      expect(args['listingId'], 'listing-1');
      expect(args['islandId'], 'island-1');
      expect(args['addressDetail'], 'H. Faiha, 2nd floor');
      expect(args['jobNotes'], contains('Gate code 4471'));
      expectNoSwallowedControls(tester);
    });

    testWidgets(
      'a listing switched to requests routes to Request a time and says so',
      (tester) async {
        h.api.on(
          'GET',
          '/v1/bookings/booking-1/book-again',
          (_) => bookAgainJson(bookingMode: 'request', modeChanged: true),
        );
        var reached = false;
        await pumpScreen(
          tester,
          const BookAgainScreen(args: BookAgainArgs(bookingId: 'booking-1')),
          overrides: h.overrides(),
          routes: {
            '/request': (_) {
              reached = true;
              return const SizedBox.shrink();
            },
          },
        );
        expect(
          find.textContaining('switched from open slots to requests'),
          findsOneWidget,
        );
        await tester.tap(find.text('Request a time'));
        await settle(tester);
        expect(reached, isTrue);
      },
    );

    testWidgets('a listing that went says so, and error offers a retry', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/bookings/booking-1/book-again',
        (_) => bookAgainJson(available: false, bookingMode: null),
      );
      await pumpScreen(
        tester,
        const BookAgainScreen(args: BookAgainArgs(bookingId: 'booking-1')),
        overrides: h.overrides(),
      );
      expect(find.text('This service is no longer offered'), findsOneWidget);

      h.api.offline('GET', '/v1/bookings/booking-2/book-again');
      await pumpScreen(
        tester,
        const BookAgainScreen(args: BookAgainArgs(bookingId: 'booking-2')),
        overrides: h.overrides(),
      );
      expect(find.text('Couldn’t load this'), findsOneWidget);
    });
  });

  group('Saved preferences', () {
    Map<String, dynamic> prefs({bool empty = false}) => {
      'addresses': empty
          ? <Object>[]
          : [
              {
                'id': 'address-1',
                'label': 'Home',
                'islandId': 'island-1',
                'islandDisplayName': 'Dh. Meedhoo',
                'addressLine': 'M. Fehivina, 3rd floor',
                'createdAt': '2026-09-15T03:00:00.000Z',
              },
            ],
      'timeWindows': empty
          ? <Object>[]
          : [
              {
                'id': 'window-1',
                'weekdays': [7, 1, 2, 3, 4],
                'startTime': '09:00',
                'endTime': '12:00',
                'label': 'Weekdays · 9:00–12:00',
                'createdAt': '2026-09-15T03:00:00.000Z',
              },
            ],
      'standingInstructions': empty ? null : 'Gate code 4471.',
    };

    testWidgets('populated: three sections, the server’s labels', (
      tester,
    ) async {
      h.api.on('GET', '/v1/users/me/saved-preferences', (_) => prefs());
      await pumpScreen(
        tester,
        const SavedPreferencesScreen(),
        overrides: h.overrides(),
      );
      expect(find.text('Home'), findsOneWidget);
      // §0.0 item 12: the ambiguous name arrives qualified, from the server.
      expect(find.text('Dh. Meedhoo'), findsOneWidget);
      expect(find.text('Weekdays · 9:00–12:00'), findsOneWidget);
      expect(find.text('Gate code 4471.'), findsOneWidget);
      expect(
        find.text('Shared with the provider on every booking.'),
        findsOneWidget,
      );
      expectNoSwallowedControls(tester);
    });

    testWidgets('empty: names what to do next', (tester) async {
      h.api.on(
        'GET',
        '/v1/users/me/saved-preferences',
        (_) => prefs(empty: true),
      );
      await pumpScreen(
        tester,
        const SavedPreferencesScreen(),
        overrides: h.overrides(),
      );
      expect(find.text('Nothing saved yet'), findsOneWidget);
      expect(find.text('Add an address'), findsOneWidget);
    });

    testWidgets('error: a retry, and nothing lost', (tester) async {
      h.api.offline('GET', '/v1/users/me/saved-preferences');
      await pumpScreen(
        tester,
        const SavedPreferencesScreen(),
        overrides: h.overrides(),
      );
      expect(find.text('Couldn’t load preferences'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the add sheet opens on no island, and Save waits for one', (
      tester,
    ) async {
      h.api.on(
        'GET',
        '/v1/users/me/saved-preferences',
        (_) => prefs(empty: true),
      );
      await pumpScreen(
        tester,
        const SavedPreferencesScreen(),
        overrides: h.overrides(),
      );
      await tester.tap(find.text('Add an address'));
      await settle(tester);
      // Never defaulted to Malé (§0.0 item 12, §Phase 7).
      expect(find.text('Choose an island'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Home');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Fehivina, 3rd floor',
      );
      await settle(tester);
      final save = find.widgetWithText(InkWell, 'Save address');
      expect(
        save.evaluate().isEmpty || tester.widget<InkWell>(save).onTap == null,
        isTrue,
      );
      expect(h.api.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  });

  testWidgets('no screen here renders a phone number', (tester) async {
    h.api.on(
      'GET',
      '/v1/bookings/booking-1/book-again',
      (_) => bookAgainJson(),
    );
    await pumpScreen(
      tester,
      const BookAgainScreen(args: BookAgainArgs(bookingId: 'booking-1')),
      overrides: h.overrides(),
    );
    // The signed-in user's own number is in the harness; nothing here shows it.
    expect(find.textContaining('7771234'), findsNothing);
    expect(find.textContaining('+960'), findsNothing);
  });
}
