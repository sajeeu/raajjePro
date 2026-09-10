import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/location/island_search_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/inputs/app_text_field.dart';
import 'package:raajjepro/shared/motion/pressable.dart';
import 'package:raajjepro/shared/states/empty_state.dart';
import 'package:raajjepro/shared/states/skeleton_loader.dart';

/// How a row shows that it is chosen.
enum IslandRowIndicator {
  /// A 26 dp circle that fills when selected — a set the customer is building
  /// up (`Create Service.dc.html` step 2).
  checkbox,

  /// A tick beside the one current choice (`Home.dc.html`'s island sheet).
  check,
}

/// The island control (§Phase 7, §0.0 item 12): a search field over the whole
/// register, and the ranked results under it.
///
/// **Search is the control, not a filter over a browsable list.** 192 entries
/// is not scrollable, so this leads with the field. A native picker or a
/// `DropdownButton` is never an acceptable island control anywhere in this
/// app, including Saved Preferences and the emergency request form.
///
/// **It never auto-selects.** A search that matches exactly one island renders
/// that island as one unselected row. Choosing is the customer's act — a
/// control that resolved it for them cannot be corrected when it picks the
/// wrong `Meedhoo`, and there are three.
///
/// **No total is printed.** The register counts 192 today against the 187 the
/// prototypes quoted; a denominator that goes stale silently is worth less to
/// a customer than the search itself, so nothing here renders a count of
/// anything.
///
/// The server ranks (prefix matches first), folds case, accents and the
/// Dhivehi apostrophe, matches the atoll code, and returns every match. This
/// widget re-implements none of that: it sends what was typed and draws what
/// came back.
class IslandSearchList extends ConsumerStatefulWidget {
  const IslandSearchList({
    required this.selectedIds,
    required this.onSelected,
    super.key,
    this.indicator = IslandRowIndicator.checkbox,
    this.autofocus = false,
    this.maxHeight,
  });

  /// The islands currently chosen, by id — never by name (§0.0 item 12).
  final Set<String> selectedIds;

  /// Called with the island the customer touched. What that means — add,
  /// remove, replace — is the caller's, not this widget's.
  final ValueChanged<Island> onSelected;

  final IslandRowIndicator indicator;
  final bool autofocus;

  /// Caps the result area and lets it scroll inside that cap — what a bottom
  /// sheet needs, so the sheet does not grow to cover the screen behind it.
  ///
  /// **Null means the opposite, and is the default**: the list grows to its
  /// full height and the *parent* scrolls it. That is what a form step wants
  /// (§Phase 9's wizard step 2 embeds this in a scrolling page), and it is not
  /// merely a preference — a scrollable list nested inside a scrolling page
  /// swallows the drag that was meant for the page, so the page stops halfway
  /// down and the customer cannot reach the button below it. The component
  /// gallery caught exactly that.
  final double? maxHeight;

  @override
  ConsumerState<IslandSearchList> createState() => _IslandSearchListState();
}

class _IslandSearchListState extends ConsumerState<IslandSearchList> {
  /// Long enough that spelling out "Kulhudhuffushi" is not fourteen requests,
  /// short enough that the list feels like it is following the typing.
  static const _debounce = Duration(milliseconds: 220);

  final _controller = TextEditingController();
  Timer? _timer;

  /// What is actually being searched for. Lags the field by [_debounce].
  String _query = '';

  /// The last results that arrived, kept on screen while the next query loads
  /// so the list does not flash back to a skeleton on every keystroke.
  List<Island>? _lastResults;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(islandSearchProvider(_query));
    final cached = results.value;
    if (cached != null) _lastResults = cached;

    // Capped: the list scrolls inside its own box. Uncapped: it grows and the
    // parent scrolls it. See `maxHeight` for why the second is the default.
    final bounded = widget.maxHeight != null;

    final list = switch (results) {
      AsyncError(:final error) when _lastResults == null => _Error(
        offline: error is ApiNetworkException,
        bounded: bounded,
        onRetry: () => ref.invalidate(islandSearchProvider(_query)),
      ),
      AsyncLoading() when _lastResults == null => _Skeleton(bounded: bounded),
      _ => _Results(
        islands: _lastResults ?? const [],
        query: _query,
        selectedIds: widget.selectedIds,
        indicator: widget.indicator,
        bounded: bounded,
        onSelected: widget.onSelected,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          // A visible label rather than the prototypes' placeholder-only
          // field: a placeholder disappears the moment a customer types, and
          // this control is reused inside a sheet, a wizard step and a form
          // where "what is this box for" is not always obvious from above it.
          label: 'Search islands',
          hint: 'Island or atoll code',
          controller: _controller,
          autofocus: widget.autofocus,
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          onChanged: _onChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        if (bounded)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight!),
            child: list,
          )
        else
          list,
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.islands,
    required this.query,
    required this.selectedIds,
    required this.indicator,
    required this.bounded,
    required this.onSelected,
  });

  final List<Island> islands;
  final String query;
  final Set<String> selectedIds;
  final IslandRowIndicator indicator;
  final bool bounded;
  final ValueChanged<Island> onSelected;

  @override
  Widget build(BuildContext context) {
    if (islands.isEmpty) {
      return _Centred(
        bounded: bounded,
        child: EmptyState(
          icon: Icons.location_off_outlined,
          title: query.isEmpty
              ? 'No islands to show'
              : 'No island matches “$query”',
          // Names what to do next, as an empty state must. The atoll code is
          // the genuinely useful hint here: it is how a Maldivian writes an
          // address, and it is the second thing this search matches on.
          body: query.isEmpty
              ? 'The island list could not be loaded. Try again in a moment.'
              : 'Check the spelling, or search by atoll code — “HDh” lists '
                    'that atoll.',
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: bounded ? null : const NeverScrollableScrollPhysics(),
      itemCount: islands.length,
      itemBuilder: (context, index) {
        final island = islands[index];
        return _IslandRow(
          island: island,
          selected: selectedIds.contains(island.id),
          indicator: indicator,
          last: index == islands.length - 1,
          onTap: () => onSelected(island),
        );
      },
    );
  }
}

class _IslandRow extends StatelessWidget {
  const _IslandRow({
    required this.island,
    required this.selected,
    required this.indicator,
    required this.last,
    required this.onTap,
  });

  final Island island;
  final bool selected;
  final IslandRowIndicator indicator;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Pressable(
      onTap: onTap,
      selected: selected,
      // Spoken as the qualified name plus its atoll, so a screen-reader user
      // hears which Meedhoo this is without having to read the second line.
      semanticLabel: '${island.displayName}, ${island.atollName}',
      focusRadius: AppRadius.md,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed ? colors.background : Colors.transparent,
          border: last
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.divider,
                    width: AppSizes.dividerStroke,
                  ),
                ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(island.displayName, style: type.cardTitle),
                    const SizedBox(height: AppSpacing.xxs),
                    // The atoll travels with the island everywhere. A row that
                    // showed only the name would leave three Meedhoos looking
                    // like a rendering bug.
                    Text(
                      island.atollName,
                      style: type.secondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _Indicator(kind: indicator, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.kind, required this.selected});

  final IslandRowIndicator kind;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;

    if (kind == IslandRowIndicator.check) {
      return SizedBox.square(
        dimension: 22,
        child: selected
            ? Icon(Icons.check_rounded, size: 20, color: colors.primary)
            : const SizedBox.shrink(),
      );
    }

    return AnimatedContainer(
      duration: motion.fast,
      curve: AppMotion.easeOut,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? colors.primary : colors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.primary : colors.border,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: colors.onPrimary)
          : null,
    );
  }
}

/// Built to the shape of `_IslandRow` rather than reusing the generic
/// card-shaped `SkeletonLoader.rows` — a skeleton that does not match the row
/// it stands in for is what makes a list jump when the data lands.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.bounded});

  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SkeletonLoader(
      label: 'Loading islands',
      // A ListView rather than a Column: where the caller caps the result
      // area, a Column of five rows inside a shorter cap overflows rather
      // than clipping. `shrinkWrap` keeps it usable in an unbounded parent.
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: bounded ? null : const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 5; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 4
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: colors.divider,
                          width: AppSizes.dividerStroke,
                        ),
                      ),
              ),
              child: const Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox.line(width: 132, height: 15),
                          SizedBox(height: AppSpacing.xs),
                          SkeletonBox.line(width: 76, height: 11),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpacing.md),
                    SkeletonBox.circle(dimension: 26),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({
    required this.offline,
    required this.bounded,
    required this.onRetry,
  });

  final bool offline;
  final bool bounded;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Centred(
      bounded: bounded,
      child: EmptyState.error(
        title: offline ? 'You’re offline' : 'Couldn’t load islands',
        body: offline
            ? 'Check your connection and try again.'
            : 'The island list didn’t load. Try again in a moment.',
        onRetry: onRetry,
      ),
    );
  }
}

/// Centres a state card. Inside a capped area it scrolls, so a tall card at
/// 200% text is still reachable; where the parent scrolls it must not add a
/// second scroller — a nested one swallows the parent's drag.
class _Centred extends StatelessWidget {
  const _Centred({required this.bounded, required this.child});

  final bool bounded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final centred = Center(child: child);
    return bounded ? SingleChildScrollView(child: centred) : centred;
  }
}
