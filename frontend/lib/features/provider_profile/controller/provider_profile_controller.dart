import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/features/provider_profile/data/provider_profile_api.dart';

// `retry: null`. Riverpod 3 auto-retries a failed `build()` with exponential
// backoff for ~30s before the screen's own error branch is reached, which
// fights the explicit "Try again" this screen provides (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

final providerProfileProvider =
    AsyncNotifierProvider.family<
      ProviderProfileController,
      PublicProviderProfile,
      String
    >(ProviderProfileController.new, isAutoDispose: true, retry: _noRetry);

class ProviderProfileController extends AsyncNotifier<PublicProviderProfile> {
  ProviderProfileController(this.providerId);

  final String providerId;

  @override
  Future<PublicProviderProfile> build() =>
      ref.read(providerProfileApiProvider).read(providerId);

  /// The error state's retry.
  Future<void> reload() async {
    state = const AsyncLoading<PublicProviderProfile>();
    state = await AsyncValue.guard(build);
  }
}

/// Whether [error] is the server saying this provider is not public — no
/// published listing, suspended, or an id that never existed, all one 404 (§1a)
/// — as distinct from the connection dropping.
bool isProviderUnavailable(Object error) =>
    error is ApiException && error.status == 404;
