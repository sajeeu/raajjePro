import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/propose_quote_screen.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// §1c step 4's slot/request window. **Flat 24 hours for every category** —
/// the per-category clocks belong to the slices that own them: §Phase 17.2's
/// `quoteApprovalMinutes` and §Phase 17.3's `emergencyAcceptWindowMinutes`,
/// neither of which this screen shows.
const acceptWindow = Duration(hours: 24);

/// **The provider accept prompt** (§Phase 17 frontend item 2).
///
/// ## Job details and the customer's name only
///
/// §1c is explicit: "job details and the customer's name only, **no contact
/// details of any kind, and no chat yet**". So the screen draws a name, a
/// time, a place and the job note — and nothing that could reach the person.
///
/// ## The countdown matches the mode's actual window
///
/// 24 hours for a **slot** booking, and for a **request** the deadline the
/// server already computed from the category's `quoteExpiryMinutes` and put on
/// the booking as `quoteDueAt` — 🔧 **§Phase 17.2**, and never the flat 24,
/// which would promise a plumber twenty-two hours they do not have. The
/// emergency window is §Phase 17.3's and is read from its own category field.
/// Counting down to a window this screen invented would be worse than no
/// countdown, which is why neither number is written here.
///
/// ## Offline, the tap is kept
///
/// §Phase 17 frontend item 12: "a lost tap costs the provider the job". Accept
/// goes through the queue §Phase 9 built — the tap is recorded, the UI shows a
/// pending state, and the reconnect sends it. §0.0 item 14 allows exactly this
/// surface and excludes the emergency accept by name; **decline is not
/// queued**, because a queued decline that lands after the customer rebooked
/// would refuse a booking they no longer have.
class ProviderAcceptScreen extends ConsumerStatefulWidget {
  const ProviderAcceptScreen({required this.args, super.key});

  static const routeName = '/bookings/accept';

  final BookingActionArgs args;

  @override
  ConsumerState<ProviderAcceptScreen> createState() =>
      _ProviderAcceptScreenState();
}

class _ProviderAcceptScreenState extends ConsumerState<ProviderAcceptScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One second, and only while this screen is up: the countdown is the
    // reason a provider acts now, and a stale one is worse than none.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
            title: 'New booking request',
            backLabel: 'Back to your bookings',
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
                        SkeletonBox.line(width: 180, height: 26),
                        SizedBox(height: AppSpacing.md),
                        SkeletonBox(height: 140),
                        SizedBox(height: AppSpacing.md),
                        SkeletonBox(height: 120),
                      ],
                    ),
                  ),
                ],
              ),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load this request',
                  body: error is ApiNetworkException
                      ? 'Nothing was accepted or declined. Check your '
                            'connection and try again.'
                      : 'Nothing was accepted or declined. Try again.',
                  onRetry: () => ref.invalidate(
                    bookingDetailProvider(widget.args.bookingId),
                  ),
                ),
              ),
              AsyncData(:final value) => _body(context, value),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Booking booking) {
    final colors = context.colors;
    final type = context.type;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final offline = ref.watch(offlineQueueProvider);
    final now = ref.read(clockProvider)();
    final queued = action.phase == BookingActionPhase.queued;

    // 🔧 **`awaiting_quote` joins `requested` here — §Phase 17.2.** A request
    // booking never passes through `requested`: it is created awaiting a
    // quote, and this guard read it as "moved on" and showed the provider an
    // "already answered" card for a job nobody had answered.
    final unanswered =
        booking.status == BookingStatus.requested ||
        booking.status == BookingStatus.awaitingQuote;
    if (!unanswered) {
      return const Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.done_all_rounded,
          title: 'Already answered',
          body:
              'This request has moved on — its record is on the booking, '
              'including who answered it and when.',
        ),
      );
    }

    // 🔧 The countdown is the **mode's own** window (§Phase 17 frontend item
    // 2: "a countdown matching the mode's actual window"). A slot booking runs
    // on the flat 24 hours; a request runs on the category's
    // `quoteExpiryMinutes`, which the server already resolved into
    // `quoteDueAt` — 2 hours on a blocked drain. Counting 24 down at a plumber
    // would promise them 22 hours they do not have.
    final deadline = booking.bookingMode == BookingKind.request
        ? booking.quoteDueAt
        : booking.createdAt?.add(acceptWindow);
    final left = deadline?.difference(now);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),

        if (queued) ...[
          const NoticeBanner(
            message:
                'Accepted — waiting to send. It goes the moment you’re back '
                'online, and nothing is lost in the meantime.',
            icon: Icons.cloud_queue_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (!offline.online) ...[
          const NoticeBanner(
            message:
                'You’re offline. Accepting still works — the tap is kept and '
                'sent when the connection comes back.',
            icon: Icons.wifi_off_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        Text(
          booking.listingName ?? booking.categoryName ?? 'Service request',
          style: type.screenTitle,
        ),
        if (left != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            left.isNegative
                ? 'The 24-hour window has passed — this closes on its own.'
                : '${_countdown(left)} left to answer',
            style: type.secondary.copyWith(
              color: left.inHours < 2 ? colors.error : colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A name. Nothing here reaches the customer, and there is
              // nothing on this screen that could (§1c).
              CounterpartyRow(party: booking.customer, caption: 'Customer'),
              const SizedBox(height: AppSpacing.sm2),
              _Detail(label: 'When', value: bookingWhen(booking.scheduledFor)),
              if ((booking.islandDisplayName ?? '').isNotEmpty ||
                  (booking.addressDetail ?? '').isNotEmpty)
                _Detail(
                  label: 'Where',
                  value: [
                    if ((booking.addressDetail ?? '').isNotEmpty)
                      booking.addressDetail ?? '',
                    if ((booking.islandDisplayName ?? '').isNotEmpty)
                      booking.islandDisplayName ?? '',
                  ].join(' · '),
                ),
              if ((booking.jobNotes ?? '').isNotEmpty)
                _Detail(label: 'The job', value: booking.jobNotes ?? ''),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(child: AmountBlock(booking: booking)),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                booking.bookingMode == BookingKind.request
                    ? 'Your quote locks the terms when they accept it'
                    : 'Accepting locks the terms',
                style: type.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The price, the date, the time and the scope stop being '
                'changeable by either of you alone. If something has to '
                'change afterwards you propose it and the customer accepts — '
                'every attempt stays on the booking’s record.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // §Phase 17.2. A `request` booking is **not** accepted — §1c has the
        // provider answer with a concrete time and a price, and the server
        // refuses a bare accept by name (`REQUEST_BOOKING_NEEDS_A_QUOTE`).
        // The quote is not queued either: it carries a price and a time, which
        // is the reason §0.0 item 14 keeps the emergency accept out of the
        // queue, and the same reasoning applies here.
        if (booking.bookingMode == BookingKind.request)
          AppButton.primary(
            label: 'Propose a time & price',
            expand: true,
            onPressed: () => Navigator.of(context).pushNamed(
              ProposeQuoteScreen.routeName,
              arguments: {'bookingId': booking.id},
            ),
          )
        else
          AppButton.primary(
            label: queued ? 'Waiting to send' : 'Accept',
            expand: true,
            loading: action.isWorking,
            onPressed: action.isWorking || queued
                ? null
                : () async {
                    final done = await controller.accept();
                    if (done) AppHaptics.commit();
                  },
          ),
        const SizedBox(height: AppSpacing.sm2),
        // Not queued, deliberately — see the class note.
        AppButton.secondary(
          label: 'Decline',
          expand: true,
          onPressed: action.isWorking || queued || !offline.online
              ? null
              : () async {
                  final done = await controller.decline();
                  if (!context.mounted) return;
                  if (done) Navigator.of(context).pop();
                },
        ),
        if (!offline.online && !queued) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Declining needs a connection — it can’t be queued, because a '
            'decline that arrives after the customer has rebooked would '
            'refuse a booking they no longer have.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  static String _countdown(Duration left) {
    if (left.inHours >= 1) {
      final minutes = left.inMinutes % 60;
      return '${left.inHours}h ${minutes}m';
    }
    if (left.inMinutes >= 1) return '${left.inMinutes} min';
    return 'Under a minute';
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          Text(value, style: type.body),
        ],
      ),
    );
  }
}
