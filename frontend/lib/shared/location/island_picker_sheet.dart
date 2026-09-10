import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/location/browsing_island_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/location/island_search_list.dart';
import 'package:raajjepro/shared/sheets/app_bottom_sheet.dart';

/// The header location bottom sheet (§Phase 7's third bullet, and its second
/// Done-when line: "the header bottom sheet lets a customer pick a browsing
/// island that persists for the session").
///
/// Single-select: tapping an island records it and closes. That is the one
/// place in this file where the choice is written — it is never inferred from
/// a single search match, never from a device location, and never defaulted to
/// Malé.
///
/// The choice lives in [browsingIslandProvider], in memory for the session. It
/// survives navigation and backgrounding and goes when the process does; see
/// that controller for why it is deliberately not stored.
class IslandPickerSheet extends ConsumerWidget {
  const IslandPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(browsingIslandProvider);

    return AppBottomSheet(
      title: 'Choose your island',
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
            child: Text(
              'We’ll show you providers who work where you are.',
              style: context.type.secondary.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          IslandSearchList(
            selectedIds: chosen == null ? const {} : {chosen.id},
            indicator: IslandRowIndicator.check,
            autofocus: true,
            // Leaves the sheet at roughly half the screen with the keyboard
            // up, rather than growing to cover the screen behind it.
            maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            onSelected: (island) {
              ref.read(browsingIslandProvider.notifier).choose(island);
              Navigator.of(context).maybePop(island);
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the picker. Returns the island chosen, or null if the customer
/// dismissed the sheet — a dismissal changes nothing.
Future<Island?> showIslandPicker(BuildContext context) {
  return showAppBottomSheet<Island>(
    context: context,
    barrierLabel: 'Close island picker',
    builder: (_) => const IslandPickerSheet(),
  );
}
