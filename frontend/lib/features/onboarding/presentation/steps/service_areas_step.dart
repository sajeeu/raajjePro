import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// §Phase 6a step 3 — default service areas (`Become a Provider.dc.html`,
/// "3 · Service area"). New in Round 21.
///
/// > A third step collects the islands the provider generally works in,
/// > stored **account-level** on `ProviderProfile`. These **pre-fill** Phase
/// > 9's wizard step 2 for every new listing and remain editable per
/// > listing — a mover may cover five islands but photograph on one. This is
/// > a default, not a constraint; per-listing service areas (§Phase 7,
/// > §Phase 8) remain authoritative for discovery.
///
/// The copy says exactly that, because the distinction is the one a provider
/// will otherwise get wrong: setting five islands here is not a promise to
/// serve five islands on every listing.
///
/// **The control is §Phase 7's [IslandMultiSelect], imported and not
/// rebuilt.** Search is the control — 192 islands is not a browsable list —
/// it never auto-selects a lone match, and the ranking, the accent and
/// apostrophe folding and the `Dh. Meedhoo` qualifying rule are all the
/// server's. `maxListHeight` is deliberately left null so the list grows and
/// this page scrolls it; a nested scroller would swallow the drag meant for
/// the page and put the CTA out of reach.
///
/// 🔧 **The artboard's atoll filter chips are not implemented**, and the
/// reason is that they would be a second way to narrow the same set. §Phase 7
/// built the multi-select as the reusable control and the server already
/// matches the atoll code inside the search box (`gdh` lists that atoll,
/// `dh mee` finds `Dh. Meedhoo`), so the chips duplicate a capability the
/// field has. Adding them would also mean changing shared Phase 7 code, which
/// invariant 5 says to flag rather than do as a side effect —
/// `docs/decisions/20-phase-6a-become-a-provider.md`.
class ServiceAreasStep extends StatelessWidget {
  const ServiceAreasStep({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final List<Island> selected;

  /// Each toggle is a real write (§Phase 7's POST/DELETE), which is what makes
  /// resuming at this step work with nothing cached on the device.
  final ValueChanged<Island> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xxl + AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Where do you usually work?', style: type.screenTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These become your default service areas — they pre-fill every '
            'new service you create, and you can narrow them down for any '
            'single service.',
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md + 2,
            ),
            decoration: BoxDecoration(
              color: colors.accentTint,
              borderRadius: AppRadius.circular(AppRadius.card),
              border: Border.all(color: colors.accentBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: AppSizes.iconLg + 1,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Customers will discover your services based on the '
                    'islands you serve.',
                    style: type.secondary.copyWith(color: colors.accentText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          IslandMultiSelect(
            selected: selected,
            onChanged: (next) {
              final touched = _changed(selected, next);
              if (touched != null) onToggle(touched);
            },
            // §Phase 7 gave this message a caller-supplied default for exactly
            // this reason: what an empty selection means here is an
            // account-level default, not one listing's coverage.
            emptySelectionMessage:
                'Add at least one island to finish setting up. You can change '
                'this later, and narrow it per service.',
          ),
        ],
      ),
    );
  }

  /// [IslandMultiSelect] hands back the whole resulting list; the write takes
  /// one island. Exactly one differs on any single toggle, so this recovers
  /// which — the diff is between two lists that came from the same widget one
  /// tap apart.
  ///
  /// Null where nothing differs. That cannot happen through the widget, and
  /// the point of returning it rather than asserting is that a no-op is the
  /// right answer if it ever does: a `firstWhere` with no match throws, and a
  /// crash is a worse failure than a tap that did nothing.
  static Island? _changed(List<Island> before, List<Island> after) {
    final added = after.where((i) => !before.any((b) => b.id == i.id));
    if (added.isNotEmpty) return added.first;
    final removed = before.where((i) => !after.any((a) => a.id == i.id));
    return removed.isEmpty ? null : removed.first;
  }
}
