/// The shape `GET /v1/users/me/profile-summary` returns — every field the
/// server's `profileSummaryDto` carries and no field it does not.
Map<String, dynamic> profileSummaryJson({
  String id = 'user-1',
  String fullName = 'Aishath Naeema',
  String memberSince = '2026-01-14T08:30:00.000Z',
  bool isProvider = false,
}) => {
  'id': id,
  'fullName': fullName,
  'memberSince': memberSince,
  'isProvider': isProvider,
};
