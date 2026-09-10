/// The shape `GET /v1/users/me/profile-summary` returns — every field the
/// server's `profileSummaryDto` carries and no field it does not.
Map<String, dynamic> profileSummaryJson({
  String id = 'user-1',
  String fullName = 'Aishath Naeema',
  String memberSince = '2026-01-14T08:30:00.000Z',
  bool isProvider = false,
  bool providerOnboardingComplete = false,
}) => {
  'id': id,
  'fullName': fullName,
  'memberSince': memberSince,
  'isProvider': isProvider,
  // §Phase 6a's signal, and what the role switcher routes on. Separate from
  // `isProvider` because they are different moments — see `role_switch.dart`.
  'providerOnboardingComplete': providerOnboardingComplete,
};
