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
/// 24 hours for slot and request. §Phase 17 asks for "a countdown matching the
/// mode's actual window (30 min / 24 h)" and the 30-minute one is emergency's,
/// which §Phase 17.3 builds with the category's own field. Counting down to a
/// window this screen invented would be worse than no countdown.
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

    if (booking.status != BookingStatus.requested) {
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

    final deadline = booking.createdAt?.add(acceptWindow);
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
              Text('Accepting locks the terms', style: type.bodyStrong),
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
