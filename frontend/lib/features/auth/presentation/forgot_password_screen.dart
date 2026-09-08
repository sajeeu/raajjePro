import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/forgot_password_controller.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/circle_back_button.dart';
import 'package:raajjepro/features/auth/presentation/widgets/countdown_text.dart';
import 'package:raajjepro/features/auth/presentation/widgets/field_reveal_toggle.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';
import 'package:raajjepro/shared/shared.dart';

/// Forgot Password (`Forgot Password.dc.html`; plan §Phase 3b). One screen,
/// the artboard's four states: request · check your inbox · set a new
/// password · the code has expired. Errors are inline, the primary action
/// carries its own loading, and nothing on the way through says whether the
/// address has an account.
///
/// **The artboard says "link" and this says "code."** Approved 2026-09-08:
/// universal and app links are a Phase 16 deliverable and no domain exists
/// yet, so a link would be a step this build cannot complete or test. The
/// mechanism is the six digits Verify Email already uses, and
/// `docs/design/sessions/round-54-reset-code-not-link.md` carries the correction
/// back to the design project.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  static const routeName = '/forgot-password';

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _code = '';
  bool _revealPassword = false;
  bool _revealConfirm = false;

  /// Set by the resend cooldown's `onDone`, to the `resendAvailableAt` that
  /// had just elapsed — the same reason Verify Email keeps one: the timer is
  /// local, so nothing in the state changes when it lapses and this widget
  /// would otherwise never rebuild to swap the countdown for the button.
  DateTime? _resendReadyFor;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  ForgotPasswordController get _ctrl =>
      ref.read(forgotPasswordControllerProvider.notifier);

  Future<void> _save() async {
    final ok = await _ctrl.confirm(_code, _password.text, _confirm.text);
    if (ok && mounted) {
      _password.clear();
      _confirm.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed — sign in with your new one'),
        ),
      );
      Navigator.of(context)
          .pushNamedAndRemoveUntil(SignInScreen.routeName, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(forgotPasswordControllerProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xxl,
              AppSpacing.md,
              AppSpacing.xxl,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: CircleBackButton(
                semanticLabel: 'Back to sign in',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  switch (s.step) {
                    ResetStep.request => _requestStep(s, colors, type),
                    ResetStep.sent => _inboxStep(s, colors, type, now),
                    ResetStep.setNew => _setNewStep(s, colors, type),
                    ResetStep.expired => _expiredStep(s, colors, type),
                  },
                  if (s.step != ResetStep.setNew) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: AppButton.text(
                        label: 'Back to Sign In',
                        size: AppButtonSize.compact,
                        onPressed: () => Navigator.of(context)
                            .pushNamedAndRemoveUntil(
                              SignInScreen.routeName,
                              (_) => false,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: AppSizes.iconSm,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Reset codes expire after 30 minutes for your security',
                          style: type.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 1 — request ----------------------------------------------------

  Widget _requestStep(
    ForgotPasswordState s,
    AppColors colors,
    AppTypography type,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: colors.accentTint,
            borderRadius: AppRadius.circular(AppRadius.sheet),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: colors.primary,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        'Forgot Password?',
        style: type.screenTitle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        "No worries. Enter your email and we'll send you a code to reset your password.",
        style: type.body.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.xl),
      if (s.formError != null) InlineNotice.error(s.formError!),
      if (s.offline)
        InlineNotice.offline(onRetry: () => _ctrl.request(_email.text)),
      AppTextField(
        key: const Key('fp-email'),
        label: 'Email address',
        controller: _email,
        hint: 'you@example.mv',
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.done,
        autocorrect: false,
        errorText: s.emailError,
        enabled: !s.busy,
        onChanged: (_) => _ctrl.emailChanged(),
        onSubmitted: (_) => _ctrl.request(_email.text),
      ),
      const SizedBox(height: AppSpacing.xl),
      AppButton.primary(
        label: s.busy ? 'Sending…' : 'Send Reset Code',
        loading: s.busy,
        expand: true,
        onPressed: s.busy ? null : () => _ctrl.request(_email.text),
      ),
    ],
  );

  // --- Step 2 — check your inbox -------------------------------------------

  Widget _inboxStep(
    ForgotPasswordState s,
    AppColors colors,
    AppTypography type,
    DateTime now,
  ) {
    final resendAt = s.resendAvailableAt;
    final resendReady =
        resendAt == null ||
        _resendReadyFor == resendAt ||
        !resendAt.isAfter(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.accentTint,
                  borderRadius: AppRadius.circular(AppRadius.card),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.mail_outline_rounded,
                  size: 32,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Check your inbox', style: type.sectionHeading),
              const SizedBox(height: AppSpacing.sm),
              // Conditional on purpose, and identical whichever way it goes:
              // the server does not say whether this address has an account
              // and neither does this sentence.
              Text(
                'If this address has a RaajjePro account, a password reset code is on its way to it.',
                style: type.secondary.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                s.email,
                style: type.bodyStrong.copyWith(color: colors.ink),
                textAlign: TextAlign.center,
              ),
              if (s.expiresAt != null) ...[
                const SizedBox(height: AppSpacing.md),
                CountdownText(
                  key: ValueKey(s.expiresAt),
                  until: s.expiresAt!,
                  format: (t) => 'The code expires in $t',
                  style: type.caption.copyWith(color: colors.warningText),
                  onDone: _ctrl.codeExpired,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        OtpCodeEntry(
          enabled: !s.busy,
          error: s.codeError != null,
          clearToken: s.clearToken,
          onChanged: (c) {
            setState(() => _code = c);
            _ctrl.codeChanged();
          },
          onCompleted: (_) {},
        ),
        const SizedBox(height: AppSpacing.lg),
        if (s.codeError != null) InlineNotice.error(s.codeError!),
        if (s.resent)
          InlineNotice.success('A new code is on its way to your inbox.'),
        if (s.formError != null) InlineNotice.error(s.formError!),
        if (s.offline)
          InlineNotice.offline(
            onRetry: () =>
                _code.length == 6 ? _ctrl.verifyCode(_code) : _ctrl.resend(),
          ),
        AppButton.primary(
          label: s.busy ? 'Checking…' : 'Continue',
          loading: s.busy,
          expand: true,
          onPressed: _code.length == 6 && !s.busy
              ? () => _ctrl.verifyCode(_code)
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: resendReady
              ? AppButton.text(
                  label: 'Resend code',
                  size: AppButtonSize.compact,
                  loading: s.busy,
                  onPressed: s.busy ? null : _ctrl.resend,
                )
              : CountdownText(
                  key: ValueKey(resendAt),
                  until: resendAt,
                  format: (t) => "Didn't get it? Resend in $t",
                  style: type.secondary.copyWith(color: colors.disabledText),
                  onDone: () => setState(() => _resendReadyFor = resendAt),
                ),
        ),
      ],
    );
  }

  // --- Step 3 — set a new password -----------------------------------------

  Widget _setNewStep(
    ForgotPasswordState s,
    AppColors colors,
    AppTypography type,
  ) {
    final longEnough = _password.text.length >= minPasswordLength;
    final mismatch =
        _confirm.text.isNotEmpty && _confirm.text != _password.text;
    final canSave = longEnough && _password.text == _confirm.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Set a new password', style: type.screenTitle),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'For ${s.email}',
          style: type.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        // The requirement states itself before submission, not only after a
        // rejection, and turns as the user types.
        AppCard(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                longEnough ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: AppSizes.iconMd,
                color: longEnough ? colors.success : colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'At least $minPasswordLength characters',
                  style: type.secondary.copyWith(
                    color: longEnough
                        ? colors.successText
                        : colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (s.formError != null) InlineNotice.error(s.formError!),
        if (s.offline) InlineNotice.offline(onRetry: _save),
        AppTextField(
          key: const Key('fp-password'),
          label: 'New password',
          controller: _password,
          hint: 'At least $minPasswordLength characters',
          obscureText: !_revealPassword,
          autofillHints: const [AutofillHints.newPassword],
          enabled: !s.busy,
          onChanged: (_) => setState(() {}),
          suffix: FieldRevealToggle(
            revealed: _revealPassword,
            onTap: () => setState(() => _revealPassword = !_revealPassword),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          key: const Key('fp-confirm'),
          label: 'Confirm new password',
          controller: _confirm,
          hint: 'Repeat your new password',
          obscureText: !_revealConfirm,
          errorText: mismatch ? "These passwords don't match yet." : null,
          enabled: !s.busy,
          onChanged: (_) => setState(() {}),
          suffix: FieldRevealToggle(
            revealed: _revealConfirm,
            onTap: () => setState(() => _revealConfirm = !_revealConfirm),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        InlineNotice.info(
          'When you save, every device signs out — all other sessions end and will need this new password.',
        ),
        AppButton.primary(
          label: s.busy ? 'Saving…' : 'Save New Password',
          loading: s.busy,
          expand: true,
          onPressed: canSave && !s.busy ? _save : null,
        ),
      ],
    );
  }

  // --- The fourth state — the code has expired -----------------------------

  Widget _expiredStep(
    ForgotPasswordState s,
    AppColors colors,
    AppTypography type,
  ) => AppCard(
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.warningTint,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.schedule_rounded, color: colors.warning, size: 28),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'This reset code has expired',
          style: type.sectionHeading,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          s.formError ?? 'Reset codes work for 30 minutes. This one has passed that — request a fresh code and use it right away.',
          style: type.secondary.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: 'Request a New Code',
          onPressed: () {
            _email.text = s.email;
            _code = '';
            _password.clear();
            _confirm.clear();
            _ctrl.startOver();
          },
        ),
      ],
    ),
  );
}
