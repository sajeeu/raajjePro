import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/verification_tier.dart';

/// The two account-level facts the My Services dashboard renders around the
/// listings themselves (§Phase 10).
///
/// **This is not the whole `OwnProviderDto`, deliberately.** §Phase 6a's
/// onboarding parses a different subset of the same endpoint and says in its
/// own note that "Phase 10's dashboard is where the tier and the subscription
/// price get a home". Two narrow models of one endpoint, each parsing what
/// its screen renders, is the shape this codebase already has; a shared model
/// carrying every field would invite a screen to render one it has no
/// business showing — the payment details, most obviously.
class ProviderWorkspace {
  const ProviderWorkspace({
    required this.verificationTier,
    required this.businessName,
    required this.suspended,
  });

  /// What a user who has no provider profile looks like. The role switcher
  /// only sends a provider who completed onboarding here, so this is the
  /// unreachable-in-practice case rather than the ordinary one — but a 404
  /// here is an answer, not a failure, exactly as it is in §Phase 6a's read.
  const ProviderWorkspace.blank()
    : verificationTier = VerificationTier.none,
      businessName = null,
      suspended = false;

  factory ProviderWorkspace.fromJson(Map<String, dynamic> json) =>
      ProviderWorkspace(
        // §1e: the tier is what the badge renders. `verificationStatus` is on
        // the same payload and is deliberately **not** parsed — it is the
        // review state of a pending submission, a different axis, and a model
        // that carried both would eventually have a screen conflate them.
        verificationTier: VerificationTier.parse(
          json['verificationTier'] as String?,
        ),
        businessName: json['businessName'] as String?,
        suspended: json['suspended'] as bool? ?? false,
      );

  /// §1e, and §Phase 10's own bullet: the badge reflects this and nothing
  /// else. Not the subscription, not `verificationStatus`, not whether the
  /// provider has any listing live.
  final VerificationTier verificationTier;

  /// Null on an individual provider who never gave one — the dashboard falls
  /// back to the account's own name.
  final String? businessName;

  /// §1a: an input to visibility and §Phase 10b's action. Read here so that
  /// nothing on this screen can claim a suspended provider's listings are
  /// reaching customers.
  final bool suspended;
}

/// The one number §1b's over-cap copy needs: how many listings this
/// provider's current entitlement lets them keep live.
///
/// Read from `GET /v1/providers/me/subscription` (§Phase 8a) rather than
/// assumed to be 1. The free cap is 1 today and the endpoint is the only
/// thing that knows it; a hardcoded "1 live service" would be wrong the first
/// time the cap moves, on a card whose whole job is explaining a limit.
class EntitlementCap {
  const EntitlementCap(this.activeListingCap);

  /// 🔧 **Null means no limit, never unknown** — §Phase 8a's own note: premium
  /// unlocks multiple active listings and names no number.
  final int? activeListingCap;

  bool get isUnlimited => activeListingCap == null;
}

/// Typed reads for the dashboard. No rule lives here — which listings are
/// hidden over the cap is the server's answer, already on each listing's
/// `visibility`; this call only supplies the number the explanation names.
class ProviderWorkspaceApi {
  const ProviderWorkspaceApi(this._api);

  final ApiClient _api;

  /// A 404 is an answer: the read deliberately does not create a provider
  /// profile (§Phase 5), so a user without one reads as blank rather than as
  /// a broken screen. Any other error propagates.
  Future<ProviderWorkspace> read() async {
    try {
      return ProviderWorkspace.fromJson(await _api.get('/v1/providers/me'));
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') {
        return const ProviderWorkspace.blank();
      }
      rethrow;
    }
  }

  Future<EntitlementCap> cap() async {
    try {
      final response = await _api.get('/v1/providers/me/subscription');
      final entitlements =
          response['entitlements'] as Map<String, dynamic>? ?? const {};
      return EntitlementCap(
        (entitlements['activeListingCap'] as num?)?.toInt(),
      );
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') {
        return const EntitlementCap(1);
      }
      rethrow;
    }
  }
}

final providerWorkspaceApiProvider = Provider<ProviderWorkspaceApi>(
  (ref) => ProviderWorkspaceApi(ref.watch(apiClientProvider)),
);
