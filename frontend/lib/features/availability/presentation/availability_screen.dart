import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/availability/controller/availability_controller.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';
import 'package:raajjepro/features/availability/presentation/widgets/rule_editor_sheet.dart';
import 'package:raajjepro/shared/shared.dart';

class AvailabilityArgs {
  const AvailabilityArgs({required this.listingId, this.serviceName});

  factory AvailabilityArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return AvailabilityArgs(
      listingId: map['listingId'] as String? ?? '',
      serviceName: map['serviceName'] as String?,
    );
  }

  final String listingId;
  final String? serviceName;
}

/// `Availability.dc.html` — a listing's weekly hours, the grid they produce,
/// and the modified-hours exceptions that bend them.
///
/// ## A rule saves in one step, and the artboard now agrees
///
/// This began as a departure. The artboard edited a rule into a **local
/// preview** — "Preview updated — not saved yet", with Save changes and
/// Discard beside it — and committed it with a second action. Building that
/// means expanding rules into times in Dart: a second implementation of the
/// server's `expandSlots`, which also folds in exceptions, time off, the lead
/// boundary and what is already reserved on *other* listings. Two
/// implementations of that will disagree, and the one on screen is the one a
/// provider would trust.
///
/// So a rule saves in one step, behind the artboard's own confirmation and
/// its exact reassurance — *"Times someone has already booked stay exactly as
/// they are. Only future, unbooked times change."* — and the grid then shows
/// what the server actually did. 🔧 **Round 57 took the preview out of the
/// artboard** (imported 2026-09-15), so the source and this screen now say
/// the same thing and the grid is titled "Your times" in both. If the
/// interaction is ever wanted back, the way to build it is a server-side dry
/// run — one implementation, asked "what would these rules produce?" — which
/// Round 57 names as the open option. Recorded in
/// `docs/decisions/24-phase-9a-availability-and-reservations.md`.
///
/// ## Time away is not edited here
///
/// It is provider-wide and lives in My Calendar, which the artboard says twice
/// and links to from both sections. This screen only points at it.
class AvailabilityScreen extends ConsumerWidget {
  const AvailabilityScreen({required this.args, super.key});

  static const routeName = '/provider/availability';

  final AvailabilityArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(availabilityControllerProvider(args.listingId));
    final notifier = ref.read(
      availabilityControllerProvider(args.listingId).notifier,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              title: 'Availability & time slots',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: switch (state) {
                AsyncLoading() => const _AvailabilitySkeleton(),
                AsyncError() => Padding(
                  padding: AppSpacing.screenInsets,
                  child: EmptyState.error(
                    title: 'Couldn’t load your hours',
                    body:
                        'Your rules and booked times are safe. Check your '
                        'connection and try again.',
                    onRetry: notifier.reload,
                  ),
                ),
                AsyncData(:final value) => _AvailabilityBody(
                  args: args,
                  state: value,
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

class _AvailabilityBody extends StatelessWidget {
  const _AvailabilityBody({
    required this.args,
    required this.state,
    required this.notifier,
  });

  final AvailabilityArgs args;
  final AvailabilityState state;
  final AvailabilityController notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isEmpty) {
      return Padding(
        padding: AppSpacing.screenInsets,
        child: EmptyState(
          icon: Icons.schedule_rounded,
          title: 'No working hours yet',
          body:
              'Add a weekly rule — like Mon–Thu, 09:00–17:00, 2 hours each — and '
              'bookable times are generated 60 days ahead, rolling. Customers can '
              'only pick times you publish here.',
          actionLabel: 'Add your first rule',
          onAction: () => _addRule(context),
        ),
      );
    }

    return ListView(
      padding: AppSpacing.screenInsets,
      children: [
        FadeUp(
          child: Text(
            'Bookable times, generated 60 days ahead',
            style: context.type.secondary.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FadeUp(
          index: 1,
          child: _SectionHeader(
            title: 'Weekly hours',
            actionLabel: 'Add rule',
            onAction: () => _addRule(context),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < state.availability.rules.length; i++)
          FadeUp(
            index: 2 + i,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
              child: _RuleRow(
                rule: state.availability.rules[i],
                onEdit: () => _editRule(context, state.availability.rules[i]),
                onRemove: () =>
                    _removeRule(context, state.availability.rules[i]),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        FadeUp(
          index: 3,
          child: _PublishedGrid(slots: state.slots, notifier: notifier),
        ),
        const SizedBox(height: AppSpacing.lg),
        FadeUp(
          index: 4,
          child: _HorizonNote(horizonDate: state.availability.horizonDate),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const FadeUp(
          index: 5,
          child: _SectionHeader(
            title: 'Modified hours',
            subtitle:
                'Seasonal schedules that change your times — like Ramadan. '
                'Trips and holidays live in My Calendar.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (state.availability.exceptions.isEmpty)
          FadeUp(
            index: 6,
            child: Text(
              'None yet — your weekly hours apply everywhere.',
              style: context.type.secondary.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          for (final exception in state.availability.exceptions)
            FadeUp(
              index: 6,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: AppSpacing.sm,
                ),
                child: _ExceptionRow(
                  exception: exception,
                  onRemove: () => notifier.removeException(exception.id),
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.xl),
        const FadeUp(index: 6, child: _CalendarLink()),
      ],
    );
  }

  Future<void> _addRule(BuildContext context) async {
    // Opens on the wizard's own step-5 window rather than empty — the
    // provider already said when they work.
    WeeklyRule defaults;
    try {
      defaults = await notifier.ruleDefaults();
    } on ApiException {
      defaults = const WeeklyRule(
        id: '',
        weekdays: [1, 2, 3, 4, 5],
        startTime: '09:00',
        endTime: '17:00',
        slotDurationMinutes: 120,
      );
    }
    if (!context.mounted) return;
    final edited = await showRuleEditor(
      context: context,
      initial: defaults,
      isNew: true,
    );
    if (edited == null || !context.mounted) return;
    await _saveWithConfirmation(context, edited);
  }

  Future<void> _editRule(BuildContext context, WeeklyRule rule) async {
    final edited = await showRuleEditor(
      context: context,
      initial: rule,
      isNew: false,
    );
    if (edited == null || !context.mounted) return;
    await _saveWithConfirmation(context, edited);
  }

  /// The artboard's save sheet, with its own copy — the reassurance is the
  /// point of the step, so it is stated before anything is written.
  Future<void> _saveWithConfirmation(
    BuildContext context,
    WeeklyRule rule,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Save these hours?',
      body:
          'Times someone has already booked stay exactly as they are. Only '
          'future, unbooked times change.',
      confirmLabel: 'Save rule',
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () => notifier.saveRule(rule));
  }

  Future<void> _removeRule(BuildContext context, WeeklyRule rule) async {
    final confirmed = await _confirm(
      context,
      title: 'Remove ${weekdayRangeLabel(rule.weekdays)}?',
      body:
          'Future unbooked times from this rule stop being offered. Times '
          'someone has already booked stay exactly as they are.',
      confirmLabel: 'Remove rule',
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () => notifier.removeRule(rule.id));
  }

  /// Runs a write, and says so out loud when the server refuses.
  ///
  /// The server's message is shown verbatim because every refusal here is a
  /// rule written for a provider to read — "Those hours overlap another rule
  /// on the same day (09:00–13:00)". A generic failure would throw that away.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
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

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) => showAppBottomSheet<bool>(
  context: context,
  builder: (context) => AppBottomSheet(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.type.sectionHeading),
        const SizedBox(height: AppSpacing.sm),
        Text(body, style: context.type.body),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Keep editing',
                onPressed: () => Navigator.of(context).pop(false),
                expand: true,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton.primary(
                label: confirmLabel,
                onPressed: () => Navigator.of(context).pop(true),
                expand: true,
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.type.sectionHeading),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle!,
                  style: context.type.secondary.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (label != null && action != null)
          AppButton.text(label: label, onPressed: action),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onEdit,
    required this.onRemove,
  });

  final WeeklyRule rule;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weekdayRangeLabel(rule.weekdays),
                  style: context.type.cardTitle,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${rule.startTime}–${rule.endTime} · '
                  '${visitLengthLabel(rule.slotDurationMinutes)} each',
                  style: context.type.secondary.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            semanticLabel: 'Edit ${weekdayRangeLabel(rule.weekdays)}',
            onTap: onEdit,
            builder: (context, state) =>
                Icon(Icons.edit_outlined, color: context.colors.textSecondary),
          ),
          Pressable(
            semanticLabel: 'Remove ${weekdayRangeLabel(rule.weekdays)}',
            onTap: onRemove,
            builder: (context, state) =>
                Icon(Icons.close_rounded, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ExceptionRow extends StatelessWidget {
  const _ExceptionRow({required this.exception, required this.onRemove});

  final HoursException exception;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exception.name, style: context.type.cardTitle),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${maldivesShortDate(maldivesDayStart(exception.startDate))} – '
                '${maldivesShortDate(maldivesDayStart(exception.endDate))} · '
                '${exception.startTime}–${exception.endTime}',
                style: context.type.secondary.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Pressable(
          semanticLabel: 'Remove ${exception.name}',
          onTap: onRemove,
          builder: (context, state) =>
              Icon(Icons.close_rounded, color: context.colors.textSecondary),
        ),
      ],
    ),
  );
}

/// The first five days of the generated grid, which is what the artboard shows.
class _PublishedGrid extends StatelessWidget {
  const _PublishedGrid({required this.slots, required this.notifier});

  static const _daysShown = 5;

  final List<TimeSlotView> slots;
  final AvailabilityController notifier;

  @override
  Widget build(BuildContext context) {
    final byDay = <String, List<TimeSlotView>>{};
    for (final slot in slots) {
      byDay.putIfAbsent(maldivesDateKey(slot.startsAt), () => []).add(slot);
    }
    final days = (byDay.keys.toList()..sort()).take(_daysShown).toList();
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your times', style: context.type.sectionHeading),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Tap an open time to block it. Reserved times belong to bookings and '
          'can’t be changed.',
          style: context.type.secondary.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Legend(),
        const SizedBox(height: AppSpacing.lg),
        for (final day in days) ...[
          Text(
            maldivesDayLabel(maldivesDayStart(day), now),
            style: context.type.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final slot in byDay[day] ?? const <TimeSlotView>[])
                _SlotChip(slot: slot, onTap: () => _tap(context, slot)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }

  Future<void> _tap(BuildContext context, TimeSlotView slot) async {
    if (slot.status == SlotStatus.reserved) {
      await showAppBottomSheet<void>(
        context: context,
        builder: (context) => AppBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reserved · ${maldivesDayLabel(slot.startsAt, DateTime.now())} '
                '${maldivesClock(slot.startsAt)}',
                style: context.type.sectionHeading,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                // The artboard's own words, and they are the accurate
                // explanation of the provider-scoped reservation: a booking on
                // ANY listing holds this time.
                'A booking on any of your listings holds your time, so you can '
                'never be double-booked. To free this time, manage the booking '
                'itself.',
                style: context.type.body,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton.secondary(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                expand: true,
              ),
            ],
          ),
        ),
      );
      return;
    }
    await notifier.toggleBlock(slot);
    AppHaptics.selection();
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.onTap});

  final TimeSlotView slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, border, ink) = switch (slot.status) {
      SlotStatus.open => (colors.surface, colors.border, colors.ink),
      SlotStatus.reserved => (
        colors.accentTint,
        colors.accentBorder,
        colors.ink,
      ),
      SlotStatus.blocked => (
        colors.surfaceMuted,
        colors.border,
        colors.textSecondary,
      ),
    };
    final statusWord = switch (slot.status) {
      SlotStatus.open => 'open',
      SlotStatus.reserved => 'reserved',
      SlotStatus.blocked => 'blocked',
    };

    return Pressable(
      semanticLabel: '${maldivesClock(slot.startsAt)}, $statusWord',
      onTap: onTap,
      focusRadius: AppRadius.pill,
      builder: (context, state) => Container(
        height: AppSizes.chipHeight,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border, width: AppSizes.inputStroke),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slot.status != SlotStatus.open) ...[
              Icon(
                Icons.lock_outline_rounded,
                size: AppSizes.iconSm,
                color: ink,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              maldivesClock(slot.startsAt),
              style: context.type.secondary.copyWith(color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: AppSpacing.lg,
      children: [
        _LegendDot(color: colors.surface, border: colors.border, label: 'Open'),
        _LegendDot(
          color: colors.accentTint,
          border: colors.accentBorder,
          label: 'Reserved',
        ),
        _LegendDot(
          color: colors.surfaceMuted,
          border: colors.border,
          label: 'Blocked',
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.border,
    required this.label,
  });

  final Color color;
  final Color border;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: AppSpacing.md,
        height: AppSpacing.md,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppRadius.xxs),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: context.type.caption),
    ],
  );
}

class _HorizonNote extends StatelessWidget {
  const _HorizonNote({required this.horizonDate});

  final String? horizonDate;

  @override
  Widget build(BuildContext context) {
    final date = horizonDate;
    // No total is printed and no count is implied — the honest statement is
    // how far ahead the window reaches, which is a fact the server just gave.
    final text = date == null
        ? 'Times are generated 60 days ahead, rolling.'
        : 'Times run through ${maldivesShortDate(maldivesDayStart(date))} — '
              'always 60 days ahead, rolling. Customers never see a time that’s '
              'blocked, taken, or already past.';
    return Row(
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
}

class _CalendarLink extends StatelessWidget {
  const _CalendarLink();

  @override
  Widget build(BuildContext context) => AppCard(
    child: Pressable(
      semanticLabel: 'Going away? Time away lives in My Calendar',
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.providerCalendar),
      builder: (context, state) => Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            color: context.colors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Going away? Time away lives in My Calendar',
              style: context.type.body,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colors.textSecondary,
          ),
        ],
      ),
    ),
  );
}

class _AvailabilitySkeleton extends StatelessWidget {
  const _AvailabilitySkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: AppSpacing.screenInsets,
    child: SkeletonLoader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox.line(width: 180),
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
