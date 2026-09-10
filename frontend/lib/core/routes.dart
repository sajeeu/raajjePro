/// Route names that cross a feature boundary.
///
/// `lib/README.md`: no feature may import another feature; they meet in
/// `core/`. A route name is exactly that kind of meeting point — Explore's
/// header avatar and nav bar have to reach Profile and Sign in without
/// importing either feature, and Phase 6's Profile has to reach destinations
/// five other phases own.
///
/// Each screen still declares `static const routeName`, which is what
/// `app.dart` registers and what a screen's own tests use; where that name is
/// needed across a boundary it is **defined here and referenced there**, so
/// there is one string per route rather than two.
///
/// Added by Phase 6, with the names Phase 6 needs. A later phase that finds
/// itself importing a sibling feature for a route name should move that name
/// here rather than keep the import.
abstract final class AppRoutes {
  // Phase 3.
  static const signIn = '/sign-in';

  /// 🔧 **Added by Phase 6a**, which is the second feature to need it:
  /// §Phase 6a's account-details step blocks Continue on an unverified email
  /// and has to carry the way out of it. Pushed with the untyped
  /// `{'email': ..., 'purpose': ...}` arguments `VerifyEmailArgs` already
  /// accepts, so no feature has to import another's controller for the type.
  static const verifyEmail = '/verify-email';

  // Phase 6.
  static const profile = '/profile';
  static const accountSettings = '/account';
  static const legal = '/legal';
  static const saved = '/saved';
  static const savedPreferences = '/saved-preferences';
  static const help = '/help';

  // Phase 4.
  static const explore = '/explore';

  /// §Phase 6a's onboarding intro — a first switch into provider mode.
  static const becomeProvider = '/become-a-provider';

  /// §Phase 10's My Services Dashboard — every later switch.
  static const providerDashboard = '/provider/services';

  // Phase 6a.

  /// §Phase 9's Create/Edit Service Wizard, entered at step 1 on a fresh
  /// draft. §Phase 6a hands off here the moment onboarding finishes — "so the
  /// very next thing the provider does is describe their first service" — and
  /// the name is here rather than on the wizard's own screen because the
  /// screen does not exist yet and the handoff does.
  static const createService = '/services/new';
}
