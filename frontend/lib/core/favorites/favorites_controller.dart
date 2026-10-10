import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/favorites/favorites_api.dart';

/// What this device knows about the signed-in customer's hearts.
///
/// A missing key is *unknown*, and renders as not saved until the status
/// lookup answers. [revision] moves on every save or unsave the server
/// accepted, so a screen that shows a count or a list of saved things —
/// Profile's row, the Saved screen — knows to read again.
@immutable
class FavoritesState {
  const FavoritesState({
    this.listings = const {},
    this.providers = const {},
    this.revision = 0,
  });

  final Map<String, bool> listings;
  final Map<String, bool> providers;
  final int revision;

  bool listingSaved(String id) => listings[id] ?? false;
  bool providerSaved(String id) => providers[id] ?? false;
}

enum FavoriteKind { listing, provider }

/// §Phase 14 — **one** saved state for the whole app, so the heart on a card,
/// the heart on the listing page and the Saved screen can never disagree
/// about the same service.
///
/// Every heart is optimistic: [set] flips the state at once, sends the write,
/// and on a refusal puts it back and returns false — the caller says so on
/// screen (`frontend/CLAUDE.md`: optimistic updates roll back visibly). Rapid
/// taps on one heart are resolved by the last one: an earlier call's failure
/// never undoes a later tap.
///
/// Scoped to the account. Signing out, or in as somebody else, starts from
/// nothing — the previous person's hearts must not stay red.
class FavoritesController extends Notifier<FavoritesState> {
  final _pendingListings = <String>{};
  final _pendingProviders = <String>{};
  bool _flushScheduled = false;
  final _generation = <(FavoriteKind, String), int>{};

  @override
  FavoritesState build() {
    ref.watch(
      authControllerProvider.select(
        (auth) => auth is AuthSignedIn ? auth.user.id : null,
      ),
    );
    _pendingListings.clear();
    _pendingProviders.clear();
    _generation.clear();
    return const FavoritesState();
  }

  bool get _signedIn => ref.read(authControllerProvider) is AuthSignedIn;

  /// Asks the server about any of these ids this device does not know yet.
  /// Every heart on a screen calls this as it appears; the requests made in
  /// one frame go out as one lookup.
  void ensure({
    Iterable<String> listingIds = const [],
    Iterable<String> providerIds = const [],
  }) {
    if (!_signedIn) return;
    _pendingListings.addAll(
      listingIds.where((id) => !state.listings.containsKey(id)),
    );
    _pendingProviders.addAll(
      providerIds.where((id) => !state.providers.containsKey(id)),
    );
    if (_flushScheduled ||
        (_pendingListings.isEmpty && _pendingProviders.isEmpty)) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final listings = _pendingListings.toList();
    final providers = _pendingProviders.toList();
    _pendingListings.clear();
    _pendingProviders.clear();

    const batch = FavoritesApi.statusBatch;
    for (var i = 0; i < listings.length || i < providers.length; i += batch) {
      final askListings = listings.skip(i).take(batch).toList();
      final askProviders = providers.skip(i).take(batch).toList();
      try {
        final saved = await ref
            .read(favoritesApiProvider)
            .status(listingIds: askListings, providerIds: askProviders);
        if (!ref.mounted) return;
        // A tap that landed while the lookup was in flight is newer than the
        // lookup's answer, so only still-unknown ids are filled in.
        state = FavoritesState(
          listings: {
            for (final id in askListings) id: saved.listingIds.contains(id),
            ...state.listings,
          },
          providers: {
            for (final id in askProviders) id: saved.providerIds.contains(id),
            ...state.providers,
          },
          revision: state.revision,
        );
      } on Object {
        // Left unknown, so the hearts read as not saved and the next screen
        // asks again. A heart is never worth an error state of its own.
      }
    }
  }

  /// What the Saved screen just read from the server is saved — for every id
  /// this device knew nothing about. A known state wins: a list read that was
  /// already in flight when the customer unsaved something must not turn the
  /// heart red again.
  void markSaved({
    Iterable<String> listingIds = const [],
    Iterable<String> providerIds = const [],
  }) {
    state = FavoritesState(
      listings: {for (final id in listingIds) id: true, ...state.listings},
      providers: {for (final id in providerIds) id: true, ...state.providers},
      revision: state.revision,
    );
  }

  /// Saves or unsaves one thing. Returns false when the server refused and
  /// the heart was put back.
  Future<bool> set(FavoriteKind kind, String id, {required bool saved}) async {
    final key = (kind, id);
    final generation = (_generation[key] ?? 0) + 1;
    _generation[key] = generation;
    final previous = _read(kind, id);

    _write(kind, id, saved);
    try {
      final api = ref.read(favoritesApiProvider);
      await switch (kind) {
        FavoriteKind.listing => api.setListing(id, saved: saved),
        FavoriteKind.provider => api.setProvider(id, saved: saved),
      };
      if (!ref.mounted) return true;
      state = FavoritesState(
        listings: state.listings,
        providers: state.providers,
        revision: state.revision + 1,
      );
      return true;
    } on Object {
      if (!ref.mounted) return false;
      // Only the latest tap on this heart may roll it back.
      if (_generation[key] == generation) _write(kind, id, previous);
      return false;
    }
  }

  bool _read(FavoriteKind kind, String id) => switch (kind) {
    FavoriteKind.listing => state.listingSaved(id),
    FavoriteKind.provider => state.providerSaved(id),
  };

  void _write(FavoriteKind kind, String id, bool saved) {
    state = FavoritesState(
      listings: kind == FavoriteKind.listing
          ? {...state.listings, id: saved}
          : state.listings,
      providers: kind == FavoriteKind.provider
          ? {...state.providers, id: saved}
          : state.providers,
      revision: state.revision,
    );
  }
}

final favoritesProvider = NotifierProvider<FavoritesController, FavoritesState>(
  FavoritesController.new,
);
