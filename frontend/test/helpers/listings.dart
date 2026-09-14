/// Category and listing JSON shaped exactly as the API returns it — the
/// category DTO from `GET /v1/categories` (§Phase 4, §Phase 8) and the owner's
/// listing from `/v1/providers/me/listings` (§Phase 8).
///
/// Spelled out rather than computed, so a fixture cannot accidentally agree
/// with a client-side copy of a rule the client must not have: the emergency
/// verdict, the callback availability and the required-field list are all the
/// **server's** answers, and a test that derived them here would be testing
/// its own arithmetic.
library;

Map<String, dynamic> categoryJson({
  required String id,
  required String name,
  String iconIdentifier = 'sparkle',
  String colorToken = 'indigo',
  int sortOrder = 0,
  String bookingMode = 'request',
  bool emergencyCapable = false,
  int? emergencyAcceptWindowMinutes,
  String? emergencyMinimumTier,
  bool callbackEligible = false,
  List<String> suggestedTags = const [],
}) => {
  'id': id,
  'name': name,
  'description': '$name services',
  'iconIdentifier': iconIdentifier,
  'colorToken': colorToken,
  'sortOrder': sortOrder,
  'bookingMode': bookingMode,
  'emergencyCapable': emergencyCapable,
  'minimumLeadTimeMinutes': 120,
  'emergencyAcceptWindowMinutes': emergencyAcceptWindowMinutes,
  'emergencyMinimumTier': emergencyMinimumTier,
  'emergencyEtaPresetsMinutes': const <int>[],
  'quoteExpiryMinutes': 120,
  'quoteApprovalMinutes': 240,
  'callbackEligible': callbackEligible,
  'occasionPresets': const <String>[],
  'suggestedTags': suggestedTags,
};

/// A slice of the real catalogue, chosen for what it exercises: a Gold-gated
/// emergency category, a Silver-gated one, a callback-ineligible one, and the
/// two the step-1 name guidance singles out.
List<Map<String, dynamic>> sampleCategories() => [
  categoryJson(
    id: 'cat-electrical',
    name: 'Electrical',
    iconIdentifier: 'bolt',
    colorToken: 'amber',
    sortOrder: 1,
    emergencyCapable: true,
    emergencyAcceptWindowMinutes: 30,
    emergencyMinimumTier: 'gold',
    callbackEligible: true,
    suggestedTags: const ['Wiring', 'Fault finding', 'Rewiring', 'Lighting'],
  ),
  categoryJson(
    id: 'cat-ac',
    name: 'AC Repair',
    iconIdentifier: 'wind',
    colorToken: 'blue',
    sortOrder: 2,
    emergencyCapable: true,
    emergencyAcceptWindowMinutes: 30,
    emergencyMinimumTier: 'silver',
    callbackEligible: true,
    suggestedTags: const ['Servicing', 'Gas refill'],
  ),
  categoryJson(
    id: 'cat-cleaning',
    name: 'Cleaning',
    sortOrder: 3,
    bookingMode: 'slot',
    suggestedTags: const ['Deep cleaning', 'Move-out'],
  ),
  categoryJson(
    id: 'cat-photography',
    name: 'Photography',
    iconIdentifier: 'camera',
    colorToken: 'orange',
    sortOrder: 4,
    suggestedTags: const ['Weddings', 'Portraits'],
  ),
  categoryJson(
    id: 'cat-boat',
    name: 'Boat Charter',
    iconIdentifier: 'boat',
    colorToken: 'cyan',
    sortOrder: 5,
    suggestedTags: const ['Fishing trips'],
  ),
];

Map<String, dynamic> mediaJson({
  required String id,
  String status = 'stored',
  String? url = 'https://media.example/one.jpg',
}) => {
  'id': id,
  'status': status,
  'contentType': 'image/jpeg',
  'byteSize': status == 'stored' ? 2048 : null,
  'url': status == 'stored' ? url : null,
};

/// The six required fields, as `publish.ts` names them. Passed in rather than
/// derived: this is the server's list and the test states it.
const List<Map<String, dynamic>> allSixMissing = [
  {'field': 'name', 'step': 'details', 'message': 'Service name'},
  {'field': 'categoryId', 'step': 'details', 'message': 'Category'},
  {
    'field': 'shortDescription',
    'step': 'details',
    'message': 'Short description',
  },
  {
    'field': 'serviceAreaIslandIds',
    'step': 'location',
    'message': 'At least one island',
  },
  {
    'field': 'pricingModel',
    'step': 'pricing',
    'message': 'How the price works',
  },
  {'field': 'coverMediaId', 'step': 'media', 'message': 'Cover image'},
];

Map<String, dynamic> listingJson({
  String id = 'listing-1',
  String? categoryId,
  String? name,
  String? shortDescription,
  String? longDescription,
  List<String> tags = const [],
  List<Map<String, dynamic>> serviceAreas = const [],
  String? pricingModel,
  int? priceLaari,
  int? priceMinLaari,
  int? priceMaxLaari,
  String? priceUnit,
  Map<String, dynamic>? coverMedia,
  List<Map<String, dynamic>> gallery = const [],
  String? bookingMode,
  List<int> workingDays = const [],
  String? workingHoursFrom,
  String? workingHoursTo,
  bool isEmergency = false,
  bool emergencyAllowed = false,
  String? emergencyReason = 'Choose a category first',
  String? emergencyRequiredTier,
  String emergencyCurrentTier = 'none',
  String? whatsIncluded,
  String? whatsNotIncluded,
  List<Map<String, dynamic>> faqs = const [],
  bool warrantyOffered = false,
  String? warrantyTermsText,
  bool insuranceDeclared = false,
  String? insuranceDetailText,
  bool callbackGuaranteeOffered = false,
  bool callbackAvailable = false,
  String status = 'draft',
  String visibility = 'active',
  List<Map<String, dynamic>> missingRequiredFields = allSixMissing,
}) => {
  'id': id,
  'providerProfileId': 'provider-1',
  'categoryId': categoryId,
  'name': name,
  'shortDescription': shortDescription,
  'longDescription': longDescription,
  'tags': tags,
  'serviceAreas': serviceAreas,
  'pricingModel': pricingModel,
  'priceLaari': priceLaari,
  'priceMinLaari': priceMinLaari,
  'priceMaxLaari': priceMaxLaari,
  'priceUnit': priceUnit,
  'coverMedia': coverMedia,
  'gallery': gallery,
  'bookingMode': bookingMode,
  'workingDays': workingDays,
  'workingHoursFrom': workingHoursFrom,
  'workingHoursTo': workingHoursTo,
  'isEmergency': isEmergency,
  'emergency': {
    'allowed': emergencyAllowed,
    'reason': emergencyAllowed ? null : emergencyReason,
    'requiredTier': emergencyRequiredTier,
    'currentTier': emergencyCurrentTier,
  },
  'whatsIncluded': whatsIncluded,
  'whatsNotIncluded': whatsNotIncluded,
  'faqs': faqs,
  'selfDeclared': {
    'warrantyOffered': warrantyOffered,
    'warrantyTermsText': warrantyTermsText,
    'insuranceDeclared': insuranceDeclared,
    'insuranceDetailText': insuranceDetailText,
  },
  'callbackGuaranteeOffered': callbackGuaranteeOffered,
  'callbackAvailable': callbackAvailable,
  'status': status,
  'visibility': visibility,
  'publishedAt': null,
  'firstPublishedAt': null,
  'missingRequiredFields': missingRequiredFields,
  'requiredFieldCount': 6,
  'viewCount': 0,
  'bookingCount': 0,
  'createdAt': '2026-09-14T06:00:00.000Z',
  'updatedAt': '2026-09-14T06:00:00.000Z',
};

/// A draft with all six required fields filled — what the review step calls
/// "Ready to publish".
Map<String, dynamic> publishableListingJson({
  String id = 'listing-1',
  String categoryId = 'cat-electrical',
  List<Map<String, dynamic>>? serviceAreas,
  bool callbackAvailable = true,
  bool emergencyAllowed = false,
  String? emergencyReason =
      'Emergency Electrical work needs gold verification; this account is '
      'silver',
  String status = 'draft',
}) => listingJson(
  id: id,
  categoryId: categoryId,
  name: 'Wiring & Fault Repair',
  shortDescription: 'Fault finding, rewiring and new installations.',
  serviceAreas:
      serviceAreas ??
      [
        {
          'id': 'i-male',
          'name': "Male'",
          'displayName': "Male'",
          'atollName': 'Kaafu',
          'atollAbbr': 'K',
          'nameAmbiguous': false,
        },
      ],
  pricingModel: 'fixed',
  priceLaari: 45000,
  priceUnit: 'visit',
  coverMedia: mediaJson(id: 'media-cover'),
  bookingMode: 'request',
  workingDays: const [1, 2, 3, 4, 5],
  workingHoursFrom: '08:00',
  workingHoursTo: '18:00',
  emergencyAllowed: emergencyAllowed,
  emergencyReason: emergencyReason,
  emergencyRequiredTier: 'gold',
  emergencyCurrentTier: 'silver',
  callbackAvailable: callbackAvailable,
  status: status,
  missingRequiredFields: const [],
);
