import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/change_controllers.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/phone_field.dart';
import 'package:raajjepro/shared/shared.dart';

/// Change phone (`Account Settings.dc.html`; plan §Phase 3). The number is
/// shown exactly as typed, the same as registration, and **never** with a
/// check mark or the word verified — nothing in this system verifies a
/// phone number (root CLAUDE.md §0.0 item 6; frontend/CLAUDE.md).
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});
  static const routeName = '/account/phone';

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  late final TextEditingController _dial;
  late final TextEditingController _number;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    final current = auth is AuthSignedIn ? auth.user.phone : null;
    // Controller ruling #1: a dead session on submit saved what was typed;
    // that draft wins over the account's current number, same as a form the
    // user was actively editing when it expired.
    final draft = ref
        .read(formDraftStoreProvider)
        .take(ChangePhoneScreen.routeName);
    _dial = TextEditingController(
      text: draft?['dialCode'] ?? current?.dialCode ?? '+960',
    );
    _number = TextEditingController(
      text: draft?['number'] ?? current?.number ?? '',
    );
  }

  @override
  void dispose() {
    _dial.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(changePhoneControllerProvider.notifier)
        .submit(_dial.text, _number.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(changePhoneControllerProvider);
    final ctrl = ref.read(changePhoneControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final current = auth is AuthSignedIn ? auth.user.phone : null;

    void clearPhoneErrors() {
      ctrl.clear('phone');
      ctrl.clear('number');
      ctrl.clear('dialCode');
    }

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Change phone',
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
                  // Plain text — no icon, no "verified".
                  Text(
                    'Current number: ${current?.display ?? 'none on file'}',
                    style: type.body.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Shown as you enter it, like registration. Nothing here checks the number belongs to you.',
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (s.offline) InlineNotice.offline(onRetry: _submit),
                  if (s.fieldErrors['form'] != null)
                    InlineNotice.error(s.fieldErrors['form']!),
                  if (s.done)
                    InlineNotice.success(
                      'Number updated — shown as you entered it',
                    ),
                  PhoneField(
                    dialCode: _dial,
                    number: _number,
                    enabled: !s.busy,
                    // Brief-vs-backend: `changePhoneBody` is the bare
                    // `{dialCode, number}` shape (`backend/src/modules/auth
                    // /schema.ts`'s `phoneField`, reused for this route), so
                    // a `VALIDATION_FAILED` path is `dialCode` or `number`,
                    // never `phone` — only the controller's own
                    // `PHONE_IN_USE` mapping uses the `phone` key. Checking
                    // all three renders whichever one the server sent under
                    // the one field this screen shows.
                    errorText:
                        s.fieldErrors['phone'] ??
                        s.fieldErrors['number'] ??
                        s.fieldErrors['dialCode'],
                    onChanged: clearPhoneErrors,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.primary(
                    label: 'Save number',
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
