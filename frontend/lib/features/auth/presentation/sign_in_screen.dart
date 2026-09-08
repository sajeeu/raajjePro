import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/sign_in_controller.dart';
import 'package:raajjepro/features/auth/presentation/forgot_password_screen.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';
import 'package:raajjepro/features/auth/presentation/widgets/field_reveal_toggle.dart';
import 'package:raajjepro/features/auth/presentation/widgets/generic_error_copy.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/rate_limit_copy.dart';
import 'package:raajjepro/features/auth/presentation/widgets/social_sign_in_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// Sign In (`Sign In.dc.html`; plan §Phase 3). States: default · failed
/// (one message, both values kept) · rate-limited (a distinct banner) ·
/// a generic failure (any other `ApiException`) · submitting (the button's
/// own loading, both fields disabled) · offline (inline notice with retry) ·
/// a third-party notice.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  static const routeName = '/sign-in';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _reveal = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(signInControllerProvider.notifier)
        .submit(_email.text, _password.text);
    if (ok && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(signInControllerProvider);
    final borderError = s.failed;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHero(),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xxl,
                AppSpacing.xxl,
                AppSpacing.xxl,
                AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome back', style: type.screenTitle),
                  const SizedBox(height: AppSpacing.xxs + 1),
                  Text(
                    'Sign in to your RaajjePro account',
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (s.failed)
                    InlineNotice.error(
                      "That email and password combination didn't work. Check both and try again.",
                    ),
                  if (s.rateLimited)
                    InlineNotice.error(rateLimitCopy(s.rateLimitedSeconds)),
                  if (s.genericError) InlineNotice.error(genericErrorCopy),
                  if (s.offline) InlineNotice.offline(onRetry: _submit),
                  if (s.socialNotice != null)
                    InlineNotice.info(s.socialNotice!),
                  AppTextField(
                    key: const Key('signin-email'),
                    label: 'Email address',
                    controller: _email,
                    // Not the fixture's sample email (`aishath@example.mv`,
                    // used by the fixtures and widget tests): a hint whose
                    // text exactly matches typed content stays mounted at
                    // opacity 0 rather than leaving the tree, and would be a
                    // second match for any `find.text` on that value.
                    hint: 'you@example.mv',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    hasError: borderError,
                    enabled: !s.busy,
                    onChanged: (_) => ref
                        .read(signInControllerProvider.notifier)
                        .clearFailure(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    key: const Key('signin-password'),
                    label: 'Password',
                    controller: _password,
                    hint: 'Enter your password',
                    obscureText: !_reveal,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    hasError: borderError,
                    enabled: !s.busy,
                    onChanged: (_) => ref
                        .read(signInControllerProvider.notifier)
                        .clearFailure(),
                    suffix: FieldRevealToggle(
                      revealed: _reveal,
                      onTap: () => setState(() => _reveal = !_reveal),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton.text(
                      label: 'Forgot password?',
                      size: AppButtonSize.compact,
                      onPressed: () =>
                          Navigator.of(context)
                              .pushNamed(ForgotPasswordScreen.routeName),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton.primary(
                    label: s.busy ? 'Signing in…' : 'Sign In',
                    loading: s.busy,
                    expand: true,
                    onPressed: s.busy ? null : _submit,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Row(
                    children: [
                      Expanded(child: Divider(color: colors.divider)),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Text(
                          'or continue with',
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: colors.divider)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SocialSignInRow(
                    onTap: (p) =>
                        ref.read(signInControllerProvider.notifier).social(p),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: type.body.copyWith(color: colors.textSecondary),
                      ),
                      AppButton.text(
                        label: 'Create Account',
                        size: AppButtonSize.compact,
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(RegisterScreen.routeName),
                      ),
                    ],
                  ),
                  // A link, not a filled control (13.5/700 in textSecondary,
                  // measured off the prototype). A full-width tinted button
                  // competed with Sign In for primary emphasis on a screen
                  // that already has a primary action — guest browsing is
                  // available here, not advertised as the equal of signing in.
                  // Pressable keeps the 48 dp tap target; only the painted box
                  // changes (docs/design/sign-in-corrections.md item 1).
                  Center(
                    child: Pressable(
                      semanticLabel: 'Continue as Guest',
                      onTap: () {
                        ref
                            .read(authControllerProvider.notifier)
                            .continueAsGuest();
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/', (_) => false);
                      },
                      builder: (context, state) => Text(
                        'Continue as Guest',
                        style: type.buttonSmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Browsing, searching and viewing providers need no account. Sign in when you want to save, book or message.',
                    // Weight 500, per the prototype. NOT the prototype's
                    // #8296B3, which is 2.78:1 on this page and fails the AA
                    // bar §Phase 1 makes non-negotiable — textSecondary is
                    // 4.99:1, compliant and visibly lighter than the 7.32:1
                    // textTertiary this used to use
                    // (docs/design/sign-in-corrections.md item 2).
                    style: type.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
