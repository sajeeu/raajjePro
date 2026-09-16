import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Payment Received** (`Payment Received.dc.html`) — the provider's side of
/// §1c step 8.
///
/// ## Three visually distinct actions, and they are three different things
///
/// §Phase 17's frontend item 5 asks for exactly this: **Payment Received**,
/// **Payment Not Received**, **Decline Booking**. The middle one is a dispute
/// and the last one is not — §1c: "Decline ≠ dispute. Separate endpoints,
/// separate statuses, visually distinct in the UI." Collapsing the two would
/// file a moderation report every time a provider simply could not take a job.
///
/// ## The honesty rule, from the other side
///
/// "Your answer is your own statement, not a check RaajjePro performed. The
/// platform can't see your bank account — only you can know whether the
/// transfer arrived." The screen never says verified, and it says plainly that
/// seven days of silence is **a review, not a confirmation**.
class ProviderReceiptScreen extends ConsumerWidget {
  const ProviderReceiptScreen({required this.args, super.key});

  static const routeName = '/bookings/receipt';

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
            title: 'Payment received?',
            backLabel: 'Back to the booking',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (booking) {
              AsyncLoading() => const _ReceiptSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load the booking',
                  body: error is ApiNetworkException
                      ? 'Nothing was answered on your behalf. Check your '
                            'connection and try again.'
                      : 'Nothing was answered on your behalf. Try again.',
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(args.bookingId)),
                ),
              ),
              AsyncData(:final value) => _ReceiptBody(booking: value),
            },
          ),
        ],
      ),
    );
  }
}

class _ReceiptBody extends ConsumerWidget {
  const _ReceiptBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final customerFirst = _firstName(booking.customer.name);
    final waiting = booking.status == BookingStatus.paymentClaimed;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        AppCard(child: AmountBlock(booking: booking)),
        const SizedBox(height: AppSpacing.md),
        CounterpartyRow(
          party: booking.customer,
          caption: 'Customer on this booking',
        ),
        const SizedBox(height: AppSpacing.md),

        // Round 24, from the provider's side: a claim that was taken back is
        // a correction, and saying so stops it reading as a broken promise.
        if (!waiting && booking.paymentClaimWithdrawnAt != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$customerFirst corrected the record',
                  style: type.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'They had marked “I’ve paid” before the transfer went '
                  'through, and took it back — usually a mis-tap on the way '
                  'to the banking app. The booking is back to awaiting '
                  'payment; you’ll be asked again when they resend it. They '
                  'can do this once, and only before you answer.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your answer is your own statement', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Not a check RaajjePro performed. The platform can’t see your '
                'bank account — only you can know whether the transfer '
                'arrived, and transfers between banks can take a working day. '
                'No answer within 7 days sends this to RaajjePro to look at: '
                'that’s a review, not a confirmation, and nothing is unlocked '
                'by it.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (!waiting)
          Text(
            'Nothing to answer right now — you’ll be asked again when '
            '$customerFirst marks it paid.',
            style: type.secondary.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          )
        else ...[
          AppButton.primary(
            label: 'Payment received',
            expand: true,
            loading: action.isWorking,
            onPressed: action.isWorking
                ? null
                : () => _confirm(
                    context,
                    ref,
                    title: 'Confirm the money arrived?',
                    body:
                        'This is your statement that the money is in your '
                        'account — check your bank first, not this screen. '
                        '$customerFirst will see “Provider confirmed '
                        'receipt”.',
                    confirmLabel: 'Yes, it arrived',
                    onConfirm: () async {
                      final done = await controller.confirmPaymentReceived();
                      if (done) AppHaptics.commit();
                      return done;
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm2),
          // "Payment not received" is a dispute, and the copy says so before
          // the tap rather than after it (§1c: decline ≠ dispute).
          AppButton.secondary(
            label: 'Payment not received',
            expand: true,
            onPressed: action.isWorking
                ? null
                : () => Navigator.of(context).pushNamed(
                    RaiseDisputeScreen.routeName,
                    arguments: {
                      'bookingId': booking.id,
                      'reason': 'payment_dispute',
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.text(
            label: 'Cancel this booking instead',
            expand: true,
            onPressed: action.isWorking
                ? null
                : () => Navigator.of(context).pushNamed(
                    CancelBookingScreen.routeName,
                    arguments: {'bookingId': booking.id},
                  ),
          ),
        ],
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String confirmLabel,
    required Future<bool> Function() onConfirm,
  }) async {
    final accepted = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheet(
        title: title,
        onClose: () => Navigator.of(sheetContext).pop(false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: context.type.secondary.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: confirmLabel,
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm2),
            AppButton.text(
              label: 'Not yet',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (accepted ?? false) await onConfirm();
  }
}

class _ReceiptSkeleton extends StatelessWidget {
  const _ReceiptSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: [
      const SizedBox(height: AppSpacing.md),
      const SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 96),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 64),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 160),
          ],
        ),
      ),
    ],
  );
}

String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'the customer';
  return trimmed.split(RegExp(r'\s+')).first;
}
