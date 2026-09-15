import 'package:flutter/material.dart';

import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 6 — Extra information. Every field here is optional and none of it
/// gates publish.
///
/// 🔧 **Round 18 (§1i): Warranty & Insurance stays, and the copy attributes
/// rather than asserts.** RaajjePro checks neither claim, so the section says
/// so and a customer will read them as "Provider states: …". They never carry
/// a check mark, a shield, a lock or the word *verified* — those belong to
/// `verificationTier`, which means something because a human checked it.
///
/// 🔧 **The duplicated FAQs accordion is gone.** The delivered mockup drew it
/// twice; it appears once.
///
/// **The callback guarantee is a different kind of promise and gets a
/// different treatment** (§1h, Round 28): RaajjePro enforces it, a claim
/// creates a linked zero-cost booking, and it is fixed at 7 days. It renders
/// in its own green-outlined card so it can never be read as one of the
/// self-declared claims above it — and on a category whose `callbackEligible`
/// is false the card is **absent, not disabled**, because a promise to redo a
/// house move for free has no referent.
class ExtrasStep extends StatefulWidget {
  const ExtrasStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  @override
  State<ExtrasStep> createState() => _ExtrasStepState();
}

class _ExtrasStepState extends State<ExtrasStep> {
  late final TextEditingController _included = TextEditingController(
    text: widget.view.listing.whatsIncluded ?? '',
  );
  late final TextEditingController _notIncluded = TextEditingController(
    text: widget.view.listing.whatsNotIncluded ?? '',
  );
  late final TextEditingController _warranty = TextEditingController(
    text: widget.view.listing.selfDeclared.warrantyTermsText ?? '',
  );
  late final TextEditingController _insurance = TextEditingController(
    text: widget.view.listing.selfDeclared.insuranceDetailText ?? '',
  );
  final TextEditingController _question = TextEditingController();
  final TextEditingController _answer = TextEditingController();

  @override
  void dispose() {
    _included.dispose();
    _notIncluded.dispose();
    _warranty.dispose();
    _insurance.dispose();
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _addFaq() {
    if (!widget.controller.addFaq(_question.text, _answer.text)) return;
    _question.clear();
    _answer.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final listing = widget.view.listing;
    final declared = listing.selfDeclared;
    final faqReady =
        _question.text.trim().isNotEmpty && _answer.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Extra information',
          body:
              'Everything on this step is optional — none of it blocks '
              'publishing. It builds trust with customers who are comparing.',
        ),
        const SizedBox(height: AppSpacing.lg2),
        WizardSection(
          children: [
            AppTextField(
              label: "What's included",
              controller: _included,
              maxLines: 3,
              hint: 'e.g. Fault diagnosis, the repair itself, a safety check…',
              textCapitalization: TextCapitalization.sentences,
              onChanged: widget.controller.setWhatsIncluded,
            ),
            const SizedBox(height: AppSpacing.md2),
            AppTextField(
              label: "What's not included",
              controller: _notIncluded,
              maxLines: 3,
              hint: 'e.g. Materials and new fittings — billed separately…',
              textCapitalization: TextCapitalization.sentences,
              onChanged: widget.controller.setWhatsNotIncluded,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg2),
        WizardSection(
          title: 'FAQs',
          helper: 'Answer the questions you get asked in chat anyway.',
          children: [
            for (var index = 0; index < listing.faqs.length; index++) ...[
              _FaqRow(
                faq: listing.faqs[index],
                onRemove: () => widget.controller.removeFaq(index),
              ),
              const SizedBox(height: AppSpacing.sm2),
            ],
            AppTextField(
              key: const Key('wizard-faq-question'),
              label: 'Question',
              controller: _question,
              hint: 'Question, e.g. Do you supply materials?',
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('wizard-faq-answer'),
                    label: 'Answer',
                    controller: _answer,
                    hint: 'Your answer…',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _addFaq(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm2),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: AppSpacing.n28,
                  ),
                  child: AppButton.primary(
                    label: 'Add',
                    size: AppButtonSize.compact,
                    onPressed: faqReady ? _addFaq : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg2),
        WizardSection(
          title: 'Warranty & insurance',
          children: [
            AppToggle(
              key: const Key('wizard-warranty'),
              label: 'I offer a warranty',
              description: 'Your own terms, in your own words.',
              value: declared.warrantyOffered,
              onChanged: (_) => widget.controller.toggleWarranty(),
            ),
            if (declared.warrantyOffered) ...[
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('wizard-warranty-terms'),
                label: 'Warranty terms',
                controller: _warranty,
                maxLines: 3,
                maxLength: 500,
                hint: 'e.g. 90-day warranty on workmanship',
                textCapitalization: TextCapitalization.sentences,
                onChanged: widget.controller.setWarrantyText,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: AppSpacing.md),
            AppToggle(
              key: const Key('wizard-insurance'),
              label: 'I hold public liability insurance',
              description: 'Insurer and what it covers.',
              value: declared.insuranceDeclared,
              onChanged: (_) => widget.controller.toggleInsurance(),
            ),
            if (declared.insuranceDeclared) ...[
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('wizard-insurance-detail'),
                label: 'Insurance details',
                controller: _insurance,
                maxLines: 3,
                maxLength: 500,
                hint: 'e.g. Allied — public liability up to MVR 100,000',
                textCapitalization: TextCapitalization.sentences,
                onChanged: widget.controller.setInsuranceText,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const WizardNote(
              message:
                  "RaajjePro doesn't check warranty or insurance details. "
                  'Customers see them exactly as you write them, marked '
                  '"Provider states: …"',
            ),
          ],
        ),
        if (listing.callbackAvailable) ...[
          const SizedBox(height: AppSpacing.lg2),
          WizardSection(
            borderColor: colors.guaranteeBorder,
            children: [
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: _EnforcedByRaajjePro(),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppToggle(
                key: const Key('wizard-callback'),
                label: 'Callback guarantee',
                description:
                    'A free return visit within 7 days if the same problem '
                    'comes back. Unlike the warranty and insurance above, '
                    'this one RaajjePro holds you to — customers can report '
                    'an unhonoured callback.',
                value: listing.callbackGuaranteeOffered,
                onChanged: (_) => widget.controller.toggleCallbackGuarantee(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The badge that separates §1h's promise from §1i's claims. It says who
/// enforces it, which is the whole distinction.
class _EnforcedByRaajjePro extends StatelessWidget {
  const _EnforcedByRaajjePro();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.successTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.n9,
        vertical: 3,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 11,
            color: colors.guaranteeText,
          ),
          const SizedBox(width: 5),
          Text(
            'Enforced by RaajjePro',
            style: context.type.pillSmall.copyWith(color: colors.guaranteeText),
          ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.faq, required this.onRemove});

  final ListingFaq faq;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md2,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(faq.question, style: type.cardTitle),
                  const SizedBox(height: 3),
                  Text(
                    faq.answer,
                    style: type.secondary.copyWith(
                      height: 1.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm2),
            Pressable(
              semanticLabel: 'Remove the FAQ "${faq.question}"',
              onTap: onRemove,
              focusRadius: AppRadius.xs,
              builder: (context, state) => Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: state.pressed ? colors.border : colors.neutralTint,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close_rounded,
                  size: 11,
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
