import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/island.dart';

/// The provider's **account-level** default coverage (§Phase 7), read for one
/// purpose: pre-filling a brand-new listing's step 2.
///
/// **It is not a listing's service areas** (ledger P7-3). §Phase 6a's step 3
/// collects this once; a listing carries its own set, and that set — never
/// this one — is what discovery matches on. The two live in different tables
/// and neither write touches the other. This provider exists so §Phase 9 can
/// read the default without importing §Phase 6a's feature, which
/// `lib/README.md` forbids: features meet in `core/`.
///
/// It reads the one field it needs out of `GET /v1/providers/me` rather than
/// modelling the whole provider profile. The conduct block, the tier and the
/// subscription price are all on that response and none of them belongs to
/// the wizard; §Phase 10's dashboard is where those get a home.
class AccountServiceAreasApi {
  const AccountServiceAreasApi(this._api);
  final ApiClient _api;

  /// The default islands, or an empty list.
  ///
  /// A provider with no profile yet answers `PROVIDER_PROFILE_NOT_FOUND`, and
  /// that is the expected reply for someone who reached the wizard without
  /// going through onboarding (§1a's implicit path). Empty, not an error —
  /// there is simply nothing to pre-fill from.
  Future<List<Island>> read() async {
    try {
      final response = await _api.get('/v1/providers/me');
      final areas = response['serviceAreas'];
      if (areas is! List) return const [];
      return List.unmodifiable(
        areas.whereType<Map<String, dynamic>>().map(Island.fromJson),
      );
    } on ApiException catch (e) {
      if (e.code == 'PROVIDER_PROFILE_NOT_FOUND') return const [];
      rethrow;
    }
  }
}

final accountServiceAreasApiProvider = Provider<AccountServiceAreasApi>(
  (ref) => AccountServiceAreasApi(ref.watch(apiClientProvider)),
);
