import 'package:flutter/foundation.dart';

import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/public/public_models.dart';

// 🔧 Phase 13 moved the shapes the provider profile shares — the provider, its
// conduct, the category, the pricing and the second signal — to
// `core/public/`. Re-exported so this feature's own imports read as before.
export 'package:raajjepro/core/public/public_models.dart';

/// §Phase 12's public listing read, as the client holds it.
///
/// **Nothing here has a field that could hold a phone number, an email or a
/// bank detail** — and that is the point rather than a convenience. The server
/// maps through DTOs with no such field (`public-listings/types.ts`), and this
/// side parses only what it names, so a value the server should never have sent
/// has nowhere to land even if it did (§1c, §Phase 12: "not for now, not
/// behind a flag").
///
/// Money is integer laari from the wire to the last widget (invariant 7).

@immutable
class PublicEmergency {
  const PublicEmergency({
    required this.available,
    required this.dispatchFeeLaari,
    required this.categoryId,
  });

  factory PublicEmergency.fromJson(Map<String, dynamic> json) =>
      PublicEmergency(
        available: json['available'] as bool? ?? false,
        dispatchFeeLaari: json['dispatchFeeLaari'] as int?,
        categoryId: json['categoryId'] as String?,
      );

  final bool available;
  final int? dispatchFeeLaari;
  final String? categoryId;
}

/// §1i's four self-declared fields. **Nothing here is verified by RaajjePro**,
/// and the screen prints each as the provider's own statement.
@immutable
class SelfDeclared {
  const SelfDeclared({this.warranty, this.insurance});

  factory SelfDeclared.fromJson(Map<String, dynamic> json) => SelfDeclared(
    warranty: (json['warrantyOffered'] as bool? ?? false)
        ? json['warrantyTermsText'] as String?
        : null,
    insurance: (json['insuranceDeclared'] as bool? ?? false)
        ? json['insuranceDetailText'] as String?
        : null,
  );

  final String? warranty;
  final String? insurance;

  List<String> get statements => [
    if (warranty != null && warranty!.trim().isNotEmpty) warranty!.trim(),
    if (insurance != null && insurance!.trim().isNotEmpty) insurance!.trim(),
  ];
}

@immutable
class Faq {
  const Faq({required this.question, required this.answer});

  factory Faq.fromJson(Map<String, dynamic> json) => Faq(
    question: json['question'] as String? ?? '',
    answer: json['answer'] as String? ?? '',
  );

  final String question;
  final String answer;
}

@immutable
class RatingSummary {
  const RatingSummary({
    required this.reviewCount,
    required this.averageRating,
    required this.starBreakdown,
    required this.tags,
  });

  factory RatingSummary.fromJson(Map<String, dynamic> json) {
    final breakdown = json['starBreakdown'];
    return RatingSummary(
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      // Null with no reviews — never 0, and never a star row of zeros.
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      starBreakdown: {
        for (var stars = 1; stars <= 5; stars++)
          stars: breakdown is Map<String, dynamic>
              ? (breakdown['$stars'] as num?)?.toInt() ?? 0
              : 0,
      },
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TagCount.fromJson)
          .toList(),
    );
  }

  final int reviewCount;
  final double? averageRating;

  /// Stars (1–5) → how many visible reviews gave that value.
  final Map<int, int> starBreakdown;

  /// Only tags three different customers applied (decision 32).
  final List<TagCount> tags;
}

@immutable
class PublicReview {
  const PublicReview({
    required this.rating,
    required this.body,
    required this.authorDisplayName,
    required this.createdAt,
  });

  factory PublicReview.fromJson(Map<String, dynamic> json) => PublicReview(
    rating: (json['rating'] as num).toInt(),
    body: json['body'] as String?,
    // Null once the author's account is anonymised; the screen supplies its
    // own placeholder and nothing about who wrote it.
    authorDisplayName: json['authorDisplayName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final int rating;
  final String? body;
  final String? authorDisplayName;
  final DateTime createdAt;
}

@immutable
class PublicListing {
  const PublicListing({
    required this.id,
    required this.name,
    required this.shortDescription,
    required this.longDescription,
    required this.category,
    required this.coverUrl,
    required this.galleryUrls,
    required this.pricing,
    required this.bookingMode,
    required this.secondSignal,
    required this.serviceAreas,
    required this.whatsIncluded,
    required this.whatsNotIncluded,
    required this.faqs,
    required this.selfDeclared,
    required this.callbackGuarantee,
    required this.emergency,
    required this.rating,
    required this.provider,
    required this.viewerIsOwner,
  });

  factory PublicListing.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'];
    return PublicListing(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      shortDescription: json['shortDescription'] as String?,
      longDescription: json['longDescription'] as String?,
      category: PublicCategory.fromJson(
        json['category'] as Map<String, dynamic>,
      ),
      coverUrl: cover is Map<String, dynamic> ? cover['url'] as String? : null,
      galleryUrls: (json['gallery'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((m) => m['url'] as String)
          .toList(),
      pricing: PublicPricing.fromJson(json['pricing'] as Map<String, dynamic>),
      bookingMode: BookingMode.parse(json['bookingMode'] as String?),
      secondSignal: SecondSignal.fromJson(
        json['secondSignal'] as Map<String, dynamic>,
      ),
      serviceAreas: (json['serviceAreas'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Island.fromJson)
          .toList(),
      whatsIncluded: _lines(json['whatsIncluded'] as String?),
      whatsNotIncluded: _lines(json['whatsNotIncluded'] as String?),
      faqs: (json['faqs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Faq.fromJson)
          .toList(),
      selfDeclared: SelfDeclared.fromJson(
        json['selfDeclared'] as Map<String, dynamic>? ?? const {},
      ),
      callbackGuarantee: json['callbackGuarantee'] as bool? ?? false,
      emergency: PublicEmergency.fromJson(
        json['emergency'] as Map<String, dynamic>? ?? const {},
      ),
      rating: RatingSummary.fromJson(json['rating'] as Map<String, dynamic>),
      provider: PublicProvider.fromJson(
        json['provider'] as Map<String, dynamic>,
      ),
      viewerIsOwner: json['viewerIsOwner'] as bool? ?? false,
    );
  }

  /// "What's included" is one text field the provider writes a line at a time.
  static List<String> _lines(String? text) => (text ?? '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final String id;
  final String name;
  final String? shortDescription;
  final String? longDescription;
  final PublicCategory category;
  final String? coverUrl;
  final List<String> galleryUrls;
  final PublicPricing pricing;
  final BookingMode bookingMode;
  final SecondSignal secondSignal;
  final List<Island> serviceAreas;
  final List<String> whatsIncluded;
  final List<String> whatsNotIncluded;
  final List<Faq> faqs;
  final SelfDeclared selfDeclared;

  /// Offered on the listing AND the category is `callbackEligible` (Round 28)
  /// — the server decided; nothing here re-derives it from a category name.
  final bool callbackGuarantee;
  final PublicEmergency emergency;
  final RatingSummary rating;
  final PublicProvider provider;

  /// The Edit control's one source. Never inferred client-side from ids.
  final bool viewerIsOwner;

  /// Hero first, then the rest, in the order the provider arranged them.
  List<String> get imageUrls => [?coverUrl, ...galleryUrls];

  /// The longer description where there is one, else the short one.
  String? get about => (longDescription?.trim().isNotEmpty ?? false)
      ? longDescription!.trim()
      : shortDescription;
}
