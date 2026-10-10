import 'fake_api.dart';
import 'provider_profile.dart';

/// A [FakeApiClient] that also plays §Phase 14's favourites endpoints, the
/// way the server does: `PUT` saves, `DELETE` unsaves, both idempotent, and
/// the status lookup answers from what is saved. A test that wants a write to
/// fail scripts that exact call with [fail] or [offline], which wins.
class FavoritesFakeApi extends FakeApiClient {
  final savedListings = <String>{};
  final savedProviders = <String>{};

  static const _base = '/v1/users/me/favorites';

  /// Every favourites write, in order: `PUT listings/listing-1`.
  List<String> get writes => [
    for (final c in calls)
      if ((c.method == 'PUT' || c.method == 'DELETE') &&
          c.path.startsWith('$_base/'))
        '${c.method} ${c.path.substring(_base.length + 1)}',
  ];

  @override
  Future<Map<String, dynamic>> get(String path) {
    if (path.startsWith('$_base/status?') &&
        !handlers.containsKey('GET $path')) {
      calls.add((method: 'GET', path: path, body: null));
      final query = Uri.parse(path).queryParameters;
      List<String> ids(String key) =>
          (query[key] ?? '').split(',').where((s) => s.isNotEmpty).toList();
      return Future.value({
        'listingIds': ids('listingIds').where(savedListings.contains).toList(),
        'providerIds': ids('providerIds')
            .where(savedProviders.contains)
            .toList(),
      });
    }
    return super.get(path);
  }

  @override
  Future<Map<String, dynamic>> put(String path, {Object? body}) =>
      _write('PUT', path) ?? super.put(path, body: body);

  @override
  Future<Map<String, dynamic>> delete(String path) =>
      _write('DELETE', path) ?? super.delete(path);

  Future<Map<String, dynamic>>? _write(String method, String path) {
    if (!path.startsWith('$_base/') || handlers.containsKey('$method $path')) {
      return null;
    }
    calls.add((method: method, path: path, body: null));
    final parts = path.substring(_base.length + 1).split('/');
    final set = parts.first == 'listings' ? savedListings : savedProviders;
    final saved = method == 'PUT';
    if (saved) {
      set.add(parts.last);
    } else {
      set.remove(parts.last);
    }
    return Future.value({'saved': saved});
  }
}

/// One `GET /v1/users/me/favorites/listings` item, in the server's wire shape.
Map<String, dynamic> savedServiceJson({
  String listingId = 'listing-1',
  String name = 'Pipe Repair & Leak Fixing',
  String providerId = 'prov-1',
  String businessName = 'Rasheed Plumbing Services',
  String tier = 'gold',
}) {
  final provider =
      providerProfileJson(
            id: providerId,
            businessName: businessName,
            tier: tier,
          )['provider']
          as Map<String, dynamic>;
  return {
    'savedAt': '2026-09-15T03:00:00.000Z',
    'listing': listingCardJson(id: listingId, name: name),
    'provider': provider,
  };
}

/// One `GET /v1/users/me/favorites/providers` item, in the server's wire shape.
Map<String, dynamic> savedProviderJson({
  String providerId = 'prov-2',
  String businessName = 'Lens & Light Studio',
  String tier = 'silver',
  int reviewCount = 58,
  double? averageRating = 4.9,
  List<String> categories = const ['Photography'],
}) {
  final provider =
      providerProfileJson(
            id: providerId,
            businessName: businessName,
            tier: tier,
          )['provider']
          as Map<String, dynamic>;
  return {
    'savedAt': '2026-09-15T03:00:00.000Z',
    'provider': provider,
    'rating': {'reviewCount': reviewCount, 'averageRating': averageRating},
    'categories': [
      for (final name in categories)
        {
          'id': 'cat-$name',
          'name': name,
          'iconIdentifier': 'camera',
          'colorToken': 'indigo',
        },
    ],
  };
}

/// Scripts the Saved screen's two reads.
void scriptSaved(
  FakeApiClient api, {
  List<Map<String, dynamic>> services = const [],
  List<Map<String, dynamic>> providers = const [],
}) {
  api
    ..on(
      'GET',
      '/v1/users/me/favorites/listings?limit=50',
      (_) => {'_list': services},
    )
    ..on(
      'GET',
      '/v1/users/me/favorites/providers?limit=50',
      (_) => {'_list': providers},
    );
}
