import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

class RegisterState {
  const RegisterState({
    this.busy = false,
    this.fieldErrors = const {},
    this.offline = false,
  });
  final bool busy;

  /// path -> message, from the API's details. `email` and `phone` get their
  /// own rich rendering; everything else renders as the field's errorText.
  final Map<String, String> fieldErrors;
  final bool offline;
  RegisterState copyWith({
    bool? busy,
    Map<String, String>? fieldErrors,
    bool? offline,
  }) => RegisterState(
    busy: busy ?? this.busy,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    offline: offline ?? this.offline,
  );
}

final registerControllerProvider =
    NotifierProvider<RegisterController, RegisterState>(RegisterController.new);

class RegisterController extends Notifier<RegisterState> {
  @override
  RegisterState build() => const RegisterState();

  /// Client checks here are UX only (root CLAUDE.md invariant 4): the server
  /// re-validates everything. Returns the verification outcome on success.
  Future<VerificationOutcome?> submit(
    RegisterRequest request, {
    required bool acceptedTerms,
    required String confirmPassword,
  }) async {
    final local = <String, String>{};
    if (request.password != confirmPassword) {
      local['confirmPassword'] = "Passwords don't match";
    }
    if (!acceptedTerms) {
      local['acceptTerms'] = 'Please accept the terms to continue.';
    }
    if (local.isNotEmpty) {
      state = state.copyWith(fieldErrors: local);
      return null;
    }
    state = state.copyWith(busy: true, fieldErrors: const {}, offline: false);
    try {
      final outcome = await ref
          .read(authControllerProvider.notifier)
          .register(request);
      state = state.copyWith(busy: false);
      return outcome;
    } on ApiException catch (e) {
      final errors = <String, String>{};
      for (final f in e.fieldErrors) {
        errors[f.path.split('.').first] = f.message;
      }
      // Unexpected codes (no per-field details to route) fall back to the
      // same fixed generic banner Task 4's sign-in controller uses — never
      // the server's raw `message`, which is not vetted for display.
      if (errors.isEmpty) {
        errors['form'] = 'Something went wrong. Please try again.';
      }
      state = state.copyWith(busy: false, fieldErrors: errors);
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return null;
  }

  void clear(String path) {
    if (!state.fieldErrors.containsKey(path)) return;
    state = state.copyWith(
      fieldErrors: Map.of(state.fieldErrors)..remove(path),
    );
  }
}
