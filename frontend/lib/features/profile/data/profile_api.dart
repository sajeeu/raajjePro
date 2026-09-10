import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';

/// What the Profile screen renders (`GET /v1/users/me/profile-summary`,
/// plan §Phase 6).
///
/// Deliberately thin, and the server's shape decides that rather than this
/// class: `backend/src/modules/account/dto.ts` records why there is no phone
/// number, no avatar, no island and no saved/booking counts here. Phases 14
/// and 17 add their counts to the same call, additively.
class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.fullName,
    required this.memberSince,
    required this.isProvider,
    required this.providerOnboardingComplete,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) => ProfileSummary(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    memberSince: DateTime.parse(json['memberSince'] as String),
    isProvider: json['isProvider'] as bool,
    // Absent on a response that predates §Phase 6a, and false is the right
    // reading of that: nobody had completed a flow that did not exist.
    providerOnboardingComplete:
        json['providerOnboardingComplete'] as bool? ?? false,
  );

  final String id;
  final String fullName;
  final DateTime memberSince;

  /// Whether this account already has a Provider Profile. Not what the role
  /// switcher routes on any more — see [providerOnboardingComplete] — but
  /// still the answer to "is there a profile", which §1a's implicit creation
  /// path and §Phase 8's wizard fallback both turn on.
  final bool isProvider;

  /// 🔧 **§Phase 6a's signal, and what the role switcher routes on.** Derived
  /// server-side from what onboarding's three steps collect plus the verified
  /// email §Phase 5 requires to finish, and never stored
  /// (`backend/src/modules/providers/onboarding.ts`). It is a different
  /// question from [isProvider], which flips at step 2 —
  /// `RoleSwitch.destinationFor` explains why the distinction matters.
  final bool providerOnboardingComplete;
}

/// Typed calls for the Profile screen. No rule lives here; the server decides.
class ProfileApi {
  const ProfileApi(this._api);
  final ApiClient _api;

  Future<ProfileSummary> summary() async =>
      ProfileSummary.fromJson(await _api.get('/v1/users/me/profile-summary'));

  /// `PATCH /v1/users/me`. Built because §Phase 6 names it; no screen calls
  /// it yet, because neither `Profile_customer.jpg` nor `Profile.dc.html`
  /// carries a name-edit control — recorded in
  /// `docs/decisions/18-phase-6-customer-profile.md`, decision 3.
  Future<void> updateName(String fullName) async {
    await _api.patch('/v1/users/me', body: {'fullName': fullName});
  }
}

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(apiClientProvider)),
);
