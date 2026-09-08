import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// `App States.dc.html` → Session expired. One action and one promise, which
/// the FormDraftStore keeps true. Nothing here may suggest work was lost.
class SessionExpiredScreen extends StatelessWidget {
  const SessionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppSpacing.screenInsets,
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.accentTint,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: colors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Signed out for your security',
                  style: type.sectionHeading,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your session expired while you were away. Sign in again to pick up where you left off.',
                  style: type.secondary.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'What you were typing is kept — it will be restored after you sign in.',
                  style: type.caption.copyWith(color: colors.textTertiary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton.primary(
                  label: 'Sign In Again',
                  expand: true,
                  onPressed: () =>
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/sign-in', (_) => false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
