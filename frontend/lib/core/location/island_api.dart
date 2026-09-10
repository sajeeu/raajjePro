import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/island.dart';

/// `GET /v1/islands?search=` (§Phase 7).
///
/// Public: a signed-out guest picks a browsing island from the header before
/// they have an account, so this carries no token requirement.
///
/// **Unpaged, on purpose.** §0.0 item 12 requires every match with no cap and
/// no "show more" — truncating hides the one island the customer came for —
/// and the register is a closed 192 rows. There is deliberately no cursor loop
/// here like `CategoryApi.list`'s, because there is no cursor to follow.
class IslandApi {
  const IslandApi(this._client);
  final ApiClient _client;

  /// Every island matching [query], ranked by the server: prefix matches
  /// first, then by name. An empty query is the whole register, which is what
  /// the picker shows before anyone types.
  ///
  /// The query is sent as typed. Case, accents and the Dhivehi apostrophe are
  /// folded server-side (§0.0 item 12), and folding them here as well would be
  /// a second implementation of a matching rule that must not drift.
  Future<List<Island>> search(String query) async {
    final trimmed = query.trim();
    final url = trimmed.isEmpty
        ? '/v1/islands'
        : '/v1/islands?search=${Uri.encodeQueryComponent(trimmed)}';
    final response = await _client.get(url);
    // `ApiClient` unwraps the envelope: a list payload arrives as `_list`.
    final data = response['_list'];
    if (data is! List) return const [];
    return List.unmodifiable(
      data.whereType<Map<String, dynamic>>().map(Island.fromJson),
    );
  }
}

final islandApiProvider = Provider<IslandApi>(
  (ref) => IslandApi(ref.watch(apiClientProvider)),
);
