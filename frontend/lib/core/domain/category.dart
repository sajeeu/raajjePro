/// How a listing in this category is booked (plan §1c). Defaulted by category
/// and overridable per listing.
///
/// The mode is a closed set; the **catalogue is not**. Nothing in this app
/// enumerates category names — §Phase 4's Done-when requires a thirteenth
/// category added through the API to reach Explore with no rebuild, so a
/// category is only ever whatever `GET /v1/categories` returned.
enum BookingMode {
  /// The customer picks from times the provider published.
  slot,

  /// The customer asks; the provider comes back with a time and a price.
  request;

  /// Anything unknown reads as `request`, which is the mode that asks the
  /// provider before anything is committed — the safe reading of a mode this
  /// build has never heard of.
  static BookingMode parse(String? value) =>
      value == 'slot' ? BookingMode.slot : BookingMode.request;

  /// The card affordance (§1c, Round 44). "Pick a time", never "Book
  /// instantly" — picking a published slot still creates a `requested`
  /// booking the provider has to accept.
  String get affordance => switch (this) {
    BookingMode.slot => 'Pick a time',
    BookingMode.request => 'Request a time',
  };
}

/// One row of the category catalogue, exactly as `GET /v1/categories` gave it.
///
/// Every per-category number the plan seeds travels on this object so that no
/// screen ever hardcodes one: the emergency tier bar (§1c), the quote windows
/// (invariant 13), the callback flag (Round 28), the lead time and the preset
/// lists. Phase 4 itself renders only the first handful; the rest are carried
/// because the alternative — each later phase fetching or, worse, inlining its
/// own copy — is exactly the drift the plan warns about.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.iconIdentifier,
    required this.colorToken,
    required this.sortOrder,
    required this.bookingMode,
    required this.emergencyCapable,
    required this.minimumLeadTimeMinutes,
    required this.emergencyAcceptWindowMinutes,
    required this.emergencyMinimumTier,
    required this.emergencyEtaPresetsMinutes,
    required this.quoteExpiryMinutes,
    required this.quoteApprovalMinutes,
    required this.callbackEligible,
    required this.occasionPresets,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) =>
      ServiceCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        iconIdentifier: json['iconIdentifier'] as String? ?? '',
        colorToken: json['colorToken'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        bookingMode: BookingMode.parse(json['bookingMode'] as String?),
        emergencyCapable: json['emergencyCapable'] as bool? ?? false,
        minimumLeadTimeMinutes:
            (json['minimumLeadTimeMinutes'] as num?)?.toInt() ?? 0,
        emergencyAcceptWindowMinutes:
            (json['emergencyAcceptWindowMinutes'] as num?)?.toInt(),
        emergencyMinimumTier: json['emergencyMinimumTier'] as String?,
        emergencyEtaPresetsMinutes: _ints(json['emergencyEtaPresetsMinutes']),
        quoteExpiryMinutes: (json['quoteExpiryMinutes'] as num?)?.toInt(),
        quoteApprovalMinutes: (json['quoteApprovalMinutes'] as num?)?.toInt(),
        callbackEligible: json['callbackEligible'] as bool? ?? false,
        occasionPresets: _strings(json['occasionPresets']),
      );

  final String id;
  final String name;
  final String description;

  /// A glyph name resolved by `CategoryIcons`; an unknown one falls back.
  final String iconIdentifier;

  /// A design-system accent token resolved by `CategoryAccents`; likewise.
  final String colorToken;
  final int sortOrder;
  final BookingMode bookingMode;

  /// One half of §1c's composed emergency rule. Never rendered as a marker on
  /// a card or offered as a search filter — Round 23 removed both, because
  /// dispatch broadcasts and never targets a provider.
  final bool emergencyCapable;

  final int minimumLeadTimeMinutes;

  /// How long a provider may take to *answer* an emergency broadcast. Arrival
  /// is per-offer and self-declared, and is not this.
  final int? emergencyAcceptWindowMinutes;

  /// `bronze` / `silver` / `gold`, or null where the category is not capable.
  /// Kept as the wire string: this app never gates on it — the backend does —
  /// and parsing it into `VerificationTier` here would invite a client-side
  /// re-implementation of a server-side rule.
  final String? emergencyMinimumTier;

  final List<int> emergencyEtaPresetsMinutes;
  final int? quoteExpiryMinutes;
  final int? quoteApprovalMinutes;

  /// Round 28. Where false, the wizard's opt-in does not render at all —
  /// absent, not disabled — and no badge appears on any card.
  final bool callbackEligible;

  final List<String> occasionPresets;

  static List<int> _ints(Object? raw) => raw is List
      ? raw.whereType<num>().map((n) => n.toInt()).toList(growable: false)
      : const [];

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList(growable: false) : const [];
}
