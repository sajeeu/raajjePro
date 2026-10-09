import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/request_time_screen.dart';
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

/// **Change the time** on a request the provider has not answered yet —
/// §Phase 17.4's reschedule, window half (decision 31 §6, owner-approved).
///
/// Nothing is agreed and nothing is held at `awaiting_quote`, so the new
/// window replaces the old one at once; the provider is told and their quote
/// clock restarts from the move. The same chips as `Request a Time`, because
/// it is the same question.
class RescheduleWindowScreen extends ConsumerStatefulWidget {
  const RescheduleWindowScreen({required this.args, super.key});

  static const routeName = '/bookings/change-time';

  final BookingActionArgs args;

  @override
  ConsumerState<RescheduleWindowScreen> createState() =>
      _RescheduleWindowScreenState();
}

class _RescheduleWindowScreenState
    extends ConsumerState<RescheduleWindowScreen> {
  final _windowText = TextEditingController();
  WindowChip? _chip;

  @override
  void initState() {
    super.initState();
    _windowText.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _windowText
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  bool get _hasWindow => _chip != null || _windowText.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return _ActionScaffold(
      bookingId: widget.args.bookingId,
      title: 'Change the time',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'Nothing was changed.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final action = ref.watch(bookingActionsProvider(booking.id));
        final first = _firstName(booking.provider.name);

        if (booking.status != BookingStatus.awaitingQuote) {
          return const Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.schedule_rounded,
              title: 'This request has moved on',
              body:
                  'The provider has already answered, so the time can’t be '
                  'changed from here. Go back to the booking to see what '
                  'it offers now.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text('Change the time', style: type.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${booking.listingName ?? 'Service'} · ${booking.provider.name}',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (action.message != null) ...[
              NoticeBanner(message: action.message ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],
            if ((booking.preferredWindowText ?? '').isNotEmpty) ...[
              Text(
                'You asked for: ${booking.preferredWindowText}',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            WhenSuitsCard(
              title: 'When suits you now?',
              chip: _chip,
              controller: _windowText,
              onChip: (chip) {
                AppHaptics.selection();
                setState(() => _chip = _chip == chip ? null : chip);
              },
              providerName: first,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: colors.neutralTint,
              child: Text(
                '$first hasn’t answered yet, so this replaces your request '
                'straight away. $first is told, and their time to reply starts '
                'again from now.',
                style: type.caption.copyWith(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: 'Send the new time',
              expand: true,
              loading: action.isWorking,
              onPressed: !_hasWindow || action.isWorking
                  ? null
                  : () => _send(booking),
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }

  Future<void> _send(Booking booking) async {
    final done = await ref
        .read(bookingActionsProvider(booking.id).notifier)
        .reschedule(
          preferredWindowChip: _chip?.wire,
          preferredWindowText: _windowText.text,
        );
    if (!mounted) return;
    if (done) {
      AppHaptics.commit();
      Navigator.of(context).pop();
    } else {
      AppHaptics.refused();
    }
  }
}

/// **The callback claim** — §1h's guarantee taken up (decision 31 §6,
/// owner-approved with four binding rules).
///
/// A claim is the customer **taking up an offer**, not reporting anything:
/// the screen is a short booking form — what came back, when suits — and
/// never borrows `Raise Dispute`'s shape, tone or red. Only a claim the
/// provider declines or lets lapse becomes a report, and the server files
/// that itself (`callback_declined`). No tick, shield or lock, and no
/// "verified", anywhere near it (§1i).
///
/// The claim makes a **new** booking at MVR 0, linked to this one, which
/// carries on in its own detail screen — so success replaces this screen
/// with that one.
class CallbackClaimScreen extends ConsumerStatefulWidget {
  const CallbackClaimScreen({required this.args, super.key});

  static const routeName = '/bookings/callback';

  final BookingActionArgs args;

  @override
  ConsumerState<CallbackClaimScreen> createState() =>
      _CallbackClaimScreenState();
}

class _CallbackClaimScreenState extends ConsumerState<CallbackClaimScreen> {
  final _whatCameBack = TextEditingController();
  final _windowText = TextEditingController();
  WindowChip? _chip;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _whatCameBack.addListener(_changed);
    _windowText.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _whatCameBack
      ..removeListener(_changed)
      ..dispose();
    _windowText
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      _whatCameBack.text.trim().isNotEmpty &&
      (_chip != null || _windowText.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return _ActionScaffold(
      bookingId: widget.args.bookingId,
      title: 'Callback',
      errorTitle: 'Couldn’t load the booking',
      errorBody: 'Nothing was sent.',
      builder: (context, booking) {
        final colors = context.colors;
        final type = context.type;
        final first = _firstName(booking.provider.name);
        final callback = booking.callback;
        final until = callback.claimableUntil;

        if (!callback.canClaim) {
          return Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.replay_rounded,
              title: callback.claimBookingId != null
                  ? 'You’ve already asked $first to come back'
                  : 'This callback can’t be claimed now',
              body: callback.claimBookingId != null
                  ? 'One return visit per job — it’s on your bookings, and '
                        'carries on there.'
                  : 'The free return visit covers seven days after the job. '
                        'You can still book $first again from the booking.',
            ),
          );
        }

        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            Text('Ask $first to come back', style: type.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              until == null
                  ? 'Free return visit if the same problem comes back.'
                  : 'Free return visit if the same problem comes back — '
                        'until ${maldivesDayLabel(until, DateTime.now())}.',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              NoticeBanner(message: _error ?? ''),
              const SizedBox(height: AppSpacing.md),
            ],
            AppTextField(
              label: 'What came back?',
              controller: _whatCameBack,
              hint: 'e.g. The kitchen tap is dripping again',
              maxLines: 4,
              maxLength: 2000,
              helper:
                  '$first sees this with the original job, so say what '
                  'you’re seeing now.',
            ),
            const SizedBox(height: AppSpacing.md),
            WhenSuitsCard(
              title: 'When suits you for the visit?',
              chip: _chip,
              controller: _windowText,
              onChip: (chip) {
                AppHaptics.selection();
                setState(() => _chip = _chip == chip ? null : chip);
              },
              providerName: first,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: colors.neutralTint,
              child: Text(
                'This makes a new booking linked to the original, at MVR 0. '
                '$first proposes a time to come back and you approve it — '
                'there’s nothing to pay and no payment step.',
                style: type.caption.copyWith(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: 'Ask $first to come back',
              expand: true,
              loading: _sending,
              onPressed: _canSend ? () => _send(booking) : null,
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      },
    );
  }

  Future<void> _send(Booking booking) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(bookingApiProvider)
          .claimCallback(
            booking.id,
            whatCameBack: _whatCameBack.text,
            preferredWindowChip: _chip?.wire,
            preferredWindowText: _windowText.text,
          );
      ref
        ..invalidate(bookingDetailProvider(booking.id))
        ..invalidate(bookingsListProvider);
      AppHaptics.commit();
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(
        BookingDetailScreen.routeName,
        arguments: {'bookingId': created.id},
      );
    } on ApiException catch (e) {
      AppHaptics.refused();
      if (mounted) setState(() => _error = e.message);
    } on ApiNetworkException {
      AppHaptics.refused();
      if (mounted) {
        setState(
          () => _error =
              'No connection — nothing was sent. What you wrote is still '
              'here; try again when you’re back online.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// "Mariyam" from "Mariyam Shifa" — how the artboards address a person.
String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'The provider';
  return trimmed.split(RegExp(r'\s+')).first;
}
