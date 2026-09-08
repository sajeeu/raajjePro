import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/shared/shared.dart';

/// Download my data (`Account Settings.dc.html`; plan §Phase 3). The export
/// is fetched as JSON and handed to the OS share sheet — never emailed. The
/// prototype's "emailed within a day" copy is the flagged divergence (plan
/// wins: `AuthApi.dataExport()` returns synchronously, so there is nothing
/// to wait a day for).
class DownloadDataScreen extends ConsumerWidget {
  const DownloadDataScreen({super.key});
  static const routeName = '/account/download';

  static const _items = [
    'Profile details',
    'Bookings and their records',
    'Reviews you wrote',
    'Message history',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(downloadControllerProvider);

    return Scaffold(
      body: Column(
        children: [
          AppHeader.page(
            title: 'Download my data',
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
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: AppSizes.iconDisc,
                        height: AppSizes.iconDisc,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.accentTint,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.download_outlined,
                          color: colors.primary,
                          size: AppSizes.iconLg,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        "A copy of everything you've put in",
                        style: type.cardTitle,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your export includes your profile, bookings, reviews and messages. It comes as a JSON file you can save or share from your phone.',
                        style: type.secondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      for (final item in _items)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: AppSizes.iconMd,
                                color: colors.success,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  item,
                                  style: type.body.copyWith(color: colors.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (s.shared)
                  InlineNotice.success(
                    'Your export is ready — saved or shared from the sheet you chose.',
                  )
                else if (s.offline)
                  InlineNotice.offline(
                    onRetry: () =>
                        ref.read(downloadControllerProvider.notifier).request(),
                  )
                else if (s.failed)
                  InlineNotice.error(
                    "Couldn't prepare your export. Try again in a moment.",
                  ),
                AppButton.primary(
                  label: 'Request my data',
                  expand: true,
                  loading: s.fetching,
                  onPressed: s.fetching
                      ? null
                      : () => ref
                            .read(downloadControllerProvider.notifier)
                            .request(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
