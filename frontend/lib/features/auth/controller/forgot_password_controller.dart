import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';

/// The three steps of `Forgot Password.dc.html`, plus the artboard's fourth
/// state. `expired` is that state — the artboard calls it "This reset link
/// has expired" and reaches it from a dead link; a code reaches it from a
/// dead code, and it does the same thing: offers a fresh one.
enum ResetStep { request, sent, setNew, expired }

/// The minimum the server enforces (`MIN_USER_PASSWORD_LENGTH`). Checked here
/// only so the requirement row can go green as the user types — the rule is
/// the backend's (root CLAUDE.md invariant 4).
const int minPasswordLength = 8;

class ForgotPasswordState {
  const ForgotPasswordState({
    this.step = ResetStep.request,
    this.email = '',
    this.busy = false,
    this.expiresAt,
    this.resendAvailableAt,
    this.emailError,
    this.codeError,
    this.attemptsRemaining,
    this.formError,
    this.offline = false,
    this.resent = false,
    this.clearToken = 0,
  });

  final ResetStep step;

  /// The address the code went to. Held across all four steps: the inbox card
  /// and the set-a-new-password header both name it, and every call carries
  /// it because none of them is authenticated.
  final String email;
  final bool busy;
  final DateTime? expiresAt;
  final DateTime? resendAvailableAt;
  final String? emailError;

  /// The code-entry error, shown under the six boxes on the inbox step.
  final String? codeError;
  final int? attemptsRemaining;

  /// Anything that is not about one field — a failed send, an unexpected code.
  final String? formError;
  final bool offline;

  /// A resend landed; the inbox card says so until the next thing happens.
  final bool resent;

  /// Bumped when [OtpCodeEntry] should clear its boxes.
  final int clearToken;

  ForgotPasswordState copyWith({
    ResetStep? step,
    String? email,
    bool? busy,
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    String? emailError,
    String? codeError,
    int? attemptsRemaining,
    String? formError,
    bool? offline,
    bool? resent,
    int? clearToken,
    bool clearErrors = false,
  }) => ForgotPasswordState(
    step: step ?? this.step,
    email: email ?? this.email,
    busy: busy ?? this.busy,
    expiresAt: expiresAt ?? this.expiresAt,
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
    emailError: clearErrors ? null : (emailError ?? this.emailError),
    codeError: clearErrors ? null : (codeError ?? this.codeError),
    attemptsRemaining: clearErrors
        ? null
        : (attemptsRemaining ?? this.attemptsRemaining),
    formError: clearErrors ? null : (formError ?? this.formError),
    offline: clearErrors ? false : (offline ?? this.offline),
    resent: resent ?? this.resent,
    clearToken: clearToken ?? this.clearToken,
  );
}

final forgotPasswordControllerProvider =
    NotifierProvider<ForgotPasswordController, ForgotPasswordState>(
      ForgotPasswordController.new,
    );

/// Drives Forgot Password (`Forgot Password.dc.html`; plan §Phase 3b).
///
/// Two things about this flow are deliberate and easy to undo by accident.
/// **The request step never reports whether an address is registered** — the
/// server answers identically either way and so does this, which is why
/// [request] has no not-found branch to write. And **the code is checked
/// before the password screen opens** ([verifyCode], which does not spend
/// it), so nobody types a new password twice over because a digit was wrong.
class ForgotPasswordController extends Notifier<ForgotPasswordState> {
  @override
  ForgotPasswordState build() => const ForgotPasswordState();

  void emailChanged() {
    if (state.emailError != null || state.formError != null || state.offline) {
      state = state.copyWith(clearErrors: true);
    }
  }

  void codeChanged() {
    if (state.codeError != null || state.offline || state.resent) {
      state = state.copyWith(clearErrors: true, resent: false);
    }
  }

  /// Step 1 → 2. Always lands on the inbox card when the call succeeds: an
  /// unknown, unverified or frozen address gets the same answer as a live one.
  Future<void> request(String emailInput) async {
    final email = emailInput.trim();
    if (!email.contains('@') || !email.contains('.')) {
      state = state.copyWith(emailError: 'Enter a valid email address');
      return;
    }
    state = state.copyWith(busy: true, clearErrors: true);
    try {
      final outcome = await ref
          .read(authApiProvider)
          .requestPasswordReset(email);
      state = state.copyWith(
        step: ResetStep.sent,
        email: email,
        busy: false,
        expiresAt: outcome.expiresAt,
        resendAvailableAt: outcome.resendAvailableAt,
        resent: false,
        clearToken: state.clearToken + 1,
      );
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, formError: _messageFor(e));
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
  }

  /// Another code to the same address, from the inbox card.
  Future<void> resend() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearErrors: true, resent: false);
    try {
      final outcome = await ref
          .read(authApiProvider)
          .requestPasswordReset(state.email);
      state = state.copyWith(
        busy: false,
        expiresAt: outcome.expiresAt,
        resendAvailableAt: outcome.resendAvailableAt,
        resent: true,
        clearToken: state.clearToken + 1,
      );
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, formError: _messageFor(e));
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
  }

  /// Step 2 → 3. Checks the code without spending it.
  Future<void> verifyCode(String code) async {
    state = state.copyWith(busy: true, clearErrors: true, resent: false);
    try {
      await ref
          .read(authApiProvider)
          .verifyPasswordResetCode(state.email, code);
      state = state.copyWith(step: ResetStep.setNew, busy: false);
    } on ApiException catch (e) {
      state = _afterCodeFailure(e);
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
  }

  /// Step 3. Returns true when the password is set — the screen then leaves
  /// for Sign In, because nothing here signs anyone in.
  Future<bool> confirm(String code, String password, String confirm) async {
    if (password.length < minPasswordLength) {
      state = state.copyWith(
        formError: 'At least $minPasswordLength characters',
      );
      return false;
    }
    if (password != confirm) {
      state = state.copyWith(formError: "These passwords don't match yet.");
      return false;
    }
    state = state.copyWith(busy: true, clearErrors: true);
    try {
      await ref
          .read(authApiProvider)
          .confirmPasswordReset(state.email, code, password);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException catch (e) {
      // A code that died between the check and the save sends the user back
      // to the expired card rather than leaving them on a form that cannot
      // succeed.
      state = _afterCodeFailure(e, backToInbox: false);
      return false;
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
      return false;
    }
  }

  /// The inbox card's own countdown reached zero. Nothing has been sent to
  /// the server — the code is simply past the moment the server told us it
  /// dies, so the screen says so rather than waiting for a doomed attempt.
  void codeExpired() {
    if (state.step == ResetStep.sent) {
      state = state.copyWith(
        step: ResetStep.expired,
        clearErrors: true,
        clearToken: state.clearToken + 1,
      );
    }
  }

  /// From the expired card: start again with the address already filled in.
  void startOver() {
    state = ForgotPasswordState(
      email: state.email,
      clearToken: state.clearToken + 1,
    );
  }

  ForgotPasswordState _afterCodeFailure(
    ApiException e, {
    bool backToInbox = true,
  }) {
    switch (e.code) {
      case 'OTP_INCORRECT':
        return state.copyWith(
          busy: false,
          step: backToInbox ? ResetStep.sent : state.step,
          codeError:
              "That code isn't right — ${e.attemptsRemaining ?? 0} ${e.attemptsRemaining == 1 ? 'attempt' : 'attempts'} left before it needs a fresh send.",
          attemptsRemaining: e.attemptsRemaining,
          clearToken: state.clearToken + 1,
        );
      case 'OTP_EXPIRED':
      case 'OTP_INVALIDATED':
        return state.copyWith(
          busy: false,
          step: ResetStep.expired,
          formError: e.code == 'OTP_INVALIDATED'
              ? 'That code was invalidated after 5 incorrect attempts.'
              : null,
          clearToken: state.clearToken + 1,
        );
      default:
        return state.copyWith(busy: false, formError: _messageFor(e));
    }
  }

  String _messageFor(ApiException e) => e.code == 'RATE_LIMITED'
      ? "You've tried this several times in a row. Wait a moment, then try again."
      : "Something went wrong on our end. It isn't you — try again in a moment.";
}
