import 'package:flutter/material.dart';

import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/format/maldives_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/availability/data/availability_models.dart';
import 'package:raajjepro/shared/shared.dart';

/// `Availability.dc.html`'s rule editor: days, a window, and a visit length.
///
/// The hour lists run 06:00–22:00 in half-hour steps, which is the artboard's
/// own range. The server accepts any valid clock time — this is the menu, not
/// the rule.
const List<String> _hourOptions = [
  '06:00',
  '06:30',
  '07:00',
  '07:30',
  '08:00',
  '08:30',
  '09:00',
  '09:30',
  '10:00',
  '10:30',
  '11:00',
  '11:30',
  '12:00',
  '12:30',
  '13:00',
  '13:30',
  '14:00',
  '14:30',
  '15:00',
  '15:30',
  '16:00',
  '16:30',
  '17:00',
  '17:30',
  '18:00',
  '18:30',
  '19:00',
  '19:30',
  '20:00',
  '20:30',
  '21:00',
  '21:30',
  '22:00',
];

/// The artboard's "Each visit" options, in minutes.
const List<int> _visitOptions = [60, 90, 120, 180, 240];

const List<String> _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Returns the edited rule, or null if the provider backed out.
Future<WeeklyRule?> showRuleEditor({
  required BuildContext context,
  required WeeklyRule initial,
  required bool isNew,
}) => showAppBottomSheet<WeeklyRule>(
  context: context,
  builder: (context) => _RuleEditorSheet(initial: initial, isNew: isNew),
);

class _RuleEditorSheet extends StatefulWidget {
  const _RuleEditorSheet({required this.initial, required this.isNew});

  final WeeklyRule initial;
  final bool isNew;

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late final Set<int> _weekdays = widget.initial.weekdays.toSet();
  late String _from = widget.initial.startTime;
  late String _to = widget.initial.endTime;
  late int _visit = widget.initial.slotDurationMinutes;

  /// The one rule checked here, and only so the Save button can explain
  /// itself. The server enforces this and three more (invariant 4).
  String? get _problem {
    if (_weekdays.isEmpty) return 'Choose at least one day.';
    if (_minutes(_to) <= _minutes(_from)) {
      return 'The finish time has to be later than the start time.';
    }
    if (_visit > _minutes(_to) - _minutes(_from)) {
      return 'Each visit is longer than the hours you set, so no times could '
          'be published.';
    }
    return null;
  }

  static int _minutes(String clock) {
    final parts = clock.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final problem = _problem;

    return AppBottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.isNew ? 'Add working hours' : 'Edit working hours',
            style: type.sectionHeading,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Days', style: type.caption),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var day = 1; day <= 7; day++) ...[
                Expanded(
                  child: _DayToggle(
                    label: _dayInitials[day - 1],
                    day: day,
                    selected: _weekdays.contains(day),
                    onTap: () {
                      AppHaptics.selection();
                      setState(() {
                        if (!_weekdays.remove(day)) _weekdays.add(day);
                      });
                    },
                  ),
                ),
                if (day < 7) const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Dropdown<String>(
                  label: 'From',
                  value: _from,
                  items: {for (final h in _hourOptions) h: h},
                  onChanged: (value) => setState(() => _from = value),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Dropdown<String>(
                  label: 'To',
                  value: _to,
                  items: {for (final h in _hourOptions) h: h},
                  onChanged: (value) => setState(() => _to = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Dropdown<int>(
            label: 'Each visit',
            value: _visitOptions.contains(_visit)
                ? _visit
                : _visitOptions.first,
            items: {for (final v in _visitOptions) v: visitLengthLabel(v)},
            onChanged: (value) => setState(() => _visit = value),
          ),
          const SizedBox(height: AppSpacing.md),
          if (problem != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
              child: NoticeBanner(message: problem),
            ),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  expand: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton.primary(
                  label: 'Save rule',
                  onPressed: problem != null
                      ? null
                      : () => Navigator.of(context).pop(
                          WeeklyRule(
                            id: widget.initial.id,
                            weekdays: _weekdays.toList()..sort(),
                            startTime: _from,
                            endTime: _to,
                            slotDurationMinutes: _visit,
                          ),
                        ),
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      // The initial alone is ambiguous out loud — two Ts and two Ss.
      semanticLabel: weekdayRangeLabel([day]),
      toggled: selected,
      onTap: onTap,
      focusRadius: AppRadius.input,
      builder: (context, state) => Container(
        height: AppSizes.compactButtonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? AppSizes.selectedStroke : AppSizes.inputStroke,
          ),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Text(
          label,
          style: context.type.bodyStrong.copyWith(
            color: selected ? colors.onPrimary : colors.ink,
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.caption),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSizes.inputHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(
              color: colors.border,
              width: AppSizes.inputStroke,
            ),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              style: context.type.body.copyWith(color: colors.ink),
              onChanged: (next) {
                if (next == null) return;
                AppHaptics.selection();
                onChanged(next);
              },
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
