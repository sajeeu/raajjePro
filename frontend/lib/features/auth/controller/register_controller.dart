import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

/// The prototype's exact copy for a duplicate email — set here, once, never
/// derived from the server's `message` (routing is on `ApiException.code`).
const _emailInUseCopy = 'This email already has a RaajjePro account.';

/// The prototype's exact copy for a duplicate phone.
const _phoneInUseCopy =
    "This number belongs to a verified provider account. If it's yours, "
    'sign in instead — or use a different number.';

class RegisterState {
  const RegisterState({
    this.busy = false,
    this.fieldErrors = const {},
    this.offline = false,
    this.emailInUse = false,
    this.phoneInUse = false,
    this.rateLimited = false,
    this.rateLimitedSeconds,
  });
  final bool busy;

  /// path -> message, from the API's `VALIDATION_FAILED` details, plus the
  /// fixed `EMAIL_IN_USE`/`PHONE_IN_USE` copy under `email`/`phone`, plus a
  /// `form` key for an unexpected code's generic banner.
  final Map<String, String> fieldErrors;
  final bool offline;

  /// `ApiException.code == 'EMAIL_IN_USE'` — never derived from `message`.
  /// Gates the Sign in / Reset password links under the email field.
  final bool emailInUse;

  /// `ApiException.code == 'PHONE_IN_USE'` — never derived from `message`.
  /// Gates the verified-provider copy with its inline sign-in link.
  final bool phoneInUse;

  /// `RATE_LIMITED`: a distinct banner from a field error (Task 4's
  /// `sign_in_controller.dart` pattern) — this is a throttle, not a mistake
  /// in what was typed.
  final bool rateLimited;

  /// Seconds remaining, from `ApiException.retryAfterSeconds`. Null when
  /// [rateLimited] is true but the server didn't say.
  final int? rateLimitedSeconds;

  RegisterState copyWith({
    bool? busy,
    Map<String, String>? fieldErrors,
    bool? offline,
    bool? emailInUse,
    bool? phoneInUse,
    bool? rateLimited,
    int? rateLimitedSeconds,
    bool clearRateLimitedSeconds = false,
  }) => RegisterState(
    busy: busy ?? this.busy,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    offline: offline ?? this.offline,
    emailInUse: emailInUse ?? this.emailInUse,
    phoneInUse: phoneInUse ?? this.phoneInUse,
    rateLimited: rateLimited ?? this.rateLimited,
    rateLimitedSeconds: clearRateLimitedSeconds
        ? null
        : (rateLimitedSeconds ?? this.rateLimitedSeconds),
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
      state = state.copyWith(
        fieldErrors: local,
        emailInUse: false,
        phoneInUse: false,
        rateLimited: false,
      );
      return null;
    }
    state = state.copyWith(
      busy: true,
      fieldErrors: const {},
      offline: false,
      emailInUse: false,
      phoneInUse: false,
      rateLimited: false,
      clearRateLimitedSeconds: true,
    );
    try {
      final outcome = await ref
          .read(authControllerProvider.notifier)
          .register(request);
      state = state.copyWith(busy: false);
      return outcome;
    } on ApiException catch (e) {
      // Routed on `e.code` alone — never on `e.message`, which is display
      // text the server is free to change (backend/CLAUDE.md: codes are the
      // contract).
      switch (e.code) {
        case 'EMAIL_IN_USE':
          state = state.copyWith(
            busy: false,
            emailInUse: true,
            fieldErrors: {'email': _emailInUseCopy},
          );
        case 'PHONE_IN_USE':
          state = state.copyWith(
            busy: false,
            phoneInUse: true,
            fieldErrors: {'phone': _phoneInUseCopy},
          );
        case 'VALIDATION_FAILED':
          final errors = <String, String>{};
          for (final f in e.fieldErrors) {
            errors[f.path.split('.').first] = f.message;
          }
          state = state.copyWith(
            busy: false,
            fieldErrors: errors.isEmpty
                ? {'form': 'Something went wrong. Please try again.'}
                : errors,
          );
        case 'RATE_LIMITED':
          state = state.copyWith(
            busy: false,
            rateLimited: true,
            rateLimitedSeconds: e.retryAfterSeconds,
          );
        default:
          // Unexpected codes fall back to the same fixed generic banner
          // Task 4's sign-in controller uses — never the server's raw
          // `message`, which is not vetted for display.
          state = state.copyWith(
            busy: false,
            fieldErrors: {'form': 'Something went wrong. Please try again.'},
          );
      }
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return null;
  }

  /// Clears one field's error as the user edits it. Clearing `email` or
  /// `phone` also drops the matching typed flag, so editing away from a
  /// duplicate value retracts its extra links along with its message.
  void clear(String path) {
    final hadError = state.fieldErrors.containsKey(path);
    final hadEmailFlag = path == 'email' && state.emailInUse;
    final hadPhoneFlag = path == 'phone' && state.phoneInUse;
    if (!hadError && !hadEmailFlag && !hadPhoneFlag) return;
    state = state.copyWith(
      fieldErrors: Map.of(state.fieldErrors)..remove(path),
      emailInUse: hadEmailFlag ? false : null,
      phoneInUse: hadPhoneFlag ? false : null,
    );
  }
}
