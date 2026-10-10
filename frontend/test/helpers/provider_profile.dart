/// `GET /v1/providers/:id/public`, written as the server's wire shape rather
/// than built from the Dart models — a fixture made from the class under test
/// would not catch a field the API renamed.
///
/// Defaults to a Gold, Maldivian-owned provider above §1f's floor with two
/// published services. Every override is a named parameter so a test states
/// only what it is about.
Map<String, dynamic> providerProfileJson({
  String id = 'prov-1',
  String? businessName = 'Rasheed Plumbing Services',
  String tier = 'gold',
  bool? maldivianOwned = true,
  bool acceptingNewCustomers = true,
  bool metricsBelowFloor = false,
  int jobsCompleted = 47,
  int? medianResponseSeconds = 720,
  double? onTimeRate = 0.91,
  int reviewCount = 31,
  double? averageRating = 4.6,
  List<Map<String, dynamic>>? tags,
  List<Map<String, dynamic>>? listings,
  String createdAt = '2026-03-04T10:00:00.000Z',
}) => {
  'provider': {
    'id': id,
    'businessName': businessName,
    'bio': null,
    'yearsOfExperience': null,
    'verificationTier': tier,
    'maldivianOwned': maldivianOwned,
    'acceptingNewCustomers': acceptingNewCustomers,
    'conduct': {
      'jobsCompletedCount': jobsCompleted,
      'metricsBelowFloor': metricsBelowFloor,
      'metrics': metricsBelowFloor
          ? null
          : {
              'completionRate': 0.94,
              'cancellationRate': 0.03,
              'noShowRate': 0.02,
              'onTimeRate': onTimeRate,
              'priceAdherenceRate': 0.97,
              'acceptanceRate': 0.9,
              'medianResponseSeconds': medianResponseSeconds,
            },
    },
    'createdAt': createdAt,
  },
  'rating': {'reviewCount': reviewCount, 'averageRating': averageRating},
  'tags':
      tags ??
      [
        {
          'key': 'on_time',
          'label': 'On time',
          'sentiment': 'positive',
          'count': 26,
        },
        {
          'key': 'arrived_late',
          'label': 'Arrived late',
          'sentiment': 'negative',
          'count': 4,
        },
      ],
  'listings':
      listings ??
      [
        listingCardJson(
          // The server reads the card's response time from the same conduct
          // block, so below the floor it is absent here too.
          secondSignal: {
            'kind': 'response_time',
            'medianResponseSeconds': metricsBelowFloor
                ? null
                : medianResponseSeconds,
          },
        ),
        listingCardJson(
          id: 'listing-2',
          name: 'Bathroom & Kitchen Plumbing Installation',
          bookingMode: 'slot',
          pricingModel: 'daily',
          priceLaari: 90000,
          priceUnit: 'day',
          callbackGuarantee: false,
        ),
      ],
};

Map<String, dynamic> listingCardJson({
  String id = 'listing-1',
  String name = 'Pipe Repair & Leak Fixing',
  String categoryName = 'Plumbing',
  String bookingMode = 'request',
  String pricingModel = 'range',
  int? priceLaari,
  int? priceMinLaari = 35000,
  String? priceUnit,
  bool callbackGuarantee = true,
  Map<String, dynamic>? secondSignal,
  int reviewCount = 22,
  double? averageRating = 4.6,
}) => {
  'id': id,
  'name': name,
  'category': {
    'id': 'cat-plumbing',
    'name': categoryName,
    'iconIdentifier': 'droplet',
    'colorToken': 'emerald',
  },
  'cover': null,
  'pricing': {
    'model': pricingModel,
    'priceLaari': priceLaari,
    'priceMinLaari': priceMinLaari,
    'priceMaxLaari': null,
    'unit': priceUnit,
  },
  'bookingMode': bookingMode,
  'secondSignal':
      secondSignal ??
      (bookingMode == 'slot'
          ? {'kind': 'next_open', 'nextOpenAt': '2026-09-16T04:00:00.000Z'}
          : {'kind': 'response_time', 'medianResponseSeconds': 720}),
  'serviceAreas': [
    {
      'id': 'isl-1',
      'name': "Male'",
      'displayName': 'Malé',
      'atollName': 'Kaafu',
      'atollAbbr': 'K',
      'nameAmbiguous': false,
    },
  ],
  'callbackGuarantee': callbackGuarantee,
  'rating': {'reviewCount': reviewCount, 'averageRating': averageRating},
};
