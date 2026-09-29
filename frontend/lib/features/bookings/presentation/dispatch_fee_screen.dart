import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/emergency_controller.dart';
import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';
import 'package:raajjepro/features/bookings/presentation/emergency_request_screen.dart';
import 'package:raajjepro/shared/shared.dart';

class DispatchFeeArgs {
  const DispatchFeeArgs({this.feeId, this.blocked = false});

  factory DispatchFeeArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return DispatchFeeArgs(
      feeId: map['feeId'] as String?,
      blocked: map['blocked'] as bool? ?? false,
    );
  }

  final String? feeId;

  /// Opened because a new booking was refused — `Dispatch Fee`'s "New
  /// bookings are on hold" state.
  final bool blocked;
}

/// **Dispatch fee** — `Dispatch Fee.dc.html`, §1c's MVR 200.
///
/// ## RaajjePro's money, not a provider's
///
/// This is the one payment on the customer's side that an admin checks, and
/// the screen says so, because every other payment a customer makes in this
/// app is to a provider and nobody checks it. The account shown is
/// RaajjePro's own, from the server's configuration — never a provider's.
///
/// ## Submitting is what lifts the hold
///
/// §1c: "The block lifts the moment the customer submits proof of transfer,
/// not when an admin confirms it." The screen says exactly that, and after
/// submitting shows the admin check as "Pending — doesn't hold you up".
class DispatchFeeScreen extends ConsumerStatefulWidget {
  const DispatchFeeScreen({required this.args, super.key});

  static const routeName = AppRoutes.dispatchFee;

  final DispatchFeeArgs args;

  @override
  ConsumerState<DispatchFeeScreen> createState() => _DispatchFeeScreenState();
}

class _DispatchFeeScreenState extends ConsumerState<DispatchFeeScreen> {
  PickedImage? _proof;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fees = ref.watch(dispatchFeesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Dispatch fee',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (fees) {
              AsyncData(:final value) => _body(context, value),
              AsyncError() => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load your dispatch fee',
                  body: 'Nothing was paid or changed. Try again.',
                  onRetry: () => ref.invalidate(dispatchFeesProvider),
                ),
              ),
              _ => const EmergencySkeleton(),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, DispatchFees all) {
    final colors = context.colors;
    final type = context.type;
    final id = widget.args.feeId;
    final fee = id == null
        ? all.outstanding
        : all.fees.where((f) => f.id == id).firstOrNull;

    if (fee == null) {
      return const Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Nothing owed',
          body:
              'You have no dispatch fee to settle. One is only ever incurred '
              'when you pick a provider for an emergency.',
        ),
      );
    }

    final settled = _submitted || fee.state != DispatchFeeState.owed;
    final bank = all.bankTransfer;
    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        if (widget.args.blocked && !settled) ...[
          NoticeBanner(
            icon: Icons.pause_circle_outline_rounded,
            message:
                'New bookings are on hold until the ${mvr(fee.amountLaari)} '
                'dispatch fee is settled. Your existing bookings run as '
                'agreed and your account isn’t suspended.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_error != null) ...[
          NoticeBanner(message: _error ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Owed to RaajjePro — not to a provider', style: type.caption),
        Text(mvr(fee.amountLaari), style: type.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'For dispatching a provider to your emergency. Separate from their '
          'callout fee — that one went to them.',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (settled)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New bookings are unblocked', style: type.cardTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  fee.state == DispatchFeeState.confirmed
                      ? 'An admin has confirmed the transfer against your '
                            'reference.'
                      : fee.state == DispatchFeeState.rejected
                      ? 'An admin couldn’t match the transfer: '
                            '${fee.rejectionReason ?? 'no reason given'}. '
                            'They’ll contact you here.'
                      : 'That happened the moment you submitted — you’re not '
                            'waiting on anyone. An admin will confirm the '
                            'transfer against your reference later. Admin '
                            'check: pending — doesn’t hold you up.',
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          )
        else ...[
          AppCard(
            child: Text(
              'This one works differently from paying a provider. You upload '
              'proof of the transfer, and a RaajjePro admin checks it against '
              'the reference. Payments to providers are never checked by '
              'anyone — this one is.',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transfer to RaajjePro', style: type.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                if (bank == null)
                  Text(
                    'RaajjePro’s account details aren’t available right now. '
                    'Try again shortly.',
                    style: type.secondary.copyWith(color: colors.textSecondary),
                  )
                else ...[
                  _Row(label: 'Account holder', value: bank.accountName),
                  _Row(label: 'Bank', value: bank.bankName),
                  _Row(
                    label: 'Account number',
                    value: bank.accountNumber,
                    copyable: true,
                  ),
                ],
                _Row(
                  label: 'Transfer reference — use it exactly',
                  value: fee.referenceCode,
                  copyable: true,
                ),
                Text(
                  'The reference is how the admin matches your transfer to '
                  'this fee — without it the match is manual and slow.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Proof of transfer', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: _proof == null
                ? 'Add your transfer receipt'
                : _proof?.fileName ?? '',
            icon: _proof == null
                ? Icons.upload_file_rounded
                : Icons.image_outlined,
            expand: true,
            onPressed: _submitting ? null : _attach,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Submit proof — lifts the hold now',
            expand: true,
            loading: _submitting,
            onPressed: _proof == null || _submitting
                ? null
                : () => _submit(fee),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'New bookings unblock the moment you submit. An admin confirms '
            'the transfer afterwards.',
            style: type.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _attach() async {
    final result = await ref.read(mediaPickerProvider).pickImage();
    if (!mounted) return;
    final image = result.image;
    setState(() {
      if (image != null) {
        _proof = image;
        _error = null;
      } else {
        _error = switch (result.failure) {
          PickFailure.cancelled || null => _error,
          PickFailure.unsupportedType =>
            'That file type isn’t supported — use a JPEG, PNG or WebP.',
          PickFailure.tooLarge =>
            'That image is over 10 MB — try a smaller one.',
        };
      }
    });
  }

  Future<void> _submit(DispatchFee fee) async {
    final proof = _proof;
    if (proof == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(emergencyApiProvider)
          .uploadFeeProofAndSubmit(fee.id, proof);
      AppHaptics.commit();
      setState(() => _submitted = true);
      ref.invalidate(dispatchFeesProvider);
    } on ApiNetworkException {
      setState(
        () => _error =
            'No connection — your proof didn’t send and nothing changed. Try '
            'again when you’re back online.',
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message.isEmpty ? genericErrorCopy : e.message);
    } on Object {
      setState(() => _error = genericErrorCopy);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
                Text(value, style: type.bodyStrong),
              ],
            ),
          ),
          if (copyable)
            AppButton.text(
              label: 'Copy',
              size: AppButtonSize.compact,
              semanticLabel: 'Copy the $label',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                AppHaptics.selection();
              },
            ),
        ],
      ),
    );
  }
}
