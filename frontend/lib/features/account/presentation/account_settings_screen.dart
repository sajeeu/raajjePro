import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/features/account/presentation/widgets/settings_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// Account settings (`Account Settings.dc.html`; plan §Phase 3). Rows the
/// plan names; Saved preferences is deferred past Phase 4 and the notification
/// toggles are Phase 19's, so neither renders here. States: loading (skeleton
/// rows) · error · populated · frozen (banner + changed delete row).
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});
  static const routeName = '/account';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final user = ref.watch(accountControllerProvider);
    final sessions = ref.watch(sessionsControllerProvider);

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Account settings',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: user.when(
              loading: () => SkeletonLoader(
                child: ListView(
                  padding: AppSpacing.screenInsets,
                  children: [
                    for (var i = 0; i < 6; i++)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(
                          bottom: AppSpacing.md,
                        ),
                        child: SkeletonRow(),
                      ),
                  ],
                ),
              ),
              error: (_, _) => Center(
                child: Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState.error(
                    title: "Couldn't load settings",
                    body: 'Your connection may have dropped. Nothing is lost — try again.',
                    onRetry: () =>
                        ref.read(accountControllerProvider.notifier).reload(),
                  ),
                ),
              ),
              data: (u) {
                final frozen = u.status == AccountStatus.frozen;
                final count = sessions.value?.length;
                return ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xxl,
                  ),
                  children: [
                    Text(
                      '${u.fullName} · ${u.email}',
                      style: type.secondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (frozen && u.deletionDeadlineAt != null) ...[
                      Container(
                        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.accentTint,
                          border: Border.all(color: colors.accentBorder),
                          borderRadius: AppRadius.circular(AppRadius.button),
                        ),
                        child: Text(
                          'Your account is frozen and will be deleted by ${shortDate(u.deletionDeadlineAt!)} at the latest.',
                          style: type.secondary.copyWith(
                            color: colors.accentText,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      title: 'Change password',
                      subtitle: 'Current password required',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account/password'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsRow(
                      icon: Icons.mail_outline_rounded,
                      title: 'Change email',
                      subtitle: 'A code goes to the new address first',
                      onTap: () =>
                          Navigator.of(context)
                              .pushNamed('/account/change-email'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsRow(
                      icon: Icons.phone_android_outlined,
                      title: 'Change phone',
                      subtitle: 'Shown as you enter it, like registration',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account/phone'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsRow(
                      icon: Icons.devices_outlined,
                      title: 'Active sessions',
                      subtitle: count == null
                          ? "Everywhere you're signed in"
                          : '$count ${count == 1 ? 'device' : 'devices'} signed in',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account/sessions'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsRow(
                      icon: Icons.download_outlined,
                      title: 'Download my data',
                      subtitle: 'Profile, bookings, reviews, messages',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account/download'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsRow(
                      icon: Icons.delete_outline_rounded,
                      title: frozen ? 'Deletion in progress' : 'Delete account',
                      subtitle: frozen
                          ? 'No new bookings or listings until it completes'
                          : 'Accepted immediately, completes within 30 days',
                      destructive: true,
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account/delete'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
