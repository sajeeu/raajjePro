import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/change_controllers.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/shared/shared.dart';

/// Change email (`Account Settings.dc.html`; plan §Phase 3). The code goes
/// to the **new** address and the account's email changes only once that
/// code is confirmed — this screen only requests the code; confirming it
/// reuses [VerifyEmailScreen] at purpose `changeEmail`.
class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});
  static const routeName = '/account/change-email';

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _reveal = false;

  @override
  void initState() {
    super.initState();
    // The Session Expired promise (controller ruling #1): a dead session on
    // submit saved the typed address (never the password); restore it here.
    final draft = ref
        .read(formDraftStoreProvider)
        .take(ChangeEmailScreen.routeName);
    final saved = draft?['newEmail'];
    if (saved != null) _email.text = saved;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newEmail = _email.text.trim();
    final currentPassword = _password.text;
    final outcome = await ref
        .read(changeEmailControllerProvider.notifier)
        .submit(newEmail, currentPassword);
    if (outcome != null && mounted) {
      Navigator.of(context).pushReplacementNamed(
        VerifyEmailScreen.routeName,
        arguments: VerifyEmailArgs(
          email: newEmail,
          purpose: OtpPurpose.changeEmail,
          initialStatus: outcome.status,
          resendAvailableAt: outcome.resendAvailableAt,
          resendOverride: () => ref
              .read(authApiProvider)
              .requestEmailChange(newEmail, currentPassword),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(changeEmailControllerProvider);
    final ctrl = ref.read(changeEmailControllerProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Change email',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "We'll send a 6-digit code to the new address. Nothing changes until you enter it.",
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (s.offline) InlineNotice.offline(onRetry: _submit),
                  if (s.fieldErrors['form'] != null)
                    InlineNotice.error(s.fieldErrors['form']!),
                  AppTextField(
                    key: const Key('ce-email'),
                    label: 'New email address',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    hint: 'you@example.mv',
                    errorText: s.fieldErrors['newEmail'],
                    enabled: !s.busy,
                    onChanged: (_) => ctrl.clear('newEmail'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    key: const Key('ce-password'),
                    label: 'Current password',
                    controller: _password,
                    obscureText: !_reveal,
                    autofillHints: const [AutofillHints.password],
                    errorText: s.fieldErrors['currentPassword'],
                    enabled: !s.busy,
                    onChanged: (_) => ctrl.clear('currentPassword'),
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
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.primary(
                    label: 'Send code',
                    loading: s.busy,
                    expand: true,
                    onPressed: s.busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
