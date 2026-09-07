import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/register_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/phone_field.dart';
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

  @override
  void dispose() {
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
        '/verify-email',
        arguments: {
          'email': _email.text.trim(),
          'status': outcome.status.name,
          'resendAvailableAt': outcome.resendAvailableAt.toIso8601String(),
        },
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHero(
              title: 'Create account',
              subtitle: 'Join RaajjePro — it only takes a minute',
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
                  if (s.offline) InlineNotice.offline(onRetry: _submit),
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
                  if (s.fieldErrors['email'] != null &&
                      s.fieldErrors['email']!.contains('already'))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.xs,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppButton.text(
                            label: 'Sign in',
                            size: AppButtonSize.compact,
                            onPressed: () =>
                                Navigator.of(context)
                                    .pushReplacementNamed('/sign-in'),
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
                                Navigator.of(context)
                                    .pushNamed('/forgot-password'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  PhoneField(
                    dialCode: _dial,
                    number: _phone,
                    errorText:
                        s.fieldErrors['phone'] != null &&
                            !s.fieldErrors['phone']!.contains(
                              'verified provider',
                            )
                        ? s.fieldErrors['phone']
                        : null,
                    errorWidget:
                        s.fieldErrors['phone'] != null &&
                            s.fieldErrors['phone']!.contains(
                              'verified provider',
                            )
                        ? Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                "This number belongs to a verified provider account. If it's yours, ",
                              ),
                              AppButton.text(
                                label: 'sign in',
                                size: AppButtonSize.compact,
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushReplacementNamed('/sign-in'),
                              ),
                              const Text(
                                ' instead — or use a different number.',
                              ),
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
                  Pressable(
                    key: const Key('reg-terms'),
                    semanticLabel:
                        'I agree to the Terms of Service and Privacy Policy${_terms ? ', checked' : ', not checked'}',
                    onTap: () {
                      setState(() => _terms = !_terms);
                      ctrl.clear('acceptTerms');
                    },
                    toggled: _terms,
                    builder: (context, state) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: AppSizes.checkbox,
                          height: AppSizes.checkbox,
                          decoration: BoxDecoration(
                            color: _terms ? colors.primary : colors.surface,
                            borderRadius: AppRadius.circular(AppRadius.xs),
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
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                "I agree to RaajjePro's ",
                                style: type.secondary,
                              ),
                              AppButton.text(
                                label: 'Terms of Service',
                                size: AppButtonSize.compact,
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushNamed('/legal/terms'),
                              ),
                              Text(' and ', style: type.secondary),
                              AppButton.text(
                                label: 'Privacy Policy',
                                size: AppButtonSize.compact,
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushNamed('/legal/privacy'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (s.fieldErrors['acceptTerms'] != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.xs,
                      ),
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
                                .pushReplacementNamed('/sign-in'),
                      ),
                    ],
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
