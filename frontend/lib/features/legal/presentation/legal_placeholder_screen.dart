import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Phase 23 owns legal content. Until then these pages exist so the Register
/// links go somewhere honest: a banner and structural headings, and **no
/// policy prose** — root CLAUDE.md 1d forbids invented binding text.
class LegalPlaceholderScreen extends StatelessWidget {
  const LegalPlaceholderScreen({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: title,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: AppSpacing.screenInsets,
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.warningTint,
                    border: Border.all(color: colors.warningBorder),
                    borderRadius: AppRadius.circular(AppRadius.button),
                  ),
                  child: Text(
                    'Placeholder — legal text pending review',
                    style: type.bodyStrong.copyWith(color: colors.warningText),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                for (final h in [
                  '1. Scope',
                  '2. Your account',
                  '3. Bookings and payment',
                  '4. Data and privacy',
                  '5. Contact',
                ]) ...[
                  Text(h, style: type.sectionHeading),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '[ placeholder — pending legal review ]',
                    style: type.secondary.copyWith(color: colors.disabledText),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
