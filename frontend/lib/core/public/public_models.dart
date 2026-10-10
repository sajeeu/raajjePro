import 'package:flutter/foundation.dart';

import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/domain/verification_tier.dart';
import 'package:raajjepro/core/listings/service_listing.dart'
    show PriceUnit, PricingModel;

/// The public shapes more than one customer-facing feature reads — §Phase 12's
/// listing page and §Phase 13's provider profile today, §Phase 15's results
/// and §Phase 16's Home when they land.
///
/// 🔧 **Moved out of `features/service_preview/` by Phase 13**, on its second
/// consumer (`lib/README.md`: no feature imports another). Nothing changed in
/// the move except [PublicConduct], which gained the rates §Phase 13's stats
/// grid prints, and [PublicListingCard], which is new.
///
/// **Nothing here has a field that could hold a phone number, an email or a
/// bank detail** — and that is the point rather than a convenience. The server
/// maps through DTOs with no such field (`public-listings/types.ts`), and this
/// side parses only what it names, so a value the server should never have sent
/// has nowhere to land even if it did (§1c).
///
/// Money is integer laari from the wire to the last widget (invariant 7).

@immutable
class PublicCategory {
  const PublicCategory({
    required this.id,
    required this.name,
    required this.iconIdentifier,
    required this.colorToken,
  });

  factory PublicCategory.fromJson(Map<String, dynamic> json) => PublicCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    iconIdentifier: json['iconIdentifier'] as String? ?? '',
    colorToken: json['colorToken'] as String? ?? '',
  );

  final String id;
  final String name;
  final String iconIdentifier;
  final String colorToken;
}

@immutable
class PublicPricing {
  const PublicPricing({
    required this.model,
    required this.priceLaari,
    required this.priceMinLaari,
    required this.priceMaxLaari,
    required this.unit,
  });

  factory PublicPricing.fromJson(Map<String, dynamic> json) => PublicPricing(
    // An unknown model reads as `quote`: "price on request" promises nothing
    // about an amount, which is the safe reading of one this build has not met.
    model: PricingModel.parse(json['model'] as String?) ?? PricingModel.quote,
    priceLaari: json['priceLaari'] as int?,
    priceMinLaari: json['priceMinLaari'] as int?,
    priceMaxLaari: json['priceMaxLaari'] as int?,
    unit: PriceUnit.parse(json['unit'] as String?),
  );

  final PricingModel model;
  final int? priceLaari;
  final int? priceMinLaari;
  final int? priceMaxLaari;
  final PriceUnit? unit;
}

/// The mode-appropriate second signal (§1c, Round 23): next open time for a
/// slot listing, median response time for a request one. Never both.
@immutable
sealed class SecondSignal {
  const SecondSignal();

  factory SecondSignal.fromJson(Map<String, dynamic> json) =>
      json['kind'] == 'next_open'
      ? NextOpen(
          json['nextOpenAt'] is String
              ? DateTime.parse(json['nextOpenAt'] as String)
              : null,
        )
      : ResponseTime((json['medianResponseSeconds'] as num?)?.toInt());
}

class NextOpen extends SecondSignal {
  const NextOpen(this.at);

  /// Null when the provider has published no time that can still be booked.
  final DateTime? at;
}

class ResponseTime extends SecondSignal {
  const ResponseTime(this.medianSeconds);

  /// Null below §1f's ten-completed-booking floor: nothing is shown, and
  /// certainly not a zero.
  final int? medianSeconds;
}

@immutable
class TagCount {
  const TagCount({required this.label, required this.count});

  factory TagCount.fromJson(Map<String, dynamic> json) => TagCount(
    label: json['label'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final String label;
  final int count;
}

/// A review count and its mean — what a card and a profile header print.
@immutable
class RatingTotals {
  const RatingTotals({required this.reviewCount, required this.averageRating});

  factory RatingTotals.fromJson(Map<String, dynamic> json) => RatingTotals(
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    // Null with no reviews — never 0.
    averageRating: (json['averageRating'] as num?)?.toDouble(),
  );

  final int reviewCount;
  final double? averageRating;
}

/// §1f's rates as numbers. Nothing renders one as a label, and there is
/// deliberately nowhere to put one.
///
/// Every rate is a fraction in `[0, 1]`, or null — **null twice over**: below
/// the floor the server sends no metrics at all, and above it a single rate can
/// still be null where nothing has been measured (an on-time rate with no
/// arrival marks). Either way the screen shows "No data yet", never a zero.
@immutable
class PublicConduct {
  const PublicConduct({
    required this.jobsCompletedCount,
    required this.belowFloor,
    required this.medianResponseSeconds,
    this.completionRate,
    this.cancellationRate,
    this.noShowRate,
    this.onTimeRate,
    this.priceAdherenceRate,
  });

  factory PublicConduct.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'];
    double? rate(String key) => metrics is Map<String, dynamic>
        ? (metrics[key] as num?)?.toDouble()
        : null;
    return PublicConduct(
      jobsCompletedCount: (json['jobsCompletedCount'] as num?)?.toInt() ?? 0,
      belowFloor: json['metricsBelowFloor'] as bool? ?? true,
      medianResponseSeconds: metrics is Map<String, dynamic>
          ? (metrics['medianResponseSeconds'] as num?)?.toInt()
          : null,
      completionRate: rate('completionRate'),
      cancellationRate: rate('cancellationRate'),
      noShowRate: rate('noShowRate'),
      onTimeRate: rate('onTimeRate'),
      priceAdherenceRate: rate('priceAdherenceRate'),
    );
  }

  /// Lifetime completed jobs — the one figure that still shows below the floor.
  final int jobsCompletedCount;

  /// §1f: fewer than ten completed bookings in the 90-day window. The server
  /// decides, and it is a different question from [jobsCompletedCount] — a
  /// provider can have 47 lifetime jobs and nine this quarter.
  final bool belowFloor;
  final int? medianResponseSeconds;
  final double? completionRate;
  final double? cancellationRate;
  final double? noShowRate;
  final double? onTimeRate;
  final double? priceAdherenceRate;
}

@immutable
class PublicProvider {
  const PublicProvider({
    required this.id,
    required this.businessName,
    required this.bio,
    required this.yearsOfExperience,
    required this.tier,
    required this.maldivianOwned,
    required this.acceptingNewCustomers,
    required this.conduct,
    this.createdAt,
  });

  factory PublicProvider.fromJson(Map<String, dynamic> json) => PublicProvider(
    id: json['id'] as String,
    businessName: json['businessName'] as String?,
    bio: json['bio'] as String?,
    yearsOfExperience: (json['yearsOfExperience'] as num?)?.toInt(),
    tier: VerificationTier.parse(json['verificationTier'] as String?),
    maldivianOwned: json['maldivianOwned'] as bool?,
    acceptingNewCustomers: json['acceptingNewCustomers'] as bool? ?? true,
    conduct: PublicConduct.fromJson(
      json['conduct'] as Map<String, dynamic>? ?? const {},
    ),
    createdAt: json['createdAt'] is String
        ? DateTime.parse(json['createdAt'] as String)
        : null,
  );

  final String id;
  final String? businessName;
  final String? bio;
  final int? yearsOfExperience;
  final VerificationTier tier;

  /// §1g. `true` only where Gold review evidenced it; null below Gold, where
  /// the attribute is absent rather than false.
  final bool? maldivianOwned;
  final bool acceptingNewCustomers;
  final PublicConduct conduct;

  /// When the profile was created — "Provider since Mar 2026".
  final DateTime? createdAt;
}

/// 🔧 §Phase 13. One published service as a card prints it — the server's
/// `PublicListingCardDto`, a strict subset of the listing page's shape. It
/// carries **no provider**: on the profile every card is the page's provider,
/// and the card takes the name and tier from there.
@immutable
class PublicListingCard {
  const PublicListingCard({
    required this.id,
    required this.name,
    required this.category,
    required this.coverUrl,
    required this.pricing,
    required this.bookingMode,
    required this.secondSignal,
    required this.serviceAreas,
    required this.callbackGuarantee,
    required this.rating,
  });

  factory PublicListingCard.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'];
    return PublicListingCard(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      category: PublicCategory.fromJson(
        json['category'] as Map<String, dynamic>,
      ),
      coverUrl: cover is Map<String, dynamic> ? cover['url'] as String? : null,
      pricing: PublicPricing.fromJson(json['pricing'] as Map<String, dynamic>),
      bookingMode: BookingMode.parse(json['bookingMode'] as String?),
      secondSignal: SecondSignal.fromJson(
        json['secondSignal'] as Map<String, dynamic>,
      ),
      serviceAreas: (json['serviceAreas'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Island.fromJson)
          .toList(),
      callbackGuarantee: json['callbackGuarantee'] as bool? ?? false,
      rating: RatingTotals.fromJson(
        json['rating'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  final String id;
  final String name;
  final PublicCategory category;
  final String? coverUrl;
  final PublicPricing pricing;
  final BookingMode bookingMode;
  final SecondSignal secondSignal;
  final List<Island> serviceAreas;

  /// Offered on the listing AND the category is `callbackEligible` (Round 28)
  /// — the server decided; nothing here re-derives it from a category name.
  final bool callbackGuarantee;
  final RatingTotals rating;
}
