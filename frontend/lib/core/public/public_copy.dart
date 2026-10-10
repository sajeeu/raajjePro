import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/listings/service_listing.dart'
    show PriceUnit, PricingModel;
import 'package:raajjepro/core/public/public_models.dart';

/// The sentences more than one public surface composes from the same data, so
/// a listing page, a profile and a card can never word one fact two ways.
///
/// 🔧 **Moved out of `features/service_preview/presentation/preview_copy.dart`
/// by Phase 13**, on its second consumer. The rules that file states still
/// govern: a number is a number (§1f — no label, and no figure below the
/// floor), and nothing promises what the data cannot keep.

/// "Pick a time" / "Request a time" — §1c's two affordances, one string, so a
/// card and a button cannot disagree about the wait.
String bookingCta(BookingMode mode) =>
    mode == BookingMode.slot ? 'Pick a time' : 'Request a time';

/// "about 12 minutes" / "about 1 hour" — the provider's median, in words.
String responseTimePhrase(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return 'under a minute';
  if (minutes < 60) {
    return 'about $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
  final hours = (minutes / 60).round();
  if (hours < 48) return 'about $hours ${hours == 1 ? 'hour' : 'hours'}';
  final days = (hours / 24).round();
  return 'about $days days';
}

/// "Tomorrow 09:00" — the first time a customer could actually book.
String nextOpenPhrase(DateTime at, DateTime now) =>
    '${maldivesDayLabel(at, now)} ${maldivesClock(at)}';

/// "47 jobs completed".
String jobsCount(int count) =>
    '$count ${count == 1 ? 'job' : 'jobs'} completed';

/// §1f's "New provider" and the job count, or the count alone.
///
/// 🔧 **Phase 13 narrowed when "New provider" is said.** §1f's floor is ten
/// completed bookings *in the 90-day window*, and [PublicConduct.belowFloor]
/// answers that; the job count beside it is lifetime. A provider with 47
/// lifetime jobs and nine this quarter is below the floor, and printing "New
/// provider · 47 jobs completed" asserts something the number beside it
/// contradicts — the trap `providers/types.ts` names. So "New provider" is
/// said only where the lifetime count is itself under the floor; above it the
/// count stands alone, and the rates stay hidden either way.
String jobsLine(PublicConduct conduct) {
  final count = conduct.jobsCompletedCount;
  if (!conduct.belowFloor || count >= conductFloor) return jobsCount(count);
  return count == 0 ? 'New provider' : 'New provider · ${jobsCount(count)}';
}

/// §1f's ten-completed-booking floor, **for wording only**. Whether the rates
/// show is the server's `metricsBelowFloor` and nothing else (invariant 4);
/// this number decides only whether "New provider" is a true thing to say.
const conductFloor = 10;

/// "94%" — a §1f rate, or null where there is no figure to print.
String? percent(double? rate) =>
    rate == null ? null : '${(rate * 100).round()}%';

/// The headline price and its unit, as a card or the price block prints it:
/// "MVR 450" + "/visit", "From MVR 350", "Price on request".
({String big, String unit}) priceHeadline(PublicPricing pricing) {
  final unitSuffix = pricing.unit?.suffix ?? '';
  return switch (pricing.model) {
    PricingModel.fixed => (big: _amount(pricing.priceLaari), unit: unitSuffix),
    PricingModel.hourly => (
      big: _amount(pricing.priceLaari),
      unit: pricing.unit?.suffix ?? PriceUnit.hour.suffix,
    ),
    PricingModel.daily => (
      big: _amount(pricing.priceLaari),
      unit: pricing.unit?.suffix ?? PriceUnit.day.suffix,
    ),
    PricingModel.range => (
      big: pricing.priceMinLaari == null
          ? 'Price on request'
          : 'From ${mvr(pricing.priceMinLaari!)}',
      unit: '',
    ),
    PricingModel.quote => (big: 'Price on request', unit: ''),
  };
}

String _amount(int? laari) => laari == null ? 'MVR —' : mvr(laari);

/// "4.6" for a mean rating, or null with no reviews — never "0.0".
String? averageText(RatingTotals rating) {
  final average = rating.averageRating;
  if (average == null || rating.reviewCount == 0) return null;
  return average.toStringAsFixed(1);
}
