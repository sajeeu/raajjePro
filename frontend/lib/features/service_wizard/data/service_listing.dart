import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/domain/island.dart';

/// The seven steps of the Create/Edit Service Wizard (§Phase 9).
///
/// The names match §Phase 8's own ("Details, Location, Pricing, Media,
/// Availability, Extra Info, Meta"), because the server puts one on every
/// missing-field row so the review step's Fix link knows where to send the
/// provider.
enum WizardStep {
  details('details', 'Details'),
  location('location', 'Location'),
  pricing('pricing', 'Pricing'),
  media('media', 'Media'),
  availability('availability', 'Availability'),
  extras('extras', 'Extras'),
  review('review', 'Review');

  const WizardStep(this.wire, this.label);

  final String wire;
  final String label;

  /// 1-based, for "Step 3 of 7".
  int get number => index + 1;
  static int get count => WizardStep.values.length;

  /// A step named by the server. Only four can carry a required field, but an
  /// unknown name falls back to Details rather than throwing — a `Fix` link
  /// that lands on the wrong step is recoverable; a crash is not.
  static WizardStep parse(String? value) => WizardStep.values.firstWhere(
    (s) => s.wire == value,
    orElse: () => WizardStep.details,
  );
}

/// How the price is calculated (§Phase 8).
enum PricingModel {
  fixed('fixed', 'Fixed price', 'One rate per job'),
  hourly('hourly', 'Hourly rate', 'Charged per hour worked'),
  daily('daily', 'Daily rate', 'Charged per day'),
  range('range', 'Price range', 'A from–to estimate'),
  quote('quote', 'Price on request', 'You quote after they ask');

  const PricingModel(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  /// §Phase 8: `range` and `quote` **force request mode** — nobody can book a
  /// set time at an unknown price. The server enforces it on a published
  /// listing; the wizard renders the consequence while the draft is still
  /// being filled in.
  bool get forcesRequestMode =>
      this == PricingModel.range || this == PricingModel.quote;

  static PricingModel? parse(String? value) {
    for (final model in PricingModel.values) {
      if (model.wire == value) return model;
    }
    return null;
  }
}

/// What the customer reads after the number — "MVR 500/session".
enum PriceUnit {
  job('job', 'per job', '/job'),
  hour('hour', 'per hour', '/hr'),
  day('day', 'per day', '/day'),
  session('session', 'per session', '/session'),
  visit('visit', 'per visit', '/visit');

  const PriceUnit(this.wire, this.label, this.suffix);

  final String wire;
  final String label;
  final String suffix;

  static PriceUnit? parse(String? value) {
    for (final unit in PriceUnit.values) {
      if (unit.wire == value) return unit;
    }
    return null;
  }
}

/// Where a listing is in its life (§Phase 8).
enum ListingStatus {
  draft,
  published;

  static ListingStatus parse(String? value) =>
      value == 'published' ? ListingStatus.published : ListingStatus.draft;
}

/// §1b's four, of which only two are the provider's to set.
enum ListingVisibility {
  active('active'),
  hiddenByProvider('hidden_by_provider'),
  hiddenOverCap('hidden_over_cap'),
  hiddenByAdmin('hidden_by_admin');

  const ListingVisibility(this.wire);
  final String wire;

  static ListingVisibility parse(String? value) =>
      ListingVisibility.values.firstWhere(
        (v) => v.wire == value,
        orElse: () => ListingVisibility.active,
      );
}

/// A media row's own state. `pending` means an upload target was issued and no
/// bytes have arrived — the media step's "Uploading…" against its
/// "Upload failed · Retry", and the reason the publish gate treats a pending
/// cover as a missing one.
enum ListingMediaStatus {
  pending,
  stored;

  static ListingMediaStatus parse(String? value) => value == 'stored'
      ? ListingMediaStatus.stored
      : ListingMediaStatus.pending;
}

/// One image. [url] is a short-lived signed URL, re-issued on every read — so
/// it is never cached past the listing it belongs to, and it is null while the
/// row is `pending`.
class ListingMedia {
  const ListingMedia({
    required this.id,
    required this.status,
    required this.contentType,
    required this.byteSize,
    required this.url,
  });

  factory ListingMedia.fromJson(Map<String, dynamic> json) => ListingMedia(
    id: json['id'] as String,
    status: ListingMediaStatus.parse(json['status'] as String?),
    contentType: json['contentType'] as String? ?? '',
    byteSize: (json['byteSize'] as num?)?.toInt(),
    url: json['url'] as String?,
  );

  final String id;
  final ListingMediaStatus status;
  final String contentType;
  final int? byteSize;
  final String? url;

  bool get isStored => status == ListingMediaStatus.stored;
}

/// One question-and-answer pair from step 6.
class ListingFaq {
  const ListingFaq({required this.question, required this.answer});

  factory ListingFaq.fromJson(Map<String, dynamic> json) => ListingFaq(
    question: json['question'] as String? ?? '',
    answer: json['answer'] as String? ?? '',
  );

  final String question;
  final String answer;

  Map<String, Object?> toJson() => {'question': question, 'answer': answer};
}

/// §1i's four self-declared fields, grouped so nothing renders the text
/// without the flag that says whether it applies.
///
/// **RaajjePro checks neither claim and the UI must say so.** Rendered
/// attributed — "Provider states: 90-day workmanship warranty" — never with a
/// check mark, a shield, a lock or the word *verified*, and never inside the
/// callback guarantee's visual treatment. Those belong to `verificationTier`,
/// which means something because a human checked it.
class SelfDeclaredCover {
  const SelfDeclaredCover({
    required this.warrantyOffered,
    required this.warrantyTermsText,
    required this.insuranceDeclared,
    required this.insuranceDetailText,
  });

  factory SelfDeclaredCover.fromJson(Map<String, dynamic> json) =>
      SelfDeclaredCover(
        warrantyOffered: json['warrantyOffered'] as bool? ?? false,
        warrantyTermsText: json['warrantyTermsText'] as String?,
        insuranceDeclared: json['insuranceDeclared'] as bool? ?? false,
        insuranceDetailText: json['insuranceDetailText'] as String?,
      );

  final bool warrantyOffered;
  final String? warrantyTermsText;
  final bool insuranceDeclared;
  final String? insuranceDetailText;

  SelfDeclaredCover copyWith({
    bool? warrantyOffered,
    Object? warrantyTermsText = _keep,
    bool? insuranceDeclared,
    Object? insuranceDetailText = _keep,
  }) => SelfDeclaredCover(
    warrantyOffered: warrantyOffered ?? this.warrantyOffered,
    warrantyTermsText: warrantyTermsText == _keep
        ? this.warrantyTermsText
        : warrantyTermsText as String?,
    insuranceDeclared: insuranceDeclared ?? this.insuranceDeclared,
    insuranceDetailText: insuranceDetailText == _keep
        ? this.insuranceDetailText
        : insuranceDetailText as String?,
  );

  static const _keep = Object();
}

/// The **server's** answer to "may this listing advertise emergency work?".
///
/// Step 5 renders [reason] rather than recomputing the rule from the category
/// and the provider's tier. §1c composes four fields across three entities and
/// the backend owns that composition (invariant 4); a second copy here is how
/// a provider ends up staring at a disabled toggle whose stated reason is
/// wrong. Nothing in this app decides emergency eligibility.
class EmergencyAvailability {
  const EmergencyAvailability({
    required this.allowed,
    required this.reason,
    required this.requiredTier,
    required this.currentTier,
  });

  factory EmergencyAvailability.fromJson(Map<String, dynamic> json) =>
      EmergencyAvailability(
        allowed: json['allowed'] as bool? ?? false,
        reason: json['reason'] as String?,
        requiredTier: json['requiredTier'] as String?,
        currentTier: json['currentTier'] as String? ?? 'none',
      );

  final bool allowed;

  /// Null when allowed. Otherwise the server's own words, naming the bar and
  /// the current tier.
  final String? reason;

  /// The category's bar — `gold` for Electrical and Plumbing, `silver` for AC
  /// Repair and Moving. Never hardcoded anywhere in this app.
  final String? requiredTier;
  final String currentTier;
}

/// One required field a listing is still missing, as the server names it.
class MissingField {
  const MissingField({
    required this.field,
    required this.step,
    required this.message,
  });

  factory MissingField.fromJson(Map<String, dynamic> json) => MissingField(
    field: json['field'] as String? ?? '',
    step: WizardStep.parse(json['step'] as String?),
    message: json['message'] as String? ?? '',
  );

  final String field;
  final WizardStep step;

  /// Human-readable, and the label the review step renders.
  final String message;
}

/// The owner's view of their own listing — everything the wizard needs to
/// resume, and the publish gate's own answer.
///
/// Parsed from `GET|PATCH /v1/providers/me/listings/:id`. There is no public
/// listing shape here: §Phase 12's Service Preview and §Phase 15's search
/// define their own.
class ServiceListing {
  const ServiceListing({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.shortDescription,
    required this.longDescription,
    required this.tags,
    required this.serviceAreas,
    required this.pricingModel,
    required this.priceLaari,
    required this.priceMinLaari,
    required this.priceMaxLaari,
    required this.priceUnit,
    required this.coverMedia,
    required this.gallery,
    required this.bookingMode,
    required this.workingDays,
    required this.workingHoursFrom,
    required this.workingHoursTo,
    required this.isEmergency,
    required this.emergency,
    required this.whatsIncluded,
    required this.whatsNotIncluded,
    required this.faqs,
    required this.selfDeclared,
    required this.callbackGuaranteeOffered,
    required this.callbackAvailable,
    required this.status,
    required this.visibility,
    required this.missingRequiredFields,
    required this.requiredFieldCount,
  });

  factory ServiceListing.fromJson(Map<String, dynamic> json) => ServiceListing(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String?,
    name: json['name'] as String?,
    shortDescription: json['shortDescription'] as String?,
    longDescription: json['longDescription'] as String?,
    tags: _strings(json['tags']),
    serviceAreas: _list(json['serviceAreas'], Island.fromJson),
    pricingModel: PricingModel.parse(json['pricingModel'] as String?),
    priceLaari: (json['priceLaari'] as num?)?.toInt(),
    priceMinLaari: (json['priceMinLaari'] as num?)?.toInt(),
    priceMaxLaari: (json['priceMaxLaari'] as num?)?.toInt(),
    priceUnit: PriceUnit.parse(json['priceUnit'] as String?),
    coverMedia: json['coverMedia'] is Map<String, dynamic>
        ? ListingMedia.fromJson(json['coverMedia'] as Map<String, dynamic>)
        : null,
    gallery: _list(json['gallery'], ListingMedia.fromJson),
    bookingMode: json['bookingMode'] == null
        ? null
        : BookingMode.parse(json['bookingMode'] as String?),
    workingDays: _ints(json['workingDays']),
    workingHoursFrom: json['workingHoursFrom'] as String?,
    workingHoursTo: json['workingHoursTo'] as String?,
    isEmergency: json['isEmergency'] as bool? ?? false,
    emergency: EmergencyAvailability.fromJson(
      json['emergency'] as Map<String, dynamic>? ?? const {},
    ),
    whatsIncluded: json['whatsIncluded'] as String?,
    whatsNotIncluded: json['whatsNotIncluded'] as String?,
    faqs: _list(json['faqs'], ListingFaq.fromJson),
    selfDeclared: SelfDeclaredCover.fromJson(
      json['selfDeclared'] as Map<String, dynamic>? ?? const {},
    ),
    callbackGuaranteeOffered:
        json['callbackGuaranteeOffered'] as bool? ?? false,
    callbackAvailable: json['callbackAvailable'] as bool? ?? false,
    status: ListingStatus.parse(json['status'] as String?),
    visibility: ListingVisibility.parse(json['visibility'] as String?),
    missingRequiredFields: _list(
      json['missingRequiredFields'],
      MissingField.fromJson,
    ),
    // Six (§0.2 item 4 added the cover image). Read from the wire so the
    // denominator is the server's, not a constant that can drift from it.
    requiredFieldCount: (json['requiredFieldCount'] as num?)?.toInt() ?? 6,
  );

  final String id;
  final String? categoryId;

  // Step 1 — Details
  final String? name;
  final String? shortDescription;
  final String? longDescription;
  final List<String> tags;

  /// Step 2 — the listing's **own** areas, never the account-level default
  /// (ledger P7-3). `ProviderServiceArea` is what a fresh draft pre-fills
  /// from; this is what discovery matches on.
  final List<Island> serviceAreas;

  // Step 3 — Pricing. Integer laari throughout (invariant 7).
  final PricingModel? pricingModel;
  final int? priceLaari;
  final int? priceMinLaari;
  final int? priceMaxLaari;
  final PriceUnit? priceUnit;

  // Step 4 — Media
  final ListingMedia? coverMedia;
  final List<ListingMedia> gallery;

  // Step 5 — Availability
  final BookingMode? bookingMode;

  /// ISO weekday numbers, 1 = Monday.
  final List<int> workingDays;
  final String? workingHoursFrom;
  final String? workingHoursTo;
  final bool isEmergency;
  final EmergencyAvailability emergency;

  // Step 6 — Extra information
  final String? whatsIncluded;
  final String? whatsNotIncluded;
  final List<ListingFaq> faqs;
  final SelfDeclaredCover selfDeclared;
  final bool callbackGuaranteeOffered;

  /// Round 28. Where false the opt-in does not render **at all** — absent, not
  /// disabled — because a promise to redo a house move for free has no
  /// referent.
  final bool callbackAvailable;

  // Step 7 — Meta
  final ListingStatus status;
  final ListingVisibility visibility;

  /// The server's own list. Kept because a publish refusal is answered from
  /// it; the header's live counter is computed locally so it stays true while
  /// a save is still queued (invariant 4 — the client copy is for UX, the
  /// server's is the rule).
  final List<MissingField> missingRequiredFields;
  final int requiredFieldCount;

  bool get isPublished => status == ListingStatus.published;

  /// True where the cover exists **and its bytes actually arrived**. An
  /// abandoned upload is a missing cover, not a present one — which is the
  /// whole reason §0.2 item 4 made it required.
  bool get hasStoredCover => coverMedia?.isStored ?? false;

  ServiceListing copyWith({
    Object? categoryId = _keep,
    Object? name = _keep,
    Object? shortDescription = _keep,
    Object? longDescription = _keep,
    List<String>? tags,
    List<Island>? serviceAreas,
    Object? pricingModel = _keep,
    Object? priceLaari = _keep,
    Object? priceMinLaari = _keep,
    Object? priceMaxLaari = _keep,
    Object? priceUnit = _keep,
    Object? coverMedia = _keep,
    List<ListingMedia>? gallery,
    Object? bookingMode = _keep,
    List<int>? workingDays,
    Object? workingHoursFrom = _keep,
    Object? workingHoursTo = _keep,
    bool? isEmergency,
    EmergencyAvailability? emergency,
    Object? whatsIncluded = _keep,
    Object? whatsNotIncluded = _keep,
    List<ListingFaq>? faqs,
    SelfDeclaredCover? selfDeclared,
    bool? callbackGuaranteeOffered,
    bool? callbackAvailable,
    ListingStatus? status,
    ListingVisibility? visibility,
    List<MissingField>? missingRequiredFields,
  }) => ServiceListing(
    id: id,
    categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
    name: name == _keep ? this.name : name as String?,
    shortDescription: shortDescription == _keep
        ? this.shortDescription
        : shortDescription as String?,
    longDescription: longDescription == _keep
        ? this.longDescription
        : longDescription as String?,
    tags: tags ?? this.tags,
    serviceAreas: serviceAreas ?? this.serviceAreas,
    pricingModel: pricingModel == _keep
        ? this.pricingModel
        : pricingModel as PricingModel?,
    priceLaari: priceLaari == _keep ? this.priceLaari : priceLaari as int?,
    priceMinLaari: priceMinLaari == _keep
        ? this.priceMinLaari
        : priceMinLaari as int?,
    priceMaxLaari: priceMaxLaari == _keep
        ? this.priceMaxLaari
        : priceMaxLaari as int?,
    priceUnit: priceUnit == _keep ? this.priceUnit : priceUnit as PriceUnit?,
    coverMedia: coverMedia == _keep
        ? this.coverMedia
        : coverMedia as ListingMedia?,
    gallery: gallery ?? this.gallery,
    bookingMode: bookingMode == _keep
        ? this.bookingMode
        : bookingMode as BookingMode?,
    workingDays: workingDays ?? this.workingDays,
    workingHoursFrom: workingHoursFrom == _keep
        ? this.workingHoursFrom
        : workingHoursFrom as String?,
    workingHoursTo: workingHoursTo == _keep
        ? this.workingHoursTo
        : workingHoursTo as String?,
    isEmergency: isEmergency ?? this.isEmergency,
    emergency: emergency ?? this.emergency,
    whatsIncluded: whatsIncluded == _keep
        ? this.whatsIncluded
        : whatsIncluded as String?,
    whatsNotIncluded: whatsNotIncluded == _keep
        ? this.whatsNotIncluded
        : whatsNotIncluded as String?,
    faqs: faqs ?? this.faqs,
    selfDeclared: selfDeclared ?? this.selfDeclared,
    callbackGuaranteeOffered:
        callbackGuaranteeOffered ?? this.callbackGuaranteeOffered,
    callbackAvailable: callbackAvailable ?? this.callbackAvailable,
    status: status ?? this.status,
    visibility: visibility ?? this.visibility,
    missingRequiredFields: missingRequiredFields ?? this.missingRequiredFields,
    requiredFieldCount: requiredFieldCount,
  );

  static const _keep = Object();

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList(growable: false) : const [];

  static List<int> _ints(Object? raw) => raw is List
      ? raw.whereType<num>().map((n) => n.toInt()).toList(growable: false)
      : const [];

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) of) =>
      raw is List
      ? raw.whereType<Map<String, dynamic>>().map(of).toList(growable: false)
      : const [];
}
