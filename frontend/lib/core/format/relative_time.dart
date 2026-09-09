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

/// `Jan 2026` — the Profile hero's "Member since" line (plan §Phase 6).
/// Month and year only: the exact day a customer signed up is not something
/// the screen has any reason to state.
String monthAndYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

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
