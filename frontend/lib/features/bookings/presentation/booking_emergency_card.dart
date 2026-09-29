import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';
import 'package:raajjepro/features/bookings/presentation/dispatch_fee_screen.dart';
import 'package:raajjepro/features/bookings/presentation/emergency_request_screen.dart';
import 'package:raajjepro/features/bookings/presentation/reveal_contact_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// The emergency block on `Booking Detail` — §Phase 17.3's three things a
/// live emergency booking can need, each drawn only where the server's
/// `emergency` block says it applies:
///
///  * the **MVR 200 dispatch fee**, to the customer, while it is owed;
///  * **"provider has not arrived"**, to the customer, once the category's
///    answer window has passed since they chose (Round 15) — before then it
///    says when, rather than offering a tap the server would refuse;
///  * the **contact numbers**, the one exception in the system (§1c). The
///    customer can start it; the provider sees the way in only once the
///    customer has.
///
/// The arrival estimate is the provider's own and is labelled as such.
class BookingEmergencyCard extends ConsumerStatefulWidget {
  const BookingEmergencyCard({
    required this.booking,
    required this.viewerIsCustomer,
    super.key,
  });

  final Booking booking;
  final bool viewerIsCustomer;

  @override
  ConsumerState<BookingEmergencyCard> createState() =>
      _BookingEmergencyCardState();
}

class _BookingEmergencyCardState extends ConsumerState<BookingEmergencyCard> {
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final b = widget.booking;
    final e = b.emergency;
    if (e == null) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final fee = e.dispatchFee;
    final reveal = e.contactReveal;
    final other = widget.viewerIsCustomer ? b.provider : b.customer;
    final notArrivedAt = e.notArrivedAvailableAt;

    final showReveal = widget.viewerIsCustomer
        ? reveal != ContactRevealState.notAvailable
        : reveal == ContactRevealState.revealed ||
              reveal == ContactRevealState.paused ||
              reveal == ContactRevealState.expired;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Emergency', style: type.bodyStrong),
          if (e.etaMinutes != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.viewerIsCustomer
                  ? '${other.name} estimated ~${e.etaMinutes} min to arrive — '
                        'their own estimate, not a guarantee.'
                  : 'You estimated ~${e.etaMinutes} min to arrive. Arriving '
                        'later than you said counts against your on-time '
                        'record.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            NoticeBanner(message: _error ?? ''),
          ],
          if (widget.viewerIsCustomer &&
              fee != null &&
              fee.state.holdsBookings) ...[
            const SizedBox(height: AppSpacing.sm2),
            Text(
              fee.state == DispatchFeeState.rejected
                  ? 'An admin couldn’t match your transfer for the '
                        '${mvr(fee.amountLaari)} dispatch fee, so new bookings '
                        'are on hold again until you submit a new one — this '
                        'job isn’t affected.'
                  : 'The ${mvr(fee.amountLaari)} dispatch fee to RaajjePro is '
                        'owed. New bookings are on hold until you submit proof '
                        'of the transfer — this job isn’t affected.',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(
              label: 'Settle ${mvr(fee.amountLaari)} now',
              expand: true,
              onPressed: () => Navigator.of(context).pushNamed(
                DispatchFeeScreen.routeName,
                arguments: {'feeId': fee.submissionId},
              ),
            ),
          ],
          if (showReveal) ...[
            const SizedBox(height: AppSpacing.sm2),
            AppButton.secondary(
              label: 'Contact numbers',
              icon: Icons.call_outlined,
              expand: true,
              onPressed: () => Navigator.of(context).pushNamed(
                RevealContactScreen.routeName,
                arguments: {'bookingId': b.id},
              ),
            ),
          ],
          if (widget.viewerIsCustomer && notArrivedAt != null) ...[
            const SizedBox(height: AppSpacing.sm2),
            if (now.isBefore(notArrivedAt))
              Text(
                'If ${other.name} hasn’t arrived, you can report it from '
                '${bookingWhenLocal(notArrivedAt).replaceFirst('at ', '')} — '
                'the request then goes out again, with no second fee.',
                style: type.caption.copyWith(color: colors.textSecondary),
              )
            else
              AppButton.text(
                label: '${other.name} hasn’t arrived',
                expand: true,
                loading: _working,
                onPressed: _working ? null : _confirmNotArrived,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmNotArrived() async {
    final other = widget.booking.provider.name;
    final ok = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheet) => AppBottomSheet(
        title: '$other hasn’t arrived?',
        onClose: () => Navigator.of(sheet).maybePop(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This releases $other and records it on their record. Your '
              'request goes straight back out to every other qualified '
              'provider — without a second dispatch fee.',
              style: sheet.type.secondary.copyWith(
                color: sheet.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.destructive(
              label: 'Release and send again',
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.text(
              label: 'Keep waiting',
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(false),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final request = await ref
          .read(emergencyApiProvider)
          .markNotArrived(widget.booking.id);
      AppHaptics.commit();
      ref.invalidate(bookingDetailProvider(widget.booking.id));
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(
        EmergencyRequestScreen.routeName,
        arguments: {'requestId': request.id},
      );
    } on ApiNetworkException {
      setState(() => _error = 'No connection — nothing was changed.');
    } on ApiException catch (e) {
      setState(() => _error = e.message.isEmpty ? genericErrorCopy : e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
