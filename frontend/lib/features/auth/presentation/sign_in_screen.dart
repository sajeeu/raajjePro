import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/sign_in_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/social_sign_in_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// Sign In (`Sign In.dc.html`; plan §Phase 3). States: default · failed
/// (one message, both values kept) · submitting (the button's own loading) ·
/// offline (inline notice with retry) · a third-party notice.
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
    if (ok && mounted)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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
            const AuthHero(
              title: 'Welcome back',
              subtitle: 'Sign in to your RaajjePro account',
            ),
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
                  if (s.failed)
                    InlineNotice.error(
                      "That email and password combination didn't work. Check both and try again.",
                    ),
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
                    onChanged: (_) => ref
                        .read(signInControllerProvider.notifier)
                        .clearFailure(),
                    suffix: Pressable(
                      semanticLabel: _reveal
                          ? 'Hide password'
                          : 'Show password',
                      onTap: () => setState(() => _reveal = !_reveal),
                      builder: (context, state) => Icon(
                        _reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: colors.textSecondary,
                        size: AppSizes.iconLg,
                      ),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton.text(
                      label: 'Forgot password?',
                      size: AppButtonSize.compact,
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/forgot-password'),
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
                            Navigator.of(context).pushNamed('/register'),
                      ),
                    ],
                  ),
                  AppButton.secondary(
                    label: 'Continue as Guest',
                    expand: true,
                    onPressed: () {
                      ref
                          .read(authControllerProvider.notifier)
                          .continueAsGuest();
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (_) => false);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Browsing, searching and viewing providers need no account. Sign in when you want to save, book or message.',
                    style: type.caption.copyWith(color: colors.textTertiary),
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
