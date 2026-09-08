import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/change_controllers.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/shared/shared.dart';

/// Change password (`Account Settings.dc.html`; plan §Phase 3 "change
/// password, change email, change phone (each re-verified)"). States:
/// default · local validation (length, mismatch) · `INVALID_CREDENTIALS`
/// under the current-password field · offline · submitting (button's own
/// loading) · success (snackbar + pop).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  static const routeName = '/account/password';

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _reveal1 = false;
  bool _reveal2 = false;
  bool _reveal3 = false;

  @override
  void initState() {
    super.initState();
    // Every field here is a password, and [ChangeFormController.run] never
    // saves one to the draft store (controller ruling #1) — so there is
    // nothing to restore. `take` is still called, for the same reason the
    // other two change screens call it: a stale draft under this key from
    // an old build must not leak into a later screen that reuses the key.
    ref.read(formDraftStoreProvider).take(ChangePasswordScreen.routeName);
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(changePasswordControllerProvider.notifier)
        .submit(_current.text, _next.text, _confirm.text);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed — other devices were signed out'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(changePasswordControllerProvider);
    final ctrl = ref.read(changePasswordControllerProvider.notifier);

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
      body: Column(
        children: [
          AppHeader.page(
            title: 'Change password',
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
                  if (s.offline) InlineNotice.offline(onRetry: _submit),
                  if (s.fieldErrors['form'] != null)
                    InlineNotice.error(s.fieldErrors['form']!),
                  AppTextField(
                    key: const Key('cp-current'),
                    label: 'Current password',
                    controller: _current,
                    obscureText: !_reveal1,
                    autofillHints: const [AutofillHints.password],
                    errorText: s.fieldErrors['currentPassword'],
                    enabled: !s.busy,
                    onChanged: (_) => ctrl.clear('currentPassword'),
                    suffix: reveal(
                      _reveal1,
                      () => setState(() => _reveal1 = !_reveal1),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    key: const Key('cp-new'),
                    label: 'New password',
                    controller: _next,
                    obscureText: !_reveal2,
                    autofillHints: const [AutofillHints.newPassword],
                    helper: 'At least 8 characters',
                    errorText: s.fieldErrors['newPassword'],
                    enabled: !s.busy,
                    onChanged: (_) => ctrl.clear('newPassword'),
                    suffix: reveal(
                      _reveal2,
                      () => setState(() => _reveal2 = !_reveal2),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    key: const Key('cp-confirm'),
                    label: 'Confirm new password',
                    controller: _confirm,
                    obscureText: !_reveal3,
                    errorText: s.fieldErrors['confirmPassword'],
                    enabled: !s.busy,
                    onChanged: (_) => ctrl.clear('confirmPassword'),
                    suffix: reveal(
                      _reveal3,
                      () => setState(() => _reveal3 = !_reveal3),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.primary(
                    label: 'Change password',
                    loading: s.busy,
                    expand: true,
                    onPressed: s.busy ? null : _submit,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Changing your password signs out every other device.',
                    style: type.caption.copyWith(color: colors.textTertiary),
                    textAlign: TextAlign.center,
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
