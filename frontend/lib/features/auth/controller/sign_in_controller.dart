import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';

class SignInState {
  const SignInState({
    this.busy = false,
    this.failed = false,
    this.offline = false,
    this.rateLimited = false,
    this.rateLimitedSeconds,
    this.genericError = false,
    this.socialNotice,
  });
  final bool busy;

  /// One undifferentiated failure: never "email not found" vs "wrong password".
  final bool failed;
  final bool offline;

  /// `RATE_LIMITED`: a distinct banner from [failed] — this is not a wrong
  /// credential, it is a throttle.
  final bool rateLimited;

  /// Seconds remaining, from `ApiException.retryAfterSeconds`. Null when
  /// [rateLimited] is true but the server didn't say — the screen falls
  /// back to a copy that doesn't name a duration.
  final int? rateLimitedSeconds;

  /// Any other `ApiException` code: a generic banner, never the credentials
  /// or rate-limit copy.
  final bool genericError;
  final String? socialNotice;

  SignInState copyWith({
    bool? busy,
    bool? failed,
    bool? offline,
    bool? rateLimited,
    int? rateLimitedSeconds,
    bool? genericError,
    String? socialNotice,
    bool clearNotice = false,
    bool clearRateLimitedSeconds = false,
  }) => SignInState(
    busy: busy ?? this.busy,
    failed: failed ?? this.failed,
    offline: offline ?? this.offline,
    rateLimited: rateLimited ?? this.rateLimited,
    rateLimitedSeconds: clearRateLimitedSeconds
        ? null
        : (rateLimitedSeconds ?? this.rateLimitedSeconds),
    genericError: genericError ?? this.genericError,
    socialNotice: clearNotice ? null : (socialNotice ?? this.socialNotice),
  );
}

final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);

class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  Future<bool> submit(String email, String password) async {
    state = state.copyWith(
      busy: true,
      failed: false,
      offline: false,
      rateLimited: false,
      genericError: false,
      clearNotice: true,
      clearRateLimitedSeconds: true,
    );
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(email.trim(), password);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException catch (e) {
      switch (e.code) {
        case 'INVALID_CREDENTIALS':
          state = state.copyWith(busy: false, failed: true);
        case 'RATE_LIMITED':
          state = state.copyWith(
            busy: false,
            rateLimited: true,
            rateLimitedSeconds: e.retryAfterSeconds,
          );
        default:
          state = state.copyWith(busy: false, genericError: true);
      }
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return false;
  }

  Future<void> social(String provider) async {
    state = state.copyWith(clearNotice: true, failed: false, offline: false);
    try {
      final device = await ref.read(deviceNameProvider.future);
      await ref
          .read(authApiProvider)
          .social(provider, 'not-implemented', device);
    } on ApiException catch (e) {
      state = state.copyWith(socialNotice: e.message);
    } on ApiNetworkException {
      state = state.copyWith(offline: true);
    }
  }

  void clearFailure() => state = state.copyWith(
    failed: false,
    offline: false,
    rateLimited: false,
    genericError: false,
    clearRateLimitedSeconds: true,
  );
}
