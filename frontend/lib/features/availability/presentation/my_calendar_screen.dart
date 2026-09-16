import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/availability/controller/availability_controller.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';
import 'package:raajjepro/shared/shared.dart';

/// `My Calendar.dc.html` — every commitment across a provider's services, and
/// the all-day time away that removes published times.
///
/// ## What the commitments list carries today, and what it does not
///
/// §Phase 9a owns the **commitment**; §Phase 17.1 owns the **booking** behind
/// it. A `Reservation` knows when it is, how long it runs, which listing it
/// belongs to and whether it is firm — it does not know the customer, the
/// reference or the booking mode, because those live on a row that does not
/// exist yet. Those three are therefore absent rather than stubbed, and
/// ledger row **P9A-1** carries the handover. In practice a provider sees the
/// designed empty state until §Phase 17.1 lands, which is the truthful thing
/// for it to say: nothing is booked, because nothing can be yet.
class MyCalendarScreen extends ConsumerWidget {
  const MyCalendarScreen({super.key});

  static const routeName = '/provider/calendar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(providerCalendarProvider);
    final notifier = ref.read(providerCalendarProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              title: 'My Calendar',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: switch (state) {
                AsyncLoading() => const _CalendarSkeleton(),
                AsyncError() => Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState.error(
                    title: 'Couldn’t load your calendar',
                    body:
                        'Your bookings and time away are safe. Check your '
                        'connection and try again.',
                    onRetry: notifier.reload,
                  ),
                ),
                AsyncData(:final value) => _CalendarBody(
                  calendar: value,
                  notifier: notifier,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({required this.calendar, required this.notifier});

  final ProviderCalendar calendar;
  final ProviderCalendarController notifier;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final byDay = <String, List<Commitment>>{};
    for (final commitment in calendar.commitments) {
      byDay
          .putIfAbsent(maldivesDateKey(commitment.startsAt), () => [])
          .add(commitment);
    }
    final days = byDay.keys.toList()..sort();

    return ListView(
      padding: AppSpacing.screenInsets,
      children: [
        FadeUp(
          child: Text(
            'Every commitment across your services',
            style: context.type.secondary.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (calendar.commitments.isEmpty)
          FadeUp(
            index: 1,
            child: EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'Nothing booked yet',
              body:
                  'When a booking is accepted — on any of your services — it '
                  'appears here automatically. Nothing to set up.',
              actionLabel: 'Add time away',
              onAction: () => _addTimeAway(context),
            ),
          )
        else ...[
          FadeUp(
            index: 1,
            child: Text('Upcoming', style: context.type.sectionHeading),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final day in days) ...[
            FadeUp(
              index: 2,
              child: Text(
                maldivesDayLabel(maldivesDayStart(day), now),
                style: context.type.caption,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final commitment in byDay[day] ?? const <Commitment>[])
              FadeUp(
                index: 2,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.sm,
                  ),
                  child: _CommitmentRow(commitment: commitment),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          const FadeUp(
            index: 3,
            child: _Note(
              'A booking on any of your listings holds your time, so you can '
              'never be double-booked.',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        FadeUp(
          index: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time away', style: context.type.sectionHeading),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'All-day absences — trips, holidays, closures.',
                      style: context.type.secondary.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton.text(
                label: 'Add',
                onPressed: () => _addTimeAway(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (calendar.timeAway.isEmpty)
          FadeUp(
            index: 5,
            child: Text(
              'None yet — add a trip or a holiday so your calendar tells the truth.',
              style: context.type.secondary.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          for (final away in calendar.timeAway)
            FadeUp(
              index: 5,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: AppSpacing.sm,
                ),
                child: _TimeAwayRow(
                  away: away,
                  onRemove: () =>
                      _run(context, () => notifier.removeTimeAway(away.id)),
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.lg),
        const FadeUp(
          index: 6,
          child: _Note(
            // Exactly what the artboard promises, and exactly what the server
            // does: time off is an input to slot generation and nothing else.
            'Where you publish time slots, times on these dates are removed. '
            'Customers can still send requests for these dates — this is your '
            'own record for deciding what to take.',
          ),
        ),
      ],
    );
  }

  Future<void> _addTimeAway(BuildContext context) async {
    final result = await showAppBottomSheet<_TimeAwayDraft>(
      context: context,
      builder: (context) => const _TimeAwaySheet(),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => notifier.addTimeAway(
        name: result.name,
        startDate: result.startDate,
        endDate: result.endDate,
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      // Time away withdraws published times, which a customer may be looking
      // at right now — that is not quietly undoable.
      AppHaptics.commit();
    } on ApiException catch (error) {
      AppHaptics.refused();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on ApiNetworkException {
      AppHaptics.refused();
      messenger.showSnackBar(
        const SnackBar(content: Text('No connection — nothing was changed.')),
      );
    }
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({required this.commitment});

  final Commitment commitment;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(maldivesClock(commitment.startsAt), style: context.type.cardTitle),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${maldivesClock(commitment.startsAt)}–'
                '${maldivesClock(commitment.endsAt)}',
                style: context.type.body,
              ),
              // 🔧 **The customer, the reference and the mode** — the three
              // fields `My Calendar.dc.html` draws and §Phase 9a could not
              // supply, because they live on a `Booking` (ledger P9A-1). A
              // hold with no booking behind it still renders the time, which
              // is what §Phase 9a's designed empty row already was.
              if (commitment.customerName != null)
                Text(
                  commitment.customerName ?? '',
                  style: context.type.secondary.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              if (commitment.bookingReference != null)
                Text(
                  commitment.bookingReference ?? '',
                  style: context.type.caption.copyWith(
                    color: context.colors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        if (commitment.bookingMode != null) ...[
          const SizedBox(width: AppSpacing.sm),
          AppChip.label(label: _modeLabel(commitment.bookingMode ?? '')),
        ] else if (commitment.provisional)
          // A quote is offered and the customer has not answered — the time is
          // held, but it is not yet an appointment, and saying so is the
          // difference between a provider planning their day and being
          // surprised by it.
          Text(
            'Awaiting reply',
            style: context.type.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
      ],
    ),
  );

  /// The mode chip, in the words the rest of the app uses for it (Round 44:
  /// "Pick a time", never "Book instantly").
  static String _modeLabel(String mode) => switch (mode) {
    'request' => 'Requested time',
    'emergency' => 'Emergency',
    _ => 'Picked time',
  };
}

class _TimeAwayRow extends StatelessWidget {
  const _TimeAwayRow({required this.away, required this.onRemove});

  final TimeAway away;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(away.name, style: context.type.cardTitle),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${maldivesShortDate(maldivesDayStart(away.startDate))} – '
                '${maldivesShortDate(maldivesDayStart(away.endDate))}',
                style: context.type.secondary.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Pressable(
          semanticLabel: 'Remove ${away.name}',
          onTap: onRemove,
          builder: (context, state) =>
              Icon(Icons.close_rounded, color: context.colors.textSecondary),
        ),
      ],
    ),
  );
}

class _TimeAwayDraft {
  const _TimeAwayDraft({
    required this.name,
    required this.startDate,
    required this.endDate,
  });
  final String name;
  final String startDate;
  final String endDate;
}

class _TimeAwaySheet extends StatefulWidget {
  const _TimeAwaySheet();

  @override
  State<_TimeAwaySheet> createState() => _TimeAwaySheetState();
}

class _TimeAwaySheetState extends State<_TimeAwaySheet> {
  final _name = TextEditingController();
  DateTimeRange? _range;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add time away', style: context.type.sectionHeading),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A name and a date range, all day. Published time slots on those '
            'dates are removed — booked times are never touched.',
            style: context.type.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _name,
            label: 'What is it?',
            hint: 'Trip to Colombo',
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: range == null
                ? 'Choose dates'
                : '${maldivesShortDate(range.start.toUtc())} – '
                      '${maldivesShortDate(range.end.toUtc())}',
            onPressed: _pickDates,
            expand: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            label: 'Add time away',
            onPressed: range == null || _name.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    _TimeAwayDraft(
                      name: _name.text.trim(),
                      startDate: _dateKey(range.start),
                      endDate: _dateKey(range.end),
                    ),
                  ),
            expand: true,
          ),
        ],
      ),
    );
  }

  /// The picker works in the device's own calendar, so its result is read as
  /// the plain year-month-day the provider tapped rather than converted —
  /// converting would move a date across the boundary on a phone left on
  /// another timezone.
  static String _dateKey(DateTime picked) =>
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}';

  Future<void> _pickDates() async {
    final today = maldives(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      // The same horizon the grid is generated over; a trip further out than
      // that cannot remove a time, because no time exists there yet.
      lastDate: DateTime(today.year, today.month, today.day + 60),
    );
    if (picked == null) return;
    AppHaptics.selection();
    setState(() => _range = picked);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.info_outline_rounded,
        size: AppSizes.iconSm,
        color: context.colors.textSecondary,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          text,
          style: context.type.secondary.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    ],
  );
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: AppSpacing.screenInsets,
    child: SkeletonLoader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox.line(width: 200),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox(
            width: double.infinity,
            height: 76,
            radius: AppRadius.card,
          ),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(
            width: double.infinity,
            height: 76,
            radius: AppRadius.card,
          ),
        ],
      ),
    ),
  );
}
