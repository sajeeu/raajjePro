import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/presentation/widgets/wizard_pieces.dart';
import 'package:raajjepro/shared/shared.dart';

/// Step 2 — Location & service area.
///
/// **The listing's own islands, not the account default** (ledger P7-3). The
/// default is copied in once when the draft is created and the two never touch
/// again: editing here changes this service and nothing else, which is what
/// the notice at the top says in the provider's words.
///
/// The control is §Phase 7's [IslandMultiSelect], embedded rather than
/// rebuilt. Search **is** the control — 192 islands is not a browsable list —
/// and everything that makes it correct (matching anywhere in the name,
/// ranking prefixes first, folding case, accents and the Dhivehi apostrophe,
/// matching the atoll code, returning every match with no cap, never
/// auto-selecting) is the server's and is not re-implemented here.
class LocationStep extends StatelessWidget {
  const LocationStep({required this.view, required this.controller, super.key});

  final WizardView view;
  final ServiceWizardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepIntro(
          title: 'Location & service area',
          body:
              'Customers only see services available on their island. At '
              'least one island is needed to publish.',
        ),
        const SizedBox(height: AppSpacing.lg2),
        const WizardNote(
          icon: Icons.place_outlined,
          tone: NoteTone.informative,
          message:
              'Pre-filled from your default coverage areas. Edit freely — '
              'changes here apply to this service only.',
        ),
        const SizedBox(height: AppSpacing.lg2),
        IslandMultiSelect(
          key: const Key('wizard-islands'),
          selected: view.listing.serviceAreas,
          emptySelectionMessage:
              "Customers browsing from islands not on your list won't see "
              'this service.',
          onChanged: controller.setServiceAreas,
        ),
      ],
    );
  }
}
