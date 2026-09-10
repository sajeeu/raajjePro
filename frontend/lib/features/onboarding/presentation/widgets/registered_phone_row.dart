import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a: the phone is "pre-filled from Phase 3 and confirmed, never
/// re-typed", and an `editingPhone` state reveals the input only on request.
///
/// **Never a check mark and never the word verified.** Nothing in this system
/// verifies a phone number (§0.0 item 6); uniqueness begins at Bronze, and
/// uniqueness is not ownership. The locked row shows the number and a Change
/// button, and that is all it claims.
class RegisteredPhoneRow extends StatelessWidget {
  const RegisteredPhoneRow({
    required this.editing,
    required this.dial,
    required this.number,
    required this.display,
    required this.errorText,
    required this.onEdit,
    required this.onChanged,
    super.key,
  });

  final bool editing;
  final TextEditingController dial;
  final TextEditingController number;
  final String? display;
  final String? errorText;
  final VoidCallback onEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    // An account with no number on file has nothing to confirm, so the input
    // is already open — the "never re-typed" rule is about not asking again
    // for something already given.
    final locked = !editing && (display?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your registered mobile number', style: type.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        if (locked)
          Container(
            constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.circular(AppRadius.input),
              border: Border.all(
                color: colors.border,
                width: AppSizes.inputStroke,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.smartphone_outlined,
                  size: AppSizes.iconLg,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(display!, style: type.cardTitle)),
                AppButton.secondary(
                  label: 'Change',
                  size: AppButtonSize.compact,
                  onPressed: onEdit,
                ),
              ],
            ),
          )
        else
          PhoneField(
            dialCode: dial,
            number: number,
            errorText: errorText,
            onChanged: onChanged,
          ),
        if (locked && errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: type.secondary.copyWith(color: colors.errorText),
          ),
        ],
        if (errorText == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            locked
                ? 'From your account. Used for booking updates, never shown '
                      'publicly.'
                : 'Any country code works — expatriate residents can keep a '
                      'foreign number.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}
