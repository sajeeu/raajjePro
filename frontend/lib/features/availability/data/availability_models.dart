import 'package:flutter/foundation.dart';

/// §Phase 9a's client-side vocabulary.
///
/// **Two kinds of time live here and they are deliberately different types.**
/// A [WeeklyRule]'s hours are a Maldives *wall clock* with no date — `HH:MM`,
/// exactly as the server stores them — while a [TimeSlotView]'s bounds are
/// real instants. Collapsing the two into `DateTime` is how a recurring
/// "09:00 every Monday" silently acquires a day, so the wall clock stays a
/// string on both sides of the wire.
///
/// **Nothing here has a field for a phone number** (§1c).
@immutable
class WeeklyRule {
  const WeeklyRule({
    required this.id,
    required this.weekdays,
    required this.startTime,
    required this.endTime,
    required this.slotDurationMinutes,
  });

  factory WeeklyRule.fromJson(Map<String, dynamic> json) => WeeklyRule(
    id: json['id'] as String,
    weekdays: (json['weekdays'] as List<dynamic>).cast<int>(),
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String,
    slotDurationMinutes: json['slotDurationMinutes'] as int,
  );

  final String id;

  /// ISO weekday numbers, 1 = Monday — the server's convention, unchanged.
  final List<int> weekdays;
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;

  Map<String, dynamic> toBody() => {
    'weekdays': weekdays,
    'startTime': startTime,
    'endTime': endTime,
    'slotDurationMinutes': slotDurationMinutes,
  };
}

/// "Modified hours" — a named date range that replaces the weekly hours.
@immutable
class HoursException {
  const HoursException({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.slotDurationMinutes,
  });

  factory HoursException.fromJson(Map<String, dynamic> json) => HoursException(
    id: json['id'] as String,
    name: json['name'] as String,
    startDate: json['startDate'] as String,
    endDate: json['endDate'] as String,
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String,
    slotDurationMinutes: json['slotDurationMinutes'] as int?,
  );

  final String id;
  final String name;

  /// `YYYY-MM-DD`, Maldives calendar days, both ends inclusive.
  final String startDate;
  final String endDate;
  final String startTime;
  final String endTime;
  final int? slotDurationMinutes;
}

/// "Time away" — an all-day, provider-wide absence.
@immutable
class TimeAway {
  const TimeAway({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
  });

  factory TimeAway.fromJson(Map<String, dynamic> json) => TimeAway(
    id: json['id'] as String,
    name: json['name'] as String,
    startDate: json['startDate'] as String,
    endDate: json['endDate'] as String,
  );

  final String id;
  final String name;
  final String startDate;
  final String endDate;
}

enum SlotStatus { open, reserved, blocked }

/// One time on the provider's own grid.
@immutable
class TimeSlotView {
  const TimeSlotView({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.heldByAnotherListing,
  });

  factory TimeSlotView.fromJson(Map<String, dynamic> json) => TimeSlotView(
    id: json['id'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    status: switch (json['status'] as String) {
      'reserved' => SlotStatus.reserved,
      'blocked' => SlotStatus.blocked,
      _ => SlotStatus.open,
    },
    heldByAnotherListing: json['heldByAnotherListing'] as bool? ?? false,
  );

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final SlotStatus status;

  /// True when the status came from a booking on a different listing rather
  /// than this slot's own row — which is what the reserved sheet explains.
  final bool heldByAnotherListing;
}

/// One time on the customer's picker. Everything here is open and bookable.
@immutable
class OpenSlot {
  const OpenSlot({
    required this.id,
    required this.startsAt,
    required this.endsAt,
  });

  factory OpenSlot.fromJson(Map<String, dynamic> json) => OpenSlot(
    id: json['id'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
  );

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
}

@immutable
class ListingAvailability {
  const ListingAvailability({
    required this.rules,
    required this.exceptions,
    required this.horizonDate,
  });

  factory ListingAvailability.fromJson(Map<String, dynamic> json) =>
      ListingAvailability(
        rules: (json['rules'] as List<dynamic>)
            .map((e) => WeeklyRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        exceptions: (json['exceptions'] as List<dynamic>)
            .map((e) => HoursException.fromJson(e as Map<String, dynamic>))
            .toList(),
        horizonDate: json['horizonDate'] as String?,
      );

  final List<WeeklyRule> rules;
  final List<HoursException> exceptions;

  /// The last Maldives day times currently reach. Null before anything is generated.
  final String? horizonDate;
}

/// What the customer picker got back, including *why* an early time is absent.
@immutable
class OpenSlots {
  const OpenSlots({
    required this.slots,
    required this.minimumLeadTimeMinutes,
    required this.bookableFrom,
  });

  factory OpenSlots.fromJson(Map<String, dynamic> json) => OpenSlots(
    slots: (json['slots'] as List<dynamic>)
        .map((e) => OpenSlot.fromJson(e as Map<String, dynamic>))
        .toList(),
    minimumLeadTimeMinutes: json['minimumLeadTimeMinutes'] as int,
    bookableFrom: DateTime.parse(json['bookableFrom'] as String),
  );

  final List<OpenSlot> slots;

  /// The category's own seeded lead time, never a constant in this app
  /// (§Phase 4, admin-editable from §Phase 10b).
  final int minimumLeadTimeMinutes;
  final DateTime bookableFrom;
}

/// What the provider is committed to, across every listing. §Phase 17.1 adds
/// the customer, the reference and the mode; a reservation carries none.
@immutable
class Commitment {
  const Commitment({
    required this.id,
    required this.listingId,
    required this.startsAt,
    required this.endsAt,
    required this.provisional,
  });

  factory Commitment.fromJson(Map<String, dynamic> json) => Commitment(
    id: json['id'] as String,
    listingId: json['listingId'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    provisional: json['kind'] == 'provisional',
  );

  final String id;
  final String listingId;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool provisional;
}

@immutable
class ProviderCalendar {
  const ProviderCalendar({required this.commitments, required this.timeAway});

  factory ProviderCalendar.fromJson(Map<String, dynamic> json) =>
      ProviderCalendar(
        commitments: (json['commitments'] as List<dynamic>)
            .map((e) => Commitment.fromJson(e as Map<String, dynamic>))
            .toList(),
        timeAway: (json['timeOff'] as List<dynamic>)
            .map((e) => TimeAway.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final List<Commitment> commitments;
  final List<TimeAway> timeAway;
}
