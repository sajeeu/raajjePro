import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/features/saved_preferences/data/saved_preferences_api.dart';

// `retry: null`: the screen draws its own "Try again", and Riverpod 3's
// default retry would hide the error behind ~30 s of silent backoff
// (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// The whole of Saved Preferences — one read, three sections.
final savedPreferencesProvider = FutureProvider.autoDispose<SavedPreferences>(
  (ref) => ref.watch(savedPreferencesApiProvider).read(),
  retry: _noRetry,
);
