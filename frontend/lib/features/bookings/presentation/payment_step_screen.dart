import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Payment Step** (`Payment Step.dc.html`) — §1c step 6 and step 7.
///
/// ## The honesty rule, which is the whole screen
///
/// RaajjePro is not in this transaction. The copy says so in the words the
/// artboard chose — "This payment never touches RaajjePro… it goes straight
/// from your bank to their account. RaajjePro can't see it, hold it or refund
/// it" — and **"I've paid" is described as the customer's own statement, not
/// as a check anybody performed**. There is no proof upload, no verification
/// language, and no certainty checkmark anywhere on this screen.
///
/// ## The bank details are not contact details
///
/// §1c: "a bank account number isn't a way to reach a person, and the
/// off-platform payment cannot physically happen without it". They are shown
/// here and on no other screen, and the copy says what they are for.
///
/// ## Round 24's withdrawal
///
/// Once the claim is sent the screen offers to take it back — once, and only
/// while the provider has not answered. The server owns both conditions; this
/// hides the control when it already knows the answer and lets the server
/// refuse when it does not.
class PaymentStepScreen extends ConsumerWidget {
  const PaymentStepScreen({required this.args, super.key});

  static const routeName = '/bookings/payment';

  final BookingActionArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Payment',
            backLabel: 'Back to the booking',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (booking) {
              AsyncLoading() => const _PaymentSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load the payment details',
                  body: error is ApiNetworkException
                      ? 'Nothing was sent. Check your connection and try again.'
                      : 'Nothing was sent. Something went wrong — try again.',
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(args.bookingId)),
                ),
              ),
              AsyncData(:final value) => _PaymentBody(booking: value),
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentBody extends ConsumerWidget {
  const _PaymentBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final details = booking.paymentDetails;
    final first = _firstName(booking.provider.name);
    final claimed = booking.status == BookingStatus.paymentClaimed;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        Text(
          claimed ? 'You’ve told $first it’s sent' : 'Pay $first directly',
          style: type.screenTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${booking.listingName ?? 'Service'} · ${bookingWhen(booking.scheduledFor)}',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        AppCard(child: AmountBlock(booking: booking)),
        const SizedBox(height: AppSpacing.md),

        if (claimed)
          _ClaimedCard(first: first)
        else
          _TransferCard(details: details, first: first),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This payment never touches RaajjePro',
                style: type.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'It goes straight from your bank to $first’s account. '
                'RaajjePro can’t see it, hold it or refund it — keep your '
                'transfer receipt. If something goes wrong, report it from '
                'this booking and RaajjePro will look into it. The booking '
                'record — what was agreed, when, and both sides’ messages — '
                'is the evidence.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (claimed) ...[
          // Round 24. Hidden once withdrawn — it is once per booking, and an
          // offered control that will certainly be refused is worse than none.
          if (booking.paymentClaimWithdrawnAt == null)
            AppButton.secondary(
              label: 'I haven’t actually paid yet — undo',
              expand: true,
              loading: action.isWorking,
              onPressed: action.isWorking
                  ? null
                  : () async {
                      final done = await controller.withdrawPaymentClaim();
                      if (done) AppHaptics.commit();
                    },
            )
          else
            Text(
              'You’ve already taken a payment claim back on this booking, so '
              'this one stands. If it was a mistake, report it from the '
              'booking and $first will see it.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
        ] else
          AppButton.primary(
            label: 'I’ve paid',
            expand: true,
            loading: action.isWorking,
            onPressed: action.isWorking || !booking.isAgreed
                ? null
                : () async {
                    final done = await controller.claimPayment();
                    if (done) AppHaptics.commit();
                  },
          ),
        const SizedBox(height: AppSpacing.sm2),
        Text(
          claimed
              ? 'That’s your word, not a check — RaajjePro hasn’t verified '
                    'anything. $first confirms receipt in this booking, and '
                    'you’ll be notified when they do. If they don’t answer '
                    'within 7 days it goes to RaajjePro to look at — a review, '
                    'not a confirmation.'
              : 'Tapping this tells $first the money is on its way. It is '
                    'your own statement — nothing here checks your bank.',
          style: type.caption.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }
}

/// The provider's registered transfer details, and the sentence saying what
/// they are and are not.
class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.details, required this.first});

  final BookingPaymentDetails? details;
  final String first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final d = details;

    // A provider who has not finished their payment details is a real state,
    // not an error: §Phase 6a collects them and a listing can be published
    // before they are complete. The customer is told what to do, not shown a
    // blank card.
    if (d == null || !d.isComplete) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No transfer details yet', style: type.bodyStrong),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$first hasn’t finished their payment details, so there is '
              'nowhere to send this yet. Ask them in the booking chat — the '
              'booking stays exactly where it is until they do.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transfer to', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.sm2),
          _DetailRow(label: 'Account holder', value: d.accountName ?? ''),
          _DetailRow(label: 'Bank', value: d.bankName ?? ''),
          _DetailRow(
            label: 'Account number',
            value: d.accountNumber ?? '',
            copyable: true,
          ),
          const SizedBox(height: AppSpacing.sm2),
          Text(
            'These details are for this transfer only — they aren’t a way to '
            'contact $first. Everything else stays in the booking chat.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ClaimedCard extends StatelessWidget {
  const _ClaimedCard({required this.first});

  final String first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happens next', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.sm2),
          const _Step(n: '1', text: 'You’ve said the transfer is sent.'),
          _Step(n: '2', text: '$first checks their own bank and answers here.'),
          const _Step(
            n: '3',
            text:
                'If they confirm, the booking moves on to the job. If they '
                'say it hasn’t arrived, you’ll both see why and can sort it '
                'out in the chat.',
          ),
          const SizedBox(height: AppSpacing.sm2),
          Text(
            'Keep your bank’s transfer receipt — it’s your proof, not '
            'RaajjePro’s.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              n,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(child: Text(text, style: type.secondary)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
                Text(value, style: type.bodyStrong),
              ],
            ),
          ),
          if (copyable)
            AppButton.text(
              label: 'Copy',
              size: AppButtonSize.compact,
              semanticLabel: 'Copy the account number',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                AppHaptics.selection();
              },
            ),
        ],
      ),
    );
  }
}

class _PaymentSkeleton extends StatelessWidget {
  const _PaymentSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: [
      const SizedBox(height: AppSpacing.md),
      const SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox.line(width: 200, height: 26),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox.line(width: 160),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(height: 96),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 190),
          ],
        ),
      ),
    ],
  );
}

String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'the provider';
  return trimmed.split(RegExp(r'\s+')).first;
}
