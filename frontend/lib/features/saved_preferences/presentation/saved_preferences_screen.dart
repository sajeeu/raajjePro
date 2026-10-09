import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/saved_preferences/controller/saved_preferences_controller.dart';
import 'package:raajjepro/features/saved_preferences/data/saved_preferences_api.dart';
import 'package:raajjepro/shared/shared.dart';

/// **Saved preferences** — `Saved Preferences.dc.html`, §1h, §Phase 17.4
/// (reattributed by the owner on 2026-09-10).
///
/// "Saved addresses with labels, preferred time windows, and standing service
/// instructions ('gate code', 'ask for the manager'), reused across bookings"
/// — and "carried forward by Book Again", which is where they are read.
///
/// ## The island is chosen, never defaulted
///
/// The artboard's add sheet opens on "Malé". §0.0 item 12 says island search
/// is the control and never auto-selects, and §Phase 7's picker is explicit
/// that nothing is "defaulted to Malé", so the sheet opens on **no** island
/// and Save waits for one. The plan wins over the artboard here, and the
/// difference is recorded in the decision record.
///
/// ## The time-window editor is the owner-approved proposal
///
/// The artboard's "Add" on that section appended a sample and drew no editor.
/// The sheet here is decision 31 §6's proposal as the owner amended it: day
/// toggles alone, Monday first (ISO 1–7, Round 58), with no Weekdays/Weekend
/// presets, a From/To pair, and a preview in the server's label form.
class SavedPreferencesScreen extends ConsumerWidget {
  const SavedPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final prefs = ref.watch(savedPreferencesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          AppHeader.page(
            title: 'Saved preferences',
            backLabel: 'Back to Profile',
            onBack: () => Navigator.of(context).maybePop(),
            surface: true,
          ),
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
                'They pre-fill every booking — and stay editable there',
                style: type.secondary.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: switch (prefs) {
              AsyncLoading() => SkeletonLoader.rows(count: 4),
              AsyncError(:final error) => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState.error(
                  title: 'Couldn’t load preferences',
                  body: error is ApiNetworkException
                      ? 'Your connection may have dropped. Nothing is lost — '
                            'try again.'
                      : 'Something went wrong fetching them. Nothing is lost '
                            '— try again.',
                  onRetry: () => ref.invalidate(savedPreferencesProvider),
                ),
              ),
              AsyncData(:final value) when value.isEmpty => Padding(
                padding: AppSpacing.screenInsets,
                child: EmptyState(
                  icon: Icons.place_outlined,
                  title: 'Nothing saved yet',
                  body:
                      'Save an address or standing instructions and every '
                      'booking starts pre-filled.',
                  actionLabel: 'Add an address',
                  onAction: () => showAddressSheet(context, ref),
                ),
              ),
              AsyncData(:final value) => _Populated(prefs: value),
            },
          ),
        ],
      ),
    );
  }
}

class _Populated extends ConsumerWidget {
  const _Populated({required this.prefs});

  final SavedPreferences prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    return ListView(
      padding: AppSpacing.screenInsets,
      children: fadeUpAll([
        const SizedBox(height: AppSpacing.md),
        _SectionHeading(
          title: 'Saved addresses',
          actionLabel: 'Add',
          onAction: () => showAddressSheet(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (prefs.addresses.isEmpty)
          Text(
            'No saved addresses yet — add one and every booking starts '
            'pre-filled.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
        for (final (index, address) in prefs.addresses.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          _AddressCard(address: address),
        ],
        const SizedBox(height: AppSpacing.xl),
        _SectionHeading(
          title: 'Preferred time windows',
          actionLabel: 'Add',
          onAction: () => showTimeWindowSheet(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (prefs.timeWindows.isEmpty)
          Text(
            'No time windows saved yet — add the days and hours that usually '
            'suit you.',
            style: type.secondary.copyWith(color: colors.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final window in prefs.timeWindows)
                AppChip.input(
                  label: window.label,
                  onRemove: () => _removeWindow(context, ref, window),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionHeading(title: 'Standing instructions'),
        const SizedBox(height: AppSpacing.sm),
        _InstructionsCard(current: prefs.standingInstructions),
        const SizedBox(height: AppSpacing.n28),
      ]),
    );
  }

  Future<void> _removeWindow(
    BuildContext context,
    WidgetRef ref,
    SavedTimeWindow window,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(savedPreferencesApiProvider).removeTimeWindow(window.id);
      ref.invalidate(savedPreferencesProvider);
      AppHaptics.commit();
      messenger.showSnackBar(
        const SnackBar(content: Text('Time window removed')),
      );
    } on ApiException catch (e) {
      AppHaptics.refused();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiNetworkException {
      AppHaptics.refused();
      messenger.showSnackBar(
        const SnackBar(content: Text('No connection — nothing was changed.')),
      );
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Row(
      children: [
        Expanded(child: Text(title, style: context.type.sectionHeading)),
        if (label != null)
          AppButton.text(
            label: label,
            size: AppButtonSize.compact,
            semanticLabel: '$label — $title',
            onPressed: onAction,
          ),
      ],
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final SavedAddress address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.place_outlined, color: colors.primary),
          const SizedBox(width: AppSpacing.sm2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(address.label, style: type.bodyStrong),
                    AppChip.label(label: address.islandDisplayName),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  address.addressLine,
                  style: type.secondary.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          _IconAction(
            icon: Icons.edit_outlined,
            label: 'Edit ${address.label}',
            onTap: () => showAddressSheet(context, ref, editing: address),
          ),
          _IconAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove ${address.label}',
            onTap: () => _remove(context, ref),
          ),
        ],
      ),
    );
  }

  /// Removal is a soft delete on the server (invariant 8). Undo saves the same
  /// address again — the removed row stays removed, as history.
  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(savedPreferencesApiProvider);
    try {
      await api.removeAddress(address.id);
      ref.invalidate(savedPreferencesProvider);
      AppHaptics.commit();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${address.label} removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await api.addAddress(
                  label: address.label,
                  islandId: address.islandId,
                  addressLine: address.addressLine,
                );
              } on Object {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Couldn’t restore it.')),
                );
              }
              ref.invalidate(savedPreferencesProvider);
            },
          ),
        ),
      );
    } on ApiException catch (e) {
      AppHaptics.refused();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiNetworkException {
      AppHaptics.refused();
      messenger.showSnackBar(
        const SnackBar(content: Text('No connection — nothing was changed.')),
      );
    }
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    semanticLabel: label,
    onTap: onTap,
    focusRadius: AppRadius.pill,
    builder: (context, s) => SizedBox.square(
      dimension: AppSizes.touchTarget,
      child: Icon(icon, color: context.colors.textSecondary),
    ),
  );
}

/// "Shared with the provider on every booking." Read, or edited in place.
class _InstructionsCard extends ConsumerStatefulWidget {
  const _InstructionsCard({required this.current});

  final String? current;

  @override
  ConsumerState<_InstructionsCard> createState() => _InstructionsCardState();
}

class _InstructionsCardState extends ConsumerState<_InstructionsCard> {
  final _draft = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final current = widget.current;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_editing) ...[
            AppTextField(
              label: 'Standing instructions',
              controller: _draft,
              hint: 'Gate code 4471. Please call from the lobby.',
              maxLines: 3,
              maxLength: 500,
              errorText: _error,
              hasError: _error != null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppButton.primary(
                    label: 'Save',
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton.secondary(
                    label: 'Cancel',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _editing = false;
                            _error = null;
                          }),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              (current ?? '').trim().isEmpty
                  ? 'Nothing yet — a gate code or who to ask for saves '
                        'explaining it every time.'
                  : current ?? '',
              style: (current ?? '').trim().isEmpty
                  ? type.secondary.copyWith(color: colors.textSecondary)
                  : type.body,
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                label: (current ?? '').trim().isEmpty ? 'Add' : 'Edit',
                size: AppButtonSize.compact,
                semanticLabel: 'Edit standing instructions',
                onPressed: () => setState(() {
                  _draft.text = current ?? '';
                  _editing = true;
                }),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Shared with the provider on every booking.',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(savedPreferencesApiProvider)
          .setStandingInstructions(_draft.text.trim());
      ref.invalidate(savedPreferencesProvider);
      AppHaptics.commit();
      if (mounted) setState(() => _editing = false);
    } on ApiException catch (e) {
      AppHaptics.refused();
      if (mounted) setState(() => _error = e.message);
    } on ApiNetworkException {
      if (mounted) {
        setState(
          () => _error =
              'No connection — nothing was saved. Your text is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// The artboard's add/edit sheet: label, island, address line.
Future<void> showAddressSheet(
  BuildContext context,
  WidgetRef ref, {
  SavedAddress? editing,
}) => showAppBottomSheet<void>(
  context: context,
  barrierLabel: 'Close address sheet',
  builder: (_) => _AddressSheet(editing: editing),
);

class _AddressSheet extends ConsumerStatefulWidget {
  const _AddressSheet({this.editing});

  final SavedAddress? editing;

  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  final _label = TextEditingController();
  final _line = TextEditingController();
  String? _islandId;
  String? _islandName;
  bool _choosingIsland = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _label.text = editing.label;
      _line.text = editing.addressLine;
      _islandId = editing.islandId;
      _islandName = editing.islandDisplayName;
    }
    _label.addListener(_changed);
    _line.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _label
      ..removeListener(_changed)
      ..dispose();
    _line
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  bool get _canSave =>
      _label.text.trim().isNotEmpty &&
      _line.text.trim().isNotEmpty &&
      _islandId != null &&
      !_saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final editing = widget.editing != null;

    if (_choosingIsland) {
      return AppBottomSheet(
        title: 'Choose an island',
        onClose: () => setState(() => _choosingIsland = false),
        child: IslandSearchList(
          selectedIds: _islandId == null ? const {} : {_islandId ?? ''},
          indicator: IslandRowIndicator.check,
          autofocus: true,
          maxHeight: MediaQuery.sizeOf(context).height * 0.42,
          onSelected: (Island island) => setState(() {
            _islandId = island.id;
            _islandName = island.displayName;
            _choosingIsland = false;
          }),
        ),
      );
    }

    return AppBottomSheet(
      title: editing ? 'Edit address' : 'Add an address',
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            NoticeBanner(message: _error ?? ''),
            const SizedBox(height: AppSpacing.md),
          ],
          AppTextField(
            label: 'Label',
            controller: _label,
            hint: 'e.g. Home',
            maxLength: 40,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Island', style: type.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: _islandName ?? 'Choose an island',
            expand: true,
            semanticLabel: _islandName == null
                ? 'Choose an island'
                : 'Island: $_islandName. Change it',
            onPressed: () => setState(() => _choosingIsland = true),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Address',
            controller: _line,
            hint: 'Building, floor, street',
            maxLength: 300,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: editing ? 'Save changes' : 'Save address',
            expand: true,
            loading: _saving,
            onPressed: _canSave ? _save : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Cancel',
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'An address only reaches a provider inside a booking you make.',
            style: type.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final islandId = _islandId;
    if (islandId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ref.read(savedPreferencesApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    final editing = widget.editing;
    try {
      if (editing == null) {
        await api.addAddress(
          label: _label.text.trim(),
          islandId: islandId,
          addressLine: _line.text.trim(),
        );
      } else {
        await api.updateAddress(
          editing.id,
          label: _label.text.trim(),
          islandId: islandId,
          addressLine: _line.text.trim(),
        );
      }
      ref.invalidate(savedPreferencesProvider);
      AppHaptics.commit();
      if (!mounted) return;
      await Navigator.of(context).maybePop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(editing == null ? 'Address saved' : 'Address updated'),
        ),
      );
    } on ApiException catch (e) {
      AppHaptics.refused();
      if (mounted) setState(() => _error = e.message);
    } on ApiNetworkException {
      if (mounted) {
        setState(
          () => _error =
              'No connection — nothing was saved. Your details are still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Half-hour steps from 06:00 to 22:00 — the same menu as the availability
/// rule editor. The server accepts any valid `HH:MM`; this is the menu, not
/// the rule.
final List<String> _hourOptions = [
  for (var m = 6 * 60; m <= 22 * 60; m += 30)
    '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}',
];

/// Monday first — ISO 1–7, the order the API speaks (Round 58).
const List<String> _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Decision 31 §6, piece 5: "Add a time window".
Future<void> showTimeWindowSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      barrierLabel: 'Close time window sheet',
      builder: (_) => const _TimeWindowSheet(),
    );

class _TimeWindowSheet extends ConsumerStatefulWidget {
  const _TimeWindowSheet();

  @override
  ConsumerState<_TimeWindowSheet> createState() => _TimeWindowSheetState();
}

class _TimeWindowSheetState extends ConsumerState<_TimeWindowSheet> {
  // No day is preselected: a window is the customer's, not a default.
  final Set<int> _days = {};
  String _from = '09:00';
  String _to = '12:00';
  bool _saving = false;
  String? _error;

  /// Explains a disabled Save. The server checks both again (invariant 4).
  String? get _problem {
    if (_days.isEmpty) return 'Choose at least one day.';
    if (_to.compareTo(_from) <= 0) {
      return 'The window has to end after it starts.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final problem = _problem;
    final sorted = _days.toList()..sort();

    return AppBottomSheet(
      title: 'Add a time window',
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            NoticeBanner(message: _error ?? ''),
            const SizedBox(height: AppSpacing.md),
          ],
          Text('Days', style: type.caption),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var day = 1; day <= 7; day++) ...[
                Expanded(
                  child: WeekdayToggle(
                    label: _dayInitials[day - 1],
                    day: day,
                    selected: _days.contains(day),
                    onTap: () {
                      AppHaptics.selection();
                      setState(() {
                        if (!_days.remove(day)) _days.add(day);
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
                child: AppDropdown<String>(
                  label: 'From',
                  value: _from,
                  items: {for (final h in _hourOptions) h: h},
                  onChanged: (value) => setState(() => _from = value),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdown<String>(
                  label: 'To',
                  value: _to,
                  items: {for (final h in _hourOptions) h: h},
                  onChanged: (value) => setState(() => _to = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            problem ?? 'Saves as ${previewTimeWindowLabel(sorted, _from, _to)}',
            style: type.secondary.copyWith(
              color: problem == null ? colors.ink : colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Save window',
            expand: true,
            loading: _saving,
            onPressed: problem != null || _saving ? null : () => _save(sorted),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Cancel',
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Future<void> _save(List<int> weekdays) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(savedPreferencesApiProvider)
          .addTimeWindow(weekdays: weekdays, startTime: _from, endTime: _to);
      ref.invalidate(savedPreferencesProvider);
      AppHaptics.commit();
      if (!mounted) return;
      await Navigator.of(context).maybePop();
      messenger.showSnackBar(SnackBar(content: Text('Saved ${saved.label}')));
    } on ApiException catch (e) {
      AppHaptics.refused();
      if (mounted) setState(() => _error = e.message);
    } on ApiNetworkException {
      if (mounted) {
        setState(
          () => _error =
              'No connection — nothing was saved. Your choice is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
