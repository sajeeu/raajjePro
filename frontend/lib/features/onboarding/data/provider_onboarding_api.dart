import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/island.dart';

/// The provider's own profile, as much of it as §Phase 6a needs
/// (`GET /v1/providers/me`).
///
/// **Not the whole `OwnProviderDto`.** The conduct block, the tier and the
/// subscription price are all on the wire and none of them belongs to this
/// flow; a model that parsed them would invite a screen to render one. Phase
/// 10's dashboard is where those get a home.
///
/// **No phone number, because the endpoint carries none.** §Phase 5 stores
/// exactly one and it is on the account, read through `AuthController`. The
/// phone this flow shows and edits is that one.
class ProviderOnboardingState {
  const ProviderOnboardingState({
    required this.businessName,
    required this.providerType,
    required this.bio,
    required this.bankName,
    required this.bankAccountName,
    required this.bankAccountNumber,
    required this.acceptingNewCustomers,
    required this.serviceAreas,
    required this.onboardingComplete,
  });

  /// What a brand-new account looks like before it has a provider profile:
  /// `GET /v1/providers/me` answers `PROVIDER_PROFILE_NOT_FOUND` and the flow
  /// starts from nothing. Not an error — it is the expected first read.
  const ProviderOnboardingState.blank()
    : businessName = null,
      providerType = null,
      bio = null,
      bankName = null,
      bankAccountName = null,
      bankAccountNumber = null,
      acceptingNewCustomers = true,
      serviceAreas = const [],
      onboardingComplete = false;

  factory ProviderOnboardingState.fromJson(Map<String, dynamic> json) {
    final payment = json['paymentDetails'] as Map<String, dynamic>? ?? const {};
    final areas = json['serviceAreas'];
    return ProviderOnboardingState(
      businessName: json['businessName'] as String?,
      providerType: ProviderType.fromWire(json['providerType'] as String?),
      bio: json['bio'] as String?,
      bankName: payment['bankName'] as String?,
      bankAccountName: payment['bankAccountName'] as String?,
      bankAccountNumber: payment['bankAccountNumber'] as String?,
      // §Phase 6a defaults the toggle on. The server's value wins wherever it
      // has one; the default only covers a payload that predates the field.
      acceptingNewCustomers: json['acceptingNewCustomers'] as bool? ?? true,
      serviceAreas: areas is List
          ? List.unmodifiable(
              areas.whereType<Map<String, dynamic>>().map(Island.fromJson),
            )
          : const [],
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    );
  }

  final String? businessName;
  final ProviderType? providerType;
  final String? bio;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final bool acceptingNewCustomers;

  /// §Phase 7's account-level default coverage — step 3's answer.
  final List<Island> serviceAreas;

  /// The server's derived answer to "is this flow finished?"
  /// (`backend/src/modules/providers/onboarding.ts`). Never recomputed here:
  /// it folds in the verified email and the required-field list, and a second
  /// copy of that rule would drift.
  final bool onboardingComplete;
}

/// §Phase 6a's `providerType` — "How will you offer services?".
///
/// Not cosmetic, and the copy on each option says why: §1e reads it to decide
/// whether Gold verification asks for personal ID or business registration
/// documents, and §1g's Maldivian-owned *business* attribute hangs from it.
enum ProviderType {
  individual('individual'),
  business('business');

  const ProviderType(this.wire);

  /// The value the API uses. Never the enum name by coincidence — the wire
  /// contract is stated rather than inferred.
  final String wire;

  /// An unknown value reads as null rather than throwing: the API is
  /// additive-only and a third type added later must not crash an installed
  /// app (`docs/api/versioning.md`).
  static ProviderType? fromWire(String? value) {
    for (final type in ProviderType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// §Phase 6a's account-details step, as one request body.
class AccountDetailsDraft {
  const AccountDetailsDraft({
    required this.businessName,
    required this.providerType,
    required this.bio,
    required this.bankName,
    required this.bankAccountName,
    required this.bankAccountNumber,
    required this.acceptingNewCustomers,
  });

  final String businessName;
  final ProviderType providerType;

  /// Optional in §Phase 6a. Empty clears it, which is a real edit.
  final String bio;
  final String bankName;
  final String bankAccountName;
  final String bankAccountNumber;
  final bool acceptingNewCustomers;

  Map<String, Object?> toJson() => {
    'businessName': businessName,
    'providerType': providerType.wire,
    'bio': bio.isEmpty ? null : bio,
    'bankName': bankName,
    'bankAccountName': bankAccountName,
    'bankAccountNumber': bankAccountNumber,
    'acceptingNewCustomers': acceptingNewCustomers,
  };
}

/// Everything the step holds, exactly as typed. **Unvalidated on purpose** —
/// `ProviderOnboardingController` owns every rule, including "you have not
/// chosen a type yet", so there is one validator rather than one here and one
/// there. It is also why `providerType` is nullable in this record and not in
/// [AccountDetailsDraft]: the draft is what goes on the wire, and it cannot
/// be built until the choice exists.
typedef AccountDetailsInput = ({
  String businessName,
  ProviderType? providerType,
  String bio,
  String bankName,
  String bankAccountName,
  String bankAccountNumber,
  bool acceptingNewCustomers,
  String dialCode,
  String phoneNumber,
  bool phoneChanged,
});

/// §Phase 6a's calls. **There are no new endpoints here** — §Phase 6a says
/// "reuse Phase 5's existing update endpoint, do not create a parallel one",
/// and step 3 reuses §Phase 7's service-area routes. The phone is the one
/// field that does not go through `PATCH /v1/providers/me`: there is no phone
/// column on `ProviderProfile` and §Phase 5's single-copy rule keeps it that
/// way, so it routes to Phase 3's `PATCH /v1/users/me/phone` through
/// `AuthApi` (`docs/decisions/17-phase-5-provider-profiles.md`).
class ProviderOnboardingApi {
  const ProviderOnboardingApi(this._api);
  final ApiClient _api;

  /// The current profile, or null where the account has none yet.
  ///
  /// A 404 is the expected answer for a customer opening this flow, not a
  /// failure — the read deliberately does not create the profile
  /// (§Phase 5, decision 11), so a first-time user gets one and starts from
  /// blank. Any other error propagates, because it means something else.
  Future<ProviderOnboardingState?> read() async {
    try {
      return ProviderOnboardingState.fromJson(
        await _api.get('/v1/providers/me'),
      );
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') return null;
      rethrow;
    }
  }

  /// Step 2. Creates the provider profile as a side effect — §1a's
  /// implicit-creation moment, and the reason there is no separate "start
  /// onboarding" call.
  Future<ProviderOnboardingState> saveAccountDetails(
    AccountDetailsDraft draft,
  ) async => ProviderOnboardingState.fromJson(
    await _api.patch('/v1/providers/me', body: draft.toJson()),
  );

  /// Step 3. Both writes return the resulting list in full, so the picker's
  /// view is exact after every change without a second read (§Phase 7).
  Future<List<Island>> addServiceArea(String islandId) async => _islands(
    await _api.post(
      '/v1/providers/me/service-areas',
      body: {'islandId': islandId},
    ),
  );

  Future<List<Island>> removeServiceArea(String islandId) async =>
      _islands(await _api.delete('/v1/providers/me/service-areas/$islandId'));

  List<Island> _islands(Map<String, dynamic> response) {
    final data = response['_list'];
    if (data is! List) return const [];
    return List.unmodifiable(
      data.whereType<Map<String, dynamic>>().map(Island.fromJson),
    );
  }
}

final providerOnboardingApiProvider = Provider<ProviderOnboardingApi>(
  (ref) => ProviderOnboardingApi(ref.watch(apiClientProvider)),
);
