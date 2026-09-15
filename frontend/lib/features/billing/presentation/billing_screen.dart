import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/billing/controller/billing_controller.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/features/billing/presentation/pay_by_bank_transfer_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Billing & subscription** (`Billing.dc.html`) — §Phase 10a part 1.
///
/// One screen, five plan states, all of them the server's: trial, premium,
/// free, paused, expired — plus the downgraded reading of `free`, where §1b's
/// hiding has already happened and the list of what it hid is real. The two
/// upgrade CTAs are different buttons for different people (§0.4): "Pay by
/// bank transfer" for anyone who can pay, "Try Premium" only for a provider
/// who has never had a trial.
///
/// **No billing rule is evaluated here** (Round 19, §Phase 23; invariant 4).
/// Every date and every number is a field off `GET /v1/providers/me/
/// subscription`: the grace end, the next period, the price cohort, the pause
/// budget. Where this screen wants a fact the server does not send, the
/// answer is a field, never a formula in Dart.
///
/// **Two artboard lines are not rendered, and one is added** — all three
/// checked against the plan on 2026-09-15 (`docs/design/sessions/round-59-…`):
///
///  * no header subtitle: "Same page on the web" states as fact a page that
///    exists only as §Phase 23's App Store contingency;
///  * no editorial pricing number in the introductory copy: the standard
///    rate is not on the wire, and §1b forbids a hardcoded platform price;
///  * the pause card carries the sentence ledger row **P8A-4** owes — that
///    pausing is the same switch as "Accepting new customers", spends a
///    ten-day allowance that does not refill, and moves the billing anchor.
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  static const routeName = AppRoutes.providerBilling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(billingControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Billing & subscription',
            backLabel: 'Back to My Services',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (state) {
              AsyncLoading() => const _BillingSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your billing',
                  body: error is ApiNetworkException
                      ? 'Your plan and payments are safe — we just couldn’t '
                            'reach them. Check your connection and try again.'
                      : 'Your plan and payments are safe — something went '
                            'wrong fetching them. Try again.',
                  onRetry: () =>
                      ref.read(billingControllerProvider.notifier).reload(),
                ),
              ),
              AsyncData(:final value) => _BillingBody(state: value),
            },
          ),
        ],
      ),
    );
  }
}

class _BillingBody extends ConsumerWidget {
  const _BillingBody({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = state.status;
    final plan = _PlanCopy.of(status);
    final submission = status.latestSubmission;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        if (submission != null && !submission.isOpenIntent)
          _SubmissionNotice(submission: submission),
        if (submission != null && !submission.isOpenIntent)
          const SizedBox(height: AppSpacing.md),
        _StateCard(state: state, plan: plan),
        const SizedBox(height: AppSpacing.md),
        _BadgeCard(tier: state.provider.verificationTier),
        const SizedBox(height: AppSpacing.md),
        const _PlanTable(),
        if (status.pausable) ...[
          const SizedBox(height: AppSpacing.md),
          _PauseCard(status: status),
        ],
        const SizedBox(height: AppSpacing.md),
        _LapseCard(state: state),
        const SizedBox(height: AppSpacing.md),
        AppCard.row(
          leading: const RowIcon(icon: Icons.receipt_long_outlined),
          title: 'Invoices',
          subtitle: 'One per confirmed payment, with PDF',
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: context.colors.textTertiary,
          ),
          semanticLabel: 'Invoices — one per confirmed payment, with PDF',
          onTap: () =>
              Navigator.of(context).pushNamed(InvoicesScreen.routeName),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Payment is by manual bank transfer, confirmed within 48 hours. '
          'We’ll remind you 7 days before a trial or period ends; after '
          'expiry nothing changes for 7 days.',
          style: context.type.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }
}

/// What the state card says, per server state. Copy from `Billing.dc.html`'s
/// `STATES`, with every date and number taken from the response.
class _PlanCopy {
  const _PlanCopy({
    required this.label,
    required this.tone,
    required this.title,
    required this.body,
    this.showPrice = false,
    this.showPay = false,
    this.showTrial = false,
    this.showResume = false,
    this.showPauseBar = false,
  });

  final String label;
  final BadgeTone tone;
  final String title;
  final String body;
  final bool showPrice;
  final bool showPay;
  final bool showTrial;
  final bool showResume;
  final bool showPauseBar;

  static _PlanCopy of(SubscriptionStatusView s) {
    final trialEnds = s.trialEndsAt;
    final periodEnd = s.currentPeriodEnd;
    switch (s.status) {
      case SubscriptionStatus.trialing:
        final days = s.trialDaysRemaining;
        return _PlanCopy(
          label: days == null
              ? 'Trial'
              : 'Trial · $days ${days == 1 ? 'day' : 'days'} left',
          tone: BadgeTone.blue,
          title: 'Premium trial',
          body:
              'Your trial ends ${_date(trialEnds)}. We’ll remind you 7 days '
              'before, and after it ends nothing changes for 7 more days. To '
              'keep Premium, pay by bank transfer any time before then.',
          showPrice: true,
          showPay: true,
        );
      case SubscriptionStatus.active:
        return _PlanCopy(
          label: 'Premium',
          tone: BadgeTone.green,
          title: 'Premium',
          body:
              'Next payment ${_date(periodEnd)}. Periods run 30 days from '
              'your billing anchor — not calendar months — so pausing moves '
              'the date with you.',
          showPrice: true,
          showPay: true,
        );
      case SubscriptionStatus.paused:
        return _PlanCopy(
          label: 'Paused · ${s.cumulativePausedDays} days of 10 used',
          tone: BadgeTone.amber,
          title: 'Premium, paused',
          body:
              'Nothing is billed while paused. Your next payment has moved '
              'with the pause — currently ${_date(periodEnd ?? trialEnds)} — '
              'and moves further for each paused day.',
          showPauseBar: true,
          showResume: true,
        );
      case SubscriptionStatus.expired:
        return _PlanCopy(
          label: 'Expired',
          tone: BadgeTone.red,
          title: 'Premium expired ${_date(periodEnd ?? trialEnds)}',
          body:
              'You’re in the 7-day grace period — nothing has changed yet. '
              'Without a confirmed payment by ${_date(s.graceEndsAt)}, '
              'services beyond your first are hidden (never deleted).',
          showPrice: true,
          showPay: true,
        );
      case SubscriptionStatus.free:
      case SubscriptionStatus.none:
        if (s.downgraded) {
          return const _PlanCopy(
            label: 'Free',
            tone: BadgeTone.grey,
            title: 'Premium lapsed',
            body:
                'Your Premium period ended and the 7-day grace period has '
                'passed. Services beyond your first are hidden — not deleted '
                '— and one confirmed payment brings them back.',
            showPrice: true,
            showPay: true,
          );
        }
        if (s.trialAvailable) {
          return const _PlanCopy(
            label: 'Free',
            tone: BadgeTone.grey,
            title: 'Free plan',
            body:
                'One active service with full search visibility. You’ve never '
                'tried Premium — the trial is 30 days, with no payment to '
                'start.',
            showPrice: true,
            showTrial: true,
          );
        }
        return const _PlanCopy(
          label: 'Free',
          tone: BadgeTone.grey,
          title: 'Free plan',
          body:
              'One active service with full search visibility. Upgrade any '
              'time — one confirmed payment unlocks Premium.',
          showPrice: true,
          showPay: true,
        );
    }
  }

  static String _date(DateTime? d) => d == null ? '—' : shortDate(maldives(d));
}

class _StateCard extends ConsumerStatefulWidget {
  const _StateCard({required this.state, required this.plan});

  final BillingState state;
  final _PlanCopy plan;

  @override
  ConsumerState<_StateCard> createState() => _StateCardState();
}

class _StateCardState extends ConsumerState<_StateCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      AppHaptics.commit();
    } else {
      AppHaptics.refused();
    }
    messenger.showSnackBar(SnackBar(content: Text(error ?? success)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final status = widget.state.status;
    final plan = widget.plan;
    final controller = ref.read(billingControllerProvider.notifier);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(plan.title, style: type.sectionHeading),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge.custom(label: plan.label, tone: plan.tone),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            plan.body,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          if (plan.showPauseBar) ...[
            const SizedBox(height: AppSpacing.md),
            _PauseBar(status: status),
          ],
          if (plan.showPrice) ...[
            const SizedBox(height: AppSpacing.md),
            _PriceBlock(status: status),
          ],
          if (plan.showPay) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: 'Pay by bank transfer',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamed(PayByBankTransferScreen.routeName),
            ),
          ],
          if (plan.showTrial) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: 'Try Premium free for 30 days',
              expand: true,
              loading: _busy,
              onPressed: () => _run(
                controller.startTrial,
                'Trial started — 30 days of Premium. No payment needed yet.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No payment to start. When the trial ends, nothing changes for '
              '7 more days.',
              textAlign: TextAlign.center,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (plan.showResume) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: status.remainingPauseAllowanceDays > 0
                  ? 'Resume now — keep the '
                        '${status.remainingPauseAllowanceDays} unused '
                        '${status.remainingPauseAllowanceDays == 1 ? 'day' : 'days'}'
                  : 'Resume now',
              expand: true,
              loading: _busy,
              onPressed: () => _run(
                controller.resume,
                'Resumed — your billing clock is running again.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `6 of 10 pause days used · resumes by itself when they run out`.
class _PauseBar extends StatelessWidget {
  const _PauseBar({required this.status});

  final SubscriptionStatusView status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final used = status.cumulativePausedDays.clamp(0, 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: used / 10,
            minHeight: AppSpacing.xs,
            backgroundColor: colors.neutralTint,
            color: colors.warning,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$used of 10 pause days used · resumes by itself when they run out',
          style: context.type.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// `MVR 75 · per 30-day period · YOUR RATE`, and which cohort that is.
///
/// The number is `nextPaymentAmountLaari` — this provider's own settled price,
/// or §1b's cohort rule before one is written. The introductory copy names no
/// standard-rate figure: it is not on the wire, and §1b's whole point is that
/// two price points coexist and neither is a platform constant.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.status});

  final SubscriptionStatusView status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final convertsAt = status.introductoryConvertsAt;
    final String cohort;
    if (status.introductory) {
      cohort = convertsAt == null
          ? 'Introductory rate for the first 100 providers, held for 12 '
                'months from your billing anchor, then the standard rate with '
                '30 days’ notice. Prices are set per provider; another '
                'provider may see a different number.'
          : 'Introductory rate for the first 100 providers, held for 12 '
                'months from your billing anchor — until '
                '${shortDate(maldives(convertsAt))}, then the standard rate '
                'with 30 days’ notice. Prices are set per provider; another '
                'provider may see a different number.';
    } else {
      cohort =
          'Standard rate. Prices are set per provider; another provider may '
          'see a different number.';
    }
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md2),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(mvr(status.nextPaymentAmountLaari), style: type.stat),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'per 30-day period',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                status.priceLaari == null ? 'YOUR NEXT PAYMENT' : 'YOUR RATE',
                style: type.overline.copyWith(color: colors.accentText),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            cohort,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The provider's most recent submitted attempt, in one line, leading to the
/// pay screen where the full state lives. Not shown for an open intent — an
/// intent nobody finished is not "pending confirmation".
class _SubmissionNotice extends StatelessWidget {
  const _SubmissionNotice({required this.submission});

  final PaymentSubmission submission;

  @override
  Widget build(BuildContext context) {
    final String message;
    final IconData icon;
    if (submission.isAwaitingConfirmation) {
      message =
          'Transfer submitted ${shortDate(maldives(submission.submittedAt!))} '
          '— pending confirmation, up to 48 hours. Nothing changes until '
          'then.';
      icon = Icons.hourglass_top_rounded;
    } else if (submission.isRejected && submission.isAppealed) {
      message =
          'Appeal sent — an admin will look at your transfer again. You can '
          'also resubmit now.';
      icon = Icons.rate_review_outlined;
    } else if (submission.isRejected) {
      message =
          'Your last transfer wasn’t confirmed. See the admin’s reason, '
          'resubmit straight away or appeal.';
      icon = Icons.error_outline_rounded;
    } else {
      return const SizedBox.shrink();
    }
    return NoticeBanner(
      message: message,
      icon: icon,
      actionLabel: 'View',
      onAction: () =>
          Navigator.of(context).pushNamed(PayByBankTransferScreen.routeName),
    );
  }
}

/// §1e and §1b together: the badge is on neither plan and cannot be bought.
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.tier});

  final VerificationTier tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final name = VerificationBadge.nameFor(tier);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tier != VerificationTier.none) ...[
            VerificationBadge(tier: tier),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Premium does not include the verification badge. ',
                    style: type.bodyStrong,
                  ),
                  TextSpan(
                    text: tier == VerificationTier.none
                        ? 'The badge is a safety check gated by verification '
                              'alone — it can’t be bought on any plan, and it '
                              'never lapses with a subscription.'
                        : 'Your $name badge is a safety check gated by '
                              'verification alone — it stays with you even if '
                              'the subscription lapses, and no plan can buy '
                              'it.',
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// §1b's tier table, as a comparison. Static because it *is* the plan's
/// table; the one number in it — the free tier's one listing — is §1b's.
class _PlanTable extends StatelessWidget {
  const _PlanTable();

  static const _rows = <(String, String, String)>[
    ('Active services', '1', 'Multiple'),
    ('Search visibility', 'Full', 'Full'),
    ('Priority placement', '—', '✓'),
    ('Analytics', '—', '✓'),
    ('Weekly digest', '—', '✓'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final head = type.overline.copyWith(color: colors.textSecondary);
    final cell = type.secondary.copyWith(color: colors.ink);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('What each plan includes', style: type.cardTitle),
          ),
          const SizedBox(height: AppSpacing.md),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  Text('FREE', style: head),
                  Text('PREMIUM', style: head),
                ],
              ),
              for (final (label, free, premium) in _rows)
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.divider)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(label, style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(free, style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(premium, style: cell),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The verification badge is on neither list — it can’t be bought '
            'on any plan.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "Pause Premium" — §1b's pause, and the sentence ledger row **P8A-4** owes.
///
/// Shown while `trialing` **or** `active`: §1b's one function "applies
/// identically" to both, so the card does too. `Billing.dc.html` draws it on
/// the premium state only; the plan wins.
class _PauseCard extends ConsumerStatefulWidget {
  const _PauseCard({required this.status});

  final SubscriptionStatusView status;

  @override
  ConsumerState<_PauseCard> createState() => _PauseCardState();
}

class _PauseCardState extends ConsumerState<_PauseCard> {
  bool _open = false;
  bool _busy = false;

  Future<void> _pause() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref.read(billingControllerProvider.notifier).pause();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _open = false;
    });
    if (error == null) {
      AppHaptics.commit();
    } else {
      AppHaptics.refused();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Paused — your next payment date stops moving today.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final remaining = widget.status.remainingPauseAllowanceDays;
    final exhausted = remaining <= 0;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(
            semanticLabel: 'Pause Premium',
            toggled: _open,
            focusRadius: AppRadius.panel,
            onTap: () {
              AppHaptics.selection();
              setState(() => _open = !_open);
            },
            builder: (context, s) => Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
              child: Row(
                children: [
                  const RowIcon(icon: Icons.pause_circle_outline_rounded),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pause Premium', style: type.cardTitle),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Going off-island, Ramadan, repairs — stop the clock',
                          style: type.secondary.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: context.motion.fast,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(
                    height: AppSizes.dividerStroke,
                    color: colors.divider,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final line in const [
                    '10 cumulative days of pause, spent in any pieces',
                    'Resume early and the unused days stay yours',
                    'At the cap it resumes by itself',
                    'Your next payment date moves by however long you paused',
                  ]) ...[
                    Text(
                      '· $line',
                      style: type.secondary.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  // Ledger row P8A-4: the toggle's billing consequence, said
                  // where the toggle's effect renders beside a live
                  // subscription.
                  Text(
                    'Pausing is the same switch as “Accepting new customers” '
                    'in your provider profile — turning that off pauses '
                    'billing too. Either way it spends this subscription’s '
                    '10 pause days, which don’t refill, and moves your '
                    'billing anchor by however long you paused.',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton.secondary(
                    label: exhausted
                        ? 'No pause days left on this subscription'
                        : 'Pause now — $remaining '
                              '${remaining == 1 ? 'day' : 'days'} available',
                    expand: true,
                    loading: _busy,
                    onPressed: exhausted ? null : _pause,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "If Premium lapses — hiding, never deleting", and on a downgraded account
/// the real list of what was hidden, with §1b's override.
///
/// The list renders only when the hiding has happened: which listing survives
/// is the server's ranking, computed at downgrade time, and is not exposed
/// beforehand — a preview here would be a second copy of §1b's rule. The
/// grace-state copy says what will happen instead of guessing to whom.
class _LapseCard extends ConsumerWidget {
  const _LapseCard({required this.state});

  final BillingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final hidden = state.hiddenOverCap;
    final live = state.live;
    final showList = state.status.downgraded && hidden.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('If Premium lapses', style: type.cardTitle),
                ),
              ),
              const AppChip.label(label: 'Hiding, never deleting'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Services beyond your first are ',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
                TextSpan(text: 'hidden, not deleted', style: type.bodyStrong),
                TextSpan(
                  text:
                      ' — numbers, reviews and history all stay, and one '
                      'confirmed payment brings everything back. A listing '
                      'with a live booking is protected and stays visible '
                      'regardless of the cap.',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (showList) ...[
            const SizedBox(height: AppSpacing.md),
            for (final listing in live)
              _LapseRow(
                name: listing.name ?? 'Untitled service',
                note: 'Stays live',
                noteColor: colors.successText,
              ),
            for (final listing in hidden)
              _LapseRow(
                name: listing.name ?? 'Untitled service',
                note: 'Hidden until a confirmed payment — nothing is deleted',
                noteColor: colors.textSecondary,
                onKeep: () => _keep(context, ref, listing),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The kept listing is your best-performing by confirmed bookings '
              'over 90 days — you can override which one.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _keep(
    BuildContext context,
    WidgetRef ref,
    ServiceListing listing,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(billingControllerProvider.notifier)
        .keepVisible(listing);
    if (error == null) {
      AppHaptics.commit();
    } else {
      AppHaptics.refused();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ?? '${listing.name ?? 'That service'} will stay live instead.',
        ),
      ),
    );
  }
}

class _LapseRow extends StatelessWidget {
  const _LapseRow({
    required this.name,
    required this.note,
    required this.noteColor,
    this.onKeep,
  });

  final String name;
  final String note;
  final Color noteColor;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: type.bodyStrong),
                Text(note, style: type.caption.copyWith(color: noteColor)),
              ],
            ),
          ),
          if (onKeep != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AppButton.secondary(
              label: 'Keep this one instead',
              size: AppButtonSize.compact,
              onPressed: onKeep,
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingSkeleton extends StatelessWidget {
  const _BillingSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonLoader(
    label: 'Loading your billing',
    child: ListView(
      padding: AppSpacing.screenInsets,
      children: const [
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 220, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 84, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 200, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 72, radius: AppRadius.panel),
      ],
    ),
  );
}
