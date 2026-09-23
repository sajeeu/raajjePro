import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **The quote, as the customer decides on it** — `Quote Received.dc.html`.
///
/// ## The countdown is the server's deadline, never a category constant
///
/// The clock runs to `quoteExpiresAt`, which the server set from the
/// category's own `quoteApprovalMinutes` — 4 hours on a blocked drain, 72 on a
/// wedding shoot (invariant 13). This screen counts down to an instant it was
/// given; it never works out a window, and there is no 72 anywhere in it.
///
/// ## Accepting is what agrees the price
///
/// §1h: at `accepted` "the agreed price, date, time and scope lock. Neither
/// party can alter them unilaterally." So the screen says what accepting
/// commits to before it offers the button, and the payment step follows
/// immediately — §1c has request bookings pass "through `awaiting_payment`
/// instantly".
///
/// ## Declining is not the only way to disagree
///
/// The artboard's own hierarchy: "Nearly right? Say so in chat" sits above
/// "Decline this quote", because the provider can revise while the quote is
/// live and a declined booking is closed. §1c built the chat at
/// `quote_offered` for exactly this.
class QuoteReceivedScreen extends ConsumerStatefulWidget {
  const QuoteReceivedScreen({required this.args, super.key});

  static const routeName = '/bookings/quote-received';

  final BookingActionArgs args;

  @override
  ConsumerState<QuoteReceivedScreen> createState() =>
      _QuoteReceivedScreenState();
}

class _QuoteReceivedScreenState extends ConsumerState<QuoteReceivedScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One second, and only while a quote is live — `dispose` stops it, and the
    // expired branch below stops reading it.
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(widget.args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Quote received',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: booking.when(
              loading: () => const _Loading(),
              error: (_, _) => Center(
                child: Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState.error(
                    title: 'Couldn’t load this quote',
                    body:
                        'Nothing was accepted. Check your connection and try '
                        'again.',
                    onRetry: () => ref.invalidate(
                      bookingDetailProvider(widget.args.bookingId),
                    ),
                  ),
                ),
              ),
              data: _body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Booking booking) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);

    // A quote that has been answered — accepted, declined, or expired by the
    // sweep — is not a decision any more. The screen says which, rather than
    // showing a dead Accept button.
    if (booking.status != BookingStatus.quoteOffered) {
      return _Answered(booking: booking);
    }

    final left = booking.quoteTimeLeft(ref.read(clockProvider)());
    final expired = left == null || left == Duration.zero;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),

        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        _Countdown(left: left, expired: expired),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quote from ${booking.provider.name}',
                style: type.overline.copyWith(color: colors.textSecondary),
              ),
              if ((booking.listingName ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(booking.listingName ?? '', style: type.cardTitle),
              ],
              const SizedBox(height: AppSpacing.md),
              _Row(
                label: 'Time offered',
                value: bookingWhen(booking.scheduledFor),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Row(
                label: 'Quoted price',
                value: mvr(booking.quotedAmountLaari ?? 0),
                strong: true,
              ),
              if ((booking.quoteNote ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${booking.provider.name}’s note',
                  style: type.overline.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  booking.quoteNote ?? '',
                  style: type.body.copyWith(color: colors.textTertiary),
                ),
              ],
              if ((booking.preferredWindowText ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Your request: ${booking.preferredWindowText}',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What accepting means', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The price, the date, the time and the scope lock. Neither of '
                'you can change them alone after that — a change has to be '
                'proposed and accepted, and every attempt stays on this '
                'booking’s record.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You pay ${booking.provider.name} directly by bank transfer. '
                'RaajjePro never handles the money.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        AppButton.primary(
          label: expired ? 'This quote expired' : 'Accept quote',
          expand: true,
          loading: action.isWorking,
          onPressed: expired || action.isWorking
              ? null
              : () => _accept(controller, booking),
        ),
        const SizedBox(height: AppSpacing.sm2),

        // Above Decline, as the artboard has it: the provider can revise while
        // the quote is live, and a declined booking is closed.
        if (booking.canMessage) ...[
          const AppButton.secondary(
            label: 'Nearly right? Say so in chat',
            expand: true,
            // §Phase 18 builds the thread. The state is 17.2's and is `open`;
            // the way in is not this slice's to invent, so the control states
            // plainly that it is coming rather than pretending to open one.
            onPressed: null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The chat opened when this quote arrived — messaging lands with '
            'the messaging module.',
            style: type.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm2),
        ],

        AppButton.text(
          label: 'Decline this quote',
          expand: true,
          onPressed: action.isWorking
              ? null
              : () => _decline(controller, booking),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _accept(
    BookingActionsController controller,
    Booking booking,
  ) async {
    final done = await controller.approveQuote();
    if (!mounted || !done) return;
    AppHaptics.commit();
    // Straight on to the payment step: §1c has a request booking pass through
    // `awaiting_payment` the instant the amount is set, and the customer's
    // next real action is the transfer.
    await Navigator.of(context).pushReplacementNamed(
      PaymentStepScreen.routeName,
      arguments: {'bookingId': booking.id},
    );
  }

  Future<void> _decline(
    BookingActionsController controller,
    Booking booking,
  ) async {
    // A confirmation, because declining closes the booking and the way back
    // is a whole new request — the same sheet shape the receipt screen uses
    // for its own irreversible answer.
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Decline this quote?',
        onClose: () => Navigator.of(sheetContext).pop(false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This closes the booking. If the time or the price is nearly '
              'right, say so in the chat instead — ${booking.provider.name} '
              'can send a new quote while this one is still live.',
              style: context.type.secondary.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.destructive(
              label: 'Decline quote',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm2),
            AppButton.text(
              label: 'Keep deciding',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final done = await controller.declineQuote();
    if (!mounted || !done) return;
    AppHaptics.commit();
    Navigator.of(context).pop();
  }
}

/// The clock, and the only place this screen renders time pressure.
///
/// It warms as it runs out — the artboard's own three bands — because the last
/// fifteen minutes of a four-hour window and the first hour of a
/// seventy-two-hour one are not the same situation.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.expired});

  final Duration? left;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final remaining = left ?? Duration.zero;
    final urgent = remaining.inMinutes <= 15;
    final soon = remaining.inMinutes <= 60;

    final (bg, fg) = expired || urgent
        ? (colors.errorTint, colors.error)
        : soon
        ? (colors.warningTint, colors.warningText)
        : (colors.accentTint, colors.accentText);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Text(
            expired ? 'Expired' : _format(remaining),
            style: type.stat.copyWith(color: fg),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            expired
                ? 'This quote is no longer on the table'
                : 'to accept — the window your service’s category sets',
            style: type.caption.copyWith(color: fg),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// `3h 42m left` when there is room, `12m 04s left` when there is not — the
  /// seconds appear only once they matter.
  static String _format(Duration left) {
    if (left.inHours >= 1) {
      return '${left.inHours}h ${left.inMinutes % 60}m left';
    }
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '${left.inMinutes}m ${seconds}s left';
  }
}

/// A quote that has already been answered, one way or another.
class _Answered extends StatelessWidget {
  const _Answered({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final accepted = booking.isAgreed;
    return Center(
      child: Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: accepted
              ? Icons.check_circle_outline_rounded
              : Icons.schedule_rounded,
          title: accepted ? 'It’s agreed' : 'This quote is closed',
          body: accepted
              ? 'The terms are locked and the booking is on its way. Its whole '
                    'record is on the booking screen.'
              : 'It was declined or its window ran out. Sending a new request '
                    'is the way back.',
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: strong ? type.price : type.bodyStrong,
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: const [
      SizedBox(height: AppSpacing.md),
      SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 84),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 180),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 120),
          ],
        ),
      ),
    ],
  );
}
