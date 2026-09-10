import type {
  BookingMode,
  Listing,
  ListingMedia,
  ListingMediaStatus,
  ListingStatus,
  ListingVisibility,
  PriceUnit,
  PricingModel,
  VerificationTier,
} from '../../generated/prisma/client.js';
import type { IslandDto } from '../location/types.js';
import type { EmergencyEligibility } from './emergency.js';
import { REQUIRED_FIELD_COUNT, type MissingField } from './publish.js';

/**
 * What a listing looks like on the wire (§Phase 8).
 *
 * **This file is the structural gate**, the same job `providers/types.ts`
 * does for the provider shapes (backend/CLAUDE.md: sensitive fields are
 * excluded in the mapping layer, not by remembering per handler). Two
 * exclusions matter here and neither is enforceable by discipline:
 *
 *   - **No phone number, at any depth.** §1c allows exactly one endpoint in
 *     the entire system to return one to another user, and it is not this
 *     module. There is no field on any shape below that could carry one, and
 *     nothing here reaches a `User` or a `ProviderProfile` row.
 *   - **No payment detail.** A listing carries a *price*; where the money
 *     goes is the provider's, reachable only through
 *     `paymentDetailsForBooking` at a booking's payment step.
 *
 * Money is integer laari in every field that carries it (invariant 7) — in
 * the database, in the DTO and in the JSON, with no float anywhere in the
 * path. A client renders MVR by dividing by 100 at the last moment.
 */

/**
 * One image. `url` is a **short-lived signed URL**, re-issued on every read
 * and never stored, so it stops working when the listing does.
 *
 * Null while the row is `pending`: an upload target has been issued and no
 * bytes have arrived, so there is nothing to point at. That is also why
 * `status` is on the wire — the wizard's media step shows an "Uploading…" and
 * an "Upload failed · Retry" state, and it needs to tell them apart.
 */
export interface ListingMediaDto {
  id: string;
  status: ListingMediaStatus;
  contentType: string;
  /** Bytes actually stored, after metadata stripping. Null until finalised. */
  byteSize: number | null;
  url: string | null;
}

/**
 * §1i's four self-declared fields, grouped so a renderer cannot pick one up
 * without the flag that says whether it applies.
 *
 * **Nothing here is verified by RaajjePro and the API must never imply it
 * is.** A response carries the provider's own text; rendering it needs the
 * attributed form — "Provider states: 90-day workmanship warranty" — never a
 * check mark, a shield, a lock or the word *verified*, and never inside the
 * callback badge's visual treatment. Those belong to `verificationTier`,
 * which means something because a human checked it.
 */
export interface SelfDeclaredCoverDto {
  warrantyOffered: boolean;
  warrantyTermsText: string | null;
  insuranceDeclared: boolean;
  insuranceDetailText: string | null;
}

/** One question-and-answer pair from step 6. */
export interface ListingFaqDto {
  question: string;
  answer: string;
}

/**
 * The server's own answer to "may this listing advertise emergency work?",
 * carried on the own-listing read.
 *
 * It is here so the wizard renders the *server's* reason rather than
 * recomputing the rule from the category and the provider's tier. Invariant 4
 * puts the enforcement server-side either way; this stops the client's
 * explanation drifting from the server's decision, which is how a provider
 * ends up staring at a disabled toggle whose stated reason is wrong.
 */
export interface EmergencyAvailabilityDto {
  allowed: boolean;
  /** Null when allowed. Otherwise the reason, naming the bar and the current tier. */
  reason: string | null;
  /** The category's own bar (§1c) — `gold` for Electrical and Plumbing, `silver` for AC Repair and Moving. Null on a category that has none. */
  requiredTier: VerificationTier | null;
  currentTier: VerificationTier;
}

/**
 * The owner's view of their own listing — everything the wizard needs to
 * resume, and the publish gate's own answer.
 *
 * There is deliberately **no public listing shape in this phase.** §Phase 12
 * owns the Service Preview page and §Phase 15 owns search; both will map
 * their own, from `PUBLICLY_VISIBLE_LISTING`. Inventing one here would be
 * guessing at what those screens show.
 */
export interface OwnListingDto {
  id: string;
  providerProfileId: string;
  categoryId: string | null;

  // Step 1 — Details
  name: string | null;
  shortDescription: string | null;
  longDescription: string | null;
  tags: string[];

  // Step 2 — Location. The listing's OWN areas, not the account default
  // (ledger P7-3): `ProviderServiceArea` is what the wizard pre-fills from,
  // and this is what discovery matches on. Islands travel with their atoll,
  // and a client must key on `id` — sixteen names are shared (§0.0 item 12).
  serviceAreas: IslandDto[];

  // Step 3 — Pricing. Integer laari (invariant 7).
  pricingModel: PricingModel | null;
  priceLaari: number | null;
  priceMinLaari: number | null;
  priceMaxLaari: number | null;
  /**
   * What the customer sees — `fixed` + `session` renders "MVR 500/session".
   *
   * There is deliberately **no `allowedPriceUnits`** beside it. The bullet
   * that introduced this field asks for "a short list per category" and the
   * plan names no subset (ledger **P8-1**), so the closed `PriceUnit` enum is
   * the whole rule and the client already has it from the API contract. A
   * field returning the same five values for every category would be a
   * response nobody could act on, and adding it later is additive.
   */
  priceUnit: PriceUnit | null;

  // Step 4 — Media
  coverMedia: ListingMediaDto | null;
  gallery: ListingMediaDto[];

  // Step 5 — Availability
  bookingMode: BookingMode | null;
  workingDays: number[];
  workingHoursFrom: string | null;
  workingHoursTo: string | null;
  isEmergency: boolean;
  emergency: EmergencyAvailabilityDto;

  // Step 6 — Extra information
  whatsIncluded: string | null;
  whatsNotIncluded: string | null;
  faqs: ListingFaqDto[];
  selfDeclared: SelfDeclaredCoverDto;
  callbackGuaranteeOffered: boolean;
  /** Round 28: false where the category is not `callbackEligible`, and §Phase 9 renders no control at all — absent, not disabled. */
  callbackAvailable: boolean;

  // Step 7 — Meta
  status: ListingStatus;
  visibility: ListingVisibility;
  publishedAt: string | null;
  firstPublishedAt: string | null;
  /**
   * §Phase 8's structured missing-field list, and §Phase 9's "N required
   * fields left to publish" counts it. Empty means publish will not fail on
   * completeness — it can still fail on the entitlement cap, which is not a
   * missing field and is not reported here.
   */
  missingRequiredFields: MissingField[];
  /** Six (§0.2 item 4 added the cover image). The denominator §Phase 9 shows. */
  requiredFieldCount: number;

  /** Rolled up from the event log, never incremented per request (§Phase 8). */
  viewCount: number;
  bookingCount: number;

  createdAt: string;
  updatedAt: string;
}

/** Everything the mapper needs, so it cannot be called with half the picture. */
export interface ListingDtoInput {
  listing: Listing;
  serviceAreas: IslandDto[];
  cover: ListingMedia | null;
  gallery: ListingMedia[];
  emergency: EmergencyEligibility;
  providerTier: VerificationTier;
  requiredTier: VerificationTier | null;
  callbackAvailable: boolean;
  missingRequiredFields: MissingField[];
  /** Issues the short-lived read URL. Injected so the mapper stays pure of storage. */
  mediaUrl: (objectKey: string) => string;
}

export function toOwnListingDto(input: ListingDtoInput): OwnListingDto {
  const { listing } = input;
  return {
    id: listing.id,
    providerProfileId: listing.providerProfileId,
    categoryId: listing.categoryId,

    name: listing.name,
    shortDescription: listing.shortDescription,
    longDescription: listing.longDescription,
    tags: listing.tags,

    serviceAreas: input.serviceAreas,

    pricingModel: listing.pricingModel,
    priceLaari: listing.priceLaari,
    priceMinLaari: listing.priceMinLaari,
    priceMaxLaari: listing.priceMaxLaari,
    priceUnit: listing.priceUnit,

    coverMedia: input.cover === null ? null : toMediaDto(input.cover, input.mediaUrl),
    gallery: input.gallery.map((row) => toMediaDto(row, input.mediaUrl)),

    bookingMode: listing.bookingMode,
    workingDays: listing.workingDays,
    workingHoursFrom: listing.workingHoursFrom,
    workingHoursTo: listing.workingHoursTo,
    isEmergency: listing.isEmergency,
    emergency: {
      allowed: input.emergency.eligible,
      reason: input.emergency.eligible ? null : input.emergency.message,
      requiredTier: input.requiredTier,
      currentTier: input.providerTier,
    },

    whatsIncluded: listing.whatsIncluded,
    whatsNotIncluded: listing.whatsNotIncluded,
    faqs: readFaqs(listing.faqs),
    selfDeclared: {
      warrantyOffered: listing.warrantyOffered,
      warrantyTermsText: listing.warrantyTermsText,
      insuranceDeclared: listing.insuranceDeclared,
      insuranceDetailText: listing.insuranceDetailText,
    },
    callbackGuaranteeOffered: listing.callbackGuaranteeOffered,
    callbackAvailable: input.callbackAvailable,

    status: listing.status,
    visibility: listing.visibility,
    publishedAt: listing.publishedAt?.toISOString() ?? null,
    firstPublishedAt: listing.firstPublishedAt?.toISOString() ?? null,
    missingRequiredFields: input.missingRequiredFields,
    requiredFieldCount: REQUIRED_FIELD_COUNT,

    viewCount: listing.viewCount,
    bookingCount: listing.bookingCount,

    createdAt: listing.createdAt.toISOString(),
    updatedAt: listing.updatedAt.toISOString(),
  };
}

export function toMediaDto(
  row: ListingMedia,
  mediaUrl: (objectKey: string) => string,
): ListingMediaDto {
  return {
    id: row.id,
    status: row.status,
    contentType: row.contentType,
    byteSize: row.byteSize,
    // A pending row has no bytes behind it, so a URL would 404. Null says so.
    url: row.status === 'stored' ? mediaUrl(row.objectKey) : null,
  };
}

/**
 * `faqs` is a Json column, so what comes back is `Prisma.JsonValue` and the
 * compiler cannot know its shape. Zod validated it on the way in; this
 * re-checks the shape on the way out rather than casting, because a hand-edited
 * row or a future migration is exactly the case a cast hides.
 */
function readFaqs(value: unknown): ListingFaqDto[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry): ListingFaqDto[] => {
    if (entry === null || typeof entry !== 'object') return [];
    const { question, answer } = entry as Record<string, unknown>;
    if (typeof question !== 'string' || typeof answer !== 'string') return [];
    return [{ question, answer }];
  });
}
