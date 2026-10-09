import 'package:flutter/foundation.dart';

import 'package:raajjepro/core/domain/verification_tier.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';

/// §Phase 17.4's two repeat-use shapes: Book Again's prefill and the weekly
/// series. Neither has a field that could hold a phone number (§1c).

/// `GET /v1/bookings/:id/book-again` — `Book Again.dc.html`.
///
/// `bookingMode` is the listing's mode **now** (§Phase 17 frontend item 13:
/// "routed by that listing's current `bookingMode`"), and null when the
/// listing is no longer offered.
@immutable
class BookAgain {
  const BookAgain({
    required this.fromBookingId,
    required this.listingId,
    required this.listingName,
    required this.categoryName,
    required this.providerName,
    required this.providerVerificationTier,
    required this.available,
    required this.bookingMode,
    required this.modeChanged,
    required this.priceLaari,
    required this.lastDoneAt,
    required this.jobNotes,
    required this.islandId,
    required this.islandDisplayName,
    required this.addressDetail,
    required this.standingInstructions,
    required this.preferredWindowLabel,
  });

  factory BookAgain.fromJson(Map<String, dynamic> json) {
    final mode = json['bookingMode'] as String?;
    return BookAgain(
      fromBookingId: json['fromBookingId'] as String? ?? '',
      listingId: json['listingId'] as String? ?? '',
      listingName: json['listingName'] as String?,
      categoryName: json['categoryName'] as String?,
      providerName: json['providerName'] as String? ?? '',
      providerVerificationTier: VerificationTier.parse(
        json['providerVerificationTier'] as String?,
      ),
      available: json['available'] as bool? ?? false,
      bookingMode: mode == null ? null : BookingKind.parse(mode),
      modeChanged: json['modeChanged'] as bool? ?? false,
      priceLaari: json['priceLaari'] as int?,
      lastDoneAt: DateTime.tryParse(json['lastDoneAt'] as String? ?? '')
          ?.toLocal(),
      jobNotes: json['jobNotes'] as String?,
      islandId: json['islandId'] as String?,
      islandDisplayName: json['islandDisplayName'] as String?,
      addressDetail: json['addressDetail'] as String?,
      standingInstructions: json['standingInstructions'] as String?,
      preferredWindowLabel: json['preferredWindowLabel'] as String?,
    );
  }

  final String fromBookingId;
  final String listingId;
  final String? listingName;
  final String? categoryName;
  final String providerName;
  final VerificationTier providerVerificationTier;
  final bool available;
  final BookingKind? bookingMode;
  final bool modeChanged;
  final int? priceLaari;
  final DateTime? lastDoneAt;
  final String? jobNotes;
  final String? islandId;
  final String? islandDisplayName;
  final String? addressDetail;
  final String? standingInstructions;
  final String? preferredWindowLabel;

  /// What goes into "About the job" on the next screen: the job as it was
  /// described last time, then the standing instructions — "Same address,
  /// same notes — nothing to re-enter."
  String get carriedNotes => [
    jobNotes,
    standingInstructions,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n\n');

  String? get addressLine {
    final parts = [
      addressDetail,
      islandDisplayName,
    ].whereType<String>().where((s) => s.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

enum RecurringSeriesStatus {
  active,
  paused,
  ended;

  static RecurringSeriesStatus parse(String? wire) => switch (wire) {
    'paused' => paused,
    'ended' => ended,
    _ => active,
  };
}

enum RecurringOccurrenceState {
  asked,
  accepted,
  missed,
  skipped,
  withdrawn;

  static RecurringOccurrenceState parse(String? wire) => switch (wire) {
    'accepted' => accepted,
    'missed' => missed,
    'skipped' => skipped,
    'withdrawn' => withdrawn,
    _ => asked,
  };
}

/// One week of a series.
@immutable
class RecurringOccurrence {
  const RecurringOccurrence({
    required this.id,
    required this.occursAt,
    required this.state,
    required this.missReason,
    required this.bookingId,
    required this.bookingStatus,
  });

  factory RecurringOccurrence.fromJson(Map<String, dynamic> json) =>
      RecurringOccurrence(
        id: json['id'] as String? ?? '',
        occursAt:
            DateTime.tryParse(json['occursAt'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        state: RecurringOccurrenceState.parse(json['state'] as String?),
        missReason: json['missReason'] as String?,
        bookingId: json['bookingId'] as String?,
        bookingStatus: json['bookingStatus'] == null
            ? null
            : BookingStatus.parse(json['bookingStatus'] as String?),
      );

  final String id;
  final DateTime occursAt;
  final RecurringOccurrenceState state;
  final String? missReason;
  final String? bookingId;
  final BookingStatus? bookingStatus;

  /// Waiting on the provider, and so still skippable.
  bool get isWaiting =>
      state == RecurringOccurrenceState.asked &&
      bookingStatus == BookingStatus.requested;
}

/// §1c's weekly series — `Recurring Booking.dc.html`.
@immutable
class RecurringSeries {
  const RecurringSeries({
    required this.id,
    required this.status,
    required this.listingId,
    required this.listingName,
    required this.customer,
    required this.provider,
    required this.pricePerVisitLaari,
    required this.nextOccurrenceAt,
    required this.nextAskAt,
    required this.nextOccurrenceSkipped,
    required this.consecutiveMisses,
    required this.occurrences,
  });

  factory RecurringSeries.fromJson(
    Map<String, dynamic> json,
  ) => RecurringSeries(
    id: json['id'] as String? ?? '',
    status: RecurringSeriesStatus.parse(json['status'] as String?),
    listingId: json['listingId'] as String? ?? '',
    listingName: json['listingName'] as String?,
    customer: BookingParty.fromJson(json['customer'] as Map<String, dynamic>?),
    provider: BookingParty.fromJson(json['provider'] as Map<String, dynamic>?),
    pricePerVisitLaari: json['pricePerVisitLaari'] as int?,
    nextOccurrenceAt: DateTime.tryParse(
      json['nextOccurrenceAt'] as String? ?? '',
    )?.toLocal(),
    nextAskAt: DateTime.tryParse(json['nextAskAt'] as String? ?? '')?.toLocal(),
    nextOccurrenceSkipped: json['nextOccurrenceSkipped'] as bool? ?? false,
    consecutiveMisses: json['consecutiveMisses'] as int? ?? 0,
    occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RecurringOccurrence.fromJson)
        .toList(growable: false),
  );

  final String id;
  final RecurringSeriesStatus status;
  final String listingId;
  final String? listingName;
  final BookingParty customer;
  final BookingParty provider;
  final int? pricePerVisitLaari;
  final DateTime? nextOccurrenceAt;
  final DateTime? nextAskAt;
  final bool nextOccurrenceSkipped;
  final int consecutiveMisses;
  final List<RecurringOccurrence> occurrences;
}
