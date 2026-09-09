import 'package:flutter/material.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The Legal row's destination (`Legal.dc.html`; reached from Phase 6's
/// Profile).
///
/// Navigation only — it lists the two documents that already exist as
/// placeholders and pushes them. **No policy prose is written here**, exactly
/// as [LegalPlaceholderScreen] writes none: root CLAUDE.md 1d forbids
/// inventing binding legal text, and §Phase 23 replaces the documents' bodies
/// with real, legally-reviewed copy.
///
/// Phase 6 builds this because §Phase 6's Done-when says every row navigates
/// and the Legal row's destination is a list of documents rather than one
/// document. Pointing the row straight at Terms of Service would have
/// mislabelled it.
class LegalIndexScreen extends StatelessWidget {
  const LegalIndexScreen({super.key});

  static const routeName = AppRoutes.legal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Legal',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
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
                const SizedBox(height: AppSpacing.lg),
                SettingsRow(
                  icon: Icons.gavel_rounded,
                  title: 'Terms of Service',
                  onTap: () => Navigator.of(context).pushNamed('/legal/terms'),
                ),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(
                  icon: Icons.shield_outlined,
                  title: 'Privacy Policy',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/legal/privacy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
