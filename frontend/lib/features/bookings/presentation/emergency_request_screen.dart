import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/categories/categories_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/emergency_controller.dart';
import 'package:raajjepro/features/bookings/data/emergency_api.dart';
import 'package:raajjepro/features/bookings/data/emergency_models.dart';
import 'package:raajjepro/features/bookings/presentation/booking_detail_screen.dart';
import 'package:raajjepro/features/bookings/presentation/dispatch_fee_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// What [EmergencyRequestScreen] is pushed with. Both optional: Home and
/// Explore (§Phases 16 and 15) open it with nothing — or with a category
/// pre-picked — and a push about a live request opens it with its id.
class EmergencyRequestArgs {
  const EmergencyRequestArgs({this.categoryId, this.requestId});

  factory EmergencyRequestArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return EmergencyRequestArgs(
      categoryId: map['categoryId'] as String?,
      requestId: map['requestId'] as String?,
    );
  }

  final String? categoryId;
  final String? requestId;
}

/// The MVR 200 the customer is told about before they send — §1c's figure,
/// and the one number on this screen the app states rather than reads,
/// because the server returns it only once it has been incurred. It is the
/// disclosure, not the charge: the charge is the server's `dispatchFee`.
const _dispatchFeeLaari = 20000;

/// **Emergency request** — `Emergency Flow.dc.html`, the customer half of
/// §Phase 17.3.
///
/// ## Raised by trade and island, never against a provider
///
/// 🔧 Owner's decision, 2026-09-28 (Round 23: "dispatch never targets a
/// provider"). The customer picks what kind of emergency it is and where; the
/// request goes to **every** provider who clears that trade's own tier bar on
/// that island, at once. The bar and the answer window are read from the
/// category and stated before anything is sent — never a literal here.
///
/// ## One screen, the whole request
///
/// Form → sent → offers collecting → choose from up to three → matched, or
/// "No one accepted in time". Every phase is the server's (`EmergencyPhase`)
/// and every countdown counts to a deadline the server gave, so the screen
/// never decides that a window has closed — it asks again.
///
/// ## What it never shows
///
/// A phone number, a distance or a rating nobody earned. Offers are compared
/// on tier, fee and the provider's **own** arrival estimate; "1.2 km" in the
/// artboard cannot be computed from islands (owner's decision) and a rating
/// waits for §Phase 11.
class EmergencyRequestScreen extends ConsumerStatefulWidget {
  const EmergencyRequestScreen({required this.args, super.key});

  static const routeName = AppRoutes.emergency;

  final EmergencyRequestArgs args;

  @override
  ConsumerState<EmergencyRequestScreen> createState() =>
      _EmergencyRequestScreenState();
}

class _EmergencyRequestScreenState
    extends ConsumerState<EmergencyRequestScreen> {
  final _notes = TextEditingController();
  final _address = TextEditingController();
  String? _categoryId;
  Island? _island;
  String? _requestId;
  bool _sending = false;
  bool _sendFailed = false;
  String? _error;
  Map<String, dynamic>? _rateLimit;
  bool _feeBlocked = false;
  String? _notesError;
  String? _islandError;
  Timer? _tick;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.args.categoryId;
    _requestId = widget.args.requestId;
    // One second for the countdowns; every fourth tick re-reads the request,
    // because offers arrive and windows close on the server.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _ticks += 1;
      final id = _requestId;
      if (id != null && _ticks % 4 == 0) {
        final live = ref.read(emergencyRequestProvider(id)).value;
        if (live == null ||
            live.phase != EmergencyPhase.matched &&
                live.phase != EmergencyPhase.closed) {
          ref.invalidate(emergencyRequestProvider(id));
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final id = _requestId;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: id == null ? 'Emergency request' : 'Your emergency',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          Expanded(
            child: id == null
                ? _rateLimit != null
                      ? _LimitView(details: _rateLimit ?? const {})
                      : _form(context)
                : _live(context, id),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // The form
  // =========================================================================

  Widget _form(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final categories = ref.watch(categoriesControllerProvider);

    return switch (categories) {
      AsyncLoading() => const EmergencySkeleton(),
      AsyncError() => Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState.error(
          title: 'Couldn’t load the trades',
          body: 'Nothing was sent. Check your connection and try again.',
          onRetry: () => ref.invalidate(categoriesControllerProvider),
        ),
      ),
      AsyncData(:final value) => () {
        final capable = value.where((c) => c.emergencyCapable).toList();
        if (capable.isEmpty) {
          return Padding(
            padding: AppSpacing.screenInsets,
            child: EmptyState(
              icon: Icons.bolt_rounded,
              title: 'No emergency trades right now',
              body:
                  'Send a normal request instead — many providers reply '
                  'within a few hours.',
              actionLabel: 'Find a provider',
              onAction: () =>
                  Navigator.of(context).pushNamed(AppRoutes.explore),
            ),
          );
        }
        final chosen = capable.where((c) => c.id == _categoryId).firstOrNull;
        return ListView(
          padding: AppSpacing.screenInsets,
          children: fadeUpAll([
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              NoticeBanner(
                message: _error ?? '',
                actionLabel: _feeBlocked ? 'Settle it now' : null,
                onAction: _feeBlocked
                    ? () => Navigator.of(context).pushNamed(
                        DispatchFeeScreen.routeName,
                        arguments: const {'blocked': true},
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_sendFailed) ...[
              const NoticeBanner(
                icon: Icons.wifi_off_rounded,
                message:
                    'Your request didn’t send. The connection dropped before '
                    'it reached us — everything you typed is still here, '
                    'nothing was sent and nothing was charged.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppCard(
              child: Text(
                'For urgent problems only — a burst pipe, a dead circuit, '
                'something that can’t wait. Dispatching costs '
                '${mvr(_dispatchFeeLaari)}, charged only when you pick a '
                'provider. If it can wait a few hours, a normal request is '
                'free of this fee.',
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('What kind of emergency?', style: type.sectionHeading),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in capable)
                  AppChip.filter(
                    label: c.name,
                    selected: c.id == _categoryId,
                    onTap: () {
                      AppHaptics.selection();
                      setState(() => _categoryId = c.id);
                    },
                  ),
              ],
            ),
            if (chosen != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _reachCopy(chosen),
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'What’s wrong?',
              controller: _notes,
              hint: 'e.g. pipe burst under the kitchen sink, water spreading',
              maxLines: 3,
              maxLength: 240,
              errorText: _notesError,
              hasError: _notesError != null,
              helper: 'Providers see this before they answer.',
            ),
            const SizedBox(height: AppSpacing.md),
            _IslandField(
              island: _island,
              error: _islandError,
              onTap: _pickIsland,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Address on the island',
              controller: _address,
              hint: 'House name, floor, street',
              maxLength: 300,
              requirement: FieldRequirement.optional,
              helper:
                  'Shared only with the provider you pick — never with the '
                  'others.',
            ),
            const SizedBox(height: AppSpacing.md),
            const _HowItWorks(),
            const SizedBox(height: AppSpacing.md),
            AppButton.primary(
              label: _sendFailed
                  ? 'Retry — send request'
                  : 'Send emergency request',
              expand: true,
              loading: _sending,
              onPressed: _sending || chosen == null ? null : _send,
            ),
            const SizedBox(height: AppSpacing.sm2),
            AppButton.text(
              label: 'Not urgent? Make a normal booking instead',
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.explore),
            ),
            const SizedBox(height: AppSpacing.n28),
          ]),
        );
      }(),
    };
  }

  /// "Goes to every Gold-verified Plumbing provider near you at the same time
  /// — they have 30 minutes to respond." Both numbers are the category's.
  String _reachCopy(ServiceCategory c) {
    final tier = VerificationTier.parse(c.emergencyMinimumTier);
    final tierWord = switch (tier) {
      VerificationTier.gold => 'Gold',
      VerificationTier.silver => 'Silver',
      VerificationTier.bronze => 'Bronze',
      VerificationTier.none => '',
    };
    final window = c.emergencyAcceptWindowMinutes;
    final who = tierWord.isEmpty
        ? 'every verified ${c.name} provider'
        : 'every $tierWord-verified ${c.name} provider';
    return window == null
        ? 'Goes to $who on your island at the same time.'
        : 'Goes to $who on your island at the same time — they have '
              '$window minutes to respond.';
  }

  Future<void> _pickIsland() async {
    final picked = await showAppBottomSheet<Island>(
      context: context,
      barrierLabel: 'Close island picker',
      builder: (sheet) => AppBottomSheet(
        title: 'Where is the emergency?',
        onClose: () => Navigator.of(sheet).maybePop(),
        child: IslandSearchList(
          selectedIds: _island == null ? const {} : {_island?.id ?? ''},
          indicator: IslandRowIndicator.check,
          autofocus: true,
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.42,
          // Never auto-selected, even on a single match (invariant 15).
          onSelected: (island) => Navigator.of(sheet).maybePop(island),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    AppHaptics.selection();
    setState(() {
      _island = picked;
      _islandError = null;
    });
  }

  Future<void> _send() async {
    final categoryId = _categoryId;
    final island = _island;
    final notes = _notes.text.trim();
    setState(() {
      _notesError = notes.isEmpty
          ? 'Describe what happened so providers know what they’re coming to.'
          : null;
      _islandError = island == null ? 'Choose the island it’s on.' : null;
    });
    if (categoryId == null || island == null || notes.isEmpty) {
      AppHaptics.refused();
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _feeBlocked = false;
    });
    try {
      final created = await ref
          .read(emergencyApiProvider)
          .create(
            categoryId: categoryId,
            islandId: island.id,
            jobNotes: notes,
            addressDetail: _address.text,
          );
      AppHaptics.commit();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendFailed = false;
        _requestId = created.id;
      });
    } on ApiNetworkException {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendFailed = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (e.code == 'EMERGENCY_RATE_LIMITED' &&
            e.details is Map<String, dynamic>) {
          _rateLimit = e.details as Map<String, dynamic>;
        } else {
          _feeBlocked = e.code == 'DISPATCH_FEE_OUTSTANDING';
          _error = e.message.isEmpty ? genericErrorCopy : e.message;
        }
      });
    }
  }

  // =========================================================================
  // The live request
  // =========================================================================

  Widget _live(BuildContext context, String id) {
    final request = ref.watch(emergencyRequestProvider(id));
    final now = ref.watch(clockProvider)();
    return switch (request) {
      AsyncData(:final value) => _LiveView(
        request: value,
        now: now,
        onTryAgain: () {
          // "Try again now": the same trade, island and words, as a new
          // request. It counts against the limit like any request does.
          _notes.text = value.jobNotes;
          _address.text = value.addressDetail ?? '';
          setState(() {
            _categoryId = value.categoryId;
            _requestId = null;
          });
          unawaited(_resendFrom(value));
        },
        onChanged: () => ref.invalidate(emergencyRequestProvider(id)),
      ),
      AsyncError(:final error) => Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState.error(
          title: 'Couldn’t load your request',
          body: error is ApiNetworkException
              ? 'Connection lost — your request is already with providers '
                    'and stays live. Try again when you’re back online.'
              : 'Your request is unaffected. Try again.',
          onRetry: () => ref.invalidate(emergencyRequestProvider(id)),
        ),
      ),
      _ => const EmergencySkeleton(),
    };
  }

  Future<void> _resendFrom(EmergencyRequest previous) async {
    // The island is re-used by id; its display name is what the server gave.
    _island = Island(
      id: previous.islandId,
      name: previous.islandDisplayName,
      displayName: previous.islandDisplayName,
      atollName: '',
      atollAbbr: '',
      nameAmbiguous: false,
    );
    await _send();
  }
}

class _LiveView extends ConsumerStatefulWidget {
  const _LiveView({
    required this.request,
    required this.now,
    required this.onTryAgain,
    required this.onChanged,
  });

  final EmergencyRequest request;
  final DateTime now;
  final VoidCallback onTryAgain;
  final VoidCallback onChanged;

  @override
  ConsumerState<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends ConsumerState<_LiveView> {
  String? _selected;
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final r = widget.request;
    final now = widget.now;

    final body = <Widget>[
      const SizedBox(height: AppSpacing.md),
      if (_error != null) ...[
        NoticeBanner(message: _error ?? ''),
        const SizedBox(height: AppSpacing.md),
      ],
    ];

    switch (r.phase) {
      case EmergencyPhase.waiting:
      case EmergencyPhase.collecting:
        final collecting = r.phase == EmergencyPhase.collecting;
        body.addAll([
          Text(
            collecting
                ? '${r.offersReceived} '
                      '${r.offersReceived == 1 ? 'provider has' : 'providers have'}'
                      ' answered'
                : 'Sent to ${r.broadcastCount} '
                      '${r.broadcastCount == 1 ? 'provider' : 'providers'}',
            style: type.screenTitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            collecting
                ? 'Holding for more offers — ${countdown(r.collectionClosesAt, now)}. '
                      'Offers are gathered for 90 seconds so you choose '
                      'between providers instead of taking the first answer.'
                : 'Every qualified ${r.categoryName} provider on '
                      '${r.islandDisplayName} got your request at the same '
                      'moment.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          _WindowCard(request: r, now: now),
          const SizedBox(height: AppSpacing.md),
          const _HowItWorks(),
          const SizedBox(height: AppSpacing.md),
          AppButton.text(
            label: 'Cancel request',
            expand: true,
            onPressed: _working ? null : _confirmCancel,
          ),
        ]);
      case EmergencyPhase.choosing:
        final chosen = r.offers.where((o) => o.id == _selected).firstOrNull;
        body.addAll([
          Text('Pick one', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${countdown(r.choiceEndsAt, now)} to choose · '
            '${countdown(r.windowEndsAt, now)} left on the whole request',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          if (r.offersReceived > r.offers.length) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${r.offersReceived} providers answered — these are the '
              '${r.offers.length} with the lowest callout fee, then the '
              'soonest arrival.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final (i, o) in r.offers.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm2),
            _OfferCard(
              offer: o,
              islandName: r.islandDisplayName,
              selected: o.id == _selected,
              onTap: () {
                AppHaptics.selection();
                setState(() => _selected = o.id);
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (chosen != null)
            AppCard(
              child: Text(
                '${mvr(chosen.calloutFeeLaari)} to ${chosen.providerName}, '
                'paid directly — the final bill may differ once parts and '
                'labour are added. Plus ${mvr(_dispatchFeeLaari)} dispatch '
                'fee to RaajjePro, by bank transfer afterwards.',
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: chosen == null
                ? 'Select a provider to continue'
                : 'Confirm ${chosen.providerName} — ${mvr(chosen.calloutFeeLaari)}',
            expand: true,
            loading: _working,
            onPressed: chosen == null || _working
                ? null
                : () => _select(chosen.id),
          ),
          const SizedBox(height: AppSpacing.sm2),
          AppButton.text(
            label:
                'Reject all and keep looking — ${countdown(r.windowEndsAt, now)} left',
            expand: true,
            onPressed: _working ? null : _confirmRejectAll,
          ),
        ]);
      case EmergencyPhase.matched:
        body.addAll([
          Text('A provider is on the way', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Coordinate the arrival in the booking — the address, the door, '
            'anything that needs saying. The callout fee is paid to them '
            'directly; the ${mvr(_dispatchFeeLaari)} dispatch fee goes to '
            'RaajjePro by bank transfer afterwards.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Open the booking',
            expand: true,
            onPressed: r.bookingId == null
                ? null
                : () => Navigator.of(context).pushReplacementNamed(
                    BookingDetailScreen.routeName,
                    arguments: {'bookingId': r.bookingId},
                  ),
          ),
        ]);
      case EmergencyPhase.closed:
        body.add(
          r.nobodyAnswered
              ? EmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'No one accepted in time',
                  body:
                      'Your request reached every qualified provider, but no '
                      'one accepted within the window. Nothing has been '
                      'charged. A scheduled request often works better — '
                      'most providers reply within a few hours.',
                  actionLabel: 'Try again now',
                  onAction: widget.onTryAgain,
                )
              : const EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Request cancelled',
                  body: 'Providers were told it closed. Nothing was charged.',
                ),
        );
        if (r.nobodyAnswered) {
          body.addAll([
            const SizedBox(height: AppSpacing.sm2),
            AppButton.secondary(
              label: 'Turn into a scheduled request',
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.explore),
            ),
          ]);
        }
    }
    body.add(const SizedBox(height: AppSpacing.n28));

    return RefreshIndicator(
      onRefresh: () async => widget.onChanged(),
      child: ListView(
        padding: AppSpacing.screenInsets,
        children: fadeUpAll(body),
      ),
    );
  }

  Future<void> _select(String offerId) => _run(
    () => ref.read(emergencyApiProvider).select(widget.request.id, offerId),
  );

  Future<void> _confirmRejectAll() async {
    final ok = await _confirm(
      title: 'Reject all ${widget.request.offers.length} offers?',
      body:
          'These providers won’t be asked again. Your request stays live and '
          'goes to everyone else — new offers can still arrive, but none are '
          'guaranteed. Nothing has been charged.',
      action: 'Reject offers',
      keep: 'Keep choosing',
    );
    if (ok) {
      await _run(
        () => ref.read(emergencyApiProvider).rejectAll(widget.request.id),
      );
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await _confirm(
      title: 'Cancel this request?',
      body:
          'Providers will be told the request is closed. Nothing has been '
          'charged.',
      action: 'Cancel request',
      keep: 'Keep waiting',
    );
    if (ok) {
      await _run(
        () => ref.read(emergencyApiProvider).cancel(widget.request.id),
      );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    required String keep,
  }) async {
    final answer = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheet) => AppBottomSheet(
        title: title,
        onClose: () => Navigator.of(sheet).maybePop(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              body,
              style: sheet.type.secondary.copyWith(
                color: sheet.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.destructive(
              label: action,
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.text(
              label: keep,
              expand: true,
              onPressed: () => Navigator.of(sheet).maybePop(false),
            ),
          ],
        ),
      ),
    );
    return answer ?? false;
  }

  Future<void> _run(Future<EmergencyRequest> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      AppHaptics.commit();
      _selected = null;
      widget.onChanged();
    } on ApiNetworkException {
      _error =
          'No connection — nothing was changed. Try again when you’re '
          'back online.';
    } on ApiException catch (e) {
      _error = e.message.isEmpty ? genericErrorCopy : e.message;
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// One offer. Provider, tier, fee, and the provider's **own** arrival
/// estimate — "part of what you're accepting", never a platform promise.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.islandName,
    required this.selected,
    required this.onTap,
  });

  final EmergencyOffer offer;
  final String islandName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      onTap: onTap,
      selected: selected,
      semanticLabel:
          '${offer.providerName}, ${mvr(offer.calloutFeeLaari)} callout fee, '
          'about ${offer.etaMinutes} minutes by their own estimate'
          '${selected ? ', selected' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(offer.providerName, style: type.cardTitle)),
              Text(mvr(offer.calloutFeeLaari), style: type.price),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          VerificationBadge(tier: offer.verificationTier),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '~${offer.etaMinutes} min to arrive — their own estimate · '
            'works on $islandName',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          Text(
            offer.ratingAverage == null
                ? 'No ratings yet'
                : '${offer.ratingAverage?.toStringAsFixed(1)} rating',
            style: type.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.request, required this.now});

  final EmergencyRequest request;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(countdown(request.windowEndsAt, now), style: type.stat),
          Text(
            request.windowMinutes == null
                ? 'remaining of the response window'
                : 'remaining of the ${request.windowMinutes}-minute response '
                      'window',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    Widget line(String head, String rest) => Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$head ', style: type.bodyStrong),
            TextSpan(
              text: rest,
              style: type.secondary.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            'Everyone qualified is asked at once.',
            'Not one at a time — they all get your request together.',
          ),
          line(
            'You choose from up to 3 offers.',
            'Each answers with their own callout fee and arrival estimate.',
          ),
          line(
            '${mvr(_dispatchFeeLaari)} only if you pick someone.',
            'A request nobody answers costs nothing. Settled afterwards by '
                'bank transfer.',
          ),
        ],
      ),
    );
  }
}

class _IslandField extends StatelessWidget {
  const _IslandField({
    required this.island,
    required this.error,
    required this.onTap,
  });

  final Island? island;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where?', style: type.bodyStrong),
        const SizedBox(height: AppSpacing.xs),
        AppButton.secondary(
          label: island == null
              ? 'Choose the island'
              : island?.displayName ?? '',
          icon: Icons.place_outlined,
          expand: true,
          semanticLabel: island == null
              ? 'Choose the island'
              : 'Island: ${island?.displayName}. Change',
          onPressed: onTap,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
            child: Text(
              error ?? '',
              style: type.caption.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}

/// "You've reached the emergency limit" — the numbers are the server's.
class _LimitView extends StatelessWidget {
  const _LimitView({required this.details});

  final Map<String, dynamic> details;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final next = DateTime.tryParse(details['nextAvailableAt'] as String? ?? '');
    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.lg),
        Text('You’ve reached the emergency limit', style: type.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Emergency requests are capped so that dispatch stays fast for '
          'everyone with a genuine emergency.',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last 24 hours · ${details['usedLast24Hours']} of '
                '${details['limitPer24Hours']} used',
                style: type.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Last 7 days · ${details['usedLast7Days']} of '
                '${details['limitPer7Days']} used',
                style: type.bodyStrong,
              ),
              if (next != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Next request available ${bookingWhenLocal(next)}',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'A normal booking has no limit — many providers respond to requests '
          'within a few hours.',
          style: type.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(
          label: 'Make a normal booking instead',
          expand: true,
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.explore),
        ),
      ]),
    );
  }
}

/// "at 14:05 on 16 Sep" in local time — a short form for one deadline.
String bookingWhenLocal(DateTime at) {
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'at $hh:$mm on ${local.day} ${months[local.month - 1]}';
}

/// The loading state every §Phase 17.3 screen shares — a skeleton, never a
/// spinner, for content that is fetching (frontend/CLAUDE.md).
class EmergencySkeleton extends StatelessWidget {
  const EmergencySkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: const [
      SizedBox(height: AppSpacing.md),
      SkeletonLoader(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox.line(width: 220, height: 26),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(height: 96),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 180),
          ],
        ),
      ),
    ],
  );
}
