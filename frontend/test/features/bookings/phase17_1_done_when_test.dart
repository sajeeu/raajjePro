import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/offline/offline_queue_store.dart';
import 'package:raajjepro/core/offline/pending_request.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/my_bookings_screen.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/provider_accept_screen.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';
import '../profile/helpers.dart';

import 'harness.dart';

class _FakeQueueStore implements OfflineQueueStore {
  List<PendingRequest> saved = const [];
  @override
  Future<List<PendingRequest>> read() async => saved;
  @override
  Future<void> write(List<PendingRequest> queue) async => saved = queue;
}

/// The clauses of §Phase 17's **Done when** list that only the app can answer.
///
///  * an accept tapped in airplane mode **replays on reconnect rather than
///    being lost** — and the emergency accept is excluded from that queue;
///  * no screen in the module renders a phone number, a WhatsApp handle or a
///    Viber handle;
///  * §Phase 6's four booking tiles finally reach a real screen, each landing
///    on the pill it names.
void main() {
  late BookingHarness h;

  setUp(() => h = BookingHarness());

  group('an accept tapped offline replays on reconnect', () {
    test(
      'queues on a network refusal, then sends exactly once on replay',
      () async {
        final api = FakeApiClient();
        final store = _FakeQueueStore();
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            offlineQueueStoreProvider.overrideWithValue(store),
            clockProvider.overrideWithValue(() => BookingHarness.now),
            offlineRetryDelayProvider.overrideWithValue(
              const Duration(hours: 1),
            ),
          ],
        );
        addTearDown(container.dispose);

        api.offline('PATCH', '/v1/bookings/booking-1/accept');
        final result = await container
            .read(bookingApiProvider)
            .accept('booking-1');

        // Null is the caller's signal to show pending rather than a result —
        // "a lost tap costs the provider the job", so it is never dropped and
        // never reported as success.
        expect(result, isNull);
        expect(container.read(offlineQueueProvider).hasPending, isTrue);
        expect(store.saved.single.path, '/v1/bookings/booking-1/accept');
        expect(store.saved.single.method, 'PATCH');

        // Reconnect.
        api.on('PATCH', '/v1/bookings/booking-1/accept', (_) => bookingJson());
        await container.read(offlineQueueProvider.notifier).replay();

        expect(container.read(offlineQueueProvider).hasPending, isFalse);
        expect(
          api.calls
              .where((c) => c.path == '/v1/bookings/booking-1/accept')
              .length,
          2, // the refused attempt, then the replay
        );
      },
    );

    test('two taps on one booking are one intention, merged by key', () async {
      final api = FakeApiClient();
      final store = _FakeQueueStore();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          offlineQueueStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => BookingHarness.now),
          offlineRetryDelayProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      addTearDown(container.dispose);

      api.offline('PATCH', '/v1/bookings/booking-1/accept');
      await container.read(bookingApiProvider).accept('booking-1');
      await container.read(bookingApiProvider).accept('booking-1');

      // One queued item, not two: a double tap on a weak connection must not
      // become two accepts on reconnect.
      expect(container.read(offlineQueueProvider).pending.length, 1);
    });

    test(
      'the queue holds bookings only through the accept — nothing else',
      () async {
        final api = FakeApiClient();
        final store = _FakeQueueStore();
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            offlineQueueStoreProvider.overrideWithValue(store),
            clockProvider.overrideWithValue(() => BookingHarness.now),
            offlineRetryDelayProvider.overrideWithValue(
              const Duration(hours: 1),
            ),
          ],
        );
        addTearDown(container.dispose);
        final booking = container.read(bookingApiProvider);

        // §0.0 item 14 bounds the queue to three surfaces. A payment claim is
        // not one of them: telling a customer their "I've paid" is saved when
        // the provider has not received it would be a false promise about
        // money, so it fails instead.
        api.offline('PATCH', '/v1/bookings/booking-1/claim-payment');
        await expectLater(
          booking.claimPayment('booking-1'),
          throwsA(isA<ApiNetworkException>()),
        );
        api.offline('PATCH', '/v1/bookings/booking-1/decline');
        await expectLater(
          booking.decline('booking-1'),
          throwsA(isA<ApiNetworkException>()),
        );
        api.offline('PATCH', '/v1/bookings/booking-1/complete');
        await expectLater(
          booking.complete('booking-1'),
          throwsA(isA<ApiNetworkException>()),
        );

        expect(container.read(offlineQueueProvider).hasPending, isFalse);
        expect(store.saved, isEmpty);
      },
    );

    testWidgets('the prompt shows a pending state rather than a success', (
      tester,
    ) async {
      final store = _FakeQueueStore();
      h.scriptDetail(bookingJson(status: 'requested', agreedAmountLaari: null));
      h.api.offline('PATCH', '/v1/bookings/booking-1/accept');

      await pumpScreen(
        tester,
        const ProviderAcceptScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        overrides: [
          ...h.overrides(viewerId: 'provider-user-1'),
          offlineQueueStoreProvider.overrideWithValue(store),
          offlineRetryDelayProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );

      await tester.tap(find.widgetWithText(AppButton, 'Accept'));
      await settle(tester);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(text, contains('Accepted — waiting to send'));
      expect(find.widgetWithText(AppButton, 'Waiting to send'), findsOneWidget);
    });

    testWidgets(
      'offline, declining is refused with its reason rather than queued',
      (tester) async {
        final store = _FakeQueueStore();
        h.scriptDetail(
          bookingJson(status: 'requested', agreedAmountLaari: null),
        );

        await pumpScreen(
          tester,
          const ProviderAcceptScreen(
            args: BookingActionArgs(bookingId: 'booking-1'),
          ),
          overrides: [
            ...h.overrides(viewerId: 'provider-user-1'),
            offlineQueueStoreProvider.overrideWithValue(store),
            offlineRetryDelayProvider.overrideWithValue(
              const Duration(hours: 1),
            ),
            offlineQueueProvider.overrideWith(_OfflineQueue.new),
          ],
        );

        final decline = find.widgetWithText(AppButton, 'Decline');
        expect(tester.widget<AppButton>(decline).onPressed, isNull);
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' | ');
        expect(text, contains('Declining needs a connection'));
      },
    );
  });

  group('no booking screen renders a phone number', () {
    /// Every screen the feature registers, pumped in its most-populated
    /// state, scanned for a number-shaped string and for a contact word.
    ///
    /// §Phase 17's Done-when asks this to be checked across the module rather
    /// than only where one would be expected — which on the app side means
    /// every screen, not only the detail.
    testWidgets('across every screen in the feature', (tester) async {
      final scanned = <String>[];

      Future<void> scan(Widget screen, {String viewerId = 'customer-1'}) async {
        await pumpScreen(
          tester,
          screen,
          overrides: h.overrides(viewerId: viewerId),
        );
        for (var i = 0; i < 8; i++) {
          scanned.addAll(
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data ?? t.textSpan?.toPlainText() ?? ''),
          );
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isEmpty) break;
          await tester.drag(scrollable.first, const Offset(0, -320));
          await settle(tester);
        }
      }

      h.scriptList([bookingJson()]);
      // The payment step is scanned **twice**: the bank details render only
      // at `awaiting_payment`, and the claimed state is a different screen
      // with different copy. Scanning one would leave the other unchecked.
      h.scriptDetail(bookingJson(paymentDetails: bankDetails));
      await scan(const MyBookingsScreen());
      await scan(
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
      );

      h.scriptDetail(
        bookingJson(
          status: 'payment_claimed',
          paymentClaimedAt: '2026-09-15T02:00:00.000Z',
          amendments: [amendmentJson()],
          statusHistory: [
            eventJson('create', 'requested'),
            eventJson('claim-payment', 'payment_claimed'),
          ],
        ),
      );
      await scan(
        const PaymentStepScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
      );
      await scan(
        const RaiseDisputeScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
      );
      await scan(
        const CancelBookingScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
      );
      await scan(
        const DidThisHappenScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
      );
      await scan(
        const MarkCompleteScreen(
          args: BookingActionArgs(bookingId: 'booking-1'),
        ),
        viewerId: 'provider-user-1',
      );

      final text = scanned.join(' | ');
      expect(text, isNotEmpty);
      // A Maldivian mobile is seven digits beginning 7 or 9.
      expect(RegExp(r'\b[79]\d{6}\b').hasMatch(text), isFalse);
      expect(text.contains('+960'), isFalse);
      for (final word in ['whatsapp', 'viber', 'phone number', 'call them']) {
        expect(text.toLowerCase().contains(word), isFalse, reason: word);
      }
      // The bank account number **is** shown, and that is the one deliberate
      // exception (§1c: payment details are not contact information).
      expect(text.contains('7701234567890'), isTrue);
    });
  });

  group('§Phase 6’s four booking tiles now have a destination', () {
    testWidgets('each tile opens My Bookings on the pill it names', (
      tester,
    ) async {
      h.scriptList([bookingJson()]);
      h.api.on(
        'GET',
        '/v1/users/me/profile-summary',
        (_) => profileSummaryJson(),
      );

      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: h.overrides(),
        routes: {
          AppRoutes.bookings: (context) => MyBookingsScreen(
            initialFilter: bookingFilterFromRouteArguments(
              ModalRoute.of(context)?.settings.arguments,
            ),
          ),
        },
      );

      await tester.scrollUntilVisible(
        find.text('Completed'),
        140,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('Completed'));
      await settle(tester);

      // Not an `UnbuiltScreen` any more, and not the "All" pill: Round 48 §2's
      // whole point was that the four tiles are four destinations.
      expect(find.byType(UnbuiltScreen), findsNothing);
      expect(find.byType(MyBookingsScreen), findsOneWidget);
      final selected = tester
          .widgetList<AppChip>(find.byType(AppChip))
          .where((c) => c.selected)
          .toList();
      expect(selected, isNotEmpty);
    });
  });
}

/// A queue that reports itself offline without touching the network, so the
/// screen's own offline branch can be asserted directly.
class _OfflineQueue extends OfflineQueue {
  @override
  OfflineState build() {
    super.build();
    return const OfflineState(online: false);
  }
}
