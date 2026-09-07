import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/api/api_config.dart';
import 'package:raajjepro/core/auth/auth_api.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return HttpApiClient(
    http: ref.watch(httpClientProvider),
    baseUrl: ApiConfig.baseUrl,
    readAccessToken: () async => (await store.read())?.accessToken,
    refreshTokens: () => ref.read(authControllerProvider.notifier).tryRefresh(),
    onSessionExpired: () async =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The one auth state the root widget switches on (spec §8). Tokens live in
/// [TokenStore]; the user comes from `/v1/auth/me` and is refreshed in the
/// background on restore so a verification or freeze done elsewhere shows.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();

  AuthApi get _api => ref.read(authApiProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  Future<String> _deviceName() async {
    try {
      return await ref.read(deviceNameProvider.future);
    } on Object {
      return 'Unknown device';
    }
  }

  Future<void> restore() async {
    final tokens = await _store.read();
    if (tokens == null) {
      state = const AuthGuest();
      return;
    }
    await refreshUser();
  }

  /// Re-reads `me`. A dead session becomes [AuthSessionExpired]; a network
  /// failure keeps whatever state we had — offline is not signed out.
  Future<void> refreshUser() async {
    try {
      state = AuthSignedIn(await _api.me());
    } on ApiException catch (e) {
      if (e.code == 'SESSION_EXPIRED' || e.code == 'UNAUTHENTICATED') {
        await sessionExpired();
      }
    } on ApiNetworkException {
      if (state is AuthUnknown) state = const AuthGuest();
    }
  }

  Future<void> signIn(String email, String password) async {
    final result = await _api.login(email, password, await _deviceName());
    await _store.write(result.tokens);
    state = AuthSignedIn(result.user);
  }

  Future<VerificationOutcome> register(RegisterRequest request) async {
    final result = await _api.register(
      request,
      idempotencyKey: _idempotencyKey(),
    );
    await _store.write(result.tokens);
    state = AuthSignedIn(result.user);
    return result.verification;
  }

  Future<bool> tryRefresh() async {
    final tokens = await _store.read();
    if (tokens == null) return false;
    try {
      await _store.write(await _api.refresh(tokens.refreshToken));
      return true;
    } on ApiException {
      await _store.clear();
      return false;
    } on ApiNetworkException {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _api.logout();
    } on Object {
      // Best effort: the local sign-out must not depend on the network.
    }
    await _store.clear();
    state = const AuthGuest();
  }

  /// Idempotent: the HTTP client's nested-refresh branch, its outer branch,
  /// and [refreshUser]'s catch can all reach this for the same expiry.
  Future<void> sessionExpired() async {
    if (state is AuthSessionExpired) return;
    await _store.clear();
    state = const AuthSessionExpired();
  }

  void continueAsGuest() => state = const AuthGuest();

  void markVerified() {
    final s = state;
    if (s is AuthSignedIn) {
      state = AuthSignedIn(s.user.copyWith(emailVerified: true));
    }
  }

  void applyUser(UserAccount user) => state = AuthSignedIn(user);

  /// A UUID v4 — the client key registration's idempotency requires.
  String _idempotencyKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
