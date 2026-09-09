import 'package:raajjepro/core/routes.dart';

/// Where "Switch to providing" goes — §Phase 6's last Done-when line, as one
/// function.
///
/// > switching to provider mode for the first time reaches the onboarding
/// > flow, and reaches My Services Dashboard directly on every subsequent
/// > switch.
///
/// The signal is `isProvider` from the profile summary, which is
/// `providerProfile !== null` on the server. It answers the question with no
/// extra request and it is trustworthy because a provider-profile *read* no
/// longer creates the row — §Phase 5 moved creation onto the write precisely
/// so that opening a screen cannot turn a customer into a provider
/// (`docs/decisions/17-phase-5-provider-profiles.md`, decision 11). A 404
/// from `GET /v1/providers/me` now answers `PROVIDER_PROFILE_NOT_FOUND` and
/// would say the same thing, but it costs a round trip to learn what the
/// screen already knows.
///
/// Both destinations are real named routes today and both land on
/// [UnbuiltScreen] until their phases build them. The decision — which route,
/// on which signal — is Phase 6's and is tested here and now; the screens
/// behind it are not.
abstract final class RoleSwitch {
  /// §Phase 6a's onboarding intro. A first switch lands here, never on the
  /// wizard directly (§Phase 6a's own Done-when).
  static const onboardingRoute = AppRoutes.becomeProvider;

  /// §Phase 10's My Services Dashboard. Every later switch lands here.
  static const dashboardRoute = AppRoutes.providerDashboard;

  static String destinationFor({required bool isProvider}) =>
      isProvider ? dashboardRoute : onboardingRoute;
}
