import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/billing/controller/billing_controller.dart';
import 'package:raajjepro/features/billing/controller/pay_flow_controller.dart';
import 'package:raajjepro/features/billing/data/billing_models.dart';
import 'package:raajjepro/features/billing/presentation/invoices_screen.dart';
import 'package:raajjepro/features/billing/presentation/widgets/billing_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Pay by bank transfer** (`Pay by Bank Transfer.dc.html`) — §1b's manual
/// payment mechanism, steps 1–3 and 5, from the provider's side.
///
/// Three phases, all decided by the **server's** latest submission:
///
///  * **form** — an intent is open (or is opened on arrival): the amount,
///    RaajjePro's account, the reference code, the proof, and submit;
///  * **pending** — submitted and in the admin's queue. "Pending grants
///    nothing yet" is said in so many words, because §1b's rule is that a
///    pending submission produces entitlements identical to no payment;
///  * **rejected** — the admin's reason, verbatim, with §1b step 5's two
///    actions as real buttons: resubmit immediately (a fresh intent, no
///    cooldown) and appeal (a re-review request on the same row).
///
/// **Built once, parameterised by purpose.** The submission's `purpose` rides
/// along and decides copy only; `subscription` is the one purpose a provider
/// reaches today and `emergency_dispatch_fee` is already on the enum.
///
/// **Nothing is queued offline.** `Pay by Bank Transfer.dc.html` drew a
/// "Saved on this phone — sends on reconnect" state; §0.0 item 14 bounds the
/// queue to three surfaces that do not include payment, and a promise that a
/// proof of payment will send when nothing will send it is a false promise
/// about money. Offline, the form stays exactly as it was, the receipt stays
/// attached, and the notice offers a live retry.
class PayByBankTransferScreen extends ConsumerStatefulWidget {
  const PayByBankTransferScreen({super.key});

  static const routeName = '/provider/billing/pay';

  @override
  ConsumerState<PayByBankTransferScreen> createState() =>
      _PayByBankTransferScreenState();
}

class _PayByBankTransferScreenState
    extends ConsumerState<PayByBankTransferScreen> {
  bool _openRequested = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final billing = ref.watch(billingControllerProvider);
    final flow = ref.watch(payFlowProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Pay by bank transfer',
            backLabel: 'Back to Billing',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (billing) {
              AsyncLoading() => const _PaySkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your billing',
                  body: error is ApiNetworkException
                      ? 'Nothing was sent. Check your connection and try '
                            'again.'
                      : 'Nothing was sent. Something went wrong on our side — '
                            'try again.',
                  onRetry: () =>
                      ref.read(billingControllerProvider.notifier).reload(),
                ),
              ),
              AsyncData(:final value) => _body(value, flow),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BillingState state, PayFlow flow) {
    final latest = state.status.latestSubmission;
    if (latest != null && latest.isAwaitingConfirmation) {
      return _PendingView(submission: latest);
    }
    if (latest != null && latest.isRejected && flow.intentId == null) {
      return _RejectedView(submission: latest, flow: flow);
    }
    // The form. Open (or resume) the intent once, on arrival.
    if (flow.intentId == null &&
        !flow.opening &&
        !flow.offline &&
        flow.error == null &&
        !_openRequested) {
      _openRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(payFlowProvider.notifier).open();
      });
    }
    return _FormView(state: state, flow: flow);
  }
}

// ---------------------------------------------------------------------------
// The form
// ---------------------------------------------------------------------------

class _FormView extends ConsumerWidget {
  const _FormView({required this.state, required this.flow});

  final BillingState state;
  final PayFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final status = state.status;
    final intent = status.latestSubmission;
    final showIntent = intent != null && intent.id == flow.intentId;
    final period = status.nextPeriod;
    final bank = status.bankTransfer;
    final notifier = ref.read(payFlowProvider.notifier);

    void toast(String message) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));

    // Opening the intent failed outright: no reference code, so no form.
    if (!showIntent && (flow.offline || flow.error != null)) {
      return Padding(
        padding: AppSpacing.screenInsets,
        child: flow.offline
            ? NoConnectionView(onRetry: notifier.open)
            : EmptyState.error(
                title: 'Couldn’t start a payment',
                body: flow.error ?? 'Something went wrong. Try again.',
                onRetry: notifier.open,
              ),
      );
    }
    if (!showIntent) return const _PaySkeleton();

    final periodLine = period == null
        ? 'Premium · 30-day period'
        : 'Premium · 30-day period · '
              '${dayAndMonth(maldives(period.start))} – '
              '${dayAndMonth(maldives(period.end))}';
    final proof = flow.proof;
    final canSubmit = flow.canSubmit && bank != null;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        LabelledCard(
          label: 'Amount to transfer',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mvr(intent.amountLaari), style: type.stat),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                periodLine,
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${status.introductory ? 'Your introductory rate.' : 'Your rate.'} '
                'The exact amount matters — a different amount can’t be '
                'confirmed.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LabelledCard(
          label: 'Transfer to',
          child: bank == null
              ? const NoticeBanner(
                  message:
                      'Bank details aren’t available yet, so a transfer can’t '
                      'be made right now. Nothing here is a placeholder — '
                      'try again later.',
                  icon: Icons.account_balance_outlined,
                )
              : Column(
                  children: [
                    FactRow(label: 'Bank', value: bank.bankName),
                    const SizedBox(height: AppSpacing.md),
                    FactRow(
                      label: 'Account name',
                      value: bank.accountName,
                      trailing: CopyButton(
                        value: bank.accountName,
                        what: 'Account name',
                        onCopied: (what) => toast('$what copied'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FactRow(
                      label: 'Account number · MVR',
                      value: bank.accountNumber,
                      mono: true,
                      trailing: CopyButton(
                        value: bank.accountNumber,
                        what: 'Account number',
                        onCopied: (what) => toast('$what copied'),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        LabelledCard(
          label: 'Your reference code — put it in the transfer note',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      intent.referenceCode,
                      style: type.stat.copyWith(letterSpacing: 1),
                    ),
                  ),
                  CopyButton(
                    value: intent.referenceCode,
                    what: 'Reference code',
                    withLabel: true,
                    onCopied: (what) => toast('$what copied'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This code is how an admin matches your transfer to your '
                'account. Without it, confirmation takes longer.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LabelledCard(
          label: 'Proof of transfer',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (proof == null)
                AppButton.secondary(
                  label: 'Add a photo or screenshot of the receipt',
                  icon: Icons.add_photo_alternate_outlined,
                  expand: true,
                  onPressed: () async {
                    final refusal = await notifier.attach();
                    if (refusal != null) {
                      AppHaptics.refused();
                      toast(refusal);
                    } else {
                      AppHaptics.selection();
                    }
                  },
                )
              else
                _ProofRow(proof: proof, onRemove: notifier.removeProof),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Uploaded, never linked — the photo goes only to the admin who '
                'confirms it.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        if (flow.offline) ...[
          const SizedBox(height: AppSpacing.md),
          NoticeBanner(
            message:
                'No connection — nothing was sent. Your receipt is still '
                'attached; try again when you’re back online.',
            icon: Icons.wifi_off_rounded,
            actionLabel: 'Try again',
            onAction: () => _submit(context, ref),
          ),
        ] else if (flow.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          NoticeBanner(message: flow.error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: 'I’ve sent the transfer',
          expand: true,
          loading: flow.submitting,
          onPressed: canSubmit ? () => _submit(context, ref) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    'Nothing activates on submission. The transfer is '
                    'confirmed against the bank statement — ',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              TextSpan(
                text: 'up to 48 hours',
                style: type.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: ' — and everything stays as it is until then.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard.row(
          leading: const RowIcon(icon: Icons.description_outlined),
          title: 'Paying accepts the Provider Agreement',
          // Root CLAUDE.md invariant 1d: legal text is a marked placeholder
          // until real legal review, and the marker is part of the copy.
          subtitle: '[placeholder — draft terms, not final policy]',
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.textTertiary,
          ),
          semanticLabel: 'Provider Agreement — placeholder, draft terms',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.legal),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  static Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(payFlowProvider.notifier).submit();
    if (ok) {
      AppHaptics.commit();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted — pending confirmation. Nothing changes until then.',
          ),
        ),
      );
    } else {
      AppHaptics.refused();
    }
  }
}

class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.proof, required this.onRemove});

  final PickedImage proof;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final kb = (proof.byteSize / 1024).round();
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          const RowIcon(icon: Icons.image_outlined),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proof.fileName,
                  style: type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$kb KB · added just now',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Pressable(
            semanticLabel: 'Remove receipt',
            focusRadius: AppRadius.pill,
            onTap: onRemove,
            builder: (context, s) => Icon(
              Icons.close_rounded,
              color: s.pressed ? colors.ink : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending
// ---------------------------------------------------------------------------

class _PendingView extends StatelessWidget {
  const _PendingView({required this.submission});

  final PaymentSubmission submission;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final at = submission.submittedAt;
    final when = at == null
        ? ''
        : 'Submitted ${shortDate(maldives(at))}, ${maldivesClock(at)}. ';
    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusBadge.custom(
                label: 'Pending confirmation',
                tone: BadgeTone.amber,
              ),
              const SizedBox(height: AppSpacing.md),
              // 🔧 **Not "an admin matches it" — plan revision 5.32, §0.0
              // item 19.** A submission whose bank-statement row matches on
              // all four of reference, amount, account and period now
              // confirms without a human. The wait and the 48 hours are
              // unchanged and are what a provider needs; naming the reviewer
              // would be wrong in the case that no longer has one.
              Text(
                '${when}Your transfer is checked against the bank statement '
                'using your reference code ${submission.referenceCode} — this '
                'takes up to 48 hours.',
                style: type.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Pending grants nothing yet. ',
                      style: type.bodyStrong,
                    ),
                    TextSpan(
                      text:
                          'Your plan, listings and price stay exactly as they '
                          'are until the transfer is confirmed. You’ll get a '
                          'notification either way.',
                      style: type.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard.row(
          leading: const RowIcon(icon: Icons.receipt_long_outlined),
          title: 'Once confirmed, the invoice appears in Invoices',
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.textTertiary,
          ),
          semanticLabel: 'Invoices',
          onTap: () =>
              Navigator.of(context).pushNamed(InvoicesScreen.routeName),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Rejected — reason, resubmit, appeal
// ---------------------------------------------------------------------------

class _RejectedView extends ConsumerWidget {
  const _RejectedView({required this.submission, required this.flow});

  final PaymentSubmission submission;
  final PayFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final appealed = submission.isAppealed;
    final appealedAt = submission.appealedAt;
    final notifier = ref.read(payFlowProvider.notifier);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                submission.reversedAt != null
                    ? 'Transfer reversed — the admin wrote:'
                    : 'Transfer not confirmed — the admin wrote:',
                style: type.cardTitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              QuotedLine(
                submission.rejectionReason ??
                    'No reason was recorded. Appeal and an admin will look '
                        'again.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (appealed) ...[
                const StatusBadge.custom(
                  label: 'Appeal sent',
                  tone: BadgeTone.blue,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${appealedAt == null ? '' : 'Sent ${shortDate(maldives(appealedAt))}. '}'
                  'An admin will look at this payment again. If you’d rather '
                  'start fresh, you can still resubmit now — there’s no '
                  'waiting period.',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
              ] else
                Text(
                  'You can resubmit straight away — there’s no waiting period. '
                  'If you think the admin is wrong, appeal and an admin looks '
                  'at it again.',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
              if (flow.offline) ...[
                const SizedBox(height: AppSpacing.md),
                const NoticeBanner(
                  message:
                      'No connection — nothing was sent. Try again when '
                      'you’re back online.',
                  icon: Icons.wifi_off_rounded,
                ),
              ] else if (flow.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                NoticeBanner(message: flow.error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton.primary(
                label: 'Resubmit now',
                expand: true,
                loading: flow.opening,
                onPressed: () {
                  AppHaptics.selection();
                  notifier.resubmit();
                },
              ),
              if (!appealed) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton.secondary(
                  label: 'Appeal',
                  expand: true,
                  onPressed: () => _appeal(context, ref),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _appeal(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showAppBottomSheet<_AppealOutcome>(
      context: context,
      builder: (_) => _AppealSheet(submissionId: submission.id),
    );
    if (sent == null) return;
    if (sent.error == null) {
      AppHaptics.commit();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Appeal sent — an admin will look at it again.'),
        ),
      );
    } else {
      AppHaptics.refused();
      messenger.showSnackBar(SnackBar(content: Text(sent.error!)));
    }
  }
}

class _AppealOutcome {
  const _AppealOutcome({this.error});
  final String? error;
}

/// The appeal, as a sheet: an optional note and one button. There is no
/// field for a new amount, code or receipt — an appeal asks for the same
/// submission to be read again; a corrected transfer is a resubmission.
class _AppealSheet extends ConsumerStatefulWidget {
  const _AppealSheet({required this.submissionId});

  final String submissionId;

  @override
  ConsumerState<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends ConsumerState<_AppealSheet> {
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final error = await ref
        .read(billingControllerProvider.notifier)
        .appeal(widget.submissionId, note: _note.text);
    if (!mounted) return;
    Navigator.of(context).pop(_AppealOutcome(error: error));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppBottomSheet(
      title: 'Appeal this decision',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'An admin will read the same receipt again. If a different '
            'transfer is needed, resubmit instead — an appeal doesn’t change '
            'what was sent.',
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Anything the admin should know?',
            requirement: FieldRequirement.optional,
            controller: _note,
            maxLines: 4,
            maxLength: 500,
            hint: 'e.g. the receipt shows the full amount on the second line',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            label: 'Send appeal',
            expand: true,
            loading: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: AppSpacing.n28),
        ],
      ),
    );
  }
}

class _PaySkeleton extends StatelessWidget {
  const _PaySkeleton();

  @override
  Widget build(BuildContext context) => SkeletonLoader(
    label: 'Preparing your payment',
    child: ListView(
      padding: AppSpacing.screenInsets,
      children: const [
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 120, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 200, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 120, radius: AppRadius.panel),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 120, radius: AppRadius.panel),
      ],
    ),
  );
}
