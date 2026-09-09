import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/features/profile/data/profile_api.dart';

// `retry: null`. Riverpod 3 auto-retries a failed `build()` with exponential
// backoff for ~30s before the screen's own error branch is ever reached,
// which fights the explicit "Try again" this screen provides and leaves a
// pending Timer past test teardown (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// `isAutoDispose: true`, which matters here rather than being a default
/// worth keeping. A plain `AsyncNotifierProvider` lives as long as the
/// `ProviderScope` — the whole app — so the summary would outlive the account
/// it describes: sign out, sign in as someone else, open Profile, and the
/// previous person's name is on screen and the role switcher is routing on
/// their `isProvider`. Disposing when nothing is watching also makes
/// §Phase 6's "reflects live data" true on the second visit, not just the
/// first.
final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, ProfileSummary>(
      ProfileController.new,
      isAutoDispose: true,
      retry: _noRetry,
    );

/// The Profile screen's one read (§Phase 6: "one call for the Profile screen").
class ProfileController extends AsyncNotifier<ProfileSummary> {
  @override
  Future<ProfileSummary> build() => ref.read(profileApiProvider).summary();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
