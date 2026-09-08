import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/verify_email_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/countdown_text.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';
import 'package:raajjepro/shared/shared.dart';

export 'package:raajjepro/features/auth/controller/verify_email_controller.dart'
    show VerifyEmailArgs, OtpPurpose;

/// Verify Email (`Verify Email.dc.html`; plan §Phase 3). Email-only, always.
/// States: entry · resent · wrong_code · code_invalidated · rate_limited ·
/// success · send_failed · offline. Two timers, two clocks.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({required this.args, super.key});
  static const routeName = '/verify-email';
  final VerifyEmailArgs args;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  String _code = '';

  /// Set by the resend-cooldown [CountdownText]'s `onDone`, to the
  /// `resendAvailableAt` that had just elapsed. That timer is purely local
  /// UI (no server round trip when it lapses), so nothing about the
  /// Riverpod state changes when it reaches zero — but this widget's own
  /// `build` still needs to re-run once so it stops showing the countdown
  /// and starts showing the "Resend code" button; without this the ternary
  /// below is only re-evaluated when *something else* rebuilds the screen
  /// (a resend, a wrong attempt, …), so the button would never appear on
  /// its own just because time passed. Storing *which* cooldown finished,
  /// rather than a bare bool, means a later resend — which sets a new,
  /// still-future `resendAvailableAt` — is not mistaken for the one
  /// that already finished.
  DateTime? _resendReadyFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final provider = verifyEmailControllerProvider(widget.args);
    final s = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final now = ref.watch(clockProvider)();
    final isChange = widget.args.purpose == OtpPurpose.changeEmail;
    final resendReady =
        _resendReadyFor == s.resendAvailableAt ||
        !s.resendAvailableAt.isAfter(now);

    void goHome() =>
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Verify email',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.xxxl,
              ),
              child: Column(
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
                        Icons.mail_outline_rounded,
                        size: 40,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    isChange ? 'Verify your new email' : 'Verify your email',
                    style: type.screenTitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'We emailed a 6-digit code to',
                    style: type.body.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  // A separate Text, not one TextSpan nested in the line
                  // above's: `find.text` on a `Text.rich` matches the whole
                  // span tree's plain text, so the address needs its own
                  // widget to be findable — and addressable — on its own.
                  Text(
                    widget.args.email,
                    style: type.bodyStrong.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isChange)
                    Center(
                      child: AppButton.text(
                        label: 'Not your address? Change it',
                        size: AppButtonSize.compact,
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed('/account/change-email'),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),

                  if (s.mode == VerifyMode.rateLimited &&
                      s.rateLimitedUntil != null) ...[
                    AppCard(
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
                            child: Icon(
                              Icons.schedule_rounded,
                              color: colors.warning,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'A short wait before the next code',
                            style: type.sectionHeading,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            "You've requested several codes in a row. You can send another in",
                            style: type.secondary.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          CountdownText(
                            key: ValueKey(s.rateLimitedUntil),
                            until: s.rateLimitedUntil!,
                            format: (t) => t,
                            style: type.stat.copyWith(
                              color: colors.warningText,
                              fontSize: 30,
                            ),
                            onDone: ctrl.rateLimitEnded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InlineNotice.info(
                      'Codes are limited to 3 per address every 15 minutes, and 5 per account each hour. Codes already in your inbox still work until they expire.',
                    ),
                  ] else if (s.mode == VerifyMode.success) ...[
                    AppCard(
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.successTint,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.check_rounded,
                              color: colors.success,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            isChange ? 'Email changed' : 'Email verified',
                            style: type.sectionHeading,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            isChange
                                ? 'Your account now uses this address. Other devices were signed out.'
                                : "You're all set — booking, enquiries and messaging are now open to you.",
                            style: type.secondary.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppButton.primary(
                            label: 'Continue',
                            onPressed: isChange
                                ? () => Navigator.of(context).pop()
                                : goHome,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    OtpCodeEntry(
                      enabled: s.mode != VerifyMode.invalidated && !s.checking,
                      error:
                          s.mode == VerifyMode.wrong ||
                          s.mode == VerifyMode.invalidated,
                      clearToken: s.clearToken,
                      onChanged: (c) {
                        setState(() => _code = c);
                        ctrl.codeChanged();
                      },
                      onCompleted: (_) {},
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (s.mode == VerifyMode.wrong)
                      InlineNotice.error(
                        "That code isn't right — ${s.attemptsRemaining ?? 0} ${s.attemptsRemaining == 1 ? 'attempt' : 'attempts'} left before it needs a fresh send.",
                      ),
                    if (s.mode == VerifyMode.invalidated) ...[
                      InlineNotice.error(
                        'That code has been invalidated after 5 incorrect attempts. Request a fresh one to continue.',
                      ),
                      AppButton.destructive(
                        label: 'Send a fresh code',
                        size: AppButtonSize.compact,
                        onPressed: ctrl.resend,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (s.mode == VerifyMode.resent)
                      InlineNotice.success(
                        'A new code is on its way to your inbox.',
                      ),
                    if (s.mode == VerifyMode.sendFailed)
                      InlineNotice.error(
                        "We couldn't send a code to this address. Check it's right, or try again in a moment.",
                      ),
                    if (s.mode == VerifyMode.offline)
                      InlineNotice.offline(
                        onRetry: () => _code.length == 6
                            ? ctrl.verify(_code)
                            : ctrl.resend(),
                      ),
                    AppButton.primary(
                      label: s.checking ? 'Checking…' : 'Verify Email',
                      loading: s.checking,
                      expand: true,
                      onPressed:
                          _code.length == 6 &&
                              !s.checking &&
                              s.mode != VerifyMode.invalidated
                          ? () => ctrl.verify(_code)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: resendReady
                          ? AppButton.text(
                              label: 'Resend code',
                              size: AppButtonSize.compact,
                              onPressed: ctrl.resend,
                            )
                          : CountdownText(
                              key: ValueKey(s.resendAvailableAt),
                              until: s.resendAvailableAt,
                              format: (t) => 'Resend code in $t',
                              style: type.secondary.copyWith(
                                color: colors.disabledText,
                              ),
                              onDone: () => setState(
                                () => _resendReadyFor = s.resendAvailableAt,
                              ),
                            ),
                    ),
                  ],

                  if (s.mode != VerifyMode.success && !isChange) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      "Booking, enquiring and messaging need a verified email. Browsing doesn't — you can finish this any time.",
                      style: type.caption.copyWith(color: colors.disabledText),
                      textAlign: TextAlign.center,
                    ),
                    Center(
                      child: AppButton.text(
                        label: "I'll do this later",
                        size: AppButtonSize.compact,
                        onPressed: goHome,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
