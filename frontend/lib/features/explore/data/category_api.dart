import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/domain/category.dart';

/// `GET /v1/categories` (§Phase 4).
///
/// Public: a signed-out guest gets the same list, which is what lets Explore
/// render before anyone has an account. The order is the endpoint's own
/// `sortOrder` and is not re-sorted here — the grid draws what it is given.
class CategoryApi {
  const CategoryApi(this._client);
  final ApiClient _client;

  /// The catalogue is unlimited (§Phase 4) so the endpoint pages, and this
  /// follows `meta.nextCursor` to the end. The seeded twelve arrive in one
  /// page and the loop runs once; the loop exists so that a hundredth
  /// category does not silently vanish off the bottom of the grid.
  ///
  /// [_maxPages] bounds it: a server bug that returned the same cursor
  /// forever would otherwise hang the screen on its loading state with no
  /// error to show.
  static const int _maxPages = 20;

  Future<List<ServiceCategory>> list() async {
    final all = <ServiceCategory>[];
    String? cursor;
    for (var page = 0; page < _maxPages; page++) {
      final query = cursor == null
          ? ''
          : '?cursor=${Uri.encodeQueryComponent(cursor)}';
      final response = await _client.get('/v1/categories$query');
      final data = response['data'];
      if (data is! List) break;
      all.addAll(
        data.whereType<Map<String, dynamic>>().map(ServiceCategory.fromJson),
      );
      final meta = response['meta'];
      cursor = meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null;
      if (cursor == null) break;
    }
    return List.unmodifiable(all);
  }
}

final categoryApiProvider = Provider<CategoryApi>(
  (ref) => CategoryApi(ref.watch(apiClientProvider)),
);
