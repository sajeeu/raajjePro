/// `GET /v1/listings/:id/public`, written as the server's wire shape rather than
/// built from the Dart models — a fixture made from the class under test would
/// not catch a field the API renamed.
///
/// Defaults to a published slot listing with a Silver provider above §1f's
/// floor. Every override is a named parameter so a test states only what it is
/// about.
Map<String, dynamic> publicListingJson({
  String id = 'listing-1',
  String name = 'Home Deep Cleaning',
  String categoryName = 'Cleaning',
  String colorToken = 'indigo',
  String bookingMode = 'slot',
  String pricingModel = 'fixed',
  int? priceLaari = 45000,
  int? priceMinLaari,
  int? priceMaxLaari,
  String? priceUnit = 'session',
  Map<String, dynamic>? secondSignal,
  bool viewerIsOwner = false,
  bool callbackGuarantee = false,
  bool emergencyAvailable = false,
  String? businessName = 'Mariyam Shifa',
  String tier = 'silver',
  bool acceptingNewCustomers = true,
  bool metricsBelowFloor = false,
  int jobsCompleted = 86,
  int? medianResponseSeconds = 720,
  bool warrantyOffered = true,
  String? warrantyText = '90-day workmanship warranty',
  bool insuranceDeclared = true,
  String? insuranceText = 'public liability insurance held',
  List<Map<String, dynamic>>? faqs,
  Map<String, dynamic>? rating,
  List<Map<String, dynamic>> gallery = const [],
}) => {
  'id': id,
  'name': name,
  'shortDescription': 'Deep cleaning for apartments.',
  'longDescription':
      'Full deep cleaning for apartments and small offices in Malé.',
  'tags': <String>[],
  'category': {
    'id': 'cat-1',
    'name': categoryName,
    'iconIdentifier': 'sparkle',
    'colorToken': colorToken,
  },
  'cover': {'id': 'm1', 'url': 'https://media.test/cover.jpg'},
  'gallery': gallery,
  'pricing': {
    'model': pricingModel,
    'priceLaari': priceLaari,
    'priceMinLaari': priceMinLaari,
    'priceMaxLaari': priceMaxLaari,
    'unit': priceUnit,
  },
  'bookingMode': bookingMode,
  'secondSignal':
      secondSignal ??
      (bookingMode == 'slot'
          ? {'kind': 'next_open', 'nextOpenAt': '2026-09-16T04:00:00.000Z'}
          : {
              'kind': 'response_time',
              'medianResponseSeconds': metricsBelowFloor
                  ? null
                  : medianResponseSeconds,
            }),
  'serviceAreas': [
    {
      'id': 'isl-1',
      'name': "Male'",
      'displayName': 'Malé',
      'atollName': 'Kaafu',
      'atollAbbr': 'K',
      'nameAmbiguous': false,
    },
    {
      'id': 'isl-2',
      'name': 'Meedhoo',
      'displayName': 'Dh. Meedhoo',
      'atollName': 'Dhaalu',
      'atollAbbr': 'Dh',
      'nameAmbiguous': true,
    },
  ],
  'whatsIncluded': 'All cleaning supplies\nKitchen deep clean',
  'whatsNotIncluded': null,
  'faqs':
      faqs ??
      [
        {
          'question': 'How long does a session take?',
          'answer': '2–4 hours for a typical two-bedroom apartment.',
        },
      ],
  'selfDeclared': {
    'warrantyOffered': warrantyOffered,
    'warrantyTermsText': warrantyOffered ? warrantyText : null,
    'insuranceDeclared': insuranceDeclared,
    'insuranceDetailText': insuranceDeclared ? insuranceText : null,
  },
  'callbackGuarantee': callbackGuarantee,
  'emergency': {
    'available': emergencyAvailable,
    'dispatchFeeLaari': emergencyAvailable ? 20000 : null,
    'categoryId': emergencyAvailable ? 'cat-1' : null,
  },
  'rating':
      rating ??
      {
        'reviewCount': 24,
        'averageRating': 4.8,
        'starBreakdown': {'1': 0, '2': 0, '3': 1, '4': 3, '5': 20},
        'tags': [
          {
            'key': 'on_time',
            'label': 'On time',
            'sentiment': 'positive',
            'count': 19,
          },
        ],
      },
  'provider': {
    'id': 'prov-1',
    'businessName': businessName,
    'bio': null,
    'yearsOfExperience': null,
    'verificationTier': tier,
    'maldivianOwned': null,
    'acceptingNewCustomers': acceptingNewCustomers,
    'conduct': {
      'jobsCompletedCount': jobsCompleted,
      'metricsBelowFloor': metricsBelowFloor,
      'metrics': metricsBelowFloor
          ? null
          : {
              'completionRate': 0.97,
              'cancellationRate': 0.01,
              'noShowRate': 0,
              'onTimeRate': null,
              'priceAdherenceRate': 0.99,
              'acceptanceRate': 0.95,
              'medianResponseSeconds': medianResponseSeconds,
            },
    },
    'createdAt': '2026-06-01T00:00:00.000Z',
  },
  'viewerIsOwner': viewerIsOwner,
};

Map<String, dynamic> reviewJson({
  int rating = 5,
  String? body = 'Spotless, and on time.',
  String? author = 'Aishath N.',
  String createdAt = '2026-09-01T08:00:00.000Z',
}) => {
  'id': 'rev-${body.hashCode}',
  'bookingId': 'b1',
  'listingId': 'listing-1',
  'rating': rating,
  'body': body,
  'tags': <Map<String, dynamic>>[],
  'authorDisplayName': author,
  'createdAt': createdAt,
};
