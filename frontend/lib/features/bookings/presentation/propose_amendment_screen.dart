import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Propose Amendment** (`Propose Amendment.dc.html`) — §1h's locked
/// agreement, from the side that wants to move it.
///
/// ## What this screen is actually for
///
/// Round 15 rejected escrow and obtained the behaviour it wanted — no price
/// hiking, no no-shows — by making the agreement immovable instead. So this is
/// not an edit form: it is a **proposal**, it changes nothing on its own, and
/// the copy says both. The artboard's own line is kept because it is the
/// clearest statement of the incentive: *charging more than the agreed price
/// without an accepted amendment shows on your public price-adherence number.*
///
/// ## Nothing is deleted by proposing
///
/// The row is written on proposal and stays whatever the answer is (§1h:
/// "every amendment attempt is recorded, accepted or not"). The screen says
/// so before the tap rather than letting a provider discover it afterwards.
class ProposeAmendmentScreen extends ConsumerStatefulWidget {
  const ProposeAmendmentScreen({required this.args, super.key});

  static const routeName = '/bookings/amend';

  final BookingActionArgs args;

  @override
  ConsumerState<ProposeAmendmentScreen> createState() =>
      _ProposeAmendmentScreenState();
}

class _ProposeAmendmentScreenState
    extends ConsumerState<ProposeAmendmentScreen> {
  final _amount = TextEditingController();
  final _scope = TextEditingController();
  final _reason = TextEditingController();
  String? _amountError;
  String? _nothingChanged;

  @override
  void dispose() {
    _amount.dispose();
    _scope.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final booking = ref.watch(bookingDetailProvider(widget.args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Change the agreement',
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
                        SkeletonBox(height: 110),
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
                  title: 'Couldn’t load the agreement',
                  body: error is ApiNetworkException
                      ? 'Nothing was proposed. Check your connection and try '
                            'again.'
                      : 'Nothing was proposed. Try again.',
                  onRetry: () => ref.invalidate(
                    bookingDetailProvider(widget.args.bookingId),
                  ),
                ),
              ),
              AsyncData(:final value) => _body(context, value, type, colors),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Booking booking,
    AppTypography type,
    AppColors colors,
  ) {
    final action = ref.watch(bookingActionsProvider(booking.id));
    final controller = ref.read(bookingActionsProvider(booking.id).notifier);
    final auth = ref.watch(authControllerProvider);
    final viewerId = auth is AuthSignedIn ? auth.user.id : null;
    final isCustomer = viewerId == null || viewerId == booking.customer.userId;
    final other = isCustomer ? booking.provider : booking.customer;
    final otherFirst = _firstName(other.name);

    if (!_amendable(booking.status)) {
      return Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: booking.status.isTerminal
              ? 'This booking is closed'
              : 'There’s nothing locked yet',
          body: booking.status.isTerminal
              ? 'The price, date, time and scope are final. Amendments only '
                    'exist while a job is live — if the work wasn’t right, '
                    'report a problem instead.'
              : 'Terms lock when the provider accepts. Until then there is '
                    'no agreement to amend.',
        ),
      );
    }

    if (booking.openAmendment != null) {
      return const Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.hourglass_empty_rounded,
          title: 'One change at a time',
          body:
              'There’s already a proposal waiting for an answer on this '
              'booking. Settle that one first — it’s on the booking screen.',
        ),
      );
    }

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        Text('Propose a change', style: type.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${booking.listingName ?? 'Service'} · ${other.name}',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (action.message != null) ...[
          NoticeBanner(message: action.message ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_nothingChanged != null) ...[
          NoticeBanner(message: _nothingChanged ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Original — stays on record', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.sm2),
              AmountBlock(booking: booking, compact: true),
              const SizedBox(height: AppSpacing.xs),
              Text(
                bookingWhen(booking.scheduledFor),
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
              if ((booking.jobNotes ?? '').isNotEmpty)
                Text(
                  booking.jobNotes ?? '',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          label: 'New price',
          controller: _amount,
          hint: booking.agreedAmountLaari == null
              ? '0'
              : mvr(booking.agreedAmountLaari ?? 0).replaceAll('MVR ', ''),
          prefix: const Text('MVR'),
          keyboardType: TextInputType.number,
          requirement: FieldRequirement.optional,
          errorText: _amountError,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'New scope',
          controller: _scope,
          hint: 'What the job now covers',
          maxLines: 3,
          maxLength: 2000,
          requirement: FieldRequirement.optional,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Why — $otherFirst sees this',
          controller: _reason,
          hint: 'Two extra rooms added on the day',
          maxLines: 2,
          maxLength: 500,
          requirement: FieldRequirement.optional,
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is how a higher charge stays clean',
                style: type.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Charging more than the agreed price without an accepted '
                'change shows on the provider’s public price-adherence '
                'number. Propose it here — if $otherFirst accepts, the new '
                'amount becomes the agreed price and the record stays intact. '
                'Nothing changes unless they accept, and every proposal is '
                'kept on the booking either way, with the original terms '
                'beside it.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        AppButton.primary(
          label: 'Send proposal',
          expand: true,
          loading: action.isWorking,
          onPressed: action.isWorking
              ? null
              : () => _submit(context, controller),
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _submit(
    BuildContext context,
    BookingActionsController controller,
  ) async {
    final rawAmount = _amount.text.trim();
    int? laari;
    if (rawAmount.isNotEmpty) {
      final rufiyaa = double.tryParse(rawAmount);
      if (rufiyaa == null || rufiyaa < 0) {
        setState(() => _amountError = 'Enter the amount in rufiyaa');
        return;
      }
      // Integer laari end to end (invariant 7).
      laari = (rufiyaa * 100).round();
    }
    final scope = _scope.text.trim();

    if (laari == null && scope.isEmpty) {
      setState(
        () => _nothingChanged =
            'Propose a new price or a change of scope — an amendment that '
            'changes nothing has nothing to accept.',
      );
      return;
    }
    setState(() {
      _amountError = null;
      _nothingChanged = null;
    });

    final done = await controller.proposeAmendment(
      amountLaari: laari,
      scopeNote: scope.isEmpty ? null : scope,
      reason: _reason.text,
    );
    if (!context.mounted) return;
    if (done) {
      AppHaptics.commit();
      Navigator.of(context).pop();
    }
  }

  static bool _amendable(BookingStatus status) =>
      status == BookingStatus.accepted ||
      status == BookingStatus.awaitingPayment ||
      status == BookingStatus.paymentClaimed ||
      status == BookingStatus.confirmed;
}

String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'they';
  return trimmed.split(RegExp(r'\s+')).first;
}
