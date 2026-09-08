import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Dial code + national number (`Register.dc.html`; plan §Phase 3). `+960`
/// is the default, foreign codes are welcome, 6-15 digits. The number is
/// shown as typed and **never** with a check mark or the word verified —
/// nothing in this system verifies it. [errorWidget] lets the caller render
/// the duplicate-phone copy with its inline sign-in route under the field.
class PhoneField extends StatelessWidget {
  const PhoneField({
    required this.dialCode,
    required this.number,
    super.key,
    this.errorText,
    this.errorWidget,
    this.onChanged,
    this.enabled = true,
  });
  final TextEditingController dialCode;
  final TextEditingController number;
  final String? errorText;
  final Widget? errorWidget;
  final VoidCallback? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final foreign =
        dialCode.text.trim() != '+960' && dialCode.text.trim().length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // `AppTextField.prefixIcon` only takes an `IconData`, so the
            // Maldivian flag glyph goes before the field as its own Text
            // rather than inside it — the foreign case instead shows a
            // `public` glyph via `prefixIcon`, which the type does support.
            if (!foreign)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppSpacing.xs,
                  bottom: AppSpacing.md + 2,
                ),
                child: Text('🇲🇻', style: type.body),
              ),
            SizedBox(
              width: 104,
              child: AppTextField(
                key: const Key('reg-dial'),
                label: 'Code',
                controller: dialCode,
                keyboardType: TextInputType.phone,
                prefixIcon: foreign ? Icons.public : null,
                hint: '+960',
                enabled: enabled,
                onChanged: (_) => onChanged?.call(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                key: const Key('reg-phone'),
                label: 'Phone Number',
                controller: number,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                hint: '777 1234',
                errorText: errorText,
                helper: foreign
                    ? 'Foreign numbers welcome — 6 to 15 digits.'
                    : null,
                enabled: enabled,
                onChanged: (_) => onChanged?.call(),
              ),
            ),
          ],
        ),
        if (errorWidget != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
            child: DefaultTextStyle(
              style: type.caption.copyWith(color: colors.errorText),
              child: errorWidget!,
            ),
          ),
      ],
    );
  }
}
