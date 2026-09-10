import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/chips/app_chip.dart';
import 'package:raajjepro/shared/location/island_search_list.dart';

/// The searchable island multi-select (§Phase 7's third bullet).
///
/// **Built standalone, not screen-specific**, exactly as §Phase 7 asks:
/// §Phase 6a's onboarding collects a provider's default coverage with it and
/// §Phase 9's wizard step 2 embeds the same widget for a listing's own service
/// areas. It owns no network state of its own beyond the search — the selected
/// set comes in and changes go out, so the screen that owns the data owns the
/// saving.
///
/// The selected islands render as removable chips above the list, and the
/// list's rows carry a checkbox. Both routes to removal do the same thing.
///
/// Nothing here prints a count of anything (§0.0 item 12).
class IslandMultiSelect extends StatelessWidget {
  const IslandMultiSelect({
    required this.selected,
    required this.onChanged,
    super.key,
    this.emptySelectionMessage =
        'Customers browsing from islands you haven’t listed won’t see you.',
    this.autofocus = false,
    this.maxListHeight,
  });

  /// The chosen islands, in the order the caller wants them shown.
  final List<Island> selected;

  /// The resulting selection after a toggle. The caller decides what to
  /// persist and when — this widget never writes.
  final ValueChanged<List<Island>> onChanged;

  /// What an empty selection means *here*. Two callers say different things —
  /// §Phase 6a is setting an account-level default, §Phase 9 a single
  /// listing's areas ("won't see this service") — and a message that tried to
  /// cover both would be true of neither.
  final String emptySelectionMessage;

  final bool autofocus;

  /// Caps the result list, for a caller embedding this in a scrolling form.
  final double? maxListHeight;

  void _toggle(Island island) {
    final next = [...selected];
    final index = next.indexWhere((i) => i.id == island.id);
    if (index >= 0) {
      next.removeAt(index);
    } else {
      next.add(island);
    }
    onChanged(List.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected.isEmpty)
          _NoneSelected(message: emptySelectionMessage)
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final island in selected)
                AppChip.input(
                  // The qualified name, so two Meedhoos in a selection are
                  // told apart on the chip and not only in the list.
                  label: island.displayName,
                  icon: Icons.location_on_outlined,
                  onRemove: () => _toggle(island),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        IslandSearchList(
          selectedIds: {for (final island in selected) island.id},
          onSelected: _toggle,
          autofocus: autofocus,
          maxHeight: maxListHeight,
        ),
      ],
    );
  }
}

/// The empty-selection state. Dashed rather than solid so it reads as a slot
/// waiting to be filled, not as a card that failed to load.
class _NoneSelected extends StatelessWidget {
  const _NoneSelected({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: colors.border, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: AppSizes.iconLg + 2,
                color: colors.textSecondary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No islands selected yet',
                style: type.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                message,
                style: type.secondary.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
