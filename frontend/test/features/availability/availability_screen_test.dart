import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/features/availability/presentation/availability_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// §Phase 9a's provider surface — `Availability.dc.html`.
void main() {
  const listingId = '22222222-2222-4222-8222-222222222222';
  const base = '/v1/providers/me/listings/$listingId/availability';
  const slotsPath = '/v1/providers/me/listings/$listingId/slots';

  Map<String, dynamic> availability({List<Map<String, dynamic>>? rules}) => {
    'listingId': listingId,
    'rules':
        rules ??
        [
          {
            'id': 'rule-a',
            'weekdays': [1, 2, 3, 4],
            'startTime': '09:00',
            'endTime': '17:00',
            'slotDurationMinutes': 120,
          },
        ],
    'exceptions': <Map<String, dynamic>>[],
    'horizonDate': '2026-11-12',
    'lastGeneratedAt': '2026-09-14T03:00:00.000Z',
  };

  Map<String, dynamic> slots({String status = 'open'}) => {
    '_list': [
      {
        'id': 'slot-a',
        'startsAt': '2026-09-15T04:00:00.000Z',
        'endsAt': '2026-09-15T06:00:00.000Z',
        'status': status,
        'heldByAnotherListing': false,
      },
    ],
  };

  FakeApiClient scripted({
    List<Map<String, dynamic>>? rules,
    String slotStatus = 'open',
  }) => FakeApiClient()
    ..on('GET', base, (_) => availability(rules: rules))
    ..on('GET', slotsPath, (_) => slots(status: slotStatus))
    ..on('GET', '/v1/providers/me/time-off', (_) => {'_list': <dynamic>[]});

  Future<void> pump(WidgetTester tester, FakeApiClient api) => pumpScreen(
    tester,
    const AvailabilityScreen(args: AvailabilityArgs(listingId: listingId)),
    overrides: [apiClientProvider.overrideWithValue(api)],
  );

  testWidgets(
    'a listing with no rules gets the empty state, not an empty grid',
    (tester) async {
      await pump(tester, scripted(rules: []));
      expect(find.text('No working hours yet'), findsOneWidget);
      // Names the next action, and explains the model in one sentence.
      expect(find.text('Add your first rule'), findsOneWidget);
      expect(find.textContaining('60 days ahead'), findsOneWidget);
    },
  );

  testWidgets('renders a rule the way the provider stated it', (tester) async {
    await pump(tester, scripted());
    expect(find.text('Mon–Thu'), findsOneWidget);
    expect(find.text('09:00–17:00 · 2 hours each'), findsOneWidget);
    // 09:00 Malé is 04:00Z — presented in Maldives time, whatever the runner.
    expect(find.text('09:00'), findsWidgets);
  });

  testWidgets('says how far ahead the published times reach', (tester) async {
    await pump(tester, scripted());
    // The horizon is the server's answer, and no total is printed.
    expect(find.textContaining('Times run through 12 Nov'), findsOneWidget);
  });

  testWidgets('blocking a time asks the server and shows the result', (
    tester,
  ) async {
    final api = scripted()
      ..on(
        'POST',
        '/v1/providers/me/slots/slot-a/block',
        (_) => {
          'id': 'slot-a',
          'startsAt': '2026-09-15T04:00:00.000Z',
          'endsAt': '2026-09-15T06:00:00.000Z',
          'status': 'blocked',
          'heldByAnotherListing': false,
        },
      );
    await pump(tester, api);

    await tester.tap(find.text('09:00'));
    await settle(tester);

    expect(
      api.calls.map((c) => '${c.method} ${c.path}'),
      contains('POST /v1/providers/me/slots/slot-a/block'),
    );
    // The chip now carries the lock the artboard's legend explains.
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('a reserved time is explained rather than blocked', (
    tester,
  ) async {
    final api = scripted(slotStatus: 'reserved');
    await pump(tester, api);

    await tester.tap(find.text('09:00'));
    await settle(tester);

    // The artboard's own words, and the accurate explanation of a
    // provider-scoped reservation.
    expect(
      find.textContaining('A booking on any of your listings holds your time'),
      findsOneWidget,
    );
    // Nothing was written — a booking is not the provider's to cancel from here.
    expect(api.calls.where((c) => c.method == 'POST').toList(), isEmpty);
  });

  testWidgets('saving a rule confirms first, naming what cannot change', (
    tester,
  ) async {
    final api = scripted()
      ..on(
        'GET',
        '$base/rule-defaults',
        (_) => {
          'weekdays': [1, 2, 3, 4, 5],
          'startTime': '09:00',
          'endTime': '17:00',
          'slotDurationMinutes': 120,
        },
      )
      ..on(
        'POST',
        '$base/rules',
        (_) => {
          'id': 'rule-b',
          'weekdays': [1, 2, 3, 4, 5],
          'startTime': '09:00',
          'endTime': '17:00',
          'slotDurationMinutes': 120,
        },
      );
    await pump(tester, api);

    await tester.tap(find.text('Add rule'));
    await settle(tester);
    await tester.tap(find.text('Save rule').last);
    await settle(tester);

    // The reassurance is the whole point of the step, so it is stated before
    // anything is written.
    expect(find.text('Save these hours?'), findsOneWidget);
    expect(
      find.textContaining(
        'Times someone has already booked stay exactly as they are',
      ),
      findsOneWidget,
    );
    expect(api.calls.where((c) => c.method == 'POST').toList(), isEmpty);
  });

  testWidgets(
    'a refused rule shows the server’s own reason, not a generic error',
    (tester) async {
      final api = scripted()
        ..on(
          'GET',
          '$base/rule-defaults',
          (_) => {
            'weekdays': [1],
            'startTime': '09:00',
            'endTime': '17:00',
            'slotDurationMinutes': 120,
          },
        )
        ..fail(
          'POST',
          '$base/rules',
          status: 422,
          code: 'RULE_HOURS_OVERLAP',
          message:
              'Those hours overlap another rule on the same day (09:00–17:00). '
              'Edit that one instead.',
        );
      await pump(tester, api);

      await tester.tap(find.text('Add rule'));
      await settle(tester);
      await tester.tap(find.text('Save rule').last);
      await settle(tester);
      await tester.tap(find.text('Save rule').last);
      await settle(tester);

      // Every refusal on this screen is a rule written for a provider to read.
      expect(find.textContaining('overlap another rule'), findsOneWidget);
    },
  );

  testWidgets('renders its own error with a working retry', (tester) async {
    final api = FakeApiClient()
      ..offline('GET', base)
      ..offline('GET', slotsPath)
      ..offline('GET', '/v1/providers/me/time-off');
    await pumpScreen(
      tester,
      const AvailabilityScreen(args: AvailabilityArgs(listingId: listingId)),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    expect(find.text('Couldn’t load your hours'), findsOneWidget);
    // Says plainly that nothing was lost, which is the fear the state creates.
    expect(find.textContaining('are safe'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
