import { BusinessRuleError } from '../../core/errors.js';
import type { BookingMode, Listing, PricingModel } from '../../generated/prisma/client.js';

/**
 * What `publish` enforces, and the only place it is written down (§Phase 8).
 *
 * Invariant 2 splits the rules in two and this file is the second half:
 * **a draft saves with zero required fields filled**, and *only* publish
 * enforces them. Nothing here runs on a draft-save, and no column in the
 * schema is NOT NULL because of anything below.
 */

/**
 * The wizard step a missing field belongs to, so the review screen can send
 * the provider to the right place rather than to the top of the form. The
 * names match §Phase 8's own seven ("Details, Location, Pricing, Media,
 * Availability, Extra Info, Meta").
 */
export type WizardStep = 'details' | 'location' | 'pricing' | 'media';

export interface MissingField {
  field: string;
  step: WizardStep;
  /** Human-readable, and the label §Phase 9's review step renders. */
  message: string;
}

/**
 * 🔧 **Six required fields, not five** (§Phase 8, §0.2 item 4).
 *
 * The sixth is the **cover image**. v4 left it optional at publish, which
 * meant a listing could go live with a blank thumbnail — the first thing a
 * customer sees on every card and in every search result. Everything else
 * (gallery beyond the cover, availability detail, extra info) stays optional,
 * and §Phase 9's progress framing counts against this list: "N required
 * fields left to publish".
 */
export const REQUIRED_FIELD_COUNT = 6;

/** The listing shape this file reads. A row, plus the two counts that live in other tables. */
export interface PublishCandidate {
  listing: Pick<
    Listing,
    | 'name'
    | 'categoryId'
    | 'shortDescription'
    | 'pricingModel'
    | 'priceLaari'
    | 'priceMinLaari'
    | 'priceMaxLaari'
    | 'coverMediaId'
    | 'bookingMode'
  >;
  /** Current (not soft-deleted) `ListingServiceArea` rows. */
  serviceAreaCount: number;
  /** True when `coverMediaId` names a media row that has actually been uploaded and finalised. */
  coverIsStored: boolean;
}

/**
 * Every required field this listing is still missing, in wizard order.
 *
 * Returns the whole list rather than the first failure: §Phase 8 asks for "a
 * structured missing-field list" and §Phase 9's review step renders all of
 * them at once with a Fix link each. Stopping at the first would make
 * publishing a five-round-trip guessing game.
 */
export function missingRequiredFields(candidate: PublishCandidate): MissingField[] {
  const { listing } = candidate;
  const missing: MissingField[] = [];

  if (isBlank(listing.name)) {
    missing.push({ field: 'name', step: 'details', message: 'Service name' });
  }
  if (listing.categoryId === null) {
    missing.push({ field: 'categoryId', step: 'details', message: 'Category' });
  }
  if (isBlank(listing.shortDescription)) {
    missing.push({ field: 'shortDescription', step: 'details', message: 'Short description' });
  }
  if (candidate.serviceAreaCount === 0) {
    missing.push({
      field: 'serviceAreaIslandIds',
      step: 'location',
      // "Customers only see services available on their island" — a published
      // listing serving nowhere is invisible to everyone, which is a worse
      // outcome for the provider than being told.
      message: 'At least one island',
    });
  }

  // "A pricing model with its price" is one required field with a shape that
  // depends on the model — `quote` genuinely has no price, and demanding one
  // would make "price on request" unpublishable.
  missing.push(...missingPricing(listing.pricingModel, listing));

  if (listing.coverMediaId === null) {
    missing.push({ field: 'coverMediaId', step: 'media', message: 'Cover image' });
  } else if (!candidate.coverIsStored) {
    // A cover row exists but no bytes ever arrived — the upload was started
    // and abandoned. Treated as missing rather than present, because a
    // pending row would otherwise satisfy the one field §0.2 added
    // specifically to stop a blank thumbnail going live.
    missing.push({
      field: 'coverMediaId',
      step: 'media',
      message: 'Cover image (the upload did not finish)',
    });
  }

  return missing;
}

function missingPricing(
  model: PricingModel | null,
  listing: PublishCandidate['listing'],
): MissingField[] {
  if (model === null) {
    return [{ field: 'pricingModel', step: 'pricing', message: 'How the price works' }];
  }
  if (model === 'quote') {
    // §Phase 8's `quote` is "price on request" — the absence of a price is
    // the choice, not an omission.
    return [];
  }
  if (model === 'range') {
    const missing: MissingField[] = [];
    if (listing.priceMinLaari === null) {
      missing.push({ field: 'priceMinLaari', step: 'pricing', message: 'Price range (from)' });
    }
    if (listing.priceMaxLaari === null) {
      missing.push({ field: 'priceMaxLaari', step: 'pricing', message: 'Price range (to)' });
    }
    return missing;
  }
  return listing.priceLaari === null
    ? [{ field: 'priceLaari', step: 'pricing', message: 'Price' }]
    : [];
}

/**
 * 🔧 **`pricingModel` constrains `bookingMode`** (§Phase 8, Round 16).
 *
 * `range` and `quote` **force request mode**; `fixed`, `hourly` and `daily`
 * permit either.
 *
 * This is not a style preference. §1c requires `agreedAmount` to be set at
 * `accepted` and no booking may reach `awaiting_payment` without one, so a
 * slot-mode listing priced `quote` is unrepresentable — the customer would be
 * booking a fixed time at an unknown price. The wizard says the same thing in
 * its own words: "Price range and Price on request can't be booked as a fixed
 * time slot — customers request a time instead, since no one can book a set
 * time at an unknown price."
 */
export function pricingModelForcesRequestMode(model: PricingModel): boolean {
  return model === 'range' || model === 'quote';
}

/** The structured error §Phase 8 asks for — "naming both fields". */
export function assertPricingAndModeAgree(
  model: PricingModel | null,
  mode: BookingMode | null,
): void {
  if (model === null || mode === null) return;
  if (!pricingModelForcesRequestMode(model)) return;
  if (mode === 'request') return;
  throw new BusinessRuleError(
    'PRICING_MODEL_REQUIRES_REQUEST_MODE',
    `A listing priced "${model}" cannot be booked as a fixed time slot — no one can book a set time at an unknown price`,
    [
      { path: 'pricingModel', message: `"${model}" requires request mode` },
      { path: 'bookingMode', message: `"${mode}" is not allowed with this pricing model` },
    ],
  );
}

/**
 * Range sanity, checked wherever a price is written rather than only at
 * publish: a from above a to is a typo the provider should hear about while
 * they are still on the pricing step.
 */
export function assertPriceRangeOrdered(min: number | null, max: number | null): void {
  if (min === null || max === null || min <= max) return;
  throw new BusinessRuleError(
    'PRICE_RANGE_INVERTED',
    'The "from" price is higher than the "to" price',
    [{ path: 'priceMinLaari', message: 'Must not be more than the "to" price' }],
  );
}

/** Trimmed-empty counts as absent — a name of three spaces is not a name. */
function isBlank(value: string | null): boolean {
  return value === null || value.trim().length === 0;
}
