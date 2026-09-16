import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';

/// Which side of a booking the caller is asking as. The server treats this as
/// the scope, not a hint — there is no shape of the request that reaches
/// somebody else's bookings.
enum BookingRole {
  customer,
  provider;

  String get wire => name;
}

/// Typed calls onto §Phase 17.1's endpoints.
///
/// ## What is queued, and what is not
///
/// **Exactly one call here queues: [accept].** §Phase 17's frontend item 12
/// asks for the slot/request accept prompt to queue and replay, "since a lost
/// tap costs the provider the job", and §0.0 item 14 bounds the queue to three
/// surfaces of which this is one. Everything else sends or fails: a customer
/// tapping "I've Paid" offline must not be told their provider has been
/// notified, because the provider is the one who acts on it next.
///
/// §Phase 17.3's emergency accept is **excluded** from the queue by name
/// (§0.0 item 14) — a replayed offer would commit a provider to a price and an
/// arrival promise calculated somewhere else, at some other time, and §1f
/// would measure them against it.
///
/// ## No response here carries a phone number
///
/// Structurally: [Booking] has no field that could hold one, and §1c allows
/// exactly one endpoint in the system to return one — §Phase 17.3's
/// `reveal-contact`, which is not among the calls below.
class BookingApi {
  const BookingApi(this._api, this._queue);

  final ApiClient _api;
  final OfflineQueue _queue;

  static const _bookings = '/v1/bookings';

  /// Page bound for [list], the same as `ListingApi.listOwn`'s and for the
  /// same reason: a server handing back the same cursor forever would hang the
  /// Bookings tab on its skeleton with no error to show.
  static const int _maxPages = 20;

  /// §Phase 17.1's slot creation. The idempotency key is required by the
  /// server, not optional politeness — a double tap on a weak atoll connection
  /// must not take two slots.
  ///
  /// Not queued: there is nothing honest to show for a booking that has not
  /// reached the provider, and the slot it is for may be gone by the time a
  /// reconnect happens.
  Future<Booking> createSlotBooking({
    required String listingId,
    required String timeSlotId,
    String? jobNotes,
    String? islandId,
    String? addressDetail,
  }) async {
    final response = await _api.post(
      '/v1/listings/$listingId/bookings',
      body: {
        'timeSlotId': timeSlotId,
        'jobNotes': ?_blankToNull(jobNotes),
        'islandId': ?islandId,
        'addressDetail': ?_blankToNull(addressDetail),
      },
      headers: {'idempotency-key': _queue.newIdempotencyKey('booking.create')},
    );
    return Booking.fromJson(response);
  }

  /// One booking, with its status timeline and — where the caller is the
  /// customer and the booking is at the payment step — the provider's bank
  /// details.
  Future<Booking> read(String bookingId) async =>
      Booking.fromJson(await _api.get('$_bookings/$bookingId'));

  /// The caller's own bookings on one side, paged to the end.
  ///
  /// The status filter the endpoint offers is deliberately **not** used: the
  /// Bookings tab's pills switch instantly over what is already loaded, the
  /// way §Phase 10's dashboard does, so the count above the list can never
  /// disagree with the list under it.
  Future<List<Booking>> list(BookingRole role) async {
    final all = <Booking>[];
    String? cursor;
    for (var page = 0; page < _maxPages; page += 1) {
      final query = StringBuffer('?role=${role.wire}&limit=50');
      if (cursor != null) query.write('&cursor=${Uri.encodeComponent(cursor)}');
      final response = await _api.get('/v1/users/me/bookings$query');
      // `ApiClient` unwraps the envelope: a list payload arrives as `_list`
      // and the envelope's `meta` as `_meta` (`ListingApi.listOwn` records
      // the same thing). Reading `data` here produced an empty list against a
      // perfectly good response, which is what the screen test caught.
      all.addAll(
        ((response['_list'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Booking.fromJson),
      );
      final meta = response['_meta'];
      cursor = meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null;
      if (cursor == null) break;
    }
    return all;
  }

  /// §1c step 2's accept, **queued and replayed** (§Phase 17 frontend item 12).
  ///
  /// Returns null when the network refused and the tap was queued — the
  /// caller's signal to show a pending state rather than a result. The server
  /// carries the booking's status in its own `WHERE`, so a replay that lands
  /// after the window closed changes nothing and says so.
  Future<Booking?> accept(String bookingId) async {
    final response = await _queue.submit(
      _queue.request(
        method: 'PATCH',
        path: '$_bookings/$bookingId/accept',
        label: 'Accepting a booking',
        // One intention per booking. A second tap on the same booking is the
        // same tap, not a second acceptance.
        mergeKey: 'booking.accept:$bookingId',
      ),
    );
    return response == null ? null : Booking.fromJson(response);
  }

  Future<Booking> decline(String bookingId, {String? reason}) =>
      _patch(bookingId, 'decline', {'reason': ?_blankToNull(reason)});

  /// §1c step 7. Self-attestation — no proof, and nothing checks it.
  Future<Booking> claimPayment(String bookingId) =>
      _patch(bookingId, 'claim-payment', null);

  /// Round 24. Allowed once, and only while the provider has not answered.
  Future<Booking> withdrawPaymentClaim(String bookingId) =>
      _patch(bookingId, 'withdraw-payment-claim', null);

  /// §1c step 8. "Provider confirmed receipt" — never "payment verified".
  Future<Booking> confirmPaymentReceived(String bookingId) =>
      _patch(bookingId, 'confirm-payment-received', null);

  Future<Booking> complete(String bookingId, {int? finalAmountLaari}) =>
      _patch(bookingId, 'complete', {'finalAmountLaari': ?finalAmountLaari});

  /// §1c step 10's prompt, answered. "No" files a report and disputes.
  Future<Booking> answerCompletionPrompt(
    String bookingId, {
    required bool happened,
  }) => _patch(bookingId, 'completion-answer', {'happened': happened});

  Future<Booking> cancel(String bookingId, {String? reason}) =>
      _patch(bookingId, 'cancel', {'reason': ?_blankToNull(reason)});

  /// Either party. The reason is one of §Phase 22's four booking reasons.
  Future<Booking> dispute(
    String bookingId, {
    required String reason,
    String? note,
  }) => _patch(bookingId, 'dispute', {
    'reason': reason,
    'note': ?_blankToNull(note),
  });

  /// §1h. Proposing is itself the record — the row is written whether or not
  /// the other party ever accepts.
  Future<Booking> proposeAmendment(
    String bookingId, {
    int? amountLaari,
    DateTime? scheduledFor,
    String? scopeNote,
    String? reason,
  }) async {
    final response = await _api.post(
      '$_bookings/$bookingId/amendments',
      body: {
        'amountLaari': ?amountLaari,
        'scheduledFor': ?scheduledFor?.toUtc().toIso8601String(),
        'scopeNote': ?_blankToNull(scopeNote),
        'reason': ?_blankToNull(reason),
      },
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('booking.amendment.create'),
      },
    );
    return Booking.fromJson(response);
  }

  /// Only the **counterparty** may answer — the server enforces it, and the
  /// UI never offers the control to the proposer.
  Future<Booking> respondToAmendment(
    String bookingId,
    String amendmentId, {
    required bool accept,
  }) async => Booking.fromJson(
    await _api.patch(
      '$_bookings/$bookingId/amendments/$amendmentId',
      body: {'accept': accept},
    ),
  );

  Future<Booking> withdrawAmendment(
    String bookingId,
    String amendmentId,
  ) async => Booking.fromJson(
    await _api.delete('$_bookings/$bookingId/amendments/$amendmentId'),
  );

  Future<Booking> _patch(
    String bookingId,
    String action,
    Map<String, dynamic>? body,
  ) async => Booking.fromJson(
    await _api.patch('$_bookings/$bookingId/$action', body: body ?? const {}),
  );

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final bookingApiProvider = Provider<BookingApi>(
  (ref) => BookingApi(
    ref.watch(apiClientProvider),
    ref.watch(offlineQueueProvider.notifier),
  ),
);
