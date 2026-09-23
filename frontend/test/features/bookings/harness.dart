import 'package:flutter_riverpod/misc.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';

import '../../helpers/fake_api.dart';

/// A signed-in user who never refetches — the shape every account test uses.
class FixedAuthController extends AuthController {
  FixedAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

/// Everything a booking test drives: one scripted booking, its list, and the
/// actions every screen calls.
class BookingHarness {
  BookingHarness() : api = FakeApiClient();

  final FakeApiClient api;

  /// A fixed clock. 2026-09-15, 08:00 Malé — the same anchor the billing
  /// harness uses, so the two suites read the same dates.
  static final DateTime now = DateTime.utc(2026, 9, 15, 3);

  /// [viewerId] is which side of the booking is reading it: the fixtures make
  /// `customer-1` the customer and `provider-user-1` the provider, and the
  /// detail screen branches on exactly that.
  List<Override> overrides({
    bool emailVerified = true,
    String viewerId = 'customer-1',
  }) => [
    apiClientProvider.overrideWithValue(api),
    clockProvider.overrideWithValue(() => now),
    authControllerProvider.overrideWith(
      () => FixedAuthController(
        AuthSignedIn(
          UserAccount.fromJson({
            'id': viewerId,
            'fullName': viewerId == 'customer-1'
                ? 'Aishath Naeema'
                : 'Mariyam Shifa',
            'email': 'someone@example.test',
            'emailVerified': emailVerified,
            'phone': {'dialCode': '+960', 'number': '7771234'},
            'status': 'active',
            'deletionDeadlineAt': null,
            'isProvider': viewerId != 'customer-1',
            'createdAt': '2026-09-06T10:00:00.000Z',
          }),
        ),
      ),
    ),
  ];

  void scriptDetail(Map<String, dynamic> booking) {
    api.on('GET', '/v1/bookings/${booking['id'] as String}', (_) => booking);
  }

  void scriptList(
    List<Map<String, dynamic>> bookings, {
    String role = 'customer',
  }) {
    api.on(
      'GET',
      '/v1/users/me/bookings?role=$role&limit=50',
      (_) => {'_list': bookings, '_meta': <String, dynamic>{}},
    );
  }
}

/// A booking, with every field the app reads and sensible defaults.
///
/// Written as the **server's wire shape** rather than as a model, because
/// that is what the screens actually parse — a fixture built from the Dart
/// class would not catch a field the API renamed.
Map<String, dynamic> bookingJson({
  String id = 'booking-1',
  String status = 'awaiting_payment',
  String bookingMode = 'slot',
  int? agreedAmountLaari = 45000,
  String? amountKind = 'fixed_price',
  int? quotedAmountLaari = 45000,
  int? finalAmountLaari,
  String? scheduledFor = '2026-09-25T09:00:00.000Z',
  String? paymentClaimedAt,
  String? paymentClaimWithdrawnAt,
  String? completionPromptedAt,
  String? cancelledByRole,
  String? occasion,
  String? preferredWindowText,
  String? quoteDueAt,
  String? quoteOfferedAt,
  String? quoteExpiresAt,
  String? quoteNote,
  String chatState = 'not_open',
  List<Map<String, dynamic>> amendments = const [],
  List<Map<String, dynamic>> statusHistory = const [],
  Map<String, dynamic>? paymentDetails,
  Map<String, dynamic>? replacement,
  String customerId = 'customer-1',
  String providerUserId = 'provider-user-1',
}) => {
  'id': id,
  'reference': 'RP-7K4M2QXB',
  'listingId': 'listing-1',
  'listingName': 'Home Deep Cleaning',
  'categoryName': 'Cleaning',
  'bookingMode': bookingMode,
  'status': status,
  'customer': {'userId': customerId, 'name': 'Aishath Naeema'},
  'provider': {'userId': providerUserId, 'name': 'Mariyam Shifa'},
  'agreedAmountLaari': agreedAmountLaari,
  'amountKind': amountKind,
  'quotedAmountLaari': quotedAmountLaari,
  'finalAmountLaari': finalAmountLaari,
  'scheduledFor': scheduledFor,
  'timeSlotId': 'slot-1',
  'durationMinutes': 120,
  'preferredWindowText': preferredWindowText,
  'preferredWindowFrom': null,
  'preferredWindowTo': null,
  'quoteDueAt': quoteDueAt,
  'quoteOfferedAt': quoteOfferedAt,
  'quoteExpiresAt': quoteExpiresAt,
  'quoteNote': quoteNote,
  'chatState': chatState,
  'occasion': occasion,
  'jobNotes': 'Two bedrooms and kitchen — keys with the caretaker',
  'islandId': 'island-1',
  'islandDisplayName': 'Malé',
  'addressDetail': 'H. Faiha, 2nd floor',
  'paymentClaimedAt': paymentClaimedAt,
  'paymentClaimWithdrawnAt': paymentClaimWithdrawnAt,
  'paymentAttestedAt': null,
  'completedAt': null,
  'completedVia': null,
  'completionPromptedAt': completionPromptedAt,
  'cancelledAt': cancelledByRole == null ? null : '2026-09-14T06:00:00.000Z',
  'cancelledByRole': cancelledByRole,
  'cancellationReason': null,
  'disputedAt': null,
  'disputeOutcome': null,
  'createdAt': '2026-09-14T03:00:00.000Z',
  'amendments': amendments,
  'statusHistory': statusHistory,
  'paymentDetails': paymentDetails,
  'replacement': replacement,
};

Map<String, dynamic> amendmentJson({
  String id = 'amendment-1',
  String status = 'proposed',
  String proposedByRole = 'provider',
  int? previousAmountLaari = 45000,
  int? proposedAmountLaari = 60000,
  String? reason = 'Two extra rooms added on the day',
}) => {
  'id': id,
  'status': status,
  'proposedByRole': proposedByRole,
  'previousAmountLaari': previousAmountLaari,
  'previousScheduledFor': null,
  'previousScopeNote': null,
  'proposedAmountLaari': proposedAmountLaari,
  'proposedScheduledFor': null,
  'proposedScopeNote': null,
  'reason': reason,
  'createdAt': '2026-09-15T02:00:00.000Z',
  'respondedAt': null,
};

Map<String, dynamic> eventJson(
  String transition,
  String toStatus, {
  String actorRole = 'customer',
}) => {
  'id': 'event-$transition',
  'fromStatus': null,
  'toStatus': toStatus,
  'actorRole': actorRole,
  'transition': transition,
  'at': '2026-09-14T03:00:00.000Z',
};

/// A request booking with a live quote on it — the state both quote screens
/// start from.
///
/// The approval deadline is **four hours out**, which is Plumbing's
/// `quoteApprovalMinutes` as the server would have computed it. The app never
/// derives that number; the fixture states it here precisely because the
/// screen's whole job is to render a deadline it was given.
Map<String, dynamic> quotedBookingJson({
  String status = 'quote_offered',
  int? quotedAmountLaari = 65000,
  String? quoteExpiresAt = '2026-09-15T07:00:00.000Z',
  String chatState = 'open',
}) => bookingJson(
  status: status,
  bookingMode: 'request',
  agreedAmountLaari: status == 'quote_offered' ? null : quotedAmountLaari,
  amountKind: status == 'quote_offered' ? null : 'quoted',
  quotedAmountLaari: quotedAmountLaari,
  scheduledFor: '2026-09-25T09:00:00.000Z',
  preferredWindowText: 'Tomorrow morning',
  quoteOfferedAt: '2026-09-15T03:00:00.000Z',
  quoteExpiresAt: quoteExpiresAt,
  quoteNote: 'Replace joint, reseal line — parts included',
  chatState: chatState,
);

const bankDetails = {
  'bankName': 'Bank of Maldives',
  'accountName': 'Mariyam Shifa',
  'accountNumber': '7701234567890',
};
