import 'package:flutter/material.dart';

import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/shared/shared.dart';

/// The pieces more than one booking screen draws. Nothing here decides
/// anything — every value is a field off the booking.

/// When a booking is, in one line: `Tue 25 Aug · 14:00`.
///
/// Maldives wall clock, through `core/format/maldives_time.dart`, because a
/// booking is an appointment somebody keeps in Malé and a device in another
/// timezone must not show a different hour for it.
String bookingWhen(DateTime? at) {
  if (at == null) return 'Time to be agreed';
  return '${maldivesWeekdayShort(at)} ${maldivesShortDate(at)} · ${maldivesClock(at)}';
}

/// The amount, its label and — for a callout fee — the sentence §1c requires
/// beside it.
class AmountBlock extends StatelessWidget {
  const AmountBlock({required this.booking, super.key, this.compact = false});

  final Booking booking;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final amount = booking.displayAmountLaari;
    final kind = booking.amountKind;

    // Before the provider accepts there is no agreed amount. What the listing
    // would come to is shown, labelled as an estimate rather than as agreed —
    // §1c sets the amount *at* acceptance, and a number that reads as agreed
    // before anyone agreed it is the thing §1h exists to prevent.
    final label = booking.isAgreed
        ? (kind?.label ?? 'Agreed price')
        : 'Listed price';
    final caution = booking.isAgreed
        ? kind?.caution
        : 'Not agreed yet — it becomes the agreed price when the provider accepts.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: type.caption.copyWith(color: colors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          amount == null ? 'No price yet' : mvr(amount),
          style: (compact ? type.bodyStrong : type.price).copyWith(
            color: colors.ink,
          ),
        ),
        if (caution != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            caution,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// §Phase 17's "status timeline showing when each transition happened and who
/// caused it".
///
/// The line for each event is written here from the transition name, so the
/// timeline reads as sentences rather than as machine states — and "who" is
/// the actor role, which is why a 24-hour auto-decline reads as *automatically*
/// rather than as the provider having refused.
class BookingTimeline extends StatelessWidget {
  const BookingTimeline({
    required this.events,
    required this.viewerIsCustomer,
    required this.counterpartyName,
    super.key,
  });

  final List<BookingStatusEvent> events;
  final bool viewerIsCustomer;
  final String counterpartyName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    if (events.isEmpty) {
      return Text(
        'No history yet.',
        style: type.caption.copyWith(color: colors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, event) in events.indexed)
          Semantics(
            label:
                '${_line(event)}, ${_who(event)}'
                '${event.at == null ? '' : ', ${bookingWhen(event.at)}'}',
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsetsDirectional.only(top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == events.length - 1
                              ? colors.primary
                              : colors.border,
                        ),
                      ),
                      if (index != events.length - 1)
                        Container(width: 1.5, height: 26, color: colors.border),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.sm2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.sm2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_line(event), style: type.body),
                          Text(
                            event.at == null
                                ? _who(event)
                                : '${_who(event)} · ${bookingWhen(event.at)}',
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// One sentence per edge of the machine. The withdrawal reads as a
  /// correction rather than as a failure — Round 24: "a withdrawal hides
  /// nothing, it corrects the record."
  String _line(BookingStatusEvent event) => switch (event.transition) {
    'create' => 'Requested',
    'accept' => 'Accepted — terms locked',
    'amount-set' => 'Price agreed',
    'decline' => 'Declined',
    'accept-timeout' => 'No answer in time — closed',
    'claim-payment' => '“I’ve paid” sent',
    'withdraw-payment-claim' => '“I’ve paid” withdrawn',
    'confirm-payment-received' => 'Provider confirmed receipt',
    'payment-silence-timeout' => 'No answer on payment — sent for review',
    'complete' => 'Marked complete',
    'complete-customer-confirmed' => 'Confirmed as done',
    'complete-unconfirmed' => 'Closed with no answer',
    'cancel' || 'provider-cancel' => 'Cancelled',
    'dispute' => 'Reported',
    'resolve-dispute' => 'Reviewed and closed',
    'resolve-unresolved-confirmed' => 'Reviewed — payment recorded',
    'resolve-unresolved-cancelled' => 'Reviewed — booking cancelled',
    _ => 'Updated',
  };

  String _who(BookingStatusEvent event) => switch (event.actorRole) {
    BookingActorRole.system => 'automatically',
    BookingActorRole.admin => 'RaajjePro',
    BookingActorRole.customer => viewerIsCustomer ? 'you' : counterpartyName,
    BookingActorRole.provider => viewerIsCustomer ? counterpartyName : 'you',
  };
}

/// §1h's locked agreement, drawn as what it is: the terms, and the note
/// saying when they stopped being changeable unilaterally.
class AgreementCard extends StatelessWidget {
  const AgreementCard({required this.booking, super.key});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final accepted = booking.amendments.where(
      (a) => a.status == BookingAmendmentStatus.accepted,
    );
    final original = accepted.isEmpty
        ? null
        : accepted.last.previousAmountLaari;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The agreement', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.sm2),
          AmountBlock(booking: booking, compact: true),
          if (original != null) ...[
            const SizedBox(height: 2),
            Text(
              'was ${mvr(original)} · amended and accepted',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm2),
          _Line(label: 'When', value: bookingWhen(booking.scheduledFor)),
          if ((booking.jobNotes ?? '').isNotEmpty)
            _Line(label: 'Scope', value: booking.jobNotes ?? ''),
          if ((booking.addressDetail ?? '').isNotEmpty ||
              (booking.islandDisplayName ?? '').isNotEmpty)
            _Line(
              label: 'Where',
              value: [
                if ((booking.addressDetail ?? '').isNotEmpty)
                  booking.addressDetail ?? '',
                if ((booking.islandDisplayName ?? '').isNotEmpty)
                  booking.islandDisplayName ?? '',
              ].join(' · '),
            ),
          const SizedBox(height: AppSpacing.sm2),
          Text(
            booking.isAgreed
                ? 'Price, date, time and scope are locked. Either of you can '
                      'propose a change — it takes effect only if the other '
                      'accepts, and every proposal stays on this record.'
                : 'Nothing is locked yet. These terms lock the moment the '
                      'provider accepts.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(child: Text(value, style: type.body)),
        ],
      ),
    );
  }
}

/// The counterparty, as much of them as anyone ever sees: a name and a
/// picture-less avatar.
///
/// **There is no contact affordance here**, because there is nothing to
/// contact with (§1c). Coordination is the booking chat, which §Phase 18
/// builds.
class CounterpartyRow extends StatelessWidget {
  const CounterpartyRow({
    required this.party,
    required this.caption,
    super.key,
  });

  final BookingParty party;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      children: [
        AppAvatar(name: party.name, size: AppSizes.avatarMedium),
        const SizedBox(width: AppSpacing.sm2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(party.name, style: type.bodyStrong),
              Text(
                caption,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The card every booking list row is.
class BookingRowCard extends StatelessWidget {
  const BookingRowCard({
    required this.booking,
    required this.viewerIsCustomer,
    required this.onTap,
    super.key,
  });

  final Booking booking;
  final bool viewerIsCustomer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final other = viewerIsCustomer ? booking.provider : booking.customer;
    final amount = booking.displayAmountLaari;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  booking.listingName ?? booking.categoryName ?? 'Service',
                  style: type.bodyStrong,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(booking.status.badge),
            ],
          ),
          if ((booking.occasion ?? '').isNotEmpty)
            Text(
              booking.occasion ?? '',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.sm2),
          CounterpartyRow(
            party: other,
            caption: viewerIsCustomer ? 'Provider' : 'Customer',
          ),
          const SizedBox(height: AppSpacing.sm2),
          Row(
            children: [
              Expanded(
                child: Text(
                  bookingWhen(booking.scheduledFor),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              if (amount != null)
                Text(
                  mvr(amount),
                  style: type.bodyStrong.copyWith(color: colors.ink),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.secondary(
            label: 'Open booking',
            onPressed: onTap,
            size: AppButtonSize.compact,
            expand: true,
            semanticLabel:
                'Open booking ${booking.reference}, '
                '${booking.listingName ?? 'service'}',
          ),
        ],
      ),
    );
  }
}
