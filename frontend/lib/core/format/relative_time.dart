/// "active now" · "12 minutes ago" · "3 hours ago" · "3 days ago". Sessions
/// use it; nothing else in this phase.
String relativeAge(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 2) return 'active now';
  if (d.inHours < 1) return '${d.inMinutes} minutes ago';
  if (d.inDays < 1) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

/// "Just now" · "12 minutes ago" · "3 hours ago" · "2 days ago" ·
/// "3 weeks ago" · `12 Aug 2026` — what §Phase 10's service card prints after
/// "Updated".
///
/// Deliberately not [relativeAge], whose first rung is "active now": that
/// reads correctly about a *session* and wrongly about an *edit*. Past a
/// month it falls back to the date, because "9 weeks ago" is a number a
/// reader has to convert and a date is not.
String relativeEdit(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.isNegative || d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inDays < 1) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  if (d.inDays < 7) {
    return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
  }
  if (d.inDays < 30) {
    final weeks = d.inDays ~/ 7;
    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  }
  return shortDate(when);
}

/// `Jan 2026` — the Profile hero's "Member since" line (plan §Phase 6).
/// Month and year only: the exact day a customer signed up is not something
/// the screen has any reason to state.
String monthAndYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `13 Sep` — one end of a period range, where the year is the same at both
/// ends and would only repeat (§Phase 10a's "Premium · 13 Sep – 12 Oct").
String dayAndMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const _months = [
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
