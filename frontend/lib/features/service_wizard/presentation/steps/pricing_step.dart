import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/data/service_listing.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 3 — Pricing.
///
/// 🔧 **Round 16 corrections, both applied here.** The delivered mockup drew
/// the Price field twice and offered Service Packages; the field appears once
/// and packages are gone (tiers stay post-v1). `priceUnit` is the pair's other
/// half, added by §Phase 8.
///
/// **Money is integer laari throughout** (invariant 7). The field collects
/// whole rufiyaa and the controller multiplies by 100; no double appears
/// anywhere on the path to the API.
class PricingStep extends StatefulWidget {
  const PricingStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  @override
  State<PricingStep> createState() => _PricingStepState();
}

class _PricingStepState extends State<PricingStep> {
  late final TextEditingController _price = TextEditingController(
    text: mvrFromLaari(widget.view.listing.priceLaari),
  );
  late final TextEditingController _min = TextEditingController(
    text: mvrFromLaari(widget.view.listing.priceMinLaari),
  );
  late final TextEditingController _max = TextEditingController(
    text: mvrFromLaari(widget.view.listing.priceMaxLaari),
  );

  @override
  void dispose() {
    _price.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final listing = widget.view.listing;
    final model = listing.pricingModel;
    final errors = widget.view.fieldErrors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Pricing',
          body:
              'Clear, transparent prices build trust and get more bookings. '
              'Always in MVR.',
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        const ControlLabel(
          label: 'How the price works',
          requirement: FieldRequirement.mandatory,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          container: true,
          label: 'Pricing model',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in PricingModel.values) ...[
                ChoiceCard(
                  key: Key('pricing-${option.wire}'),
                  title: option.label,
                  description: option.description,
                  selected: model == option,
                  onTap: () => widget.controller.choosePricingModel(option),
                ),
                if (option != PricingModel.values.last)
                  const SizedBox(height: AppSpacing.sm + 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        WizardNote(
          tone: (model?.forcesRequestMode ?? false)
              ? NoteTone.cautionary
              : NoteTone.plain,
          message:
              "Price range and Price on request can't be booked as a fixed "
              'time slot — customers request a time instead, since no one can '
              'book a set time at an unknown price.',
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        if (model == PricingModel.quote)
          const WizardSection(
            title: 'No price shown',
            helper:
                'Customers see "Price on request" and send you the job '
                'details. You reply with a quote in chat.',
            children: [],
          )
        else
          WizardSection(
            children: [
              if (model == PricingModel.range)
                _PriceRangeFields(
                  from: _min,
                  to: _max,
                  errorText: errors['priceMinLaari'] ?? errors['priceMaxLaari'],
                  onFrom: widget.controller.setPriceMin,
                  onTo: widget.controller.setPriceMax,
                )
              else
                _MoneyField(
                  fieldKey: const Key('wizard-price'),
                  label: 'Price',
                  requirement: FieldRequirement.mandatory,
                  controller: _price,
                  errorText: errors['priceLaari'],
                  onChanged: widget.controller.setPrice,
                ),
              const SizedBox(height: AppSpacing.lg),
              const ControlLabel(label: 'Shown to customers as'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final unit in PriceUnit.values)
                    AppChip.filter(
                      label: unit.label,
                      selected: listing.priceUnit == unit,
                      onTap: () => widget.controller.choosePriceUnit(unit),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Separate from how it's calculated — an hourly rate can still "
                'read "per visit".',
                style: type.helper,
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg + 2),
        WizardNote(
          icon: Icons.visibility_outlined,
          tone: NoteTone.informative,
          message:
              'On your card, customers see: '
              '${customerPricePreview(listing)}',
        ),
      ],
    );
  }
}

/// The "MVR" chip, then digits. Numeric keyboard, digits only — a price with
/// a stray letter in it is a typo the field can simply refuse.
class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.fieldKey,
    this.requirement,
    this.errorText,
  });

  final Key? fieldKey;
  final String label;
  final FieldRequirement? requirement;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTextField(
      key: fieldKey,
      label: label,
      requirement: requirement,
      controller: controller,
      errorText: errorText,
      hint: '0',
      keyboardType: TextInputType.number,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        // Six digits of rufiyaa. A full-day boat charter is a real five-figure
        // price; seven would be a typo.
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: onChanged,
      prefix: Container(
        height: 32,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md - 1,
        ),
        decoration: BoxDecoration(
          color: colors.neutralTint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: Text(
          'MVR',
          style: context.type.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.neutralText,
          ),
        ),
      ),
    );
  }
}

class _PriceRangeFields extends StatelessWidget {
  const _PriceRangeFields({
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
    this.errorText,
  });

  final TextEditingController from;
  final TextEditingController to;
  final ValueChanged<String> onFrom;
  final ValueChanged<String> onTo;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ControlLabel(
          label: 'Price range',
          requirement: FieldRequirement.mandatory,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MoneyField(
                fieldKey: const Key('wizard-price-min'),
                label: 'From',
                controller: from,
                onChanged: onFrom,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _MoneyField(
                fieldKey: const Key('wizard-price-max'),
                label: 'To',
                controller: to,
                onChanged: onTo,
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: context.type.helper.copyWith(color: context.colors.error),
          ),
        ],
      ],
    );
  }
}
