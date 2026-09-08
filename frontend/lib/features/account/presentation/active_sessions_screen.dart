import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/shared/shared.dart';

/// Active sessions (`Account Settings.dc.html`; plan §Phase 3). Revoking a
/// device signs out only that device — never the whole account. The DTO
/// carries neither an IP nor a user agent, so nothing here renders one.
class ActiveSessionsScreen extends ConsumerWidget {
  const ActiveSessionsScreen({super.key});
  static const routeName = '/account/sessions';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final sessions = ref.watch(sessionsControllerProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Active sessions',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: sessions.when(
              loading: () => Padding(
                padding: AppSpacing.screenInsets,
                child: SkeletonLoader.rows(),
              ),
              error: (_, _) => Center(
                child: Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState.error(
                    title: "Couldn't load your devices",
                    body: 'Your connection may have dropped. Nothing is lost — try again.',
                    onRetry: () => ref.invalidate(sessionsControllerProvider),
                  ),
                ),
              ),
              data: (list) => ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  Text(
                    "Everywhere you're signed in. Revoking a device signs out only that device.",
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.devices_outlined,
                      title: 'No devices signed in',
                      body: 'Sign in again on a device to see it here.',
                    ),
                  for (final s in list) ...[
                    _SessionRow(session: s, now: now),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session, required this.now});
  final SessionInfo session;
  final DateTime now;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref
        .read(sessionActionControllerProvider.notifier)
        .signOutThisDevice();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Sign out ${session.deviceName}?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Only that device is signed out. This one stays.',
              style: sheetContext.type.secondary.copyWith(
                color: sheetContext.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.destructive(
              key: const Key('confirm-revoke'),
              label: 'Revoke',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(
              label: 'Keep signed in',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final name = await ref
          .read(sessionActionControllerProvider.notifier)
          .revoke(session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name signed out — only that device')),
        );
      }
    } on Object {
      // ApiException, ApiNetworkException, or the StateError a stale id
      // (already revoked elsewhere, or the list refreshed under us) raises
      // from `firstWhere` — every one of them left this row silently stuck
      // with no feedback at all before final review #6.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't revoke that device. Try again."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(sessionActionControllerProvider);
    final ageText = session.current
        ? 'active now'
        : 'Last used ${relativeAge(session.lastSeenAt, now)}';

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accentTint,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.smartphone_outlined,
              color: colors.primary,
              size: AppSizes.iconLg,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.deviceName,
                        style: type.cardTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.current) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.successTint,
                          border: Border.all(color: colors.successBorder),
                          borderRadius: AppRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'This device',
                          style: type.pill.copyWith(color: colors.successText),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  ageText,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (session.current)
            AppButton.text(
              label: 'Sign out',
              size: AppButtonSize.compact,
              loading: action.signingOut,
              onPressed: action.signingOut
                  ? null
                  : () => _signOut(context, ref),
            )
          else
            AppButton.secondary(
              label: 'Revoke',
              size: AppButtonSize.compact,
              loading: action.revokingId == session.id,
              onPressed: action.revokingId != null
                  ? null
                  : () => _revoke(context, ref),
            ),
        ],
      ),
    );
  }
}
