import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/availability/presentation/slot_picker_screen.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// What [BookSlotScreen] is pushed with.
class BookSlotArgs {
  const BookSlotArgs({required this.listingId, this.serviceName});

  factory BookSlotArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return BookSlotArgs(
      listingId: map['listingId'] as String? ?? '',
      serviceName: map['serviceName'] as String?,
    );
  }

  final String listingId;
  final String? serviceName;
}

/// **Booking a published time** — the second half of `Pick a Time.dc.html`,
/// and the close of ledger row **P9A-1**.
///
/// §Phase 9a built the time grid and stopped where the artboard continues,
/// because everything past it — address, job notes, the email-verification
/// gate, Confirm — is booking creation and belongs to this slice. This screen
/// is that continuation: it pushes [SlotPickerScreen], takes the [PickedSlot]
/// it pops, and turns it into a booking.
///
/// ## The affordance is "Pick a time", never "Book instantly" (Round 44)
///
/// Picking a published slot creates a `requested` booking the provider still
/// has to accept, on the same 24-hour clock as any other. The copy says so on
/// the confirm button and again underneath it — "Book instantly" named an
/// immediacy the state machine does not produce.
///
/// ## The verification gate is stated, not hidden
///
/// §1c gates booking on a verified email. The server refuses regardless
/// (invariant 4), and a customer who has not verified is told why here rather
/// than being handed a refusal after filling the form in.
class BookSlotScreen extends ConsumerStatefulWidget {
  const BookSlotScreen({required this.args, super.key});

  static const routeName = '/book';

  final BookSlotArgs args;

  @override
  ConsumerState<BookSlotScreen> createState() => _BookSlotScreenState();
}

class _BookSlotScreenState extends ConsumerState<BookSlotScreen> {
  final _notes = TextEditingController();
  final _address = TextEditingController();
  PickedSlot? _slot;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final auth = ref.watch(authControllerProvider);
    final verified = auth is AuthSignedIn && auth.user.emailVerified;
    final slot = _slot;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: widget.args.serviceName ?? 'Book this service',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: ListView(
              padding: AppSpacing.screenInsets,
              children: fadeUpAll([
                const SizedBox(height: AppSpacing.md),

                if (_error != null) ...[
                  NoticeBanner(message: _error ?? ''),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('When', style: type.bodyStrong),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        slot == null
                            ? 'Pick one of the provider’s open times.'
                            : bookingWhen(slot.startsAt),
                        style: slot == null
                            ? type.secondary.copyWith(
                                color: colors.textSecondary,
                              )
                            : type.body,
                      ),
                      const SizedBox(height: AppSpacing.sm2),
                      AppButton.secondary(
                        label: slot == null ? 'Pick a time' : 'Change the time',
                        expand: true,
                        onPressed: _pickTime,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  label: 'Where',
                  controller: _address,
                  hint: 'House name, floor, street',
                  maxLength: 300,
                  requirement: FieldRequirement.optional,
                  helper:
                      'Anything more precise can go in the booking chat once '
                      'the provider accepts.',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'About the job',
                  controller: _notes,
                  hint: 'Two bedrooms and a kitchen — keys with the caretaker',
                  maxLines: 4,
                  maxLength: 2000,
                  requirement: FieldRequirement.optional,
                  helper:
                      'This is what the provider sees when they decide. It '
                      'also becomes the agreed scope when they accept.',
                ),
                const SizedBox(height: AppSpacing.md),

                if (!verified) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verify your email first', style: type.bodyStrong),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Booking, enquiries and messages all need a verified '
                          'email address — it is how a provider knows there is '
                          'a real person behind a job.',
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm2),
                        AppButton.secondary(
                          label: 'Verify email',
                          expand: true,
                          onPressed: () => Navigator.of(context).pushNamed(
                            AppRoutes.verifyEmail,
                            arguments: {
                              'email': auth is AuthSignedIn
                                  ? auth.user.email
                                  : '',
                              'purpose': 'verify_email',
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppButton.primary(
                  label: 'Send request',
                  expand: true,
                  loading: _sending,
                  onPressed: slot == null || !verified || _sending
                      ? null
                      : _send,
                ),
                const SizedBox(height: AppSpacing.sm2),
                Text(
                  'This asks the provider to take the job. They have 24 hours '
                  'to answer, and the price is agreed the moment they accept — '
                  'nothing is charged here and nothing goes through RaajjePro.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.n28),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await Navigator.of(context).pushNamed<Object?>(
      SlotPickerScreen.routeName,
      arguments: {
        'listingId': widget.args.listingId,
        'serviceName': ?widget.args.serviceName,
      },
    );
    if (!mounted) return;
    if (picked is PickedSlot) {
      setState(() {
        _slot = picked;
        _error = null;
      });
    }
  }

  Future<void> _send() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final booking = await ref
          .read(bookingApiProvider)
          .createSlotBooking(
            listingId: widget.args.listingId,
            timeSlotId: slot.slotId,
            jobNotes: _notes.text,
            addressDetail: _address.text,
          );
      ref.invalidate(bookingsListProvider);
      if (!mounted) return;
      AppHaptics.commit();
      // Replace rather than push: going "back" to a form that has already
      // been sent is an invitation to send it twice.
      await Navigator.of(context).pushReplacementNamed(
        BookingDetailScreen.routeName,
        arguments: {'bookingId': booking.id},
      );
    } on ApiException catch (e) {
      // The server's own sentence — `SLOT_NO_LONGER_AVAILABLE` says "that time
      // is no longer available", which is exactly what the customer needs and
      // is the artboard's own copy. The time is cleared so the next tap is a
      // fresh choice rather than a retry of a gone one.
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (e.code == 'SLOT_NO_LONGER_AVAILABLE' ||
            e.code == 'PROVIDER_TIME_UNAVAILABLE' ||
            e.code == 'SLOT_NOT_FOUND') {
          _slot = null;
        }
      });
    } on ApiNetworkException {
      if (!mounted) return;
      setState(
        () => _error =
            'No connection — nothing was sent. Your details are still here; '
            'try again when you’re back online.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
