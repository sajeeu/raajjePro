/// Category JSON shaped exactly as `GET /v1/categories` returns it.
Map<String, dynamic> categoryJson({
  required String id,
  required String name,
  String iconIdentifier = 'droplet',
  String colorToken = 'emerald',
  int sortOrder = 1,
  String bookingMode = 'request',
  bool emergencyCapable = false,
  int minimumLeadTimeMinutes = 60,
  int? emergencyAcceptWindowMinutes,
  String? emergencyMinimumTier,
  List<int> emergencyEtaPresetsMinutes = const [],
  int? quoteExpiryMinutes,
  int? quoteApprovalMinutes,
  bool callbackEligible = false,
  List<String> occasionPresets = const [],
}) => {
  'id': id,
  'name': name,
  'description': '$name services.',
  'iconIdentifier': iconIdentifier,
  'colorToken': colorToken,
  'sortOrder': sortOrder,
  'bookingMode': bookingMode,
  'emergencyCapable': emergencyCapable,
  'minimumLeadTimeMinutes': minimumLeadTimeMinutes,
  'emergencyAcceptWindowMinutes': emergencyAcceptWindowMinutes,
  'emergencyMinimumTier': emergencyMinimumTier,
  'emergencyEtaPresetsMinutes': emergencyEtaPresetsMinutes,
  'quoteExpiryMinutes': quoteExpiryMinutes,
  'quoteApprovalMinutes': quoteApprovalMinutes,
  'callbackEligible': callbackEligible,
  'occasionPresets': occasionPresets,
};

/// The seeded twelve, in seed order — the shape the real endpoint returns.
List<Map<String, dynamic>> seededTwelve() {
  const rows = [
    ('Cleaning', 'sparkle', 'indigo', 'slot'),
    ('Plumbing', 'droplet', 'emerald', 'request'),
    ('Electrical', 'bolt', 'amber', 'request'),
    ('AC Repair', 'wind', 'blue', 'request'),
    ('Beauty', 'heart', 'pink', 'slot'),
    ('Photography', 'camera', 'orange', 'request'),
    ('Pest Control', 'bug', 'green', 'request'),
    ('Appliance Repair', 'appliance', 'sky', 'request'),
    ('Moving', 'box', 'burntOrange', 'request'),
    ('Fitness', 'dumbbell', 'violet', 'slot'),
    ('Home Repairs', 'hammer', 'yellow', 'request'),
    ('Boat Charter', 'boat', 'cyan', 'request'),
  ];
  return [
    for (final (i, row) in rows.indexed)
      categoryJson(
        id: 'cat-${i + 1}',
        name: row.$1,
        iconIdentifier: row.$2,
        colorToken: row.$3,
        sortOrder: i + 1,
        bookingMode: row.$4,
        emergencyCapable: const {
          'Plumbing',
          'Electrical',
          'AC Repair',
          'Moving',
        }.contains(row.$1),
      ),
  ];
}
