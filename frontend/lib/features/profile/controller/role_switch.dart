import 'package:raajjepro/core/routes.dart';

/// Where "Switch to providing" goes — §Phase 6's last Done-when line, as one
/// function.
///
/// > switching to provider mode for the first time reaches the onboarding
/// > flow, and reaches My Services Dashboard directly on every subsequent
/// > switch.
///
/// 🔧 **The signal changed in Phase 6a, and `isProvider` was not enough.**
///
/// It was `isProvider` — `providerProfile !== null` on the server — and that
/// answered "first switch or later switch" only if the two moments were the
/// same. They are not. Onboarding's step 2 *is* §1a's profile-creation
/// moment, so `isProvider` flips one step before the flow ends: a provider
/// who closed the app on step 3 read as a returning provider and was sent to
/// a dashboard, never seeing the step they stopped on. §Phase 6a requires the
/// opposite — *"a provider who abandons onboarding after step 1 or 2 … and
/// returns later resumes from wherever they left off"* — and it is *"a
/// provider who already **completed** onboarding"* who never sees the flow
/// again.
///
/// So the signal is now `providerOnboardingComplete`, from the same one
/// `profile-summary` call: derived server-side from what §Phase 6a's three
/// steps collect plus the verified email §Phase 5 requires to finish
/// (`backend/src/modules/providers/onboarding.ts`). §Phase 6's own wording,
/// "a returning provider goes straight to My Services Dashboard", reads the
/// same way — someone mid-flow has not returned yet.
///
/// `isProvider` is unchanged and still on the wire; it answers a different
/// question (does a profile exist) that §Phase 5's implicit creation path and
/// §Phase 8's wizard fallback both care about.
///
/// The dashboard route still lands on [UnbuiltScreen] until §Phase 10 builds
/// it; the onboarding route is real as of Phase 6a.
abstract final class RoleSwitch {
  /// §Phase 6a's onboarding flow. A first switch — and a resumed one — lands
  /// here, never on the wizard directly (§Phase 6a's own Done-when).
  static const onboardingRoute = AppRoutes.becomeProvider;

  /// §Phase 10's My Services Dashboard. Every switch after onboarding is
  /// finished lands here.
  static const dashboardRoute = AppRoutes.providerDashboard;

  static String destinationFor({required bool onboardingComplete}) =>
      onboardingComplete ? dashboardRoute : onboardingRoute;
}
