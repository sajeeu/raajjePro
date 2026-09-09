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
}
