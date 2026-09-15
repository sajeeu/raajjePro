import 'package:raajjepro/core/listings/service_listing.dart';

/// The six required fields, computed locally so the header's counter is true
/// the instant a field changes — including while a save is still queued
/// offline.
///
/// **This is UX, not the rule** (invariant 4). The rule lives in
/// `backend/src/modules/listings/publish.ts` and runs at
/// `POST …/listings/:id/publish`; what publish refuses is what counts, and the
/// review step renders the server's own list when it does. This mirror exists
/// because "N required fields left to publish" is on every step's header and
/// cannot wait for a round trip that may not happen for an hour.
///
/// The messages are word-for-word the server's, so a provider never reads two
/// different names for the same field.
List<MissingField> missingRequiredFields(ServiceListing listing) {
  final missing = <MissingField>[];

  if (_blank(listing.name)) {
    missing.add(
      const MissingField(
        field: 'name',
        step: WizardStep.details,
        message: 'Service name',
      ),
    );
  }
  if (listing.categoryId == null) {
    missing.add(
      const MissingField(
        field: 'categoryId',
        step: WizardStep.details,
        message: 'Category',
      ),
    );
  }
  if (_blank(listing.shortDescription)) {
    missing.add(
      const MissingField(
        field: 'shortDescription',
        step: WizardStep.details,
        message: 'Short description',
      ),
    );
  }
  if (listing.serviceAreas.isEmpty) {
    missing.add(
      const MissingField(
        field: 'serviceAreaIslandIds',
        step: WizardStep.location,
        message: 'At least one island',
      ),
    );
  }
  missing.addAll(_missingPricing(listing));
  if (listing.coverMedia == null) {
    missing.add(
      const MissingField(
        field: 'coverMediaId',
        step: WizardStep.media,
        message: 'Cover image',
      ),
    );
  } else if (!listing.hasStoredCover) {
    missing.add(
      const MissingField(
        field: 'coverMediaId',
        step: WizardStep.media,
        message: 'Cover image (the upload did not finish)',
      ),
    );
  }
  return List.unmodifiable(missing);
}

/// One required field whose shape depends on the model — `quote` genuinely has
/// no price, and demanding one would make "price on request" unpublishable.
List<MissingField> _missingPricing(ServiceListing listing) {
  final model = listing.pricingModel;
  if (model == null) {
    return const [
      MissingField(
        field: 'pricingModel',
        step: WizardStep.pricing,
        message: 'How the price works',
      ),
    ];
  }
  if (model == PricingModel.quote) return const [];
  if (model == PricingModel.range) {
    return [
      if (listing.priceMinLaari == null)
        const MissingField(
          field: 'priceMinLaari',
          step: WizardStep.pricing,
          message: 'Price range (from)',
        ),
      if (listing.priceMaxLaari == null)
        const MissingField(
          field: 'priceMaxLaari',
          step: WizardStep.pricing,
          message: 'Price range (to)',
        ),
    ];
  }
  return listing.priceLaari == null
      ? const [
          MissingField(
            field: 'priceLaari',
            step: WizardStep.pricing,
            message: 'Price',
          ),
        ]
      : const [];
}

/// Trimmed-empty counts as absent — a name of three spaces is not a name.
bool _blank(String? value) => value == null || value.trim().isEmpty;
