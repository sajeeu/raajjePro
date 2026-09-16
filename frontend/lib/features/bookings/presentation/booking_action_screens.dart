import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// What every booking action screen is pushed with. Built from untyped route
/// arguments, the shape `VerifyEmailArgs` established, so no feature has to
/// import this one's types to push it.
class BookingActionArgs {
  const BookingActionArgs({required this.bookingId, this.reason});

  factory BookingActionArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return BookingActionArgs(
      bookingId: map['bookingId'] as String? ?? '',
      reason: map['reason'] as String?,
    );
  }

  final String bookingId;

  /// Pre-selects a dispute reason where the screen was reached from a control
  /// that already knows it — "Payment not received" is the one case.
  final String? reason;
}

/// The shell every action screen shares: header, the four states, and the
/// booking underneath.
///
/// Written once rather than five times, because the loading, error and
/// "already done" states are identical on all of them and a screen that
/// forgot one is exactly what the screen-state rule exists to catch.
class _ActionScaffold extends ConsumerWidget {
  const _ActionScaffold({
    required this.bookingId,
    required this.title,
    required this.errorTitle,
    required this.errorBody,
    required this.builder,
  });

  final String bookingId;
  final String title;
  final String errorTitle;
  final String errorBody;
  final Widget Function(BuildContext context, Booking booking) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: title,
            backLabel: 'Back to the booking',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (booking) {
              AsyncLoading() => ListView(
                padding: AppSpacing.screenInsets,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const SkeletonLoader(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox.line(width: 200, height: 26),
                        SizedBox(height: AppSpacing.md),
                        SkeletonBox(height: 120),
                        SizedBox(height: AppSpacing.md),
                        SkeletonBox(height: 160),
                      ],
                    ),
                  ),
                ],
              ),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: errorTitle,
                  body: error is ApiNetworkException
                      ? '$errorBody Check your connection and try again.'
                      : '$errorBody Try again.',
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(bookingId)),
                ),
              ),
              AsyncData(:final value) => builder(context, value),
            },
          ),
        ],
      ),
    );
  }
}

/// **Cancel Booking** (`Cancel Booking.dc.html`).
///
/// The artboard's own framing is kept: "Plans change — this one's simple". A
/// pre-payment cancellation frees the time, tells the other party, and — for a
/// customer — **goes on nobody's record**. §1f is explicit that "customer
/// cancellations never count against a provider", and the copy says which of
/// the two is cancelling rather than implying a penalty that does not exist.
class CancelBookingScreen extends ConsumerStatefulWidget {
  const CancelBookingScreen({required this.args, super.key});

  static const routeName = '/bookings/cancel';

  final BookingActionArgs args;

  @override
  ConsumerState<CancelBookingScreen> createState() =>
      _CancelBookingScreenState();
}

class _CancelBookingScreenState extends ConsumerState<CancelBookingScreen> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ActionScaffold(
      bookingId: widget.args.bookingId,
      title: 'Cancel booking',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'Nothing was cancelled.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final action = ref.watch(bookingActionsProvider(booking.id));
        final controller = ref.read(
          bookingActionsProvider(booking.id).notifier,
        );

        if (booking.status.isTerminal) {
          return const Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: 'This booking is already closed',
              body:
                  'Nothing to cancel — its whole record stays on the booking, '
                  'including how it ended.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text('Cancel this booking', style: type.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${booking.listingName ?? 'Service'} · '
              '${booking.provider.name}',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (action.message != null) ...[
              NoticeBanner(message: action.message ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What happens', style: type.bodyStrong),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    booking.isAgreed
                        ? '${bookingWhen(booking.scheduledFor)} goes back into '
                              'the calendar and the other party is told right '
                              'away. Nothing has been paid through RaajjePro, '
                              'so there is nothing here to refund.'
                        : 'The request is withdrawn and the time is freed. '
                              'Nobody has agreed anything yet.',
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            AppTextField(
              label: 'Why are you cancelling?',
              controller: _reason,
              hint: 'Optional — skip it if you like',
              maxLines: 3,
              maxLength: 500,
              requirement: FieldRequirement.optional,
              helper:
                  'Only the other party and RaajjePro see this. It never '
                  'appears on anyone’s public profile.',
            ),
            const SizedBox(height: AppSpacing.lg),

            AppButton.destructive(
              label: 'Cancel booking',
              expand: true,
              loading: action.isWorking,
              onPressed: action.isWorking
                  ? null
                  : () async {
                      final done = await controller.cancel(
                        reason: _reason.text,
                      );
                      if (!context.mounted) return;
                      if (done) {
                        AppHaptics.commit();
                        Navigator.of(context).pop();
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.sm2),
            AppButton.text(
              label: 'Keep this booking',
              expand: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }
}

/// **Raise Dispute** (`Raise Dispute.dc.html`) — §Phase 17 item 11.
///
/// The four reasons are §Phase 22's `booking` enumeration and nothing else:
/// Round 17 scoped report reasons by target type precisely so the queue can be
/// measured, and free text as the primary input would have produced a log
/// nobody can count. The note is free text *beside* the reason, not instead
/// of it.
///
/// §1c: a dispute after completion is accepted and **the booking stays
/// completed** — the copy says so before the tap, because a customer expecting
/// a reopened job would otherwise be told nothing happened.
class RaiseDisputeScreen extends ConsumerStatefulWidget {
  const RaiseDisputeScreen({required this.args, super.key});

  static const routeName = '/bookings/dispute';

  final BookingActionArgs args;

  @override
  ConsumerState<RaiseDisputeScreen> createState() => _RaiseDisputeScreenState();
}

class _RaiseDisputeScreenState extends ConsumerState<RaiseDisputeScreen> {
  /// §Phase 22's four, with the hint the artboard wrote for each.
  static const _reasons = <(String, String, String)>[
    (
      'work_not_done',
      'The work wasn’t done',
      'Nobody came, or the job was left unfinished',
    ),
    (
      'price_changed_on_site',
      'The price changed on site',
      'More was charged than the agreed amount, with no accepted change',
    ),
    (
      'unsafe_work',
      'The work was unsafe',
      'Something was left dangerous or damaged',
    ),
    (
      'payment_dispute',
      'The payment doesn’t match',
      'The transfer and what was agreed don’t line up',
    ),
  ];

  late String _reason = widget.args.reason ?? _reasons.first.$1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ActionScaffold(
      bookingId: widget.args.bookingId,
      title: 'Report a problem',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'Nothing was reported.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final action = ref.watch(bookingActionsProvider(booking.id));
        final controller = ref.read(
          bookingActionsProvider(booking.id).notifier,
        );
        final alreadyDisputed = booking.status == BookingStatus.disputed;

        if (alreadyDisputed) {
          return const Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.gavel_outlined,
              title: 'Your report is already open',
              body:
                  'An admin is looking at it and you’ll hear back on the '
                  'booking. Adding a second report doesn’t speed it up.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text('Something went wrong', style: type.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              booking.status == BookingStatus.completed
                  ? 'The booking stays completed — a report runs on its own '
                        'track and doesn’t reopen it.'
                  : 'Put it on the record. An admin reviews what this booking '
                        'holds and answers here.',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (action.message != null) ...[
              NoticeBanner(message: action.message ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],

            Text('What is being reported?', style: type.bodyStrong),
            const SizedBox(height: AppSpacing.sm),
            for (final (value, label, hint) in _reasons) ...[
              _ReasonOption(
                label: label,
                hint: hint,
                selected: _reason == value,
                onTap: () => setState(() => _reason = value),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.sm),

            AppTextField(
              label: 'What happened?',
              controller: _note,
              hint: 'Optional, but it helps',
              maxLines: 4,
              maxLength: 1000,
              requirement: FieldRequirement.optional,
            ),
            const SizedBox(height: AppSpacing.md),

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What RaajjePro holds — and acts on',
                    style: type.bodyStrong,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'This booking’s full record: the agreed terms, every '
                    'amendment, and both sides’ payment statements. An admin '
                    'reviews exactly that, and patterns across bookings count '
                    'against a provider. The payment itself moved outside '
                    'RaajjePro, so it can’t be refunded or reversed from here.',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            AppButton.primary(
              label: 'Submit report',
              expand: true,
              loading: action.isWorking,
              onPressed: action.isWorking
                  ? null
                  : () async {
                      final done = await controller.dispute(
                        reason: _reason,
                        note: _note.text,
                      );
                      if (!context.mounted) return;
                      if (done) {
                        AppHaptics.commit();
                        Navigator.of(context).pop();
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: '$label. $hint',
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? colors.accentTint : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? colors.primary : colors.borderCard,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: type.bodyStrong),
            Text(
              hint,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// **Mark Complete** (`Mark Complete.dc.html`) — §Phase 17 item 13.
///
/// ## The final amount, and why the field is only sometimes there
///
/// An **emergency** booking cannot be completed without it: §1c calls it "the
/// number a price dispute needs, and a provider has no incentive to volunteer
/// it when it reflects badly on them", which is exactly why it gates the
/// endpoint rather than sitting as an optional extra. On every other mode it
/// is optional — §1f's price adherence reads it where it exists, and a slot
/// job that came to more than was agreed is what that metric measures.
///
/// The screen says what happens if the provider never does this, because the
/// honest answer is reassuring: the customer is asked after 7 days and a
/// 3-day grace closes it either way. Silence does not block reviews.
class MarkCompleteScreen extends ConsumerStatefulWidget {
  const MarkCompleteScreen({required this.args, super.key});

  static const routeName = '/bookings/complete';

  final BookingActionArgs args;

  @override
  ConsumerState<MarkCompleteScreen> createState() => _MarkCompleteScreenState();
}

class _MarkCompleteScreenState extends ConsumerState<MarkCompleteScreen> {
  final _finalAmount = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _finalAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ActionScaffold(
      bookingId: widget.args.bookingId,
      title: 'Mark complete',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'The job wasn’t marked complete.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final action = ref.watch(bookingActionsProvider(booking.id));
        final controller = ref.read(
          bookingActionsProvider(booking.id).notifier,
        );
        final needsFinalAmount = booking.bookingMode == BookingKind.emergency;
        final open = booking.openAmendment;

        if (booking.status == BookingStatus.completed) {
          return const Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Already marked complete',
              body:
                  'Reviews are open on both sides, and the chat stays open '
                  'for 7 days.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text('Mark the job complete', style: type.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${booking.listingName ?? 'Service'} · '
              '${bookingWhen(booking.scheduledFor)}',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (action.message != null) ...[
              NoticeBanner(message: action.message ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],

            // §1h: completing freezes the terms, so anything still open would
            // be stuck there. Said before the tap, not after it.
            if (open != null) ...[
              const NoticeBanner(
                message:
                    'A change to the agreement is still waiting for an '
                    'answer. Settle it before you close the job — completing '
                    'freezes the terms as they stand.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            AppCard(child: AmountBlock(booking: booking)),
            const SizedBox(height: AppSpacing.md),

            if (needsFinalAmount) ...[
              AppTextField(
                label: 'Final amount — required',
                controller: _finalAmount,
                hint: '0',
                prefix: const Text('MVR'),
                keyboardType: TextInputType.number,
                requirement: FieldRequirement.mandatory,
                errorText: _amountError,
                helper:
                    'What the job actually came to — the callout fee plus the '
                    'parts and labour agreed on site. If the price is ever '
                    'disputed this is the number that settles it, which is why '
                    'the job can’t be closed without it.',
              ),
              const SizedBox(height: AppSpacing.md),
            ] else ...[
              AppTextField(
                label: 'Final amount charged',
                controller: _finalAmount,
                hint: 'Leave blank if the agreed price stood',
                prefix: const Text('MVR'),
                keyboardType: TextInputType.number,
                requirement: FieldRequirement.optional,
                errorText: _amountError,
                helper:
                    'Only fill this in if the total differed. Charging more '
                    'than the agreed price without an accepted change shows on '
                    'your public price-adherence number.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Not marking it complete doesn’t bury it',
                    style: type.bodyStrong,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'After 7 days the customer is asked whether the job '
                    'happened; if they don’t answer either, a 3-day grace '
                    'closes it on its own. Reviews open either way — silence '
                    'doesn’t block them.',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            AppButton.primary(
              label: 'Mark complete',
              expand: true,
              loading: action.isWorking,
              onPressed: action.isWorking
                  ? null
                  : () => _submit(context, controller, needsFinalAmount),
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }

  Future<void> _submit(
    BuildContext context,
    BookingActionsController controller,
    bool required,
  ) async {
    final raw = _finalAmount.text.trim();
    int? laari;
    if (raw.isNotEmpty) {
      // Integer laari end to end (invariant 7): what is typed is rufiyaa, and
      // the conversion happens once, here, where the field is read.
      final rufiyaa = double.tryParse(raw);
      if (rufiyaa == null || rufiyaa < 0) {
        setState(() => _amountError = 'Enter the amount in rufiyaa');
        return;
      }
      laari = (rufiyaa * 100).round();
    } else if (required) {
      setState(() => _amountError = 'An emergency job needs its final amount');
      return;
    }
    setState(() => _amountError = null);

    final done = await controller.complete(finalAmountLaari: laari);
    if (!context.mounted) return;
    if (done) {
      AppHaptics.commit();
      Navigator.of(context).pop();
    }
  }
}

/// **Did This Happen** (`Did This Happen.dc.html`) — §1c step 10's prompt.
///
/// Two answers and a third that is silence:
///  * **Yes** completes the booking as a genuine two-sided completion;
///  * **No** goes to the moderation queue "same path as a dispute", so the
///    screen says so rather than implying a private note;
///  * nothing closes it anyway after three more days, tagged as unconfirmed —
///    which is what stops a silent provider blocking reviews forever.
class DidThisHappenScreen extends ConsumerWidget {
  const DidThisHappenScreen({required this.args, super.key});

  static const routeName = '/bookings/did-this-happen';

  final BookingActionArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionScaffold(
      bookingId: args.bookingId,
      title: 'Did this happen?',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'Nothing was answered on your behalf.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final action = ref.watch(bookingActionsProvider(booking.id));
        final controller = ref.read(
          bookingActionsProvider(booking.id).notifier,
        );

        if (booking.status != BookingStatus.confirmed) {
          return const Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nothing to answer',
              body:
                  'This booking has already moved on — its record shows how '
                  'it closed.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text(
              'Did ${booking.provider.name} complete this job?',
              style: type.screenTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The booked time was ${bookingWhen(booking.scheduledFor)} and '
              'nobody has marked it done.',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (action.message != null) ...[
              NoticeBanner(message: action.message ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CounterpartyRow(
                    party: booking.provider,
                    caption: 'Provider on this booking',
                  ),
                  const SizedBox(height: AppSpacing.sm2),
                  AmountBlock(booking: booking, compact: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            AppButton.primary(
              label: 'Yes — the job was done',
              expand: true,
              loading: action.isWorking,
              onPressed: action.isWorking
                  ? null
                  : () async {
                      final done = await controller.answerCompletionPrompt(
                        happened: true,
                      );
                      if (!context.mounted) return;
                      if (done) {
                        AppHaptics.commit();
                        Navigator.of(context).pop();
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.sm2),
            AppButton.secondary(
              label: 'No — it didn’t happen',
              expand: true,
              onPressed: action.isWorking
                  ? null
                  : () async {
                      final done = await controller.answerCompletionPrompt(
                        happened: false,
                      );
                      if (!context.mounted) return;
                      if (done) Navigator.of(context).pop();
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Saying no opens a report an admin reviews — repeated no-shows '
              'count against a provider across all their bookings, so your '
              'answer matters beyond this one. If you answer neither, this '
              'closes on its own in three days and reviews open anyway.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }
}
