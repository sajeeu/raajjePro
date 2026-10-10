import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/categories/categories_controller.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/search/data/search_api.dart';
import 'package:raajjepro/features/search/presentation/search_copy.dart';
import 'package:raajjepro/shared/shared.dart';

/// Where the sheet opens. Each dropdown chip opens it at its own section, and
/// the filters button opens it at the top.
enum FilterSection { category, price, mode }

/// The **Filters** sheet. `Discovery.dc.html` draws the chips that open it
/// but not the sheet, so the owner approved this design on 2026-10-10: one
/// sheet holding Category (on a search), Price, How you book and
/// Maldivian-owned, applied together.
///
/// Price is two whole-rufiyaa fields rather than preset bands, because bands
/// would be numbers nobody decided. The Apply button counts what the
/// draft would show before the customer commits to it, read from the same
/// endpoint with a one-result page.
///
/// It edits a draft. Nothing changes on the results screen until Apply, and
/// dismissing the sheet discards the draft.
Future<SearchFilters?> showFiltersSheet(
  BuildContext context, {
  required SearchFilters current,
  required SearchFilters initial,
  required bool showCategory,
  required String? islandId,
  FilterSection? focus,
}) {
  return showAppBottomSheet<SearchFilters>(
    context: context,
    barrierLabel: 'Close filters',
    builder: (_) => FiltersSheet(
      current: current,
      initial: initial,
      showCategory: showCategory,
      islandId: islandId,
      focus: focus,
    ),
  );
}

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({
    required this.current,
    required this.initial,
    required this.showCategory,
    required this.islandId,
    this.focus,
    super.key,
  });

  final SearchFilters current;

  /// What "Reset" returns to: how the results screen opened.
  final SearchFilters initial;
  final bool showCategory;
  final String? islandId;
  final FilterSection? focus;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  // The draft is this sheet's own, local interaction: it lives exactly as
  // long as the sheet and is handed back on Apply (frontend/CLAUDE.md).
  late SearchFilters _draft = widget.current;
  late final _min = TextEditingController(
    text: widget.current.priceMinMvr?.toString() ?? '',
  );
  late final _max = TextEditingController(
    text: widget.current.priceMaxMvr?.toString() ?? '',
  );

  final _sectionKeys = {
    for (final section in FilterSection.values) section: GlobalKey(),
  };

  Timer? _debounce;
  int? _count;
  int _countRequest = 0;

  @override
  void initState() {
    super.initState();
    _recount();
    final focus = widget.focus;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _sectionKeys[focus]?.currentContext;
        if (target != null && target.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              duration: context.motion.base,
              curve: AppMotion.easeOut,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  bool get _priceInverted =>
      _draft.priceMinMvr != null &&
      _draft.priceMaxMvr != null &&
      _draft.priceMinMvr! > _draft.priceMaxMvr!;

  void _update(SearchFilters next) {
    setState(() => _draft = next);
    _recount();
  }

  void _onPriceChanged() {
    _update(
      _draft.copyWith(
        price: (int.tryParse(_min.text), int.tryParse(_max.text)),
      ),
    );
  }

  /// How many results the draft would show, for the button. Debounced so a
  /// customer typing "350" sends one request, not three. An answer that
  /// arrives after a newer request is dropped.
  void _recount() {
    _debounce?.cancel();
    setState(() => _count = null);
    if (_priceInverted) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final request = ++_countRequest;
      try {
        final page = await ref
            .read(searchApiProvider)
            .page(_draft, islandId: widget.islandId, limit: 1);
        if (mounted && request == _countRequest) {
          setState(() => _count = page.total);
        }
      } on Object {
        // The button falls back to "Show services". The count is a courtesy,
        // and Apply still works without it.
      }
    });
  }

  void _reset() {
    AppHaptics.selection();
    _min.clear();
    _max.clear();
    _update(
      SearchFilters(
        query: widget.initial.query,
        categoryId: widget.initial.categoryId,
        categoryName: widget.initial.categoryName,
        sort: _draft.sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final count = _count;

    return AppBottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Filters', style: type.sectionHeading),
                ),
              ),
              AppButton.text(label: 'Reset', onPressed: _reset),
            ],
          ),
          if (widget.showCategory) ...[
            const SizedBox(height: AppSpacing.md),
            _SectionLabel(
              'Category',
              key: _sectionKeys[FilterSection.category],
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategoryChoices(
              selectedId: _draft.categoryId,
              onChanged: (category) {
                AppHaptics.selection();
                _update(
                  _draft.copyWith(category: (category?.id, category?.name)),
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.lg2),
          _SectionLabel('Price (MVR)', key: _sectionKeys[FilterSection.price]),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Min',
                  controller: _min,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  hasError: _priceInverted,
                  onChanged: (_) => _onPriceChanged(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  label: 'Max',
                  controller: _max,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  hasError: _priceInverted,
                  errorText: _priceInverted
                      ? 'Max must be at least the min'
                      : null,
                  onChanged: (_) => _onPriceChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            priceNote,
            style: type.secondary.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg2),
          _SectionLabel('How you book', key: _sectionKeys[FilterSection.mode]),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final mode in <BookingMode?>[null, ...BookingMode.values])
                AppChip.filter(
                  label: mode == null ? 'Any' : bookingCta(mode),
                  selected: _draft.mode == mode,
                  onTap: () {
                    AppHaptics.selection();
                    _update(_draft.copyWith(mode: (mode,)));
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg2),
          AppToggle(
            label: maldivianOwnedTitle,
            description: maldivianOwnedNote,
            value: _draft.maldivianOwned,
            onChanged: (value) =>
                _update(_draft.copyWith(maldivianOwned: value)),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            label: count == null
                ? 'Show services'
                : 'Show ${serviceCount(count)}',
            onPressed: _priceInverted
                ? null
                : () {
                    AppHaptics.selection();
                    Navigator.of(context).pop(_draft);
                  },
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: context.type.overline.copyWith(
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// "Any" and the catalogue's categories, from the same endpoint Explore's
/// grid reads, so a category added through the API appears here too.
class _CategoryChoices extends ConsumerWidget {
  const _CategoryChoices({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<ServiceCategory?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesControllerProvider).value ?? const [];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppChip.filter(
          label: 'Any',
          selected: selectedId == null,
          onTap: () => onChanged(null),
        ),
        for (final category in categories)
          AppChip.filter(
            label: category.name,
            selected: selectedId == category.id,
            onTap: () => onChanged(category),
          ),
      ],
    );
  }
}
