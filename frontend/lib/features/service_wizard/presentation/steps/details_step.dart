import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/core/theme/category_icons.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 1 — Details. Three of the six required fields live here.
class DetailsStep extends ConsumerStatefulWidget {
  const DetailsStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  @override
  ConsumerState<DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<DetailsStep> {
  late final TextEditingController _name = TextEditingController(
    text: widget.view.listing.name ?? '',
  );
  late final TextEditingController _short = TextEditingController(
    text: widget.view.listing.shortDescription ?? '',
  );
  late final TextEditingController _long = TextEditingController(
    text: widget.view.listing.longDescription ?? '',
  );
  final TextEditingController _tag = TextEditingController();

  /// Why the last Add did nothing. Inline under the field, never a toast
  /// (frontend/CLAUDE.md).
  String? _tagNote;

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    _long.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tag.text.trim();
    if (raw.isEmpty) return;
    final tags = widget.view.listing.tags;
    setState(() {
      if (tags.contains(raw)) {
        _tagNote = 'Already added.';
      } else if (tags.length >= maxListingTags) {
        _tagNote =
            'That is all $maxListingTags tags — remove one to add another.';
      } else {
        _tagNote = null;
        widget.controller.addCustomTag(raw);
        _tag.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final view = widget.view;
    final listing = view.listing;
    final category = view.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Service details',
          body:
              'A clear name and description help customers find and choose '
              'you.',
        ),
        const SizedBox(height: AppSpacing.xl),
        const WizardNote(
          icon: Icons.check_circle_outline_rounded,
          tone: NoteTone.reassuring,
          message:
              'Saved as a draft as you go — nothing here is required until '
              'you publish.',
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          key: const Key('wizard-name'),
          label: 'Service name',
          requirement: FieldRequirement.mandatory,
          controller: _name,
          maxLength: 80,
          hint: 'e.g. Wiring & Fault Repair',
          helper: _nameHelper(category),
          textCapitalization: TextCapitalization.sentences,
          onChanged: widget.controller.setName,
        ),
        const SizedBox(height: AppSpacing.xl),
        const ControlLabel(
          label: 'Category',
          requirement: FieldRequirement.mandatory,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CategoryGrid(
          categories: view.categories,
          selectedId: listing.categoryId,
          onSelected: widget.controller.chooseCategory,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          key: const Key('wizard-short-description'),
          label: 'Short description',
          requirement: FieldRequirement.mandatory,
          controller: _short,
          maxLength: 120,
          maxLines: 2,
          hint: 'One sentence about your service…',
          helper: 'Shown in search results. Be concise and specific.',
          textCapitalization: TextCapitalization.sentences,
          onChanged: widget.controller.setShortDescription,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          label: 'Detailed description',
          requirement: FieldRequirement.optional,
          controller: _long,
          maxLength: 800,
          maxLines: 6,
          hint:
              "What's included, your process, why customers should choose "
              'you…',
          textCapitalization: TextCapitalization.sentences,
          onChanged: widget.controller.setLongDescription,
        ),
        const SizedBox(height: AppSpacing.xl),
        WizardSection(
          title: 'Tags',
          requirement: FieldRequirement.optional,
          helper:
              'Relevant tags help customers find you in search. Up to '
              '$maxListingTags.',
          children: [
            if (category == null)
              const _ChooseCategoryFirst()
            else ...[
              Text(
                'Suggested for ${category.name}'.toUpperCase(),
                style: type.overline.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final tag in category.suggestedTags)
                    AppChip.filter(
                      label: tag,
                      selected: listing.tags.contains(tag),
                      onTap: () => widget.controller.toggleTag(tag),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      key: const Key('wizard-custom-tag'),
                      label: 'Add your own tag',
                      controller: _tag,
                      hint: 'Anything not covered? Add your own…',
                      errorText: _tagNote,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm2),
                  Padding(
                    // Clears the field's own label row, so the button lines up
                    // with the input rather than with the label.
                    padding: const EdgeInsetsDirectional.only(
                      top: AppSpacing.xxl + AppSpacing.xxs,
                    ),
                    child: AppButton.primary(
                      label: 'Add',
                      size: AppButtonSize.compact,
                      onPressed: _addTag,
                    ),
                  ),
                ],
              ),
              if (_customTags(view).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final tag in _customTags(view))
                      AppChip.input(
                        label: tag,
                        onRemove: () => widget.controller.toggleTag(tag),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }

  /// Anything the provider typed themselves — everything not in this
  /// category's suggestions.
  static List<String> _customTags(WizardView view) {
    final suggested = view.category?.suggestedTags ?? const <String>[];
    return [
      for (final tag in view.listing.tags)
        if (!suggested.contains(tag)) tag,
    ];
  }

  /// 🔧 **Round 25/26 guidance for the activity categories.** Photography and
  /// Boat Charter sell distinct offerings rather than one repeatable job, and
  /// a provider who lists "Photography" once cannot price a wedding and a
  /// product shoot on the same listing.
  ///
  /// Keyed on the seeded `iconIdentifier`, not on the display name: it is a
  /// stable token this app already resolves for icons and accents, and it
  /// survives a category being renamed the way "Computer" became "Appliance
  /// Repair". **It is still an enumeration of two categories in Flutter**,
  /// which the plan names by name and seeds no flag for — the right home is a
  /// `Category.listingGuidance` column whenever one is added. Guidance copy
  /// only: nothing is enforced and no package entity exists (tiers stay
  /// post-v1, Round 16).
  static const _offeringGuidanceIcons = {'camera', 'boat'};

  static String _nameHelper(ServiceCategory? category) =>
      _offeringGuidanceIcons.contains(category?.iconIdentifier)
      ? "Name the specific service — 'Fishing Trip', 'Wedding "
            "Photography'. Customers book the offering, not the category."
      : 'What customers see first in results.';
}

/// The twelve, three across. Both the glyph and the colour come from tokens
/// the seed wrote, each with a neutral fallback — a thirteenth category added
/// through the API renders here with no rebuild.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ServiceCategory> categories;
  final String? selectedId;
  final ValueChanged<ServiceCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.sm2,
        crossAxisSpacing: AppSpacing.sm2,
        // Tall enough for a two-line name at a larger text size — "Appliance
        // Repair" is the one that decides this.
        mainAxisExtent: 96,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryChoice(
          category: category,
          selected: category.id == selectedId,
          onTap: () => onSelected(category),
        );
      },
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ServiceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = CategoryAccents.resolve(category.colorToken);

    return Pressable(
      semanticLabel: category.name,
      toggled: selected,
      onTap: onTap,
      minSize: 0,
      focusRadius: AppRadius.button,
      builder: (context, state) => SizedBox.expand(
        child: AnimatedContainer(
          duration: context.motion.fast,
          decoration: BoxDecoration(
            color: selected ? colors.accentTint : colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: selected ? colors.primary : colors.borderCard,
              width: AppSizes.inputStroke,
            ),
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.n13,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.tint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CategoryIcons.resolve(category.iconIdentifier),
                  size: 19,
                  color: accent.icon,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tags are category-scoped, so with no category there is nothing to suggest.
/// It says what to do, rather than rendering an empty row of chips.
class _ChooseCategoryFirst extends StatelessWidget {
  const _ChooseCategoryFirst();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: colors.neutralBorder,
          width: AppSizes.inputStroke,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(
              Icons.sell_outlined,
              size: AppSizes.iconLg,
              color: colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.n11),
            Expanded(
              child: Text(
                "Choose a category above first — we'll suggest tags customers "
                'actually search for.',
                style: context.type.secondary.copyWith(
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
