import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/features/availability/presentation/slot_picker_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// §Phase 9a's customer picker.
///
/// The rule these all circle is §1c's: **no picker ever shows an unavailable
/// time**. That is enforced server-side, so what a widget test can prove is
/// the other half — that this screen renders exactly what it was given, adds
/// nothing of its own, and never invents a time from a rule or a clock.
void main() {
  const listingId = '11111111-1111-4111-8111-111111111111';
  const path = '/v1/listings/$listingId/slots';

  /// 09:00 and 13:00 Malé on Tuesday 15 September 2026, as the server sends them.
  Map<String, dynamic> slotsPayload({
    int leadMinutes = 180,
    List<Map<String, String>>? slots,
  }) => {
    'listingId': listingId,
    'minimumLeadTimeMinutes': leadMinutes,
    'bookableFrom': '2026-09-14T06:00:00.000Z',
    'slots':
        slots ??
        [
          {
            'id': 'slot-a',
            'startsAt': '2026-09-15T04:00:00.000Z',
            'endsAt': '2026-09-15T06:00:00.000Z',
          },
          {
            'id': 'slot-b',
            'startsAt': '2026-09-15T08:00:00.000Z',
            'endsAt': '2026-09-15T10:00:00.000Z',
          },
          {
            'id': 'slot-c',
            'startsAt': '2026-09-16T04:00:00.000Z',
            'endsAt': '2026-09-16T06:00:00.000Z',
          },
        ],
  };

  Future<FakeApiClient> pump(
    WidgetTester tester, {
    void Function(FakeApiClient api)? script,
    NavigatorObserver? observer,
  }) async {
    final api = FakeApiClient();
    script?.call(api);
    await pumpScreen(
      tester,
      const SlotPickerScreen(
        args: SlotPickerArgs(
          listingId: listingId,
          serviceName: 'Home Deep Cleaning',
        ),
      ),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    return api;
  }

  testWidgets('renders a skeleton while the times are loading', (tester) async {
    final gate = Completer<void>();
    final api = FakeApiClient()..gate = gate;
    api.on('GET', path, (_) => slotsPayload());
    await pumpScreen(
      tester,
      const SlotPickerScreen(args: SlotPickerArgs(listingId: listingId)),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    // A skeleton rather than a spinner or a blank screen (frontend/CLAUDE.md),
    // and no time is on screen before the server has said which are open.
    expect(find.byType(SkeletonLoader), findsOneWidget);
    expect(find.text('09:00'), findsNothing);

    gate.complete();
    await settle(tester);
    expect(find.byType(SkeletonLoader), findsNothing);
    expect(find.text('09:00'), findsOneWidget);
  });

  testWidgets('shows the times the server sent, and only those', (
    tester,
  ) async {
    await pump(
      tester,
      script: (api) => api.on('GET', path, (_) => slotsPayload()),
    );

    // 09:00 Malé is 04:00Z; 13:00 Malé is 08:00Z. The screen presents in
    // Maldives time without ever calling `toLocal()`, so these hold whatever
    // timezone the test runner is in.
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('13:00'), findsOneWidget);
    // The third slot belongs to the next day and is not on the selected one.
    expect(find.text('11:00'), findsNothing);
  });

  testWidgets('explains the missing early times in the category’s own number', (
    tester,
  ) async {
    await pump(
      tester,
      script: (api) =>
          api.on('GET', path, (_) => slotsPayload(leadMinutes: 120)),
    );
    // Read from the response, never a constant: Beauty seeds 120 where
    // Cleaning seeds 180, and §Phase 10b keeps both editable.
    expect(find.textContaining('2 hours'), findsOneWidget);
  });

  testWidgets(
    'offers nothing to tap when the provider has published no times',
    (tester) async {
      await pump(
        tester,
        script: (api) =>
            api.on('GET', path, (_) => slotsPayload(slots: const [])),
      );
      expect(find.text('No times published yet'), findsOneWidget);
      // An empty state names what to do next rather than reporting absence.
      expect(find.text('Back to the service'), findsOneWidget);
    },
  );

  testWidgets('renders its own error with a working retry', (tester) async {
    final api = await pump(tester, script: (api) => api.offline('GET', path));
    expect(find.text('Couldn’t load the open times'), findsOneWidget);

    api.on('GET', path, (_) => slotsPayload());
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('09:00'), findsOneWidget);
  });

  testWidgets('continues with the chosen slot and nothing else', (
    tester,
  ) async {
    final api = FakeApiClient()..on('GET', path, (_) => slotsPayload());
    PickedSlot? popped;

    await pumpScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<PickedSlot>(
              MaterialPageRoute(
                builder: (_) => const SlotPickerScreen(
                  args: SlotPickerArgs(listingId: listingId),
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    // Continue is inert until a time is chosen: there is nothing to continue
    // with, and a button that looks live and does nothing reads as broken.
    final continueButton = find.widgetWithText(AppButton, 'Continue');
    expect(tester.widget<AppButton>(continueButton).onPressed, isNull);

    await tester.tap(find.text('13:00'));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(popped, isNotNull);
    expect(popped!.slotId, 'slot-b');
    expect(popped!.startsAt, DateTime.parse('2026-09-15T08:00:00.000Z'));
    // The screen made exactly one call — it did not book anything. Creating a
    // booking is §Phase 17.1's, and this screen must not grow one.
    expect(api.calls.map((c) => '${c.method} ${c.path}'), ['GET $path']);
  });

  testWidgets(
    'switching day clears the chosen time rather than keeping a stale one',
    (tester) async {
      await pump(
        tester,
        script: (api) => api.on('GET', path, (_) => slotsPayload()),
      );
      await tester.tap(find.text('13:00'));
      await settle(tester);

      await tester.tap(find.text('16')); // the 16 September rail entry
      await settle(tester);

      final continueButton = find.widgetWithText(AppButton, 'Continue');
      expect(tester.widget<AppButton>(continueButton).onPressed, isNull);
    },
  );
}
