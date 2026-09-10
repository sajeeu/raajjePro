import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/location/island_api.dart';

// Riverpod 3's exponential-backoff auto-retry is off for the same reason the
// categories controller turns it off: the list offers an explicit "Try again",
// and a silent background retry fights it and outlives the test.
Duration? _noRetry(int retryCount, Object error) => null;

/// Island search results for one query (§Phase 7, §0.0 item 12).
///
/// Keyed on the query so that a customer spelling out "Kulhudhuffushi" and
/// then backspacing gets the earlier answer from the cache instead of a second
/// round trip. `autoDispose` keeps that cache from growing for the life of the
/// app — a search box can produce a lot of distinct keys.
///
/// The **server** ranks and filters. Nothing here re-sorts or trims the list:
/// a client-side second opinion on which islands match is exactly the drift
/// §0.0 item 12 exists to prevent, and it would also be the only place a cap
/// could creep back in.
final islandSearchProvider = FutureProvider.autoDispose
    .family<List<Island>, String>(
      (ref, query) => ref.watch(islandApiProvider).search(query),
      retry: _noRetry,
    );
