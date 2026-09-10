import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The account email, read-only with a verified indicator.
///
/// **Unverified blocks Continue** (§Phase 6a), so the notice carries the way
/// out of it. This is the one check mark on this screen that is honest: the
/// address was confirmed by a link, unlike the number above it.
class AccountEmailRow extends StatelessWidget {
  const AccountEmailRow({
    required this.email,
    required this.verified,
    required this.errorText,
    required this.onVerify,
    super.key,
  });

  final String email;
  final bool verified;
  final String? errorText;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account email', style: type.bodyStrong),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: verified ? colors.surfaceMuted : colors.warningTint,
            borderRadius: AppRadius.circular(AppRadius.input),
            border: Border.all(
              color: verified ? colors.border : colors.warningBorder,
              width: AppSizes.inputStroke,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: type.body.copyWith(color: colors.textTertiary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (verified)
                Semantics(
                  label: 'Email verified',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: AppSizes.iconLg,
                        color: colors.success,
                      ),
                      const SizedBox(width: AppSpacing.xxs + 1),
                      ExcludeSemantics(
                        child: Text(
                          // 🔧 **"Email verified", not the bare "Verified"
                          // the artboard shows.** `design_rules_test.dart`
                          // bans the bare word in `lib/`, and it is right to:
                          // §1e's badge is three tiers with their own copy,
                          // and a lone "Verified" anywhere in this app risks
                          // reading as that. Naming the thing that was
                          // actually checked is also more truthful — the row
                          // above it holds a number nothing has verified.
                          'Email verified',
                          style: type.caption.copyWith(
                            color: colors.successText,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                AppButton.primary(
                  label: 'Verify email',
                  size: AppButtonSize.compact,
                  onPressed: onVerify,
                ),
            ],
          ),
        ),
        if (!verified) ...[
          const SizedBox(height: AppSpacing.sm),
          NoticeBanner(
            message:
                errorText ??
                'Verify your email to continue — booking notifications and '
                    'customer messages are sent here.',
            onAction: onVerify,
            actionLabel: 'Verify',
          ),
        ],
      ],
    );
  }
}
