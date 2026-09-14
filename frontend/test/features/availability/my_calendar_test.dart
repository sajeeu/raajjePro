import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/features/availability/presentation/my_calendar_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// `My Calendar.dc.html` — commitments across every service, and time away.
void main() {
  const path = '/v1/providers/me/calendar';

  Map<String, dynamic> calendar({
    List<Map<String, dynamic>> commitments = const [],
    List<Map<String, dynamic>> timeOff = const [],
  }) => {'commitments': commitments, 'timeOff': timeOff};

  Future<void> pump(WidgetTester tester, FakeApiClient api) => pumpScreen(
    tester,
    const MyCalendarScreen(),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  testWidgets(
    'with nothing booked, says so and offers the one thing to set up',
    (tester) async {
      // The state a provider actually sees until §Phase 17.1 lands, and it is
      // the truthful one: nothing is booked because nothing can be yet.
      await pump(tester, FakeApiClient()..on('GET', path, (_) => calendar()));

      expect(find.text('Nothing booked yet'), findsOneWidget);
      expect(
        find.textContaining('appears here automatically. Nothing to set up'),
        findsOneWidget,
      );
      expect(find.text('Add time away'), findsWidgets);
    },
  );

  testWidgets(
    'lists a commitment in Maldives time, grouped by its Maldives day',
    (tester) async {
      await pump(
        tester,
        FakeApiClient()..on(
          'GET',
          path,
          (_) => calendar(
            commitments: [
              {
                'id': 'r1',
                'listingId': 'l1',
                // 21:00 Malé on 15 September — 16:00Z the same day. Grouping
                // by UTC date would file it correctly by luck; the next one
                // would not.
                'startsAt': '2026-09-15T16:00:00.000Z',
                'endsAt': '2026-09-15T18:00:00.000Z',
                'kind': 'firm',
              },
            ],
          ),
        ),
      );

      expect(find.text('21:00'), findsWidgets);
      expect(find.text('21:00–23:00'), findsOneWidget);
    },
  );

  testWidgets(
    'marks a quote’s hold as awaiting a reply rather than as booked',
    (tester) async {
      await pump(
        tester,
        FakeApiClient()..on(
          'GET',
          path,
          (_) => calendar(
            commitments: [
              {
                'id': 'r2',
                'listingId': 'l1',
                'startsAt': '2026-09-15T04:00:00.000Z',
                'endsAt': '2026-09-15T06:00:00.000Z',
                'kind': 'provisional',
              },
            ],
          ),
        ),
      );

      // A provisional hold is the provider's time, but it is not an
      // appointment — saying "booked" would be the difference between planning
      // a day and being surprised by it.
      expect(find.text('Awaiting reply'), findsOneWidget);
    },
  );

  testWidgets('lists time away and states exactly what it does', (
    tester,
  ) async {
    await pump(
      tester,
      FakeApiClient()..on(
        'GET',
        path,
        (_) => calendar(
          timeOff: [
            {
              'id': 't1',
              'name': 'Trip to Colombo',
              'startDate': '2026-09-20',
              'endDate': '2026-09-24',
            },
          ],
        ),
      ),
    );

    expect(find.text('Trip to Colombo'), findsOneWidget);
    expect(find.text('20 Sep – 24 Sep'), findsOneWidget);
    // The honest scope: it removes published slots, and it does not stop a
    // request coming in for those dates.
    expect(
      find.textContaining('Customers can still send requests for these dates'),
      findsOneWidget,
    );
  });

  testWidgets('renders its own error with a working retry', (tester) async {
    final api = FakeApiClient()..offline('GET', path);
    await pump(tester, api);
    expect(find.text('Couldn’t load your calendar'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);

    api.on('GET', path, (_) => calendar());
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Nothing booked yet'), findsOneWidget);
  });
}
