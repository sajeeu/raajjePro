import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_action_screens.dart';
import 'package:raajjepro/features/bookings/presentation/emergency_request_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Contact numbers** — `Reveal Contact.dc.html`, and the single place in
/// RaajjePro where a phone number reaches another user (§1c).
///
/// ## The seven conditions, told as the customer meets them
///
/// Only on an emergency booking the provider has accepted; the customer
/// starts it and the provider cannot; both numbers at once, never one-way; the
/// provider is told; it ends 24 hours after the booking closes; it is on the
/// record. Every one is enforced by the server — the screen explains them and
/// renders whatever state the server reports, including the kill switch's
/// "Number sharing is paused right now", which is not an error.
///
/// ## The number is not "verified"
///
/// Round 11: "The reveal UI states that the number was confirmed at
/// verification, never that it is 'verified' as a live property." No check
/// mark, no "verified" — a sentence about when a person last looked at it,
/// and only where one did (Bronze and up).
class RevealContactScreen extends ConsumerStatefulWidget {
  const RevealContactScreen({required this.args, super.key});

  static const routeName = '/bookings/reveal-contact';

  final BookingActionArgs args;

  @override
  ConsumerState<RevealContactScreen> createState() =>
      _RevealContactScreenState();
}

class _RevealContactScreenState extends ConsumerState<RevealContactScreen> {
  ContactReveal? _revealed;
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final booking = ref.watch(bookingDetailProvider(widget.args.bookingId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Contact numbers',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (booking) {
              AsyncData(:final value) => _body(context, value),
              AsyncError() => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load this booking',
                  body: 'Nothing was shared. Try again.',
                  onRetry: () => ref.invalidate(
                    bookingDetailProvider(widget.args.bookingId),
                  ),
                ),
              ),
              _ => const EmergencySkeleton(),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Booking booking) {
    final colors = context.colors;
    final type = context.type;
    final auth = ref.watch(authControllerProvider);
    final viewerId = auth is AuthSignedIn ? auth.user.id : null;
    final isCustomer = viewerId == booking.customer.userId;
    final other = isCustomer ? booking.provider : booking.customer;
    final state =
        booking.emergency?.contactReveal ?? ContactRevealState.notAvailable;
    final revealed = _revealed;

    final children = <Widget>[const SizedBox(height: AppSpacing.md)];
    if (_error != null) {
      children.addAll([
        NoticeBanner(message: _error ?? ''),
        const SizedBox(height: AppSpacing.md),
      ]);
    }

    if (revealed != null) {
      children.addAll(_numbers(context, booking, revealed, isCustomer));
    } else {
      switch (state) {
        case ContactRevealState.paused:
          children.add(
            EmptyState(
              icon: Icons.pause_circle_outline_rounded,
              title: 'Number sharing is paused right now',
              body:
                  'RaajjePro has switched contact reveal off across the app '
                  'for the moment. It’s nothing about you, ${other.name} or '
                  'this booking — and it isn’t an error. The booking chat is '
                  'unaffected.',
            ),
          );
        case ContactRevealState.expired:
          children.add(
            EmptyState(
              icon: Icons.lock_clock_outlined,
              title: 'Access has ended',
              body:
                  'The numbers stayed available for 24 hours after this '
                  'booking closed and have now been removed — from your side '
                  'and from ${other.name}’s, at the same time.',
            ),
          );
        case ContactRevealState.notAvailable:
          children.add(
            const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Numbers aren’t shared on this booking',
              body:
                  'Everything goes through the booking chat. The one '
                  'exception is an emergency booking a provider has accepted.',
            ),
          );
        case ContactRevealState.available:
        case ContactRevealState.revealed:
          children.addAll([
            Text(
              'The one place in RaajjePro where numbers are shared',
              style: type.sectionHeading,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Everything normally stays in chat. If chat isn’t fast enough '
              '— finding the door, getting through a locked gate, anything '
              'that needs a voice — numbers can be shared. It only ever works '
              'like this:',
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (head, rest) in [
                    (
                      'Only here —',
                      'an emergency booking the provider has accepted. Slot '
                          'and request bookings never have this.',
                    ),
                    (
                      'The customer starts it —',
                      'it never happens on its own, and the provider can’t '
                          'start it.',
                    ),
                    ('Both at once —', 'never one-way.'),
                    ('The other side is told —', 'the moment it happens.'),
                    (
                      'It ends —',
                      '24 hours after this booking closes, the numbers are '
                          'gone on both sides.',
                    ),
                    (
                      'It’s recorded —',
                      'every reveal goes on the record, and RaajjePro '
                          'reviews the patterns.',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.sm,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$head ', style: type.bodyStrong),
                            TextSpan(
                              text: rest,
                              style: type.secondary.copyWith(
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
            const SizedBox(height: AppSpacing.md),
            if (isCustomer || state == ContactRevealState.revealed)
              AppButton.primary(
                label: state == ContactRevealState.revealed
                    ? 'Show the numbers'
                    : 'Share numbers both ways',
                expand: true,
                loading: _working,
                onPressed: _working ? null : () => _reveal(booking.id),
              )
            else
              Text(
                'Only ${other.name} can start sharing numbers. Until then, '
                'the booking chat is the way to reach them.',
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
            if (isCustomer && state == ContactRevealState.available) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${other.name} sees your number the same moment you see '
                'theirs, and is told it happened.',
                style: type.caption.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ]);
      }
    }
    children.add(const SizedBox(height: AppSpacing.n28));

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll(children),
    );
  }

  List<Widget> _numbers(
    BuildContext context,
    Booking booking,
    ContactReveal r,
    bool isCustomer,
  ) {
    final colors = context.colors;
    final type = context.type;
    final theirs = isCustomer
        ? (r.providerName, r.providerPhone)
        : (r.customerName, r.customerPhone);
    final yours = isCustomer
        ? (r.customerName, r.customerPhone)
        : (r.providerName, r.providerPhone);
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(theirs.$1, style: type.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: SelectableText(theirs.$2, style: type.price)),
                AppButton.text(
                  label: 'Copy',
                  size: AppButtonSize.compact,
                  semanticLabel: 'Copy ${theirs.$1}’s number',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: theirs.$2));
                    AppHaptics.selection();
                  },
                ),
              ],
            ),
            if (isCustomer) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                r.providerTier.meets(VerificationTier.bronze)
                    ? 'This number was confirmed by an admin when '
                          '${r.providerName} was verified as a provider. It '
                          'isn’t checked live.'
                    : 'This number hasn’t been checked by anyone.',
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
            Text(
              'Your number — what ${theirs.$1} now sees',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            Text('${yours.$1} · ${yours.$2}', style: type.bodyStrong),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Both numbers disappear 24 hours after this booking closes. This '
        'reveal is on the record, and RaajjePro reviews reveal patterns.',
        style: type.caption.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.md),
      AppButton.secondary(
        label: 'Back to the booking',
        expand: true,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ];
  }

  Future<void> _reveal(String bookingId) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final r = await ref.read(emergencyApiProvider).revealContact(bookingId);
      AppHaptics.commit();
      setState(() => _revealed = r);
    } on ApiNetworkException {
      setState(() => _error = 'No connection — nothing was shared. Try again.');
    } on ApiException catch (e) {
      setState(() => _error = e.message.isEmpty ? genericErrorCopy : e.message);
      ref.invalidate(bookingDetailProvider(bookingId));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
