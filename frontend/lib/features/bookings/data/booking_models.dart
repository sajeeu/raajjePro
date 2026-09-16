import 'package:flutter/foundation.dart';

import 'package:raajjepro/shared/shared.dart';

/// §1c's status machine, as the app reads it.
///
/// **The wire values are the server's and are not re-derived here.** `unknown`
/// exists because the API contract is additive-only: a status a later slice
/// adds must render as *something* on an installed app rather than crash it.
enum BookingStatus {
  requested,
  awaitingQuote,
  quoteOffered,
  emergencyOffered,
  accepted,
  awaitingPayment,
  paymentClaimed,
  confirmed,
  completed,
  cancelled,
  declined,
  disputed,
  disputeResolved,
  paymentUnresolved,
  unknown;

  static BookingStatus parse(String? wire) => switch (wire) {
    'requested' => requested,
    'awaiting_quote' => awaitingQuote,
    'quote_offered' => quoteOffered,
    'emergency_offered' => emergencyOffered,
    'accepted' => accepted,
    'awaiting_payment' => awaitingPayment,
    'payment_claimed' => paymentClaimed,
    'confirmed' => confirmed,
    'completed' => completed,
    'cancelled' => cancelled,
    'declined' => declined,
    'disputed' => disputed,
    'dispute_resolved' => disputeResolved,
    'payment_unresolved' => paymentUnresolved,
    _ => unknown,
  };

  /// Nothing is waiting on this booking any more (§1c).
  ///
  /// `paymentUnresolved` and `disputed` are deliberately absent: both read
  /// like endings and an admin still owes somebody an answer on each.
  bool get isTerminal =>
      this == completed ||
      this == cancelled ||
      this == declined ||
      this == disputeResolved;

  /// The badge §Phase 1 already wrote the copy for. Mapping happens here,
  /// once — `StatusBadge` holds the words and no screen restates them.
  BadgeStatus get badge => switch (this) {
    requested || awaitingQuote => BadgeStatus.waitingProvider,
    quoteOffered => BadgeStatus.quoteReceived,
    emergencyOffered => BadgeStatus.waitingProvider,
    accepted || awaitingPayment => BadgeStatus.awaitingPayment,
    paymentClaimed => BadgeStatus.paymentSent,
    confirmed => BadgeStatus.receiptConfirmed,
    completed => BadgeStatus.completed,
    cancelled => BadgeStatus.cancelled,
    declined => BadgeStatus.declined,
    disputed || disputeResolved => BadgeStatus.disputed,
    paymentUnresolved => BadgeStatus.unresolved,
    unknown => BadgeStatus.waitingProvider,
  };
}

enum BookingKind {
  slot,
  request,
  emergency;

  static BookingKind parse(String? wire) => switch (wire) {
    'request' => request,
    'emergency' => emergency,
    _ => slot,
  };
}

enum BookingActorRole {
  customer,
  provider,
  admin,
  system;

  static BookingActorRole parse(String? wire) => switch (wire) {
    'provider' => provider,
    'admin' => admin,
    'system' => system,
    _ => customer,
  };
}

/// Round 17's table, and **the one place its customer-facing labels live**.
///
/// The derivation is the server's — the client never decides which kind an
/// amount is. What the client owns is the wording beside the number, and the
/// last one is not decoration: §1c requires honest framing, and "a customer
/// paying a callout fee must not believe they are paying for the job".
enum AmountKind {
  fixedPrice,
  hourlyTotal,
  dailyTotal,
  quoted,
  calloutFee,
  unknown;

  static AmountKind parse(String? wire) => switch (wire) {
    'fixed_price' => fixedPrice,
    'hourly_total' => hourlyTotal,
    'daily_total' => dailyTotal,
    'quoted' => quoted,
    'callout_fee' => calloutFee,
    _ => unknown,
  };

  String get label => switch (this) {
    fixedPrice => 'Agreed price',
    hourlyTotal => 'Agreed total',
    dailyTotal => 'Agreed total',
    quoted => 'Quoted price',
    calloutFee => 'Callout fee',
    unknown => 'Agreed amount',
  };

  /// The sentence that goes under the number, where the number needs one.
  String? get caution => this == calloutFee
      ? 'What this provider charges to attend. The final bill may differ.'
      : null;
}

enum BookingAmendmentStatus {
  proposed,
  accepted,
  rejected,
  withdrawn;

  static BookingAmendmentStatus parse(String? wire) => switch (wire) {
    'accepted' => accepted,
    'rejected' => rejected,
    'withdrawn' => withdrawn,
    _ => proposed,
  };
}

/// One row of §Phase 17's "status timeline showing when each transition
/// happened and who caused it".
@immutable
class BookingStatusEvent {
  const BookingStatusEvent({
    required this.id,
    required this.toStatus,
    required this.actorRole,
    required this.transition,
    required this.at,
  });

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) =>
      BookingStatusEvent(
        id: json['id'] as String? ?? '',
        toStatus: BookingStatus.parse(json['toStatus'] as String?),
        actorRole: BookingActorRole.parse(json['actorRole'] as String?),
        transition: json['transition'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '')?.toLocal(),
      );

  final String id;
  final BookingStatus toStatus;
  final BookingActorRole actorRole;

  /// The machine's own name for the edge — `accept`, `claim-payment`,
  /// `withdraw-payment-claim`. What the timeline line is written from.
  final String transition;
  final DateTime? at;
}

/// §1h's amendment, with the original terms beside the proposed ones.
@immutable
class BookingAmendment {
  const BookingAmendment({
    required this.id,
    required this.status,
    required this.proposedByRole,
    required this.previousAmountLaari,
    required this.proposedAmountLaari,
    required this.previousScheduledFor,
    required this.proposedScheduledFor,
    required this.previousScopeNote,
    required this.proposedScopeNote,
    required this.reason,
    required this.createdAt,
  });

  factory BookingAmendment.fromJson(Map<String, dynamic> json) =>
      BookingAmendment(
        id: json['id'] as String? ?? '',
        status: BookingAmendmentStatus.parse(json['status'] as String?),
        proposedByRole: BookingActorRole.parse(
          json['proposedByRole'] as String?,
        ),
        previousAmountLaari: json['previousAmountLaari'] as int?,
        proposedAmountLaari: json['proposedAmountLaari'] as int?,
        previousScheduledFor: DateTime.tryParse(
          json['previousScheduledFor'] as String? ?? '',
        )?.toLocal(),
        proposedScheduledFor: DateTime.tryParse(
          json['proposedScheduledFor'] as String? ?? '',
        )?.toLocal(),
        previousScopeNote: json['previousScopeNote'] as String?,
        proposedScopeNote: json['proposedScopeNote'] as String?,
        reason: json['reason'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
            ?.toLocal(),
      );

  final String id;
  final BookingAmendmentStatus status;
  final BookingActorRole proposedByRole;
  final int? previousAmountLaari;
  final int? proposedAmountLaari;
  final DateTime? previousScheduledFor;
  final DateTime? proposedScheduledFor;
  final String? previousScopeNote;
  final String? proposedScopeNote;
  final String? reason;
  final DateTime? createdAt;

  bool get isOpen => status == BookingAmendmentStatus.proposed;
}

/// The other party to a booking.
///
/// **There is no phone field here and there may never be one** (§1c). A name
/// and the user id the chat thread is opened with is all a counterparty gets.
@immutable
class BookingParty {
  const BookingParty({required this.userId, required this.name});

  factory BookingParty.fromJson(Map<String, dynamic>? json) => BookingParty(
    userId: json?['userId'] as String? ?? '',
    name: json?['name'] as String? ?? '',
  );

  final String userId;
  final String name;
}

/// The provider's registered bank transfer details, shown at the payment step
/// and nowhere else.
///
/// §1c: "**Payment details are not contact information.** A bank account
/// number isn't a way to reach a person, and the off-platform payment cannot
/// physically happen without it."
@immutable
class BookingPaymentDetails {
  const BookingPaymentDetails({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  factory BookingPaymentDetails.fromJson(Map<String, dynamic> json) =>
      BookingPaymentDetails(
        bankName: json['bankName'] as String?,
        accountName: json['accountName'] as String?,
        accountNumber: json['accountNumber'] as String?,
      );

  final String? bankName;
  final String? accountName;
  final String? accountNumber;

  bool get isComplete =>
      (bankName ?? '').isNotEmpty &&
      (accountName ?? '').isNotEmpty &&
      (accountNumber ?? '').isNotEmpty;
}

/// §1h's replacement prefill — present only on a booking the **provider**
/// cancelled, and only to the customer.
@immutable
class ReplacementPrefill {
  const ReplacementPrefill({
    required this.listingId,
    required this.bookingMode,
    required this.scheduledFor,
    required this.jobNotes,
    required this.islandId,
    required this.addressDetail,
  });

  factory ReplacementPrefill.fromJson(Map<String, dynamic> json) =>
      ReplacementPrefill(
        listingId: json['listingId'] as String? ?? '',
        bookingMode: BookingKind.parse(json['bookingMode'] as String?),
        scheduledFor: DateTime.tryParse(json['scheduledFor'] as String? ?? '')
            ?.toLocal(),
        jobNotes: json['jobNotes'] as String?,
        islandId: json['islandId'] as String?,
        addressDetail: json['addressDetail'] as String?,
      );

  final String listingId;
  final BookingKind bookingMode;
  final DateTime? scheduledFor;
  final String? jobNotes;
  final String? islandId;
  final String? addressDetail;
}

/// One booking, as every booking screen reads it.
///
/// **Nothing here is computed from a rule the server owns.** The status, the
/// amount, the amount's kind and whether a replacement is offered are all
/// fields off the wire — §Phase 10a established this boundary (Round 19) and
/// a booking is the surface where getting it wrong costs the most.
@immutable
class Booking {
  const Booking({
    required this.id,
    required this.reference,
    required this.listingId,
    required this.listingName,
    required this.categoryName,
    required this.bookingMode,
    required this.status,
    required this.customer,
    required this.provider,
    required this.agreedAmountLaari,
    required this.amountKind,
    required this.quotedAmountLaari,
    required this.finalAmountLaari,
    required this.scheduledFor,
    required this.durationMinutes,
    required this.occasion,
    required this.jobNotes,
    required this.islandDisplayName,
    required this.addressDetail,
    required this.paymentClaimedAt,
    required this.paymentClaimWithdrawnAt,
    required this.completedAt,
    required this.completionPromptedAt,
    required this.cancelledByRole,
    required this.cancellationReason,
    required this.createdAt,
    required this.amendments,
    required this.statusHistory,
    required this.paymentDetails,
    required this.replacement,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: json['id'] as String? ?? '',
    reference: json['reference'] as String? ?? '',
    listingId: json['listingId'] as String? ?? '',
    listingName: json['listingName'] as String?,
    categoryName: json['categoryName'] as String?,
    bookingMode: BookingKind.parse(json['bookingMode'] as String?),
    status: BookingStatus.parse(json['status'] as String?),
    customer: BookingParty.fromJson(json['customer'] as Map<String, dynamic>?),
    provider: BookingParty.fromJson(json['provider'] as Map<String, dynamic>?),
    agreedAmountLaari: json['agreedAmountLaari'] as int?,
    amountKind: json['amountKind'] == null
        ? null
        : AmountKind.parse(json['amountKind'] as String?),
    quotedAmountLaari: json['quotedAmountLaari'] as int?,
    finalAmountLaari: json['finalAmountLaari'] as int?,
    scheduledFor: DateTime.tryParse(json['scheduledFor'] as String? ?? '')
        ?.toLocal(),
    durationMinutes: json['durationMinutes'] as int?,
    occasion: json['occasion'] as String?,
    jobNotes: json['jobNotes'] as String?,
    islandDisplayName: json['islandDisplayName'] as String?,
    addressDetail: json['addressDetail'] as String?,
    paymentClaimedAt: DateTime.tryParse(
      json['paymentClaimedAt'] as String? ?? '',
    )?.toLocal(),
    paymentClaimWithdrawnAt: DateTime.tryParse(
      json['paymentClaimWithdrawnAt'] as String? ?? '',
    )?.toLocal(),
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? '')
        ?.toLocal(),
    completionPromptedAt: DateTime.tryParse(
      json['completionPromptedAt'] as String? ?? '',
    )?.toLocal(),
    cancelledByRole: json['cancelledByRole'] == null
        ? null
        : BookingActorRole.parse(json['cancelledByRole'] as String?),
    cancellationReason: json['cancellationReason'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal(),
    amendments: ((json['amendments'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BookingAmendment.fromJson)
        .toList(growable: false),
    statusHistory: ((json['statusHistory'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BookingStatusEvent.fromJson)
        .toList(growable: false),
    paymentDetails: json['paymentDetails'] == null
        ? null
        : BookingPaymentDetails.fromJson(
            json['paymentDetails'] as Map<String, dynamic>,
          ),
    replacement: json['replacement'] == null
        ? null
        : ReplacementPrefill.fromJson(
            json['replacement'] as Map<String, dynamic>,
          ),
  );

  final String id;
  final String reference;
  final String listingId;
  final String? listingName;
  final String? categoryName;
  final BookingKind bookingMode;
  final BookingStatus status;
  final BookingParty customer;
  final BookingParty provider;
  final int? agreedAmountLaari;
  final AmountKind? amountKind;
  final int? quotedAmountLaari;
  final int? finalAmountLaari;
  final DateTime? scheduledFor;
  final int? durationMinutes;
  final String? occasion;
  final String? jobNotes;
  final String? islandDisplayName;
  final String? addressDetail;
  final DateTime? paymentClaimedAt;
  final DateTime? paymentClaimWithdrawnAt;
  final DateTime? completedAt;
  final DateTime? completionPromptedAt;
  final BookingActorRole? cancelledByRole;
  final String? cancellationReason;
  final DateTime? createdAt;
  final List<BookingAmendment> amendments;
  final List<BookingStatusEvent> statusHistory;
  final BookingPaymentDetails? paymentDetails;
  final ReplacementPrefill? replacement;

  /// The number a screen shows, and the label beside it. Before the provider
  /// has accepted there is no agreed amount — what exists is what the listing
  /// would come to, and it is labelled as such rather than as agreed.
  int? get displayAmountLaari => agreedAmountLaari ?? quotedAmountLaari;

  bool get isAgreed => agreedAmountLaari != null;

  /// §1h: an amendment waiting for somebody. At most one can be open.
  BookingAmendment? get openAmendment {
    for (final a in amendments) {
      if (a.isOpen) return a;
    }
    return null;
  }

  /// §1c step 10's prompt is showing and unanswered.
  bool get awaitsCompletionAnswer =>
      status == BookingStatus.confirmed && completionPromptedAt != null;
}
