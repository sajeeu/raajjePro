import 'package:flutter/foundation.dart';

import 'package:raajjepro/core/domain/verification_tier.dart';

/// §Phase 17.3's shapes, as the app reads them.
///
/// ## Every clock here is the server's
///
/// The overall window is the category's `emergencyAcceptWindowMinutes`, the
/// collection window is 90 seconds and the choice is five minutes — and **the
/// app computes none of them**. Each arrives as a deadline and the screens
/// count down to it, so a category an admin re-configures moves the next
/// request's countdown without an app release (invariant 13's posture,
/// applied to emergency).
///
/// ## Only one shape here carries a phone number
///
/// [ContactReveal], which is what `POST /v1/bookings/:id/reveal-contact`
/// answers — the single exception in the system (§1c). Nothing else in this
/// file has a field that could hold one: an offer is a name, a tier, a fee
/// and an estimate, and a broadcast withholds even the address.

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Where an emergency **request** is, as the server derives it. The screen
/// switches on this and never works a phase out from timestamps of its own.
enum EmergencyPhase {
  /// Sent to every eligible provider; nobody has answered this round.
  waiting,

  /// The first answer opened the 90-second collection window.
  collecting,

  /// The window closed: up to three offers, five minutes to pick.
  choosing,

  /// An offer was selected; its booking is live.
  matched,

  /// Ended without a match — nobody answered in time, or the customer cancelled.
  closed;

  static EmergencyPhase parse(String? wire) => switch (wire) {
    'collecting' => collecting,
    'choosing' => choosing,
    'matched' => matched,
    'closed' => closed,
    _ => waiting,
  };
}

/// Whether the reveal would answer, and why not — `Reveal Contact`'s states.
enum ContactRevealState {
  notAvailable,
  available,
  revealed,
  expired,

  /// §Phase 10b's kill switch. "It isn't an error."
  paused;

  static ContactRevealState parse(String? wire) => switch (wire) {
    'available' => available,
    'revealed' => revealed,
    'expired' => expired,
    'paused' => paused,
    _ => notAvailable,
  };
}

enum EmergencyOfferState {
  open,
  selected,
  notSelected,
  rejected,
  expired,
  lapsed,
  noShow,
  cancelled;

  static EmergencyOfferState parse(String? wire) => switch (wire) {
    'selected' => selected,
    'not_selected' => notSelected,
    'rejected' => rejected,
    'expired' => expired,
    'lapsed' => lapsed,
    'no_show' => noShow,
    'cancelled' => cancelled,
    _ => open,
  };
}

/// One provider's bid, as the customer compares it side by side.
@immutable
class EmergencyOffer {
  const EmergencyOffer({
    required this.id,
    required this.providerName,
    required this.verificationTier,
    required this.ratingAverage,
    required this.calloutFeeLaari,
    required this.etaMinutes,
    required this.state,
  });

  factory EmergencyOffer.fromJson(Map<String, dynamic> json) => EmergencyOffer(
    id: json['id'] as String? ?? '',
    providerName: json['providerName'] as String? ?? '',
    verificationTier: VerificationTier.parse(
      json['verificationTier'] as String?,
    ),
    ratingAverage: (json['ratingAverage'] as num?)?.toDouble(),
    calloutFeeLaari: json['calloutFeeLaari'] as int? ?? 0,
    etaMinutes: json['etaMinutes'] as int? ?? 0,
    state: EmergencyOfferState.parse(json['state'] as String?),
  );

  final String id;
  final String providerName;
  final VerificationTier verificationTier;

  /// Null until §Phase 11 builds reviews. The card says so rather than
  /// showing a number nobody earned.
  final double? ratingAverage;
  final int calloutFeeLaari;

  /// The provider's **own** estimate (Round 22) — never a platform promise.
  final int etaMinutes;
  final EmergencyOfferState state;
}

/// The MVR 200 fee incurred on selection, as the booking reports it.
@immutable
class EmergencyDispatchFee {
  const EmergencyDispatchFee({
    required this.submissionId,
    required this.amountLaari,
    required this.referenceCode,
    required this.state,
  });

  factory EmergencyDispatchFee.fromJson(Map<String, dynamic> json) =>
      EmergencyDispatchFee(
        submissionId: json['submissionId'] as String? ?? '',
        amountLaari: json['amountLaari'] as int? ?? 0,
        referenceCode: json['referenceCode'] as String? ?? '',
        state: DispatchFeeState.parse(json['state'] as String?),
      );

  final String submissionId;
  final int amountLaari;
  final String referenceCode;
  final DispatchFeeState state;
}

/// §1c: the hold lifts on proof submission, never on the admin's later
/// decision. §0.0 item 24: a **rejected** proof leaves the fee unsettled, so
/// the hold is back; a **waived** fee — the platform cancelled the booking —
/// never holds anything.
enum DispatchFeeState {
  owed,
  submitted,
  confirmed,
  rejected,
  waived;

  static DispatchFeeState parse(String? wire) => switch (wire) {
    'submitted' => submitted,
    'confirmed' => confirmed,
    'rejected' => rejected,
    'waived' => waived,
    _ => owed,
  };

  /// Whether a fee in this state holds new bookings — the server decides,
  /// and this mirrors it for the copy.
  bool get holdsBookings => this == owed || this == rejected;
}

/// One emergency request as its customer sees it — `Emergency Flow` from the
/// tap to the match.
///
/// 🔧 An emergency is a **request** until someone is chosen (owner's decision,
/// 2026-09-28): raised by category and island, never against a listing, and
/// the booking is created when the customer picks an offer.
@immutable
class EmergencyRequest {
  const EmergencyRequest({
    required this.id,
    required this.status,
    required this.phase,
    required this.categoryId,
    required this.categoryName,
    required this.minimumTier,
    required this.windowMinutes,
    required this.islandId,
    required this.islandDisplayName,
    required this.jobNotes,
    required this.addressDetail,
    required this.windowEndsAt,
    required this.collectionClosesAt,
    required this.choiceEndsAt,
    required this.broadcastCount,
    required this.offersReceived,
    required this.offers,
    required this.bookingId,
    required this.dispatchFee,
  });

  factory EmergencyRequest.fromJson(Map<String, dynamic> json) =>
      EmergencyRequest(
        id: json['id'] as String? ?? '',
        status: json['status'] as String? ?? 'requested',
        phase: EmergencyPhase.parse(json['phase'] as String?),
        categoryId: json['categoryId'] as String? ?? '',
        categoryName: json['categoryName'] as String? ?? '',
        minimumTier: VerificationTier.parse(json['minimumTier'] as String?),
        windowMinutes: json['windowMinutes'] as int?,
        islandId: json['islandId'] as String? ?? '',
        islandDisplayName: json['islandDisplayName'] as String? ?? '',
        jobNotes: json['jobNotes'] as String? ?? '',
        addressDetail: json['addressDetail'] as String?,
        windowEndsAt: _date(json['windowEndsAt']),
        collectionClosesAt: _date(json['collectionClosesAt']),
        choiceEndsAt: _date(json['choiceEndsAt']),
        broadcastCount: json['broadcastCount'] as int? ?? 0,
        offersReceived: json['offersReceived'] as int? ?? 0,
        offers: ((json['offers'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EmergencyOffer.fromJson)
            .toList(growable: false),
        bookingId: json['bookingId'] as String?,
        dispatchFee: json['dispatchFee'] is Map<String, dynamic>
            ? EmergencyDispatchFee.fromJson(
                json['dispatchFee'] as Map<String, dynamic>,
              )
            : null,
      );

  final String id;

  /// The server's own word — `requested`, `emergency_offered`, `matched`,
  /// `declined` or `cancelled`. `declined` is "No one accepted in time".
  final String status;
  final EmergencyPhase phase;
  final String categoryId;
  final String categoryName;

  /// The category's bar — "every Gold-verified Plumbing provider".
  final VerificationTier minimumTier;

  /// The category's answer window, for the copy that names it. Never a literal.
  final int? windowMinutes;
  final String islandId;
  final String islandDisplayName;
  final String jobNotes;
  final String? addressDetail;
  final DateTime? windowEndsAt;
  final DateTime? collectionClosesAt;
  final DateTime? choiceEndsAt;

  /// "Sent to 4 providers."
  final int broadcastCount;
  final int offersReceived;

  /// At most three, and only once collection has closed — ranked by the
  /// server, never re-sorted here.
  final List<EmergencyOffer> offers;
  final String? bookingId;
  final EmergencyDispatchFee? dispatchFee;

  bool get nobodyAnswered => status == 'declined';
}

/// The `emergency` block on an emergency **booking's** detail read.
@immutable
class EmergencyDetails {
  const EmergencyDetails({
    required this.requestId,
    required this.etaMinutes,
    required this.dispatchFee,
    required this.notArrivedAvailableAt,
    required this.contactReveal,
  });

  factory EmergencyDetails.fromJson(Map<String, dynamic> json) =>
      EmergencyDetails(
        requestId: json['requestId'] as String?,
        etaMinutes: json['etaMinutes'] as int?,
        dispatchFee: json['dispatchFee'] is Map<String, dynamic>
            ? EmergencyDispatchFee.fromJson(
                json['dispatchFee'] as Map<String, dynamic>,
              )
            : null,
        notArrivedAvailableAt: _date(json['notArrivedAvailableAt']),
        contactReveal: ContactRevealState.parse(
          json['contactReveal'] as String?,
        ),
      );

  final String? requestId;

  /// The chosen provider's own estimate — theirs, never a platform guarantee.
  final int? etaMinutes;
  final EmergencyDispatchFee? dispatchFee;
  final DateTime? notArrivedAvailableAt;
  final ContactRevealState contactReveal;
}

/// This provider's own offer on a broadcast, and what became of it.
@immutable
class MyEmergencyOffer {
  const MyEmergencyOffer({
    required this.id,
    required this.state,
    required this.calloutFeeLaari,
    required this.etaMinutes,
    required this.bookingId,
  });

  factory MyEmergencyOffer.fromJson(Map<String, dynamic> json) =>
      MyEmergencyOffer(
        id: json['id'] as String? ?? '',
        state: EmergencyOfferState.parse(json['state'] as String?),
        calloutFeeLaari: json['calloutFeeLaari'] as int? ?? 0,
        etaMinutes: json['etaMinutes'] as int? ?? 0,
        bookingId: json['bookingId'] as String?,
      );

  final String id;
  final EmergencyOfferState state;
  final int calloutFeeLaari;
  final int etaMinutes;

  /// Set once this offer was chosen — the booking the provider now has.
  final String? bookingId;
}

/// An open emergency request as a broadcast recipient sees it — `Provider
/// Emergency` before anyone is chosen. Job details and the customer's first name only;
/// "Exact address is shared if the customer picks you".
@immutable
class EmergencyBroadcast {
  const EmergencyBroadcast({
    required this.requestId,
    required this.categoryName,
    required this.customerFirstName,
    required this.jobNotes,
    required this.islandDisplayName,
    required this.createdAt,
    required this.windowEndsAt,
    required this.collectionClosesAt,
    required this.choiceEndsAt,
    required this.etaPresetsMinutes,
    required this.myOffer,
    required this.passed,
    required this.canOffer,
  });

  factory EmergencyBroadcast.fromJson(Map<String, dynamic> json) =>
      EmergencyBroadcast(
        requestId: json['requestId'] as String? ?? '',
        categoryName: json['categoryName'] as String? ?? '',
        customerFirstName: json['customerFirstName'] as String? ?? '',
        jobNotes: json['jobNotes'] as String?,
        islandDisplayName: json['islandDisplayName'] as String?,
        createdAt: _date(json['createdAt']),
        windowEndsAt: _date(json['windowEndsAt']),
        collectionClosesAt: _date(json['collectionClosesAt']),
        choiceEndsAt: _date(json['choiceEndsAt']),
        etaPresetsMinutes:
            ((json['etaPresetsMinutes'] as List<dynamic>?) ?? const [])
                .whereType<int>()
                .toList(growable: false),
        myOffer: json['myOffer'] is Map<String, dynamic>
            ? MyEmergencyOffer.fromJson(json['myOffer'] as Map<String, dynamic>)
            : null,
        passed: json['passed'] as bool? ?? false,
        canOffer: json['canOffer'] as bool? ?? false,
      );

  final String requestId;
  final String categoryName;
  final String customerFirstName;
  final String? jobNotes;
  final String? islandDisplayName;
  final DateTime? createdAt;
  final DateTime? windowEndsAt;
  final DateTime? collectionClosesAt;
  final DateTime? choiceEndsAt;
  final List<int> etaPresetsMinutes;
  final MyEmergencyOffer? myOffer;

  /// This provider passed on it — recorded, never counted (owner, 2026-09-28).
  final bool passed;
  final bool canOffer;
}

/// **The only shape in this app that holds a phone number** — the answer to
/// `reveal-contact`, and nothing else constructs it. Both numbers or none
/// (§1c: "Both parties see each other's number, or neither does"). No
/// WhatsApp or Viber field; neither is collected anywhere.
@immutable
class ContactReveal {
  const ContactReveal({
    required this.customerName,
    required this.customerPhone,
    required this.providerName,
    required this.providerPhone,
    required this.providerTier,
    required this.revealedAt,
    required this.expiresAt,
  });

  factory ContactReveal.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? const {};
    final provider = json['provider'] as Map<String, dynamic>? ?? const {};
    return ContactReveal(
      customerName: customer['name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      providerName: provider['name'] as String? ?? '',
      providerPhone: provider['phone'] as String? ?? '',
      providerTier: VerificationTier.parse(
        provider['verificationTier'] as String?,
      ),
      revealedAt: _date(json['revealedAt']),
      expiresAt: _date(json['expiresAt']),
    );
  }

  final String customerName;
  final String customerPhone;
  final String providerName;
  final String providerPhone;
  final VerificationTier providerTier;
  final DateTime? revealedAt;
  final DateTime? expiresAt;
}

/// One dispatch fee, as `Dispatch Fee` renders it.
@immutable
class DispatchFee {
  const DispatchFee({
    required this.id,
    required this.requestId,
    required this.amountLaari,
    required this.referenceCode,
    required this.state,
    required this.rejectionReason,
  });

  factory DispatchFee.fromJson(Map<String, dynamic> json) => DispatchFee(
    id: json['id'] as String? ?? '',
    requestId: json['requestId'] as String?,
    amountLaari: json['amountLaari'] as int? ?? 0,
    referenceCode: json['referenceCode'] as String? ?? '',
    state: DispatchFeeState.parse(json['state'] as String?),
    rejectionReason: json['rejectionReason'] as String?,
  );

  final String id;
  final String? requestId;
  final int amountLaari;
  final String referenceCode;
  final DispatchFeeState state;
  final String? rejectionReason;
}

/// RaajjePro's **own** account — never a provider's.
@immutable
class PlatformBankAccount {
  const PlatformBankAccount({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  factory PlatformBankAccount.fromJson(Map<String, dynamic> json) =>
      PlatformBankAccount(
        bankName: json['bankName'] as String? ?? '',
        accountName: json['accountName'] as String? ?? '',
        accountNumber: json['accountNumber'] as String? ?? '',
      );

  final String bankName;
  final String accountName;
  final String accountNumber;
}

@immutable
class DispatchFees {
  const DispatchFees({required this.fees, required this.bankTransfer});

  factory DispatchFees.fromJson(Map<String, dynamic> json) => DispatchFees(
    fees: ((json['fees'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DispatchFee.fromJson)
        .toList(growable: false),
    bankTransfer: json['bankTransfer'] is Map<String, dynamic>
        ? PlatformBankAccount.fromJson(
            json['bankTransfer'] as Map<String, dynamic>,
          )
        : null,
  );

  final List<DispatchFee> fees;
  final PlatformBankAccount? bankTransfer;

  /// The fee that is holding new bookings, if any — owed, or rejected
  /// (§0.0 item 24).
  DispatchFee? get outstanding {
    for (final fee in fees.reversed) {
      if (fee.state.holdsBookings) return fee;
    }
    return null;
  }
}
