import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/format/money.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/bookings/controller/bookings_controller.dart';
import 'package:raajjepro/features/bookings/data/booking_api.dart';
import 'package:raajjepro/features/bookings/data/booking_models.dart';
import 'package:raajjepro/features/bookings/data/repeat_models.dart';
import 'package:raajjepro/features/bookings/presentation/widgets/booking_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// What [RecurringBookingScreen] is pushed with: the booking "Make this
/// recurring" was tapped on, or a series to open directly.
class RecurringBookingArgs {
  const RecurringBookingArgs({this.bookingId, this.seriesId});

  factory RecurringBookingArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return RecurringBookingArgs(
      bookingId: map['bookingId'] as String?,
      seriesId: map['seriesId'] as String?,
    );
  }

  final String? bookingId;
  final String? seriesId;
}

/// **A weekly series** — `Recurring Booking.dc.html`, §1c "Recurring
/// bookings", §Phase 17 frontend item 10.
///
/// Two views, as the artboard draws them: the **offer** ("Same time next
/// week?") from a booking, and the **series** ("Tuesdays · 14:00") once one
/// exists. A booking that is already one week of a series opens the series.
///
/// ## A weekly ask, never a subscription
///
/// §1c: "Each occurrence still requires individual provider accept.
/// Recurrence is a convenience, not a standing pre-authorization." The copy
/// says so on both views, in the artboard's words, because a customer who
/// believed next Tuesday was booked would turn up to — or wait in for — a
/// visit nobody agreed to.
class RecurringBookingScreen extends ConsumerStatefulWidget {
  const RecurringBookingScreen({required this.args, super.key});

  static const routeName = '/bookings/recurring';

  final RecurringBookingArgs args;

  @override
  ConsumerState<RecurringBookingScreen> createState() =>
      _RecurringBookingScreenState();
}

class _RecurringBookingScreenState
    extends ConsumerState<RecurringBookingScreen> {
  /// Set once the series exists — from the args, the booking, or the ask.
  String? _seriesId;

  /// The artboard's "Asked — Tuesdays are now a series" confirmation.
  RecurringSeries? _justAsked;

  @override
  void initState() {
    super.initState();
    _seriesId = widget.args.seriesId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final seriesId = _seriesId;
    final bookingId = widget.args.bookingId;

    Widget body;
    String title = 'Weekly series';
    String? subtitle;

    if (_justAsked != null) {
      final s = _justAsked;
      title = 'Same time next week?';
      subtitle = s == null ? null : _seriesSubtitle(s);
      body = s == null ? const SizedBox.shrink() : _AskedView(series: s);
    } else if (seriesId != null) {
      final series = ref.watch(recurringSeriesProvider(seriesId));
      if (series case AsyncData(:final value)) {
        title = '${_weekdayLong(_anchor(value))}s · ${_clockOf(value)}';
        subtitle = _seriesSubtitle(value, withPrice: true);
      }
      body = switch (series) {
        AsyncLoading() => const _RecurringSkeleton(),
        AsyncError(:final error) => _errorView(
          error,
          () => ref.invalidate(recurringSeriesProvider(seriesId)),
        ),
        AsyncData(:final value) => _SeriesView(series: value),
      };
    } else if (bookingId != null) {
      final booking = ref.watch(bookingDetailProvider(bookingId));
      title = 'Same time next week?';
      if (booking case AsyncData(:final value)) {
        subtitle = '${value.listingName ?? 'Booking'} · ${value.provider.name}';
        final existing = value.recurringSeriesId;
        if (existing != null) {
          // Already one week of a series: the series is what to show.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _seriesId = existing);
          });
        }
      }
      body = switch (booking) {
        AsyncLoading() => const _RecurringSkeleton(),
        AsyncError(:final error) => _errorView(
          error,
          () => ref.invalidate(bookingDetailProvider(bookingId)),
        ),
        AsyncData(:final value) => _OfferView(
          booking: value,
          onAsked: (series) => setState(() {
            _justAsked = series;
            _seriesId = series.id;
          }),
          onExisting: (id) => setState(() => _seriesId = id),
        ),
      };
    } else {
      body = _errorView(null, () => Navigator.of(context).maybePop());
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: title,
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  subtitle,
                  style: context.type.secondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _errorView(Object? error, VoidCallback onRetry) => Padding(
    padding: AppSpacing.screenInsets,
    child: EmptyState.error(
      title: 'Couldn’t load the series',
      body:
          'Your connection may have dropped. The series itself is '
          'unchanged. Try again.',
      onRetry: onRetry,
    ),
  );
}

/// "Same time next week?" — the offer, from one booking.
class _OfferView extends ConsumerStatefulWidget {
  const _OfferView({
    required this.booking,
    required this.onAsked,
    required this.onExisting,
  });

  final Booking booking;
  final ValueChanged<RecurringSeries> onAsked;
  final ValueChanged<String> onExisting;

  @override
  ConsumerState<_OfferView> createState() => _OfferViewState();
}

class _OfferViewState extends ConsumerState<_OfferView> {
  bool _sending = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final booking = widget.booking;
    final at = booking.scheduledFor;
    final next = at?.add(const Duration(days: 7));
    final first = _firstName(booking.provider.name);
    final weekday = next == null ? 'week' : _weekdayLong(next);
    final amount = booking.displayAmountLaari;
    final canRepeat =
        booking.bookingMode == BookingKind.slot &&
        (booking.status == BookingStatus.confirmed ||
            booking.status == BookingStatus.completed);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.xs),
        if (_error != null) ...[
          NoticeBanner(message: _error ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(
                    name: booking.provider.name,
                    size: AppSizes.avatarMedium,
                  ),
                  const SizedBox(width: AppSpacing.sm2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bookingWhen(at), style: type.bodyStrong),
                        Text(
                          booking.listingName ?? 'This booking',
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(booking.status.badge),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: AppSpacing.md),
              Text('NEXT ${weekday.toUpperCase()}', style: type.overline),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                [
                  bookingWhen(next),
                  if (amount != null) mvr(amount),
                ].join(' · '),
                style: type.stat,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Same address, same notes — nothing to re-enter.',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(
          label: 'Ask $first for next $weekday',
          expand: true,
          loading: _sending,
          onPressed: canRepeat && !_sending ? _ask : null,
        ),
        const SizedBox(height: AppSpacing.sm2),
        Text(
          canRepeat
              ? 'This starts a weekly ask, not a subscription — every week is '
                    'a fresh request that $first accepts or declines. You can '
                    'stop any time.'
              : 'A booking can repeat weekly once it is for a published time '
                    'and $first has confirmed it.',
          style: type.caption.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _ask() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final series = await ref
          .read(bookingApiProvider)
          .createSeries(widget.booking.id);
      ref.invalidate(bookingsListProvider);
      if (!mounted) return;
      AppHaptics.commit();
      widget.onAsked(series);
    } on ApiException catch (e) {
      if (!mounted) return;
      final details = e.details;
      final existing = details is Map<String, dynamic>
          ? details['seriesId'] as String?
          : null;
      if (e.code == 'RECURRING_SERIES_EXISTS' && existing != null) {
        widget.onExisting(existing);
        return;
      }
      AppHaptics.refused();
      setState(() => _error = e.message);
    } on ApiNetworkException {
      if (!mounted) return;
      setState(
        () => _error =
            'No connection — nothing was asked. Try again when you’re back '
            'online.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// The artboard's "Asked — Tuesdays are now a series".
class _AskedView extends StatelessWidget {
  const _AskedView({required this.series});

  final RecurringSeries series;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final asked = series.occurrences.isEmpty ? null : series.occurrences.last;
    final first = _firstName(series.provider.name);
    final weekday = asked == null ? 'week' : _weekdayLong(asked.occursAt);

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.xs),
        AppCard(
          child: Column(
            children: [
              Text(
                'Asked — ${weekday}s are now a series',
                style: type.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                asked == null
                    ? ''
                    : asked.state == RecurringOccurrenceState.missed
                    ? '$first has no open time on ${bookingWhen(asked.occursAt)}, '
                          'so that week is skipped. The ask goes out again '
                          'the week after.'
                    : '${bookingWhen(asked.occursAt)} is with $first to '
                          'accept. Each week after that, the ask goes out '
                          'again — $first says yes every time, or that week '
                          'simply doesn’t happen.',
                style: type.secondary.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              if (asked?.isWaiting ?? false)
                const StatusBadge(BadgeStatus.waitingProvider),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.text(
          label: 'Back to booking',
          expand: true,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ]),
    );
  }
}

/// "Tuesdays · 14:00" — the series and its weeks.
class _SeriesView extends ConsumerStatefulWidget {
  const _SeriesView({required this.series});

  final RecurringSeries series;

  @override
  ConsumerState<_SeriesView> createState() => _SeriesViewState();
}

enum _EndPhase { idle, confirm }

class _SeriesViewState extends ConsumerState<_SeriesView> {
  _EndPhase _end = _EndPhase.idle;
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final series = widget.series;
    final first = _firstName(series.provider.name);
    final paused = series.status == RecurringSeriesStatus.paused;
    final ended = series.status == RecurringSeriesStatus.ended;

    final rows = <_WeekRow>[
      for (final o in series.occurrences) _WeekRow.fromOccurrence(o, first),
      // The next week, not asked yet — skippable ahead of time.
      if (!ended &&
          !paused &&
          series.nextOccurrenceAt != null &&
          !series.nextOccurrenceSkipped &&
          !series.occurrences.any((o) => o.occursAt == series.nextOccurrenceAt))
        _WeekRow.future(
          series.nextOccurrenceAt ?? DateTime.now(),
          series.nextAskAt,
        ),
    ];

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.xs),
        if (_error != null) ...[
          NoticeBanner(message: _error ?? ''),
          const SizedBox(height: AppSpacing.md),
        ],
        if (paused) ...[
          _WarningPanel(
            title: series.pauseCause == RecurringPauseCause.customer
                ? 'Series paused — three weeks couldn’t be asked'
                : 'Series paused — three weeks weren’t confirmed',
            body: _pausedBody(series.pauseCause, first),
            children: [
              Expanded(
                child: AppButton.primary(
                  label: 'Keep asking weekly',
                  loading: _working,
                  onPressed: _working ? null : _resume,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton.destructive(
                  label: 'End the series',
                  onPressed: _working ? null : _confirmEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          color: colors.neutralTint,
          child: Text(
            'A series is a weekly ask, not a standing booking — $first '
            'accepts each week. A week $first doesn’t confirm simply '
            'doesn’t happen; the series carries on.',
            style: type.caption.copyWith(color: colors.textTertiary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.event_repeat_rounded,
            title: 'No weeks yet',
            body: 'The first week is asked for as soon as the series starts.',
          )
        else
          AppCard(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                for (final (index, row) in rows.indexed) ...[
                  if (index > 0) Divider(height: 1, color: colors.divider),
                  _WeekTile(
                    row: row,
                    canSkip: row.skippable && !ended && !paused && !_working,
                    onSkip: () => _skip(row.occursAt),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Skipping frees one week and tells $first — the series continues. '
          'Ending the series stops the weekly ask for good; past bookings '
          'keep their records.',
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (ended)
          AppCard(
            color: colors.neutralTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Series ended', style: type.bodyStrong),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '$first has been told, pending asks are withdrawn, and every '
                  'past booking keeps its record. You can start a new series '
                  'from any confirmed slot booking.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          )
        else if (_end == _EndPhase.confirm)
          _WarningPanel(
            title: 'End the series?',
            body:
                'The weekly ask stops and any week $first hasn’t accepted yet '
                'is withdrawn. Confirmed and past weeks are untouched.',
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Keep it going',
                  onPressed: _working
                      ? null
                      : () => setState(() => _end = _EndPhase.idle),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton.destructive(
                  label: 'Yes, end it',
                  loading: _working,
                  onPressed: _working ? null : _endSeries,
                ),
              ),
            ],
          )
        else if (!paused)
          AppButton.text(
            label: 'End the series',
            expand: true,
            onPressed: _confirmEnd,
          ),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  /// Names the provider only when all three misses were theirs. A run the
  /// customer's own unsettled fee blocked says what lifts it — proof of the
  /// transfer, not admin confirmation (§1c). A mix names neither party.
  static String _pausedBody(RecurringPauseCause cause, String first) =>
      switch (cause) {
        RecurringPauseCause.provider =>
          '$first didn’t confirm three weeks in a row, so the weekly '
              'ask has stopped going out. Keep asking, or end the series — '
              'nothing is charged either way.',
        RecurringPauseCause.customer =>
          'New bookings are on hold until the MVR 200 emergency dispatch fee '
              'is settled, so three weeks couldn’t be asked for and the '
              'weekly ask has stopped. Submitting your transfer proof lifts '
              'the hold — then keep asking weekly. Nothing is charged for '
              'the series either way.',
        RecurringPauseCause.mixed =>
          'Three weeks in a row didn’t go ahead, so the weekly ask has '
              'stopped going out. Each week below says why. Keep asking, or '
              'end the series — nothing is charged either way.',
      };

  void _confirmEnd() => setState(() => _end = _EndPhase.confirm);

  Future<void> _skip(DateTime occursAt) =>
      _act((api) => api.skipWeek(widget.series.id, occursAt));

  Future<void> _resume() => _act((api) => api.resumeSeries(widget.series.id));

  Future<void> _endSeries() async {
    await _act((api) => api.endSeries(widget.series.id));
    if (mounted) setState(() => _end = _EndPhase.idle);
  }

  Future<void> _act(
    Future<RecurringSeries> Function(BookingApi api) action,
  ) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action(ref.read(bookingApiProvider));
      ref
        ..invalidate(recurringSeriesProvider(widget.series.id))
        ..invalidate(bookingsListProvider);
      AppHaptics.commit();
    } on ApiException catch (e) {
      AppHaptics.refused();
      if (mounted) setState(() => _error = e.message);
    } on ApiNetworkException {
      if (mounted) {
        setState(
          () => _error =
              'No connection — nothing was changed. Try again when you’re '
              'back online.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// One week, as the series list draws it.
class _WeekRow {
  const _WeekRow({
    required this.occursAt,
    required this.sub,
    required this.badge,
    required this.skippable,
    required this.muted,
  });

  factory _WeekRow.fromOccurrence(RecurringOccurrence o, String first) {
    switch (o.state) {
      case RecurringOccurrenceState.asked:
        return _WeekRow(
          occursAt: o.occursAt,
          sub: 'Asked — $first hasn’t answered yet',
          badge: const StatusBadge(BadgeStatus.waitingProvider),
          skippable: o.isWaiting,
          muted: false,
        );
      case RecurringOccurrenceState.accepted:
        final done = o.bookingStatus == BookingStatus.completed;
        return _WeekRow(
          occursAt: o.occursAt,
          sub: done ? '$first came this week' : '$first accepted this week',
          badge: StatusBadge(
            done ? BadgeStatus.completed : BadgeStatus.confirmed,
          ),
          skippable: false,
          muted: false,
        );
      case RecurringOccurrenceState.missed:
        return _WeekRow(
          occursAt: o.occursAt,
          sub: switch (o.missReason) {
            'no_open_slot' =>
              '$first had no open time that week; your series continues',
            'provider_unavailable' =>
              '$first wasn’t taking bookings that week; your series continues',
            'customer_blocked' =>
              'Couldn’t be asked while the dispatch fee was unsettled; your '
                  'series continues',
            'could_not_ask' =>
              'This week couldn’t be asked for; your series continues',
            _ => 'This week was not confirmed; your series continues next week',
          },
          badge: const StatusBadge.custom(
            label: 'Not confirmed',
            tone: BadgeTone.grey,
          ),
          skippable: false,
          muted: true,
        );
      case RecurringOccurrenceState.skipped:
        return _WeekRow(
          occursAt: o.occursAt,
          sub:
              'You freed this week — $first has been told. The series '
              'continues.',
          badge: const StatusBadge.custom(
            label: 'Skipped by you',
            tone: BadgeTone.grey,
          ),
          skippable: false,
          muted: true,
        );
      case RecurringOccurrenceState.withdrawn:
        return _WeekRow(
          occursAt: o.occursAt,
          sub: 'Withdrawn when the series ended',
          badge: const StatusBadge.custom(
            label: 'Withdrawn',
            tone: BadgeTone.grey,
          ),
          skippable: false,
          muted: true,
        );
    }
  }

  factory _WeekRow.future(DateTime occursAt, DateTime? askAt) => _WeekRow(
    occursAt: occursAt,
    sub: askAt == null
        ? 'Not asked yet'
        : 'The ask goes out on ${maldivesDayLabel(askAt, DateTime.now())}',
    badge: null,
    skippable: true,
    muted: false,
  );

  final DateTime occursAt;
  final String sub;
  final StatusBadge? badge;
  final bool skippable;
  final bool muted;
}

class _WeekTile extends StatelessWidget {
  const _WeekTile({
    required this.row,
    required this.canSkip,
    required this.onSkip,
  });

  final _WeekRow row;
  final bool canSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final badge = row.badge;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookingWhen(row.occursAt),
                  style: type.bodyStrong.copyWith(
                    color: row.muted ? colors.textSecondary : colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  row.sub,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (canSkip)
            AppButton.secondary(
              label: 'Skip',
              size: AppButtonSize.compact,
              semanticLabel: 'Skip ${bookingWhen(row.occursAt)}',
              onPressed: onSkip,
            )
          else
            ?badge,
        ],
      ),
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({
    required this.title,
    required this.body,
    required this.children,
  });

  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warningTint,
        border: Border.all(color: colors.warningBorder),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: type.bodyStrong.copyWith(color: colors.warningText),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: type.secondary.copyWith(color: colors.warningText),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(children: children),
          ],
        ),
      ),
    );
  }
}

class _RecurringSkeleton extends StatelessWidget {
  const _RecurringSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.screenInsets,
    children: const [
      SizedBox(height: AppSpacing.md),
      SkeletonLoader(
        child: Column(
          children: [
            SkeletonBox(height: 90),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 200),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 52),
          ],
        ),
      ),
    ],
  );
}

const _longWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Maldives wall-clock weekday, so "next Tuesday" is Tuesday in Malé.
String _weekdayLong(DateTime instant) =>
    _longWeekdays[maldives(instant).weekday - 1];

DateTime _anchor(RecurringSeries s) => s.occurrences.isNotEmpty
    ? s.occurrences.last.occursAt
    : (s.nextOccurrenceAt ?? DateTime.now());

String _clockOf(RecurringSeries s) => maldivesClock(_anchor(s));

String _seriesSubtitle(RecurringSeries s, {bool withPrice = false}) {
  final price = s.pricePerVisitLaari;
  return [
    s.listingName ?? 'Weekly series',
    s.provider.name,
    if (withPrice && price != null) '${mvr(price)} a visit',
  ].join(' · ');
}

String _firstName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'the provider';
  return trimmed.split(RegExp(r'\s+')).first;
}
