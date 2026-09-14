import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/availability/controller/availability_controller.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';
import 'package:raajjepro/shared/shared.dart';

/// What [SlotPickerScreen] pops with. §Phase 17.1's booking flow takes it into
/// `POST /v1/bookings`.
@immutable
class PickedSlot {
  const PickedSlot({
    required this.slotId,
    required this.startsAt,
    required this.endsAt,
  });
  final String slotId;
  final DateTime startsAt;
  final DateTime endsAt;
}

class SlotPickerArgs {
  const SlotPickerArgs({required this.listingId, this.serviceName});

  /// Built from untyped route arguments so no feature has to import another's
  /// types to push this — the shape `VerifyEmailArgs` established.
  factory SlotPickerArgs.fromRouteArguments(Object? arguments) {
    final map = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};
    return SlotPickerArgs(
      listingId: map['listingId'] as String? ?? '',
      serviceName: map['serviceName'] as String?,
    );
  }

  final String listingId;
  final String? serviceName;
}

/// §Phase 9a's customer slot picker — "showing **only currently open,
/// not-yet-passed slots**, never an unavailable or already-elapsed time".
///
/// ## What this screen is, and what it deliberately is not
///
/// It is the **time-selection** half of `Pick a Time.dc.html`. Everything
/// below the time grid on that artboard — address, job notes, the price
/// footer, the email-verification gate, Confirm and "Request sent" — is
/// **booking creation**, which is §Phase 17.1. Building it here would mean
/// inventing a booking endpoint this phase has no business defining.
///
/// So picking a time and continuing pops a [PickedSlot], and §Phase 17.1
/// pushes this from its own flow. Ledger row **P9A-1** carries the handover.
///
/// ## It cannot show an unavailable time even if it wanted to
///
/// Every filter is the server's: open, past the category's own lead time, not
/// yet elapsed **at query time**, and not overlapping anything the provider is
/// already holding on another listing. Nothing here re-derives any of it, and
/// there is no client-side clock deciding what is bookable — which is what
/// makes §1c's "no picker ever shows an unavailable time" true rather than
/// hopeful.
class SlotPickerScreen extends ConsumerStatefulWidget {
  const SlotPickerScreen({required this.args, super.key});

  static const routeName = '/book/pick-a-time';

  final SlotPickerArgs args;

  @override
  ConsumerState<SlotPickerScreen> createState() => _SlotPickerScreenState();
}

class _SlotPickerScreenState extends ConsumerState<SlotPickerScreen> {
  String? _selectedDay;
  String? _selectedSlotId;

  /// Set when a slot was refused as taken. `Pick a Time.dc.html` shows it as a
  /// banner above the grid rather than a toast, because the customer has to
  /// choose again and the reason belongs beside the choice.
  String? _takenTime;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(openSlotsProvider(widget.args.listingId));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              title: 'Pick a time',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: switch (state) {
                AsyncLoading() => const _PickerSkeleton(),
                AsyncError() => _PickerError(
                  onRetry: () => ref
                      .read(openSlotsProvider(widget.args.listingId).notifier)
                      .reload(),
                ),
                AsyncData(:final value) =>
                  value.slots.isEmpty
                      ? _NoTimesPublished(serviceName: widget.args.serviceName)
                      : _PickerBody(
                          slots: value,
                          serviceName: widget.args.serviceName,
                          selectedDay: _selectedDay,
                          selectedSlotId: _selectedSlotId,
                          takenTime: _takenTime,
                          onDay: _selectDay,
                          onSlot: _selectSlot,
                          onContinue: () => _continueWith(value),
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selectDay(String day) {
    AppHaptics.selection();
    setState(() {
      _selectedDay = day;
      _selectedSlotId = null;
    });
  }

  void _selectSlot(OpenSlot slot) {
    // The clearest `selection` surface in the app: a choice changed, and
    // nothing has landed yet — the commit happens when the booking is sent,
    // which is §Phase 17.1's.
    AppHaptics.selection();
    setState(() {
      _selectedSlotId = slot.id;
      _takenTime = null;
    });
  }

  void _continueWith(OpenSlots slots) {
    final id = _selectedSlotId;
    if (id == null) return;
    final slot = slots.slots.where((s) => s.id == id).firstOrNull;
    if (slot == null) {
      // It went while the screen was open. Say which one, clear the choice,
      // and refresh — "Nothing was sent", as the artboard puts it.
      AppHaptics.refused();
      setState(() {
        _takenTime = null;
        _selectedSlotId = null;
      });
      unawaitedReload();
      return;
    }
    Navigator.of(context).pop(
      PickedSlot(slotId: slot.id, startsAt: slot.startsAt, endsAt: slot.endsAt),
    );
  }

  void unawaitedReload() {
    ref.read(openSlotsProvider(widget.args.listingId).notifier).reload();
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.slots,
    required this.serviceName,
    required this.selectedDay,
    required this.selectedSlotId,
    required this.takenTime,
    required this.onDay,
    required this.onSlot,
    required this.onContinue,
  });

  final OpenSlots slots;
  final String? serviceName;
  final String? selectedDay;
  final String? selectedSlotId;
  final String? takenTime;
  final void Function(String day) onDay;
  final void Function(OpenSlot slot) onSlot;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final byDay = <String, List<OpenSlot>>{};
    for (final slot in slots.slots) {
      byDay.putIfAbsent(maldivesDateKey(slot.startsAt), () => []).add(slot);
    }
    final days = byDay.keys.toList()..sort();
    final day = selectedDay != null && byDay.containsKey(selectedDay)
        ? selectedDay!
        : days.first;
    final times = byDay[day] ?? const <OpenSlot>[];
    final selected = times.where((s) => s.id == selectedSlotId).firstOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screenInsets,
            children: [
              if (serviceName != null)
                FadeUp(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: AppSpacing.md,
                    ),
                    child: Text(serviceName!, style: type.cardTitle),
                  ),
                ),
              if (takenTime != null)
                FadeUp(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: AppSpacing.lg,
                    ),
                    child: NoticeBanner(
                      message:
                          '$takenTime is no longer available. Someone else took it '
                          'while you were deciding — nothing was sent.',
                    ),
                  ),
                ),
              FadeUp(index: 2, child: Text('Date', style: type.sectionHeading)),
              const SizedBox(height: AppSpacing.sm),
              FadeUp(index: 3, child: _LeadTimeNote(slots: slots)),
              const SizedBox(height: AppSpacing.md),
              FadeUp(
                index: 4,
                child: _DateRail(days: days, selected: day, onTap: onDay),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeUp(
                index: 5,
                child: Text(
                  'Open times · ${maldivesDayLabel(maldivesDayStart(day), DateTime.now())}',
                  style: type.sectionHeading,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeUp(
                index: 6,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final slot in times)
                      _TimeChip(
                        slot: slot,
                        selected: slot.id == selectedSlotId,
                        onTap: () => onSlot(slot),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeUp(
                index: 6,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: AppSizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        // Round 44: a slot booking is not instant. The
                        // provider accepting is what confirms it, in every
                        // mode — so this screen never says "booked".
                        'Choosing a time asks the provider for it — nothing is '
                        'booked until they accept.',
                        style: type.secondary.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _PickerFooter(
          selected: selected,
          onContinue: selected == null ? null : onContinue,
        ),
      ],
    );
  }
}

/// Why an early time is missing, in the category's own number.
///
/// §Phase 4 seeds `minimumLeadTimeMinutes` per category and §Phase 10b keeps
/// it editable, so this renders whatever the server said and never a constant.
class _LeadTimeNote extends StatelessWidget {
  const _LeadTimeNote({required this.slots});

  final OpenSlots slots;

  @override
  Widget build(BuildContext context) {
    final minutes = slots.minimumLeadTimeMinutes;
    if (minutes <= 0) return const SizedBox.shrink();
    return Text(
      'This service needs ${visitLengthLabel(minutes)}’ notice, so the earliest '
      'you can book is ${maldivesDayLabel(slots.bookableFrom, DateTime.now()).toLowerCase()} '
      'at ${maldivesClock(slots.bookableFrom)}.',
      style: context.type.secondary.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _DateRail extends StatelessWidget {
  const _DateRail({
    required this.days,
    required this.selected,
    required this.onTap,
  });

  final List<String> days;
  final String selected;
  final void Function(String day) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return SizedBox(
      height: AppSizes.touchTarget + AppSpacing.lg,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final day = days[index];
          final instant = maldivesDayStart(day);
          final isSelected = day == selected;
          return Pressable(
            semanticLabel: maldivesDayLabel(instant, DateTime.now()),
            selected: isSelected,
            onTap: () => onTap(day),
            focusRadius: AppRadius.input,
            builder: (context, state) => Container(
              width: AppSizes.iconDisc + AppSpacing.md,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : colors.surface,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.border,
                  width: isSelected
                      ? AppSizes.selectedStroke
                      : AppSizes.inputStroke,
                ),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    maldivesWeekdayShort(instant),
                    style: type.caption.copyWith(
                      color: isSelected
                          ? colors.onPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${maldives(instant).day}',
                    style: type.cardTitle.copyWith(
                      color: isSelected ? colors.onPrimary : colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final OpenSlot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      semanticLabel:
          '${maldivesClock(slot.startsAt)} to ${maldivesClock(slot.endsAt)}',
      selected: selected,
      onTap: onTap,
      focusRadius: AppRadius.pill,
      builder: (context, state) => Container(
        height: AppSizes.chipHeight,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? AppSizes.selectedStroke : AppSizes.inputStroke,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          maldivesClock(slot.startsAt),
          style: context.type.bodyStrong.copyWith(
            color: selected ? colors.onPrimary : colors.ink,
          ),
        ),
      ),
    );
  }
}

class _PickerFooter extends StatelessWidget {
  const _PickerFooter({required this.selected, required this.onContinue});

  final OpenSlot? selected;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final slot = selected;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Padding(
        padding: AppSpacing.screenInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slot != null) ...[
              Text(
                '${maldivesDayLabel(slot.startsAt, DateTime.now())} · '
                '${maldivesClock(slot.startsAt)}–${maldivesClock(slot.endsAt)}',
                style: context.type.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppButton.primary(
              label: 'Continue',
              onPressed: onContinue,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: AppSpacing.screenInsets,
    child: SkeletonLoader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox.line(width: 120),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(
            width: double.infinity,
            height: 64,
            radius: AppRadius.input,
          ),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox.line(width: 160),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(
            width: double.infinity,
            height: 96,
            radius: AppRadius.input,
          ),
        ],
      ),
    ),
  );
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: AppSpacing.screenInsets,
    child: EmptyState.error(
      title: 'Couldn’t load the open times',
      body: 'Your connection may have dropped. Nothing was sent; try again.',
      onRetry: onRetry,
    ),
  );
}

class _NoTimesPublished extends StatelessWidget {
  const _NoTimesPublished({required this.serviceName});

  final String? serviceName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: AppSpacing.screenInsets,
    child: EmptyState(
      icon: Icons.event_busy_rounded,
      title: 'No times published yet',
      // Names what to do next rather than reporting absence. The artboard's
      // action is "Message the provider", which is §Phase 18's — so until
      // that exists this offers the one thing that really works.
      body: serviceName == null
          ? 'This provider hasn’t put up any open times right now. Check back, or '
                'look at another service.'
          : 'The provider hasn’t put up open times for $serviceName right now. '
                'Check back, or look at another service.',
      actionLabel: 'Back to the service',
      onAction: () => Navigator.of(context).maybePop(),
    ),
  );
}
