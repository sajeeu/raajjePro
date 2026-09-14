import 'package:flutter/material.dart';

import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/hour_field.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// ISO weekday numbers, 1 = Monday, with the short labels step 5 renders.
const List<(int, String)> isoWeekdays = [
  (1, 'Mon'),
  (2, 'Tue'),
  (3, 'Wed'),
  (4, 'Thu'),
  (5, 'Fri'),
  (6, 'Sat'),
  (7, 'Sun'),
];

/// Step 5 — Availability.
///
/// 🔧 **Round 16 correction: "Accepting New Customers" is not here.** It is an
/// account-level setting (§Phase 5) that §Phase 8a's billing pause keys off,
/// so a per-listing copy would be actively wrong — and the sentence about what
/// it does to billing belongs to §Phase 10's dashboard and §Phase 10a's
/// billing screen, where it renders beside a live subscription (ledger P8A-4).
///
/// 🔧 **Round 17: every number here is read from the category being edited.**
/// The emergency response window is `emergencyAcceptWindowMinutes` and the
/// tier bar is `emergencyMinimumTier`; neither is written down in this file.
/// A Moving provider reads **30 minutes** like every other emergency category
/// (Round 22 — the 120 this once carried described how long a mover takes to
/// *arrive*, not how long they may take to *answer*), and a provider told the
/// wrong window distrusts everything else the app tells them.
///
/// **Eligibility itself is the server's answer, rendered verbatim.** §1c
/// composes it from four fields across three entities; nothing here compares a
/// tier to a bar.
class AvailabilityStep extends StatelessWidget {
  const AvailabilityStep({
    required this.view,
    required this.controller,
    super.key,
  });

  final WizardView view;
  final ServiceWizardController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final listing = view.listing;
    final category = view.category;
    final model = listing.pricingModel;
    final slotsBlocked = model?.forcesRequestMode ?? false;
    final emergency = listing.emergency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Availability',
          body: 'How customers book this service, and when you work.',
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        const ControlLabel(label: 'How this service is booked'),
        const SizedBox(height: AppSpacing.sm),
        ChoiceCard(
          key: const Key('booking-mode-slot'),
          title: 'Fixed time slots',
          // 🔧 Round 56: a slot booking still needs the provider to accept
          // (§0.0 item 13) — "Book instantly" named an immediacy the state
          // machine does not produce.
          description:
              'Customers pick from the times you publish, then you accept.',
          selected: listing.bookingMode == BookingMode.slot && !slotsBlocked,
          disabledReason: slotsBlocked
              ? '${model!.label} pricing can’t be booked as a fixed slot — '
                    'switch pricing to enable this.'
              : null,
          onTap: () => controller.chooseBookingMode(BookingMode.slot),
        ),
        const SizedBox(height: AppSpacing.sm + 1),
        ChoiceCard(
          key: const Key('booking-mode-request'),
          title: 'Request a time',
          description: 'Customers send a request; you come back with a time.',
          selected: listing.bookingMode != BookingMode.slot || slotsBlocked,
          onTap: () => controller.chooseBookingMode(BookingMode.request),
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        WizardSection(
          title: 'Working days',
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (day, label) in isoWeekdays)
                  AppChip.filter(
                    label: label,
                    selected: listing.workingDays.contains(day),
                    onTap: () => controller.toggleWorkingDay(day),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: HourField(
                    label: 'From',
                    value: listing.workingHoursFrom,
                    onChanged: (value) =>
                        controller.setWorkingHours(from: value),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: HourField(
                    label: 'To',
                    value: listing.workingHoursTo,
                    onChanged: (value) => controller.setWorkingHours(to: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Your simple working window for this service. Recurring rules '
              'and time off live in your provider Availability settings.',
              style: type.helper,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        WizardSection(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.warningTint,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.bolt_outlined,
                    size: 19,
                    color: colors.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.md + 1),
                Expanded(
                  child: AppToggle(
                    key: const Key('wizard-emergency'),
                    label: 'Emergency callouts',
                    value: listing.isEmergency,
                    // The server's own sentence, naming the bar and the
                    // current tier. Rendered, never recomputed.
                    disabledReason: emergency.allowed ? null : emergency.reason,
                    onChanged: emergency.allowed
                        ? (_) => controller.toggleEmergency()
                        : null,
                  ),
                ),
              ],
            ),
            if (emergency.allowed) ...[
              const SizedBox(height: AppSpacing.sm + 2),
              Text(
                _expectation(category),
                style: type.secondary.copyWith(
                  height: 1.5,
                  color: colors.textSecondary,
                ),
              ),
              if (listing.isEmergency) ...[
                const SizedBox(height: AppSpacing.sm),
                const WizardNote(
                  icon: Icons.schedule_rounded,
                  tone: NoteTone.cautionary,
                  message:
                      'Answering fast and arriving fast are different '
                      'commitments — you state your own arrival estimate each '
                      'time you answer. If you need two hours to load the '
                      'van, say so when you reply.',
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }

  /// The category's own response window, or nothing at all.
  ///
  /// A null window would mean a capable category with no seeded number, which
  /// is a misconfigured row rather than a default to invent — so the sentence
  /// is dropped rather than printed with a guess. The four emergency
  /// categories all carry 30 today, Moving included (Round 22), and this
  /// still reads the column so they can diverge again.
  static String _expectation(ServiceCategory? category) {
    final window = category?.emergencyAcceptWindowMinutes;
    final noun = category == null ? '' : '${category.name} ';
    final opening =
        'Customers can reach you outside your working hours for urgent '
        '${noun}jobs.';
    return window == null
        ? opening
        : '$opening Customers expect a response within $window minutes.';
  }
}
