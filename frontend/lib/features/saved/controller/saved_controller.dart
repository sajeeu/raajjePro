import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/favorites/favorites_controller.dart';
import 'package:raajjepro/features/saved/data/saved_api.dart';

// `retry: null`. Riverpod 3 auto-retries a failed `build()` with exponential
// backoff for ~30s before the screen's own error branch is reached, which
// fights the explicit "Try again" this screen provides (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Everything the Saved screen read, both lists behind one skeleton.
@immutable
class SavedLists {
  const SavedLists({required this.services, required this.providers});

  final List<SavedService> services;
  final List<SavedProvider> providers;
}

/// §Phase 14's Saved screen.
///
/// "Reflects it immediately" is held two ways. An **unsave** — here or on any
/// other screen — removes the row at once, because the screen filters what it
/// read through the app's one saved state (`favoritesProvider`). A **save**
/// made elsewhere while this screen sits in the stack has nothing to show
/// until the server is asked, so every accepted write re-reads the lists,
/// quietly, keeping what is on screen until the answer lands.
final savedProvider = AsyncNotifierProvider<SavedController, SavedLists>(
  SavedController.new,
  isAutoDispose: true,
  retry: _noRetry,
);

class SavedController extends AsyncNotifier<SavedLists> {
  @override
  Future<SavedLists> build() async {
    ref.listen(favoritesProvider.select((s) => s.revision), (previous, next) {
      if (previous != next) refreshQuietly();
    });
    return _read();
  }

  Future<SavedLists> _read() async {
    final api = ref.read(savedApiProvider);
    final (services, providers) = await (api.services(), api.providers()).wait;
    // What the server just listed is saved, so every heart drawn from it is
    // red without a second lookup.
    ref
        .read(favoritesProvider.notifier)
        .markSaved(
          listingIds: services.map((s) => s.listing.id),
          providerIds: providers.map((p) => p.provider.id),
        );
    return SavedLists(services: services, providers: providers);
  }

  /// The error state's retry.
  Future<void> reload() async {
    state = const AsyncLoading<SavedLists>();
    state = await AsyncValue.guard(_read);
  }

  /// A re-read that keeps the current lists on screen. A failure leaves them
  /// as they were — the next write or visit tries again.
  Future<void> refreshQuietly() async {
    try {
      final next = await _read();
      if (ref.mounted) state = AsyncData(next);
    } on Object {
      // Keep what is shown.
    }
  }
}
