/// Presenting stored UTC instants in Maldives time (§Phase 9a).
///
/// The backend's `core/maldives-time.ts` is the other half of this convention
/// and carries the full reasoning. The short version: Maldives Standard Time
/// is **UTC+5 year round, with no DST**, so the offset is a constant rather
/// than a zone lookup — and a **day** is a Maldives calendar day,
/// `[date 00:00+05, date+1 00:00+05)`, never the UTC date.
///
/// Every screen in this feature groups, labels and compares by [maldives], and
/// none of them calls `toLocal()`. That matters even in a single-timezone
/// market: a device left on another timezone — a traveller's phone, an
/// emulator on UTC, a test runner — would otherwise file a 21:00 Malé
/// appointment under the wrong heading while the server and the provider both
/// call it Tuesday.
library;

const Duration _maldivesOffset = Duration(hours: 5);

/// The same instant, shifted so its `.year` / `.month` / `.day` / `.hour`
/// read as Maldives wall-clock values.
///
/// The result is a `DateTime` whose own timezone flag is meaningless — it is a
/// *reading*, not an instant, and it must never be sent back to the server or
/// compared against one. Use [isSameMaldivesDay] and [maldivesDateKey] rather
/// than comparing two of these by `==`.
DateTime maldives(DateTime instant) => instant.toUtc().add(_maldivesOffset);

/// `YYYY-MM-DD` in Maldives time — the form every API date parameter takes.
String maldivesDateKey(DateTime instant) {
  final d = maldives(instant);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Whether two instants fall on the same Maldives calendar day.
bool isSameMaldivesDay(DateTime a, DateTime b) =>
    maldivesDateKey(a) == maldivesDateKey(b);

/// `14:00` — a slot's start, as a provider and a customer both read it.
String maldivesClock(DateTime instant) {
  final d = maldives(instant);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Mon` — the three-letter weekday of the Maldives day an instant falls on.
String maldivesWeekdayShort(DateTime instant) =>
    _weekdays[maldives(instant).weekday - 1];

/// `Mon 14 Sep`, or `Today` / `Tomorrow` when [now] makes that clearer.
String maldivesDayLabel(DateTime instant, DateTime now) {
  if (isSameMaldivesDay(instant, now)) return 'Today';
  if (isSameMaldivesDay(instant, now.add(const Duration(days: 1)))) {
    return 'Tomorrow';
  }
  final d = maldives(instant);
  return '${maldivesWeekdayShort(instant)} ${d.day} ${_months[d.month - 1]}';
}

/// `14 Sep` — for a horizon or a date range, where the weekday adds nothing.
String maldivesShortDate(DateTime instant) {
  final d = maldives(instant);
  return '${d.day} ${_months[d.month - 1]}';
}

/// Parses a `YYYY-MM-DD` Maldives calendar day into the instant it opens at.
DateTime maldivesDayStart(String dateKey) =>
    DateTime.parse('${dateKey}T00:00:00Z').subtract(_maldivesOffset);

/// The ISO weekday names a rule renders as — `Mon–Thu`, or `Mon, Wed, Fri`.
String weekdayRangeLabel(List<int> weekdays) {
  if (weekdays.isEmpty) return 'No days';
  final sorted = [...weekdays]..sort();
  final names = sorted.map((d) => _weekdays[d - 1]).toList();
  if (sorted.length == 1) return names.first;
  // Contiguous runs read as a range, which is how the artboard writes them
  // ("Mon–Thu"); anything else lists the days.
  final contiguous = sorted.last - sorted.first == sorted.length - 1;
  return contiguous ? '${names.first}–${names.last}' : names.join(', ');
}

/// `2 hours` / `90 min` — a visit length, as the rule editor states it.
String visitLengthLabel(int minutes) {
  if (minutes % 60 != 0) return '$minutes min';
  final hours = minutes ~/ 60;
  return hours == 1 ? '1 hour' : '$hours hours';
}
