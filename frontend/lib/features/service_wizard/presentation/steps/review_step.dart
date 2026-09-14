import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/data/service_listing.dart';
import 'package:raajjepro/features/service_wizard/presentation/steps/availability_step.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 7 — Review & publish.
///
/// **The missing-field list is per field, with its own Fix link.** §Phase 8
/// returns a row per required field carrying the wizard step it belongs to,
/// and this renders one tappable row each rather than a single "form
/// invalid": publishing must not be a five-round-trip guessing game.
class ReviewStep extends StatelessWidget {
  const ReviewStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  static const _dash = '—';

  @override
  Widget build(BuildContext context) {
    final missing = view.missing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Review & publish',
          body: 'Check everything looks right. Tap any section to edit it.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (missing.isEmpty)
          _ReadyCard(count: view.listing.requiredFieldCount)
        else
          _MissingCard(
            missing: missing,
            emphasised: view.publishAttempted,
            onFix: controller.goTo,
          ),
        if (view.formError != null) ...[
          const SizedBox(height: AppSpacing.md),
          NoticeBanner(message: view.formError!),
        ],
        const SizedBox(height: AppSpacing.lg),
        for (final section in _sections(view)) ...[
          _ReviewCard(
            section: section,
            onEdit: () => controller.goTo(section.step),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  static List<_Section> _sections(WizardView view) {
    final listing = view.listing;
    final islands = listing.serviceAreas.isEmpty
        ? 'None selected'
        : [for (final island in listing.serviceAreas) island.displayName]
              .join(', ');
    final days = listing.workingDays.isEmpty
        ? 'None set'
        : listing.workingDays.length == 7
        ? 'Every day'
        : [
            for (final (day, label) in isoWeekdays)
              if (listing.workingDays.contains(day)) label,
          ].join(', ');
    final hours =
        listing.workingHoursFrom == null || listing.workingHoursTo == null
        ? _dash
        : '${listing.workingHoursFrom} – ${listing.workingHoursTo}';
    final declared = listing.selfDeclared;

    return [
      _Section(
        title: 'Details',
        step: WizardStep.details,
        rows: [
          _Row('Name', _or(listing.name), missing: _blank(listing.name)),
          _Row(
            'Category',
            view.category?.name ?? _dash,
            missing: listing.categoryId == null,
          ),
          _Row(
            'Description',
            _or(listing.shortDescription),
            missing: _blank(listing.shortDescription),
          ),
          _Row('Tags', listing.tags.isEmpty ? _dash : listing.tags.join(' · ')),
        ],
      ),
      _Section(
        title: 'Location',
        step: WizardStep.location,
        rows: [_Row('Islands', islands, missing: listing.serviceAreas.isEmpty)],
      ),
      _Section(
        title: 'Pricing',
        step: WizardStep.pricing,
        rows: [
          _Row('How it works', listing.pricingModel?.label ?? _dash),
          _Row(
            'Customers see',
            customerPricePreview(listing),
            missing: customerPricePreview(listing).contains(_dash),
          ),
        ],
      ),
      _Section(
        title: 'Media',
        step: WizardStep.media,
        rows: [
          _Row(
            'Cover image',
            listing.hasStoredCover
                ? 'Uploaded'
                : listing.coverMedia == null
                ? 'Missing'
                : 'Upload unfinished',
            missing: !listing.hasStoredCover,
          ),
          _Row(
            'Gallery',
            listing.gallery.isEmpty
                ? 'None'
                : '${listing.gallery.length} '
                      'photo${listing.gallery.length == 1 ? '' : 's'}',
          ),
        ],
      ),
      _Section(
        title: 'Availability',
        step: WizardStep.availability,
        rows: [
          _Row(
            'Booked via',
            listing.bookingMode == null
                ? _dash
                : listing.bookingMode!.name == 'slot'
                ? 'Fixed time slots'
                : 'Request a time',
          ),
          _Row('Days', days),
          _Row('Hours', hours),
          _Row('Emergency', _emergency(view)),
        ],
      ),
      _Section(
        title: 'Extras',
        step: WizardStep.extras,
        rows: [
          // Attributed, never asserted (§1i). The customer will read exactly
          // this shape, and it never carries a tick.
          _Row(
            'Warranty',
            declared.warrantyOffered && !_blank(declared.warrantyTermsText)
                ? 'Provider states: ${declared.warrantyTermsText}'
                : _dash,
          ),
          _Row(
            'Insurance',
            declared.insuranceDeclared && !_blank(declared.insuranceDetailText)
                ? 'Provider states: ${declared.insuranceDetailText}'
                : _dash,
          ),
          if (listing.callbackAvailable)
            _Row(
              'Callback',
              listing.callbackGuaranteeOffered
                  ? 'On — 7-day, enforced by RaajjePro'
                  : 'Off',
            ),
          _Row('FAQs', listing.faqs.isEmpty ? _dash : '${listing.faqs.length}'),
        ],
      ),
    ];
  }

  static String _emergency(WizardView view) {
    if (!view.listing.emergency.allowed) return 'Not available';
    if (!view.listing.isEmergency) return 'Off';
    final window = view.category?.emergencyAcceptWindowMinutes;
    return window == null ? 'On' : 'On — $window min response expected';
  }

  static bool _blank(String? value) => value == null || value.trim().isEmpty;

  static String _or(String? value) => _blank(value) ? _dash : value!;
}

class _Section {
  const _Section({required this.title, required this.step, required this.rows});
  final String title;
  final WizardStep step;
  final List<_Row> rows;
}

class _Row {
  const _Row(this.label, this.value, {this.missing = false});
  final String label;
  final String value;
  final bool missing;
}

/// Publishing is refused until this list is empty, and each row goes straight
/// to the step that owns it.
class _MissingCard extends StatelessWidget {
  const _MissingCard({
    required this.missing,
    required this.emphasised,
    required this.onFix,
  });

  final List<MissingField> missing;

  /// True once publish has actually been refused — the border tightens, but
  /// the list itself is the same list it was before the attempt.
  final bool emphasised;
  final ValueChanged<WizardStep> onFix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final count = missing.length;

    return Container(
      key: const Key('wizard-missing-fields'),
      decoration: BoxDecoration(
        color: colors.warningTint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: emphasised ? colors.warning : colors.warningBorder,
          width: AppSizes.inputStroke,
        ),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg + 1,
        vertical: AppSpacing.lg - 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: AppSizes.iconMd,
                color: colors.warningText,
              ),
              const SizedBox(width: AppSpacing.sm + 1),
              Expanded(
                child: Text(
                  '$count required field${count == 1 ? '' : 's'} missing',
                  style: type.bodyStrong.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.warningText,
                  ),
                ),
              ),
            ],
          ),
          for (final field in missing)
            Pressable(
              semanticLabel: '${field.message}, fix on ${field.step.label}',
              onTap: () => onFix(field.step),
              focusRadius: AppRadius.xs,
              builder: (context, state) => Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.warningBorder)),
                ),
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: AppSpacing.sm2,
                  horizontal: 2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm2),
                    Expanded(
                      child: Text(
                        field.message,
                        style: type.secondary.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Text(
                      field.step.label,
                      style: type.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.warningText,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: AppSizes.iconMd,
                      color: colors.warningText,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const Key('wizard-ready'),
      decoration: BoxDecoration(
        color: colors.successTint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: colors.successBorder),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg + 1,
        vertical: AppSpacing.lg - 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: AppSizes.iconLg,
            color: colors.successText,
          ),
          const SizedBox(width: AppSpacing.sm2),
          Expanded(
            child: Text(
              'Ready to publish — all $count required fields are complete.',
              style: context.type.secondary.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: colors.successText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.section, required this.onEdit});

  final _Section section;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      radius: AppRadius.tile,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg + 1,
        AppSpacing.xs,
        AppSpacing.lg + 1,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: AppSpacing.md - 1,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: type.cardTitle.copyWith(fontSize: 14.5),
                  ),
                ),
                AppButton.text(
                  key: Key('review-edit-${section.step.wire}'),
                  label: 'Edit',
                  size: AppButtonSize.compact,
                  icon: Icons.edit_outlined,
                  semanticLabel: 'Edit ${section.title}',
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
          for (final row in section.rows)
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.divider)),
              ),
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: AppSpacing.sm2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.label,
                      style: type.secondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md2),
                  Expanded(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.end,
                      style: type.secondary.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: row.missing ? colors.warningText : colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
