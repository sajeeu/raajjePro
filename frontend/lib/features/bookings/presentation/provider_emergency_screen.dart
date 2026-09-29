import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/emergency_controller.dart';
import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/emergency_request_screen.dart';
import 'package:raajjepro/shared/shared.dart';

class ProviderEmergencyArgs {
  const ProviderEmergencyArgs({required this.requestId});

  factory ProviderEmergencyArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return ProviderEmergencyArgs(requestId: map['requestId'] as String? ?? '');
  }

  final String requestId;
}

/// **An emergency near you** — `Provider Emergency.dc.html`, the provider half
/// of §Phase 17.3.
///
/// ## A bid, not a race
///
/// Round 15: offers coexist, and the customer picks from up to three side by
/// side — "answering first doesn't win it". The screen says so above the form,
/// because the old instinct (tap fast, quote high) is exactly what the
/// collection window was built to defeat.
///
/// ## The fee and the arrival estimate, together
///
/// Round 22: both go in the one call. **No arrival preset is preselected**
/// and the offer cannot be sent without one — "preselecting anything anchors
/// the estimate", and on-time rate is measured against what the provider
/// chose. The presets are the category's (`emergencyEtaPresetsMinutes`),
/// never a list in this file.
///
/// ## Never queued
///
/// §0.0 item 14: the emergency accept is excluded from the offline queue by
/// name. Offline, the send control is replaced by a notice with a live retry,
/// so a provider never believes they have bid when they have not.
///
/// ## Passing
///
/// 🔧 "Decline this request" is a recorded pass that takes the request off
/// this provider's list and **does not count** in the acceptance rate (owner's
/// decision, 2026-09-28). The artboard's sheet says "Declining is counted in
/// your acceptance rate"; that sentence is wrong and is not reproduced.
class ProviderEmergencyScreen extends ConsumerStatefulWidget {
  const ProviderEmergencyScreen({required this.args, super.key});

  static const routeName = AppRoutes.providerEmergency;

  final ProviderEmergencyArgs args;

  @override
  ConsumerState<ProviderEmergencyScreen> createState() =>
      _ProviderEmergencyScreenState();
}

class _ProviderEmergencyScreenState
    extends ConsumerState<ProviderEmergencyScreen> {
  final _fee = TextEditingController();
  final _customEta = TextEditingController();
  int? _presetEta;
  bool _sending = false;
  bool _offline = false;
  String? _error;
  String? _feeError;
  String? _etaError;
  Timer? _tick;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _customEta.addListener(() => setState(() {}));
    _fee.addListener(() => setState(() {}));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks += 1;
      // Re-read every few seconds: the customer's choice is what releases or
      // chooses this provider, and it happens on the server.
      if (_ticks % 4 == 0) {
        ref.invalidate(emergencyBroadcastProvider(widget.args.requestId));
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _fee.dispose();
    _customEta.dispose();
    super.dispose();
  }

  int? get _eta {
    final custom = int.tryParse(_customEta.text.trim());
    return custom ?? _presetEta;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final broadcast = ref.watch(
      emergencyBroadcastProvider(widget.args.requestId),
    );
    final now = ref.watch(clockProvider)();

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Emergency near you',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: switch (broadcast) {
              AsyncData(:final value) => _body(context, value, now),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: error is ApiException && error.status == 404
                    ? EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'This request isn’t on your list',
                        body:
                            'It may have closed, or it went to providers in '
                            'another trade or island. The next emergency near '
                            'you reaches you the moment it’s sent.',
                        actionLabel: 'Back to jobs',
                        onAction: () => Navigator.of(context).maybePop(),
                      )
                    : EmptyState.error(
                        title: 'Couldn’t load this request',
                        body: error is ApiNetworkException
                            ? 'You’re offline. Emergency offers need a live '
                                  'connection.'
                            : 'Something went wrong fetching it. Try again.',
                        onRetry: () => ref.invalidate(
                          emergencyBroadcastProvider(widget.args.requestId),
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

  Widget _body(BuildContext context, EmergencyBroadcast b, DateTime now) {
    final colors = context.colors;
    final type = context.type;
    final mine = b.myOffer;
    final children = <Widget>[
      const SizedBox(height: AppSpacing.md),
      _RequestCard(broadcast: b, now: now),
      const SizedBox(height: AppSpacing.md),
    ];

    if (b.passed) {
      children.add(
        const EmptyState(
          icon: Icons.do_not_disturb_on_outlined,
          title: 'You passed on this one',
          body:
              'It’s off your list and nobody was told. The next emergency '
              'near you still reaches you first thing.',
        ),
      );
    } else if (mine != null && mine.state != EmergencyOfferState.expired) {
      children.addAll(_outcome(context, b, mine, now));
    } else if (!b.canOffer) {
      children.add(
        const EmptyState(
          icon: Icons.schedule_rounded,
          title: 'This request closed',
          body:
              'Offers have closed or the response window ended. Nothing more '
              'is needed from you — the next emergency near you still '
              'reaches you.',
        ),
      );
    } else {
      children.addAll(_form(context, b));
    }
    children.add(const SizedBox(height: AppSpacing.n28));

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        ...children.take(1),
        if (_error != null) ...[
          NoticeBanner(message: _error ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],
        ...children.skip(1),
        if (b.canOffer && !b.passed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nobody is told if you pass.',
            style: type.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }

  List<Widget> _form(BuildContext context, EmergencyBroadcast b) {
    final colors = context.colors;
    final type = context.type;
    final fee = int.tryParse(_fee.text.trim());
    final eta = _eta;
    return [
      AppCard(
        child: Text(
          'This is a bid, not a race. Other providers are being asked at the '
          'same time. ${b.customerFirstName} sees up to 3 offers side by side '
          'and picks one — answering first doesn’t win it. Quote the fee '
          'you’d actually charge and an arrival you can actually make.',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppTextField(
        label: 'Your callout fee',
        controller: _fee,
        prefix: Text('MVR ', style: type.bodyStrong),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 5,
        errorText: _feeError,
        hasError: _feeError != null,
        helper:
            'What you charge to attend. Parts and labour are agreed and '
            'settled directly with ${b.customerFirstName} afterwards.',
      ),
      const SizedBox(height: AppSpacing.md),
      Text('When can you get there?', style: type.bodyStrong),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final m in b.etaPresetsMinutes)
            AppChip.filter(
              label: '$m min',
              selected: _customEta.text.trim().isEmpty && _presetEta == m,
              onTap: () {
                AppHaptics.selection();
                _customEta.clear();
                setState(() {
                  _presetEta = m;
                  _etaError = null;
                });
              },
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      AppTextField(
        label: 'Or your own, in minutes',
        controller: _customEta,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 4,
        requirement: FieldRequirement.optional,
        errorText: _etaError,
        hasError: _etaError != null,
        helper:
            'Your own estimate — ${b.customerFirstName} sees it next to every '
            'other offer. Arriving later than you said counts against your '
            'on-time record.',
      ),
      const SizedBox(height: AppSpacing.md),
      if (_offline) ...[
        NoticeBanner(
          icon: Icons.wifi_off_rounded,
          message:
              'You’re offline. Emergency offers need a live connection — your '
              'fee and arrival estimate have to be current, and offers are '
              'collected in 90 seconds. Your offer did not send.',
          actionLabel: 'Retry',
          onAction: () => _send(b),
        ),
      ] else
        AppButton.primary(
          label: fee != null && fee > 0 && eta != null
              ? 'Send offer — ${mvr(fee * 100)}, $eta min'
              : 'Send offer',
          expand: true,
          loading: _sending,
          onPressed: _sending ? null : () => _send(b),
        ),
      const SizedBox(height: AppSpacing.sm2),
      AppButton.text(
        label: 'Pass on this request',
        expand: true,
        onPressed: _sending ? null : () => _confirmPass(b),
      ),
    ];
  }

  List<Widget> _outcome(
    BuildContext context,
    EmergencyBroadcast b,
    MyEmergencyOffer mine,
    DateTime now,
  ) {
    final colors = context.colors;
    final type = context.type;
    final fee = mvr(mine.calloutFeeLaari);
    switch (mine.state) {
      case EmergencyOfferState.open:
        final deadline = b.choiceEndsAt ?? b.windowEndsAt;
        return [
          Text('Your offer is in', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$fee callout · ~${mine.etaMinutes} min. ${b.customerFirstName} '
            'has until ${countdown(deadline, now)} to choose. Being first in '
            'doesn’t matter; the fee, arrival time and verification do.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Stay reachable — if ${b.customerFirstName} picks you, the '
            'address appears on the booking and the job starts right away.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ];
      case EmergencyOfferState.selected:
      case EmergencyOfferState.noShow:
      case EmergencyOfferState.cancelled:
        return [
          Text('${b.customerFirstName} picked you', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The job is yours at $fee callout — you said '
            '~${mine.etaMinutes} min. Collect the callout fee directly from '
            '${b.customerFirstName}. Parts and labour are agreed on site and '
            'settled the same way.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Open the booking',
            expand: true,
            onPressed: mine.bookingId == null
                ? null
                : () => Navigator.of(context).pushReplacementNamed(
                    BookingDetailScreen.routeName,
                    arguments: {'bookingId': mine.bookingId},
                  ),
          ),
        ];
      case EmergencyOfferState.notSelected:
      case EmergencyOfferState.rejected:
        return [
          EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: '${b.customerFirstName} chose another offer',
            body:
                'This one’s closed. Your offer of $fee was seen and compared '
                '— nothing more to do. Every new ${b.categoryName} emergency '
                'near you still reaches you the moment it’s sent.',
          ),
        ];
      case EmergencyOfferState.expired:
      case EmergencyOfferState.lapsed:
        return [
          const EmptyState(
            icon: Icons.schedule_rounded,
            title: 'This request closed',
            body:
                'The customer didn’t decide in time, so it lapsed. Nothing '
                'more is needed from you.',
          ),
        ];
    }
  }

  Future<void> _send(EmergencyBroadcast b) async {
    final fee = int.tryParse(_fee.text.trim());
    final eta = _eta;
    setState(() {
      _feeError = fee == null || fee <= 0
          ? 'Enter the fee you charge to attend.'
          : null;
      _etaError = eta == null || eta <= 0
          ? 'Choose when you can get there.'
          : null;
      _error = null;
    });
    if (fee == null || fee <= 0 || eta == null || eta <= 0) {
      AppHaptics.refused();
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(emergencyApiProvider)
          .offer(b.requestId, calloutFeeLaari: fee * 100, etaMinutes: eta);
      AppHaptics.commit();
      _offline = false;
      ref.invalidate(emergencyBroadcastProvider(b.requestId));
    } on ApiNetworkException {
      // Not queued (§0.0 item 14). Said plainly, with a live retry.
      _offline = true;
    } on ApiException catch (e) {
      _error = e.message.isEmpty ? genericErrorCopy : e.message;
      ref.invalidate(emergencyBroadcastProvider(b.requestId));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmPass(EmergencyBroadcast b) async {
    final ok = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheet) => AppBottomSheet(
        title: 'Pass on this request?',
        onClose: () => Navigator.of(sheet).maybePop(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'It comes off your list and nobody is told you passed. It '
              'doesn’t count against your record.',
              style: sheet.type.secondary.copyWith(
                color: sheet.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.primary(
              label: 'Pass',
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.text(
              label: 'Keep it open',
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(false),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(emergencyApiProvider).pass(b.requestId);
      ref.invalidate(emergencyBroadcastProvider(b.requestId));
    } on ApiNetworkException {
      if (mounted) {
        setState(
          () => _error = 'No connection — nothing was changed. Try again.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }
}

/// The job, as the provider sees it before being chosen — "job details and
/// the customer's name only". No address: "Exact address is shared if the
/// customer picks you". No distance: the system knows islands, not metres.
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.broadcast, required this.now});

  final EmergencyBroadcast broadcast;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final b = broadcast;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${b.categoryName} emergency · from ${b.customerFirstName}',
            style: type.cardTitle,
          ),
          if ((b.jobNotes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('“${b.jobNotes}”', style: type.body),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${b.islandDisplayName ?? ''} · exact address is shared if '
            '${b.customerFirstName} picks you',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            b.collectionClosesAt != null &&
                    now.isBefore(b.collectionClosesAt ?? now)
                ? 'Offers close in ${countdown(b.collectionClosesAt, now)}'
                : '${countdown(b.windowEndsAt, now)} left on the request',
            style: type.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
