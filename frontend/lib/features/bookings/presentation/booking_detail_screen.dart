import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/payment_step_screen.dart';
import 'package:raajjepro/features/bookings/presentation/propose_amendment_screen.dart';
import 'package:raajjepro/features/bookings/presentation/propose_quote_screen.dart';
import 'package:raajjepro/features/bookings/presentation/provider_receipt_screen.dart';
import 'package:raajjepro/features/bookings/presentation/quote_received_screen.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Arguments for [BookingDetailScreen], built from untyped route arguments so
/// no feature has to import this one's types to push it.
class BookingDetailArgs {
  const BookingDetailArgs({required this.bookingId});

  factory BookingDetailArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return BookingDetailArgs(bookingId: map['bookingId'] as String? ?? '');
  }

  final String bookingId;
}

/// **Booking Detail** (`Booking Detail.dc.html`) — the hub every other booking
/// screen is reached from, and the record §1h calls the evidence in a dispute.
///
/// ## One screen, both sides
///
/// The artboard is drawn for the customer; the same booking has a provider
/// reading it, and the provider's actions are different ones. Rather than two
/// screens that drift, the viewer's side is derived once — from whether the
/// signed-in user is the booking's customer — and every action list branches
/// on it. §1c makes the two asymmetric on purpose: the customer pays and
/// attests, the provider accepts, confirms and completes.
///
/// ## What is not here
///
/// **No contact affordance of any kind** (§1c). The counterparty is a name.
/// Coordination is the booking chat, which §Phase 18 builds — until it does,
/// the detail says so rather than drawing a dead button.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({required this.args, super.key});

  static const routeName = '/bookings/detail';

  final BookingDetailArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Booking',
            backLabel: 'Back to your bookings',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (booking) {
              AsyncLoading() => const _DetailSkeleton(),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load this booking',
                  body: error is ApiNetworkException
                      ? 'Nothing has changed — we just couldn’t reach it. '
                            'Check your connection and try again.'
                      : 'Nothing has changed — something went wrong fetching '
                            'it. Try again.',
                  onRetry: () =>
                      ref.invalidate(bookingDetailProvider(args.bookingId)),
                ),
              ),
              AsyncData(:final value) => _DetailBody(booking: value),
            },
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final auth = ref.watch(authControllerProvider);
    final viewerId = auth is AuthSignedIn ? auth.user.id : null;
    final isCustomer = viewerId == null || viewerId == booking.customer.userId;
    final other = isCustomer ? booking.provider : booking.customer;
    final action = ref.watch(bookingActionsProvider(booking.id));
    final open = booking.openAmendment;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.listingName ??
                        booking.categoryName ??
                        'Service booking',
                    style: type.screenTitle,
                  ),
                  if ((booking.occasion ?? '').isNotEmpty)
                    Text(
                      booking.occasion ?? '',
                      style: type.secondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  Text(
                    booking.reference,
                    style: type.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(booking.status.badge),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        // §1c step 10. The prompt is the server's — `completionPromptedAt` is
        // set by the job, never by a clock in the app.
        if (isCustomer && booking.awaitsCompletionAnswer) ...[
          _PromptCard(
            title: 'Did this happen?',
            body:
                'The booked time has passed and ${other.name} hasn’t marked '
                'the job complete. One tap settles it — and if nobody answers, '
                'it closes on its own after three days.',
            actionLabel: 'Answer now',
            onAction: () => Navigator.of(context).pushNamed(
              DidThisHappenScreen.routeName,
              arguments: {'bookingId': booking.id},
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // §1h. Only the counterparty may answer, so only they see the
        // decision; the proposer sees it as waiting.
        if (open != null) ...[
          _AmendmentCard(
            booking: booking,
            amendment: open,
            viewerIsCustomer: isCustomer,
            counterpartyName: other.name,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // §1h's replacement prefill — the customer of a booking the provider
        // walked away from. Never a broadcast: "normal bookings do not
        // broadcast", so this is a route back into the flow, not a dispatch.
        if (booking.replacement != null) ...[
          _PromptCard(
            title: 'Your booking, ready to send again',
            body:
                'Everything is carried over — the service, the time and your '
                'notes. You only pick a new time. This goes to '
                '${other.name} alone; it isn’t sent out to other providers.',
            actionLabel: 'Pick a new time',
            onAction: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        CounterpartyRow(
          party: other,
          caption: isCustomer
              ? 'Provider on this booking'
              : 'Customer on this booking',
        ),
        const SizedBox(height: AppSpacing.md),
        AgreementCard(booking: booking),
        const SizedBox(height: AppSpacing.md),

        if (booking.finalAmountLaari != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Final amount charged', style: type.bodyStrong),
                const SizedBox(height: 2),
                Text(mvr(booking.finalAmountLaari ?? 0), style: type.price),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'What the job came to in total, recorded by the provider.',
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
              Text('What has happened', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.sm2),
              BookingTimeline(
                events: booking.statusHistory,
                viewerIsCustomer: isCustomer,
                counterpartyName: other.name,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _ChatNotice(counterpartyName: other.name, booking: booking),
        const SizedBox(height: AppSpacing.md),

        ..._actions(context, ref, booking: booking, isCustomer: isCustomer),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  /// The actions this booking offers **this** viewer, in this state.
  ///
  /// The list is derived from the status rather than from a flag, so a booking
  /// that moved underneath the screen offers what it now allows. The server
  /// refuses anything stale regardless (invariant 4) — this is what a person
  /// is *shown*, not what is enforced.
  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref, {
    required Booking booking,
    required bool isCustomer,
  }) {
    final actions = <Widget>[];
    void push(String route) =>
        Navigator.of(context)
            .pushNamed(route, arguments: {'bookingId': booking.id});

    if (isCustomer) {
      // §Phase 17.2. A live quote is the one thing on this booking waiting on
      // the customer, and its own screen carries the countdown.
      if (booking.status == BookingStatus.quoteOffered) {
        actions.add(
          AppButton.primary(
            label: 'See the quote',
            expand: true,
            onPressed: () => push(QuoteReceivedScreen.routeName),
          ),
        );
      }
      if (booking.status == BookingStatus.awaitingPayment) {
        actions.add(
          AppButton.primary(
            label: 'Continue to payment',
            expand: true,
            onPressed: () => push(PaymentStepScreen.routeName),
          ),
        );
      }
      if (booking.status == BookingStatus.paymentClaimed) {
        actions.add(
          AppButton.secondary(
            label: 'Review what you sent',
            expand: true,
            onPressed: () => push(PaymentStepScreen.routeName),
          ),
        );
      }
      if (booking.status == BookingStatus.requested ||
          // §Phase 17.2: `Request a Time`'s own "Cancel this request".
          booking.status == BookingStatus.awaitingQuote ||
          booking.status == BookingStatus.accepted ||
          booking.status == BookingStatus.awaitingPayment) {
        actions.add(
          AppButton.text(
            label: booking.status == BookingStatus.awaitingQuote
                ? 'Cancel this request'
                : 'Cancel this booking',
            expand: true,
            onPressed: () => push(CancelBookingScreen.routeName),
          ),
        );
      }
    } else {
      // §Phase 17.2. The provider's answer to a request is a time and a price
      // together — never a bare accept, which the server refuses by name.
      if (booking.status == BookingStatus.awaitingQuote ||
          booking.status == BookingStatus.quoteOffered) {
        actions.add(
          AppButton.primary(
            label: booking.status == BookingStatus.quoteOffered
                ? 'Revise your quote'
                : 'Propose a time & price',
            expand: true,
            onPressed: () => push(ProposeQuoteScreen.routeName),
          ),
        );
      }
      if (booking.status == BookingStatus.paymentClaimed) {
        actions.add(
          AppButton.primary(
            label: 'Answer the payment',
            expand: true,
            onPressed: () => push(ProviderReceiptScreen.routeName),
          ),
        );
      }
      if (booking.status == BookingStatus.confirmed) {
        actions.add(
          AppButton.primary(
            label: 'Mark the job complete',
            expand: true,
            onPressed: () => push(MarkCompleteScreen.routeName),
          ),
        );
      }
      if (!booking.status.isTerminal &&
          booking.status != BookingStatus.requested) {
        actions.add(
          AppButton.text(
            label: 'Cancel this booking',
            expand: true,
            onPressed: () => push(CancelBookingScreen.routeName),
          ),
        );
      }
    }

    // §1h: either party may propose, while there is an agreement to amend.
    if (_amendable(booking.status) && booking.openAmendment == null) {
      actions.insert(
        actions.isEmpty ? 0 : 1,
        AppButton.secondary(
          label: 'Propose a change',
          expand: true,
          onPressed: () => push(ProposeAmendmentScreen.routeName),
        ),
      );
    }

    // §1c: a late dispute is accepted and queues separately, so this stays
    // available after completion — it is not a transition, it is a record.
    if (booking.status != BookingStatus.disputed &&
        booking.status != BookingStatus.disputeResolved &&
        booking.status != BookingStatus.requested) {
      actions.add(
        AppButton.text(
          label: 'Report a problem',
          expand: true,
          onPressed: () => push(RaiseDisputeScreen.routeName),
        ),
      );
    }

    return [
      for (final (index, widget) in actions.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.sm2),
        widget,
      ],
    ];
  }

  static bool _amendable(BookingStatus status) =>
      status == BookingStatus.accepted ||
      status == BookingStatus.awaitingPayment ||
      status == BookingStatus.paymentClaimed ||
      status == BookingStatus.confirmed;
}

/// §1h's amendment, and the decision where the viewer is the one who has to
/// make it.
class _AmendmentCard extends ConsumerWidget {
  const _AmendmentCard({
    required this.booking,
    required this.amendment,
    required this.viewerIsCustomer,
    required this.counterpartyName,
  });

  final Booking booking;
  final BookingAmendment amendment;
  final bool viewerIsCustomer;
  final String counterpartyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final viewerRole = viewerIsCustomer
        ? BookingActorRole.customer
        : BookingActorRole.provider;
    final mine = amendment.proposedByRole == viewerRole;
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final working = ref.watch(bookingActionsProvider(booking.id)).isWorking;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mine
                ? 'Your proposal · on the record'
                : 'Change proposed — your decision',
            style: type.bodyStrong,
          ),
          const SizedBox(height: AppSpacing.sm2),
          if (amendment.proposedAmountLaari != null)
            _Change(
              label: 'Price',
              from: amendment.previousAmountLaari == null
                  ? null
                  : mvr(amendment.previousAmountLaari ?? 0),
              to: mvr(amendment.proposedAmountLaari ?? 0),
            ),
          if (amendment.proposedScheduledFor != null)
            _Change(
              label: 'Time',
              from: amendment.previousScheduledFor == null
                  ? null
                  : bookingWhen(amendment.previousScheduledFor),
              to: bookingWhen(amendment.proposedScheduledFor),
            ),
          if ((amendment.proposedScopeNote ?? '').isNotEmpty)
            _Change(
              label: 'Scope',
              from: amendment.previousScopeNote,
              to: amendment.proposedScopeNote ?? '',
            ),
          if ((amendment.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm2),
            Text(
              mine ? 'Your reason' : '$counterpartyName’s reason',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            Text('“${amendment.reason}”', style: type.body),
          ],
          const SizedBox(height: AppSpacing.sm2),
          Text(
            mine
                ? 'The agreement hasn’t changed. It takes effect only if '
                      '$counterpartyName accepts, and the proposal stays on '
                      'this record either way.'
                : 'If you accept, this becomes the agreement. If you reject, '
                      'the original stands. Either way the proposal stays on '
                      'the record, with the original terms beside it.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm2),
          if (mine)
            AppButton.text(
              label: 'Withdraw this proposal',
              expand: true,
              loading: working,
              onPressed: working
                  ? null
                  : () => controller.withdrawAmendment(amendment.id),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Reject',
                    loading: working,
                    onPressed: working
                        ? null
                        : () => controller.respondToAmendment(
                            amendment.id,
                            accept: false,
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm2),
                Expanded(
                  child: AppButton.primary(
                    label: 'Accept',
                    loading: working,
                    onPressed: working
                        ? null
                        : () => controller.respondToAmendment(
                            amendment.id,
                            accept: true,
                          ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.label, required this.from, required this.to});

  final String label;
  final String? from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          Text(from == null ? to : '$from → $to', style: type.bodyStrong),
        ],
      ),
    );
  }
}

/// A prompt the server raised, drawn as a card with one way forward.
class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.secondary(
            label: actionLabel,
            expand: true,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// §1c's coordination rule, stated honestly.
///
/// The chat is §Phase 18's and does not exist yet, so this says what the
/// channel *is* and when it opens. **No control is drawn** — not even an
/// `InertControl`: its own note says a dead tap that advertises an action
/// with a person on the other end of it belongs absent instead, and a
/// "Message" button is exactly that (Round 23's precedent). It never offers a
/// phone number, because there is not one to offer (§1c).
class _ChatNotice extends StatelessWidget {
  const _ChatNotice({required this.counterpartyName, required this.booking});

  final String counterpartyName;
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final open =
        booking.status != BookingStatus.requested &&
        booking.status != BookingStatus.declined;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Talking to $counterpartyName', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            open
                ? 'Everything about this job — the exact address, access '
                      'instructions, arrival updates — goes through the '
                      'booking chat. It stays open for 7 days after the job '
                      'is done, then locks with the history kept.'
                : 'The booking chat opens the moment $counterpartyName '
                      'accepts. Until then they see your job details and your '
                      'name, and nothing else.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screenInsets,
      children: [
        const SizedBox(height: AppSpacing.md),
        const SkeletonLoader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox.line(width: 220, height: 26),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox.line(width: 120),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 120),
              SizedBox(height: AppSpacing.md),
              SkeletonBox(height: 180),
            ],
          ),
        ),
      ],
    );
  }
}
