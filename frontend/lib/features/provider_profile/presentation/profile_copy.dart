import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/public/public_models.dart';

// `displayName` moved to `core/public/` on its second consumer (§Phase 14's
// Saved providers); re-exported so this feature's imports are unchanged.
export 'package:raajjepro/core/public/public_copy.dart' show displayName;

/// Every sentence the provider profile composes from data, in one place so the
/// words are testable without pumping a widget.
///
/// §1f governs all of it: **numbers and counts, and nothing else**. There is no
/// function here that could produce "Prone to cancel", "Price hiking" or any
/// euphemism for them, and below the floor there is no rate at all.

/// One cell of the stats grid: the figure, or null for "No data yet", and what
/// it counts.
typedef MetricCell = ({String? value, String label});

/// §1f's track record, in the artboard's order. A rate that is null above the
/// floor — nothing measured yet, such as an on-time rate with no arrival marks
/// — is "No data yet", never a zero.
///
/// Acceptance rate is not here: the artboard's grid does not draw it, and §1f's
/// own example line ("94% on time · 3% cancelled · usually responds in 12
/// minutes · 47 jobs completed") does not use it either.
List<MetricCell> trackRecord(PublicConduct conduct) => [
  (value: percent(conduct.completionRate), label: 'completed'),
  (value: percent(conduct.cancellationRate), label: 'cancelled'),
  (value: percent(conduct.noShowRate), label: 'no-show'),
  (value: percent(conduct.onTimeRate), label: 'on time'),
  (value: percent(conduct.priceAdherenceRate), label: 'price honoured'),
  (value: '${conduct.jobsCompletedCount}', label: 'jobs completed'),
];

/// The below-floor card's two lines. See `jobsLine` for why "New provider" is
/// said only where the lifetime count is itself under ten.
({String title, String body}) belowFloorCopy(PublicConduct conduct) => (
  title: jobsLine(conduct),
  // "in the last 90 days" because that is what the floor measures; without it
  // a provider with 47 jobs would read as having fewer than ten.
  body:
      'Reliability numbers appear once a provider has completed ten '
      'bookings in the last 90 days.',
);

/// "Provider since Mar 2026" — the month in the Maldives, not in UTC.
String? providerSince(PublicProvider provider) {
  final created = provider.createdAt;
  return created == null
      ? null
      : 'Provider since ${monthAndYear(maldives(created))}';
}

/// "31 reviews across all services" / "No reviews yet".
String reviewsAcross(RatingTotals rating) {
  final count = rating.reviewCount;
  if (count == 0) return 'No reviews yet';
  return '$count ${count == 1 ? 'review' : 'reviews'} across all services';
}

/// "On time (26)".
String tagChip(TagCount tag) => '${tag.label} (${tag.count})';

/// "2 published services".
String servicesHeading(int count) =>
    '$count published ${count == 1 ? 'service' : 'services'}';
