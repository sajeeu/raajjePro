import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';

class SignInState {
  const SignInState({
    this.busy = false,
    this.failed = false,
    this.offline = false,
    this.socialNotice,
  });
  final bool busy;

  /// One undifferentiated failure: never "email not found" vs "wrong password".
  final bool failed;
  final bool offline;
  final String? socialNotice;

  SignInState copyWith({
    bool? busy,
    bool? failed,
    bool? offline,
    String? socialNotice,
    bool clearNotice = false,
  }) => SignInState(
    busy: busy ?? this.busy,
    failed: failed ?? this.failed,
    offline: offline ?? this.offline,
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
      clearNotice: true,
    );
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(email.trim(), password);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException {
      state = state.copyWith(busy: false, failed: true);
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

  void clearFailure() => state = state.copyWith(failed: false, offline: false);
}
