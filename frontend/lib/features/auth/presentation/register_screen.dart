import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/register_controller.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/rate_limit_copy.dart';
import 'package:raajjepro/features/auth/presentation/widgets/role_toggle.dart';
import 'package:raajjepro/shared/shared.dart';

/// Register (`Register.dc.html`; plan §Phase 3, §1a "provider variant adds
/// Business / Trade Name"). States: default · field errors (VALIDATION_FAILED,
/// EMAIL_IN_USE with routes, PHONE_IN_USE with its copy) · submitting ·
/// offline. Registering as Offer Services creates an account only; Become a
/// Provider (Phase 6a) is what sets someone up as a provider.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  static const routeName = '/register';

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  AccountRole _role = AccountRole.customer;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _dial = TextEditingController(text: '+960');
  final _phone = TextEditingController();
  final _business = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _reveal1 = false;
  bool _reveal2 = false;
  bool _terms = false;

  /// The two legal links are spans inside the consent sentence, not buttons
  /// beside it, so they need recognizers this State owns and disposes.
  late final TapGestureRecognizer _tosTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _tosTap = TapGestureRecognizer()
      ..onTap = () => Navigator.of(context).pushNamed('/legal/terms');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => Navigator.of(context).pushNamed('/legal/privacy');
  }

  @override
  void dispose() {
    _tosTap.dispose();
    _privacyTap.dispose();
    for (final c in [
      _name,
      _email,
      _dial,
      _phone,
      _business,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final device = await ref.read(deviceNameProvider.future);
    final request = RegisterRequest(
      role: _role,
      fullName: _name.text,
      email: _email.text,
      dialCode: _dial.text,
      number: _phone.text,
      password: _password.text,
      businessName: _role == AccountRole.provider ? _business.text : null,
      deviceName: device,
    );
    final outcome = await ref
        .read(registerControllerProvider.notifier)
        .submit(request, acceptedTerms: _terms, confirmPassword: _confirm.text);
    if (outcome != null && mounted) {
      Navigator.of(context).pushReplacementNamed(
        VerifyEmailScreen.routeName,
        arguments: VerifyEmailArgs(
          email: _email.text.trim(),
          purpose: OtpPurpose.verifyEmail,
          initialStatus: outcome.status,
          resendAvailableAt: outcome.resendAvailableAt,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(registerControllerProvider);
    final ctrl = ref.read(registerControllerProvider.notifier);
    final isProvider = _role == AccountRole.provider;

    Widget reveal(bool on, VoidCallback toggle) => Pressable(
      semanticLabel: on ? 'Hide password' : 'Show password',
      onTap: toggle,
      builder: (context, state) => Icon(
        on ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: colors.textSecondary,
        size: AppSizes.iconLg,
      ),
    );

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxxl,
          ),
          child: FadeUpColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: CircleBackButton(
                  semanticLabel: 'Back to sign in',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Create account', style: type.screenTitle),
              const SizedBox(height: AppSpacing.n5),
              Text(
                'Join RaajjePro — it only takes a minute',
                style: type.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (s.offline) InlineNotice.offline(onRetry: _submit),
              if (s.rateLimited)
                InlineNotice.error(rateLimitCopy(s.rateLimitedSeconds)),
              if (s.fieldErrors['form'] != null)
                InlineNotice.error(s.fieldErrors['form']!),
              Text('I want to…', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.sm),
              RoleToggle(
                value: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                key: const Key('reg-name'),
                label: 'Full Name',
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                errorText: s.fieldErrors['fullName'],
                enabled: !s.busy,
                onChanged: (_) => ctrl.clear('fullName'),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('reg-email'),
                label: 'Email Address',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                // Not the fixture's sample email (`aishath@example.mv`,
                // used by the fixtures and widget tests) — Task 4's
                // `sign_in_screen.dart` documents why: a hint whose text
                // exactly matches typed content stays mounted at opacity
                // 0 rather than leaving the tree, and would be a second
                // match for any `find.text` on that value.
                hint: 'you@example.mv',
                errorText: s.fieldErrors['email'],
                enabled: !s.busy,
                onChanged: (_) => ctrl.clear('email'),
              ),
              if (s.emailInUse)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppButton.text(
                        label: 'Sign in',
                        size: AppButtonSize.compact,
                        onPressed: () =>
                            Navigator.of(context)
                                .pushReplacementNamed(SignInScreen.routeName),
                      ),
                      Text(
                        '·',
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      AppButton.text(
                        label: 'Reset password',
                        size: AppButtonSize.compact,
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/forgot-password'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              PhoneField(
                dialCode: _dial,
                number: _phone,
                enabled: !s.busy,
                errorText: s.phoneInUse ? null : s.fieldErrors['phone'],
                errorWidget: s.phoneInUse
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            "This number belongs to a verified provider account. If it's yours, ",
                          ),
                          AppButton.text(
                            label: 'sign in',
                            size: AppButtonSize.compact,
                            onPressed: () => Navigator.of(context)
                                .pushReplacementNamed(SignInScreen.routeName),
                          ),
                          const Text(' instead — or use a different number.'),
                        ],
                      )
                    : null,
                onChanged: () {
                  ctrl.clear('phone');
                  setState(() {});
                },
              ),
              if (isProvider) ...[
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  key: const Key('reg-business'),
                  label: 'Business / Trade Name',
                  controller: _business,
                  helper: 'The name customers will see on your listings',
                  textCapitalization: TextCapitalization.words,
                  errorText: s.fieldErrors['businessName'],
                  enabled: !s.busy,
                  onChanged: (_) => ctrl.clear('businessName'),
                ),
                const SizedBox(height: AppSpacing.sm),
                InlineNotice.info(
                  "This creates your account only — you'll list services through Become a Provider after signing up.",
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('reg-password'),
                label: 'Password',
                controller: _password,
                obscureText: !_reveal1,
                autofillHints: const [AutofillHints.newPassword],
                helper: 'At least 8 characters',
                errorText: s.fieldErrors['password'],
                enabled: !s.busy,
                onChanged: (_) => ctrl.clear('password'),
                suffix: reveal(
                  _reveal1,
                  () => setState(() => _reveal1 = !_reveal1),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('reg-confirm'),
                label: 'Confirm Password',
                controller: _confirm,
                obscureText: !_reveal2,
                errorText: s.fieldErrors['confirmPassword'],
                enabled: !s.busy,
                onChanged: (_) => ctrl.clear('confirmPassword'),
                suffix: reveal(
                  _reveal2,
                  () => setState(() => _reveal2 = !_reveal2),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // 🔧 Rebuilt 2026-09-16, for two defects that shared one cause.
              //
              // The legal links were `AppButton.text` compacts — 44 dp tall —
              // sitting in a `Wrap` beside a 26 dp checkbox aligned to
              // `start`. That made the first line 44 dp, centred the words
              // inside it, and left the checkbox stranded 11 dp above them.
              // Worse, they were *controls inside a tappable row*: `Pressable`
              // wraps its child in `Semantics(excludeSemantics: true)`, so
              // both links vanished from the semantics tree and a screen
              // reader was asked to consent to two documents it could not
              // open.
              //
              // `Register.dc.html` draws one flowing span with inline `<a>`s,
              // which is the shape that fixes both: the line is the text's own
              // 18.75 dp, and nothing interactive nests inside anything else.
              // The links are spans with recognizers — `RenderParagraph` gives
              // each its own semantics node — and the row keeps the tap that
              // toggles consent.
              Pressable(
                key: const Key('reg-terms'),
                // Returns the child unwrapped, which is the whole point: the
                // consent semantics are declared below, so the link spans
                // inside the sentence are not swallowed with them.
                excludeSemantics: true,
                semanticLabel: '',
                onTap: () {
                  setState(() => _terms = !_terms);
                  ctrl.clear('acceptTerms');
                },
                toggled: _terms,
                builder: (context, state) => Semantics(
                  container: true,
                  // Without this the consent node *merges* its descendants,
                  // which put the two link spans back out of reach by a second
                  // route — measured, not assumed: they read as 0 reachable
                  // until this was added.
                  explicitChildNodes: true,
                  checked: _terms,
                  label:
                      "I agree to RaajjePro's Terms of Service and "
                      'Privacy Policy',
                  onTap: () {
                    setState(() => _terms = !_terms);
                    ctrl.clear('acceptTerms');
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Centred on the first line rather than pinned to the
                      // top of the block, so a sentence that wraps to two
                      // lines does not drag the checkbox upward.
                      SizedBox(
                        height:
                            type.secondary.fontSize! * type.secondary.height!,
                        child: Center(
                          child: Container(
                            width: AppSizes.checkbox,
                            height: AppSizes.checkbox,
                            decoration: BoxDecoration(
                              color: _terms ? colors.primary : colors.surface,
                              borderRadius: AppRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: _terms
                                    ? colors.primary
                                    : colors.neutralBorder,
                                width: AppSizes.inputStroke,
                              ),
                            ),
                            child: _terms
                                ? Icon(
                                    Icons.check_rounded,
                                    size: AppSizes.iconMd,
                                    color: colors.onPrimary,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: type.secondary,
                            children: [
                              const TextSpan(text: "I agree to RaajjePro's "),
                              TextSpan(
                                text: 'Terms of Service',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                                recognizer: _tosTap,
                                semanticsLabel: 'Terms of Service',
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                                recognizer: _privacyTap,
                                semanticsLabel: 'Privacy Policy',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (s.fieldErrors['acceptTerms'] != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
                  child: Text(
                    s.fieldErrors['acceptTerms']!,
                    style: type.caption.copyWith(color: colors.errorText),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              AppButton.primary(
                label: isProvider
                    ? 'Create Provider Account'
                    : 'Create Account',
                loading: s.busy,
                expand: true,
                onPressed: s.busy ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                  AppButton.text(
                    label: 'Sign In',
                    size: AppButtonSize.compact,
                    onPressed: () =>
                        Navigator.of(context)
                            .pushReplacementNamed(SignInScreen.routeName),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
