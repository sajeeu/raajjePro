import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a step 1 — the intro (`Become a Provider.dc.html`, "1 · Intro").
///
/// > what being a provider on RaajjePro means in plain terms —
/// > subscription-only monetization stays invisible here (that's Phase
/// > 8a/10a's job, later), this screen is about the mechanics: publish a
/// > service, get bookings, get paid directly by the customer, communicate
/// > entirely through the app.
///
/// **Nothing here mentions money RaajjePro collects**, and that is the plan's
/// instruction rather than an omission: the subscription, the trial and the
/// free-listing cap are §Phase 8a's and §Phase 10a's, and a price on the
/// front door of a flow whose whole first screen is "here is how this works"
/// answers a question nobody has asked yet.
///
/// **The four rows are the four mechanics**, in the artboard's order and with
/// its copy. "Get paid directly" is load-bearing rather than reassuring:
/// §1b's off-platform payment rule is the single thing a new provider is most
/// likely to have assumed the other way round.
///
/// This step persists nothing. It is why §Phase 6a's resume rule starts at
/// step 2, and why "Not right now" leaves no trace to resume from.
class IntroStep extends StatelessWidget {
  const IntroStep({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xxl + AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Hero(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'How it works',
            style: type.overline.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg + 2,
              vertical: AppSpacing.xxs + 2,
            ),
            child: Column(
              children: [
                for (final (index, row) in _mechanics.indexed) ...[
                  if (index > 0)
                    Divider(height: 1, thickness: 1, color: colors.divider),
                  _MechanicRow(row: row),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.xxs / 2,
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: AppSizes.iconMd + 1,
                  color: colors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  // The reassurance the "Not right now" action makes true:
                  // nothing is published, and nothing is committed, until the
                  // provider creates a service.
                  'You can switch back to customer mode anytime. Nothing is '
                  'published until you create your first service.',
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _mechanics = [
    (
      icon: Icons.work_outline_rounded,
      accent: _Accent.blue,
      title: 'List your services',
      body: 'Add what you offer and the islands you cover.',
    ),
    (
      icon: Icons.calendar_today_outlined,
      accent: _Accent.green,
      title: 'Receive bookings & interest',
      body: 'Customers near you discover your profile and reach out.',
    ),
    (
      icon: Icons.chat_bubble_outline_rounded,
      accent: _Accent.violet,
      title: 'Agree on the job in chat',
      body: 'Discuss details, timing and scope — all in the app.',
    ),
    (
      icon: Icons.credit_card_outlined,
      accent: _Accent.amber,
      title: 'Get paid directly',
      body: 'Customers pay you directly when the job is done.',
    ),
  ];
}

/// The four icon tints the artboard uses down the list, named rather than
/// literal: the values are tokens and the *assignment* of one per row is the
/// artboard's. Each is an icon on a tint, so the 3:1 graphics bar applies
/// rather than the 4.5:1 text one — `success` and `warning` are documented as
/// icon-grade only in `AppColors`, and this is that use.
enum _Accent { blue, green, violet, amber }

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return DecoratedBox(
      decoration: BoxDecoration(
        // Phase 1's own CTA gradient, not a second copy of its stops — it is
        // directional (so the highlight mirrors under RTL) and its middle stop
        // is the one `contrast_test.dart` checks white text against.
        gradient: colors.ctaGradient,
        borderRadius: AppRadius.circular(AppRadius.feature),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.xxl - 2,
          AppSpacing.xxl + 2,
          AppSpacing.xxl - 2,
          AppSpacing.xxl + AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.onPrimary.withValues(alpha: .16),
                border: Border.all(
                  color: colors.onPrimary.withValues(alpha: .28),
                ),
                borderRadius: AppRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: AppSizes.iconSm + 2,
                    color: colors.onPrimary,
                  ),
                  const SizedBox(width: AppSpacing.xs + 1),
                  Text(
                    'For Providers',
                    style: type.pill.copyWith(color: colors.onPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg - 2),
            Text(
              'Offer your services on RaajjePro',
              style: type.screenTitle.copyWith(color: colors.onPrimary),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Text(
              'Turn your skills into bookings from customers across the '
              'Maldives — on your terms.',
              style: type.body.copyWith(
                color: colors.onPrimary.withValues(alpha: .86),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MechanicRow extends StatelessWidget {
  const _MechanicRow({required this.row});

  final ({IconData icon, _Accent accent, String title, String body}) row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final violet = CategoryAccents.byToken[AccentToken.violet]!;
    final (fill, ink) = switch (row.accent) {
      _Accent.blue => (colors.accentTint, colors.primary),
      _Accent.green => (colors.successTint, colors.success),
      _Accent.violet => (violet.tint, violet.icon),
      _Accent.amber => (colors.warningTint, colors.warning),
    };

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: AppSpacing.lg - 1,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconButtonSize,
            height: AppSizes.iconButtonSize,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AppRadius.circular(AppRadius.input),
            ),
            child: Icon(row.icon, size: AppSizes.iconLg + 3, color: ink),
          ),
          const SizedBox(width: AppSpacing.lg - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: type.cardTitle),
                const SizedBox(height: AppSpacing.xxs / 2),
                Text(
                  row.body,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
