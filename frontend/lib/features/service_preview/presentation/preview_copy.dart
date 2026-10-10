import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/listings/service_listing.dart'
    show PriceUnit, PricingModel;
import 'package:raajjepro/features/service_preview/data/public_listing_models.dart';

/// Every sentence the Service Preview composes from data, in one place so the
/// words are testable without pumping a widget.
///
/// Three rules govern them, all from the plan:
///
///  * **A number is a number.** §1f rejected every editorial label, so a
///    conduct figure is printed or it is not — there is no "Fast responder"
///    here, and below the ten-job floor there is no figure at all.
///  * **Nothing the provider said is dressed as something RaajjePro checked**
///    (§1i). Self-declared statements are attributed in the screen, not here.
///  * **No promise the data cannot keep.** The prototype's "usually within the
///    hour" had no source, so it is gone; a response time appears only when
///    the server sent one.

/// The price block: the headline figure, its unit, the pill, the explainer and
/// the sticky footer's two lines.
class PriceCopy {
  const PriceCopy({
    required this.big,
    required this.unit,
    required this.label,
    required this.note,
    required this.footPrice,
    required this.footSub,
  });

  final String big;
  final String unit;
  final String label;
  final String note;
  final String footPrice;
  final String footSub;
}

PriceCopy priceCopy(PublicPricing pricing, String providerName) {
  final unitSuffix = pricing.unit?.suffix ?? '';
  switch (pricing.model) {
    case PricingModel.fixed:
      final big = _amount(pricing.priceLaari);
      return PriceCopy(
        big: big,
        unit: unitSuffix,
        label: 'Flat rate',
        note: 'One price, stated up front. What you see is what you pay.',
        footPrice: '$big $unitSuffix'.trim(),
        footSub: _perLabel(pricing.unit) ?? 'flat rate',
      );
    case PricingModel.hourly:
      final big = _amount(pricing.priceLaari);
      final unit = pricing.unit?.suffix ?? PriceUnit.hour.suffix;
      return PriceCopy(
        big: big,
        unit: unit,
        label: 'Hourly rate',
        note:
            'Charged per hour worked — the hours are agreed with you as you '
            'book.',
        footPrice: '$big $unit',
        footSub: 'per hour',
      );
    case PricingModel.daily:
      final big = _amount(pricing.priceLaari);
      final unit = pricing.unit?.suffix ?? PriceUnit.day.suffix;
      return PriceCopy(
        big: big,
        unit: unit,
        label: 'Daily rate',
        note: 'Charged per working day.',
        footPrice: '$big $unit',
        footSub: 'per day',
      );
    case PricingModel.range:
      final min = pricing.priceMinLaari;
      final big = min == null ? 'Price on request' : 'From ${mvr(min)}';
      return PriceCopy(
        big: big,
        unit: '',
        label: 'Starting price',
        note:
            'This is a starting price, not the final amount. $providerName '
            'quotes your actual price before you confirm anything.',
        footPrice: big,
        footSub: 'final price quoted first',
      );
    case PricingModel.quote:
      return PriceCopy(
        big: 'Price on request',
        unit: '',
        label: 'Quoted per job',
        note:
            'Describe the job and $providerName replies with a quote before '
            'anything is booked.',
        footPrice: 'Price on request',
        footSub: 'quote before booking',
      );
  }
}

String _amount(int? laari) => laari == null ? 'MVR —' : mvr(laari);

String? _perLabel(PriceUnit? unit) => unit?.label;

/// "Pick a time" / "Request a time" — §1c's two affordances and the CTA, one
/// string, so the card and the button cannot disagree about the wait.
String bookingCta(BookingMode mode) =>
    mode == BookingMode.slot ? 'Pick a time' : 'Request a time';

String bookingModeSub(PublicListing listing, String providerName) {
  switch (listing.bookingMode) {
    case BookingMode.slot:
      return 'Pick one of $providerName’s published times — $providerName '
          'confirms it.';
    case BookingMode.request:
      return 'You suggest a time; $providerName replies with a time and a '
          'price.';
  }
}

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

/// §1f's "New provider" and the job count, or the count alone once the
/// window's floor is met. Never a rate, never a label.
String jobsLine(PublicConduct conduct) {
  final count = conduct.jobsCompletedCount;
  final jobs = '$count ${count == 1 ? 'job' : 'jobs'} completed';
  if (!conduct.belowFloor) return jobs;
  return count == 0 ? 'New provider' : 'New provider · $jobs';
}

/// The line under the provider's name: the mode's second signal, then jobs.
String providerLine(PublicListing listing, DateTime now) {
  final signal = listing.secondSignal;
  final parts = <String>[
    switch (signal) {
          NextOpen(:final at) =>
            at == null
                ? 'No open times right now'
                : 'Next available: ${nextOpenPhrase(at, now)}',
          ResponseTime(:final medianSeconds) =>
            medianSeconds == null
                ? null
                : 'Usually replies in ${responseTimePhrase(medianSeconds)}',
        } ??
        '',
    jobsLine(listing.provider.conduct),
  ].where((part) => part.isNotEmpty).toList();
  return parts.join(' · ');
}

/// "4.8 (24 reviews)" or "No reviews yet" — never a 0.0.
String ratingLine(RatingSummary rating) {
  final average = rating.averageRating;
  if (average == null || rating.reviewCount == 0) return 'No reviews yet';
  final count = rating.reviewCount;
  return '${average.toStringAsFixed(1)} '
      '($count ${count == 1 ? 'review' : 'reviews'})';
}

/// "2 weeks ago" for a review's date; a calendar date past a few months.
String reviewAge(DateTime when, DateTime now) {
  final days = now.difference(when).inDays;
  if (days < 1) return 'Today';
  if (days < 14) return days == 1 ? 'Yesterday' : '$days days ago';
  if (days < 60) return '${(days / 7).floor()} weeks ago';
  if (days < 365) return '${(days / 30).floor()} months ago';
  return maldivesShortDate(when);
}
