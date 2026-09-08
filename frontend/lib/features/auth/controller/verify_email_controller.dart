import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';

enum OtpPurpose { verifyEmail, changeEmail }

enum VerifyMode {
  entry,
  resent,
  wrong,
  invalidated,
  rateLimited,
  success,
  sendFailed,
  offline,
}

class VerifyEmailArgs {
  const VerifyEmailArgs({
    required this.email,
    required this.purpose,
    this.initialStatus,
    this.resendAvailableAt,
    this.resendOverride,
  });
  final String email;
  final OtpPurpose purpose;
  final VerificationStatus? initialStatus;
  final DateTime? resendAvailableAt;

  /// Task 9's change-email flow resends through a different endpoint
  /// (`/v1/users/me/change-email/request`, not `/v1/auth/verify-email/send`).
  /// Supplying this lets [VerifyEmailController.resend] call the right one
  /// without this screen needing to know which purpose it is.
  final Future<VerificationOutcome> Function()? resendOverride;

  /// Accepts the typed args or the map Register pushed before this class existed.
  static VerifyEmailArgs fromRouteArguments(Object? a) {
    if (a is VerifyEmailArgs) return a;
    final m = a as Map<String, dynamic>;
    return VerifyEmailArgs(
      email: m['email'] as String,
      purpose: m['purpose'] == 'changeEmail'
          ? OtpPurpose.changeEmail
          : OtpPurpose.verifyEmail,
      initialStatus: VerificationStatus.values
          .asNameMap()[m['status'] as String?],
      resendAvailableAt: m['resendAvailableAt'] is String
          ? DateTime.parse(m['resendAvailableAt'] as String)
          : null,
    );
  }
}

class VerifyEmailState {
  const VerifyEmailState({
    required this.mode,
    this.checking = false,
    this.attemptsRemaining,
    required this.resendAvailableAt,
    this.rateLimitedUntil,
    this.clearToken = 0,
  });
  final VerifyMode mode;
  final bool checking;
  final int? attemptsRemaining;
  final DateTime resendAvailableAt;
  final DateTime? rateLimitedUntil;

  /// Bumped whenever [OtpCodeEntry] should clear its six boxes (a wrong
  /// attempt, an invalidation, a resend).
  final int clearToken;

  VerifyEmailState copyWith({
    VerifyMode? mode,
    bool? checking,
    int? attemptsRemaining,
    bool clearAttemptsRemaining = false,
    DateTime? resendAvailableAt,
    DateTime? rateLimitedUntil,
    int? clearToken,
  }) => VerifyEmailState(
    mode: mode ?? this.mode,
    checking: checking ?? this.checking,
    attemptsRemaining: clearAttemptsRemaining
        ? null
        : (attemptsRemaining ?? this.attemptsRemaining),
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
    rateLimitedUntil: rateLimitedUntil ?? this.rateLimitedUntil,
    clearToken: clearToken ?? this.clearToken,
  );
}

final verifyEmailControllerProvider =
    NotifierProvider.family<
      VerifyEmailController,
      VerifyEmailState,
      VerifyEmailArgs
    >(VerifyEmailController.new);

/// Drives Verify Email (spec §8). Two timers are two fields: the resend
/// cooldown (advisory, 60 s after each send) and the rate-limit wait (the
/// server's `retryAfterSeconds`). Modes map one-to-one onto the prototype.
///
/// Riverpod 3 dropped `FamilyNotifier` — a family [Notifier] instead takes
/// its argument through the constructor, which [NotifierProvider.family]
/// invokes with the key each time. `args` below is that constructor field,
/// not an override of `build`.
class VerifyEmailController extends Notifier<VerifyEmailState> {
  VerifyEmailController(this.args);
  final VerifyEmailArgs args;

  @override
  VerifyEmailState build() {
    final now = ref.read(clockProvider)();
    final failed =
        args.initialStatus == VerificationStatus.suppressed ||
        args.initialStatus == VerificationStatus.failed;
    return VerifyEmailState(
      mode: failed ? VerifyMode.sendFailed : VerifyMode.entry,
      resendAvailableAt: args.resendAvailableAt ?? now,
    );
  }

  void codeChanged() {
    if (state.mode == VerifyMode.wrong ||
        state.mode == VerifyMode.resent ||
        state.mode == VerifyMode.offline) {
      state = state.copyWith(mode: VerifyMode.entry);
    }
  }

  void rateLimitEnded() {
    if (state.mode == VerifyMode.rateLimited) {
      state = state.copyWith(mode: VerifyMode.entry);
    }
  }

  Future<void> verify(String code) async {
    state = state.copyWith(checking: true);
    try {
      final api = ref.read(authApiProvider);
      if (args.purpose == OtpPurpose.verifyEmail) {
        await api.confirmVerification(code);
        ref.read(authControllerProvider.notifier).markVerified();
      } else {
        ref
            .read(authControllerProvider.notifier)
            .applyUser(await api.confirmEmailChange(code));
      }
      state = state.copyWith(checking: false, mode: VerifyMode.success);
    } on ApiException catch (e) {
      // Routed on `e.code` alone (backend/CLAUDE.md: codes are the contract).
      // The confirm endpoint's documented set is exactly these three; an
      // unrecognised code still needs *a* rendering, so it falls back to the
      // wrong-code banner rather than being silently swallowed.
      final next = switch (e.code) {
        'OTP_INVALIDATED' => VerifyMode.invalidated,
        'OTP_EXPIRED' => VerifyMode.invalidated,
        _ => VerifyMode.wrong,
      };
      state = state.copyWith(
        checking: false,
        mode: next,
        attemptsRemaining: e.attemptsRemaining,
        clearToken: state.clearToken + 1,
      );
    } on ApiNetworkException {
      state = state.copyWith(checking: false, mode: VerifyMode.offline);
    }
  }

  Future<void> resend() async {
    final now = ref.read(clockProvider)();
    try {
      final send =
          args.resendOverride ??
          (args.purpose == OtpPurpose.verifyEmail
              ? () => ref.read(authApiProvider).sendVerification()
              : () => throw StateError(
                  'change-email resend needs a resendOverride (Task 9)',
                ));
      final outcome = await send();
      state = state.copyWith(
        mode: outcome.status == VerificationStatus.sent
            ? VerifyMode.resent
            : VerifyMode.sendFailed,
        resendAvailableAt: outcome.resendAvailableAt,
        clearAttemptsRemaining: true,
        clearToken: state.clearToken + 1,
      );
    } on ApiException catch (e) {
      if (e.code == 'OTP_RATE_LIMITED') {
        state = state.copyWith(
          mode: VerifyMode.rateLimited,
          rateLimitedUntil: now.add(
            Duration(seconds: e.retryAfterSeconds ?? 60),
          ),
        );
      } else if (e.code == 'EMAIL_ALREADY_VERIFIED') {
        ref.read(authControllerProvider.notifier).markVerified();
        state = state.copyWith(mode: VerifyMode.success);
      } else {
        state = state.copyWith(mode: VerifyMode.sendFailed);
      }
    } on ApiNetworkException {
      state = state.copyWith(mode: VerifyMode.offline);
    }
  }
}
