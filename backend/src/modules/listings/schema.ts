import { z } from 'zod';

/**
 * Request validation for the listing surface (§Phase 8).
 *
 * ## Everything is optional, and that is the requirement
 *
 * Invariant 2: "a draft must be saveable with zero required fields filled".
 * So `createListingBody` accepts an empty object and `updateListingBody` is
 * `.partial()` throughout — the wizard PATCHes one step at a time and a
 * half-filled step is a normal save, not an error. The six required fields
 * are enforced at publish, by `publish.ts`, and nowhere else.
 *
 * ## Note what a provider cannot send
 *
 * Absent keys are the enforcement — an unknown key is stripped, so no handler
 * has to remember to ignore one:
 *
 *   - `status` — `publish` is its own endpoint with its own gate. A PATCH
 *     that could set `published` would bypass the required-field list, the
 *     entitlement cap and the pricing/booking-mode rule in one line.
 *   - `visibility` — its own endpoint too, and only two of the four values
 *     are the provider's to set (§1b: `hidden_over_cap` belongs to the
 *     entitlement system and `hidden_by_admin` to moderation).
 *   - `viewCount` / `bookingCount` — rolled up from the event log.
 *   - `providerProfileId` — the owner is the caller, never a body field.
 */

/** Trim first, then measure: a name of three spaces is not a name. */
const trimmed = (max: number) => z.string().trim().max(max);

/**
 * Money arrives as integer laari and is never a float or a decimal string
 * (invariant 7). `z.int()` refuses `450.5`, which is the shape a client that
 * had been doing MVR arithmetic would send.
 *
 * The ceiling is deliberately generous rather than tuned — a full-day boat
 * charter is a real five-figure MVR price — but finite, because an unbounded
 * integer in a money column is how a typo becomes a listing priced at nine
 * billion laari.
 */
const laari = z.int().min(0).max(100_000_000);

/** `HH:MM`, 24-hour. The wizard's own hour list runs 06:00–22:00; this accepts any valid clock time. */
const clockTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:MM, 24-hour');

/**
 * §Phase 9 step 1: "Relevant tags help customers find you in search. Up to
 * 10." Round 12 made them category-scoped chips with free text underneath,
 * so the *values* are open — nothing here checks a tag against a list — and
 * only the count and length are bounded.
 */
const tags = z.array(trimmed(40).min(1)).max(10);

const faqs = z
  .array(
    z.object({
      question: trimmed(200).min(1),
      answer: trimmed(1000).min(1),
    }),
  )
  .max(20);

export const pricingModel = z.enum(['fixed', 'hourly', 'daily', 'range', 'quote']);
export const priceUnit = z.enum(['job', 'hour', 'day', 'session', 'visit']);
export const bookingMode = z.enum(['slot', 'request']);

/** ISO weekday numbers, 1 = Monday. A set, so a duplicated day is a client bug rather than a stored one. */
const workingDays = z
  .array(z.int().min(1).max(7))
  .max(7)
  .refine((days) => new Set(days).size === days.length, { message: 'Repeated day' });

/**
 * Draft creation takes a category so the listing can default its
 * `bookingMode` from the seed straight away (§1c). Optional like everything
 * else: §Phase 6a's handoff opens "a fresh draft, pre-populated with
 * nothing".
 */
export const createListingBody = z
  .object({
    categoryId: z.uuid(),
  })
  .partial();

export const updateListingBody = z
  .object({
    // -- Step 1, Details --
    categoryId: z.uuid().nullable(),
    name: trimmed(120).nullable(),
    shortDescription: trimmed(200).nullable(),
    longDescription: trimmed(2000).nullable(),
    tags,

    // -- Step 2, Location --
    /**
     * The listing's own service areas, sent as **the whole set** — this step
     * is a multi-select and a PATCH of it replaces what is there.
     *
     * Island **ids**, never names (§0.0 item 12): sixteen normalised names
     * occur in more than one atoll and `Meedhoo` exists in three, so a name
     * would silently serve the wrong atoll. Nothing in this module accepts a
     * name for an island anywhere.
     *
     * Not conflated with `ProviderServiceArea` (ledger P7-3): that is the
     * account-level default §Phase 6a collects and §Phase 9's step 2
     * pre-fills from, and this is what a customer's island filter reads.
     */
    serviceAreaIslandIds: z.array(z.uuid()).max(192),

    // -- Step 3, Pricing --
    pricingModel: pricingModel.nullable(),
    priceLaari: laari.nullable(),
    priceMinLaari: laari.nullable(),
    priceMaxLaari: laari.nullable(),
    priceUnit: priceUnit.nullable(),

    // -- Step 4, Media --
    /** Must name one of this listing's own stored images; the service checks that. */
    coverMediaId: z.uuid().nullable(),
    /** Gallery order, as the whole list. "Use the arrows to reorder — the first photo shows first." */
    galleryMediaIds: z.array(z.uuid()).max(20),

    // -- Step 5, Availability --
    bookingMode,
    workingDays,
    workingHoursFrom: clockTime.nullable(),
    workingHoursTo: clockTime.nullable(),
    /** Gated by §1c's composed rule on every write, not only at publish (§Phase 8: "enforced on publish and update"). */
    isEmergency: z.boolean(),

    // -- Step 6, Extra information --
    whatsIncluded: trimmed(1000).nullable(),
    whatsNotIncluded: trimmed(1000).nullable(),
    faqs,
    /** §1i, self-declared and never verified. Neither gates publish. */
    warrantyOffered: z.boolean(),
    warrantyTermsText: trimmed(500).nullable(),
    insuranceDeclared: z.boolean(),
    insuranceDetailText: trimmed(500).nullable(),
    /** Round 28: refused on a category whose `callbackEligible` is false. */
    callbackGuaranteeOffered: z.boolean(),
  })
  .partial()
  .refine((body) => Object.keys(body).length > 0, { message: 'Change at least one field' });

/**
 * The two values a **provider** may set (§1b, Round 17).
 *
 * `hidden_over_cap` is the entitlement system's alone and `hidden_by_admin`
 * is moderation's, and the distinction is load-bearing: under a single
 * `hidden` value an upgrade would silently republish a listing the provider
 * had deliberately withdrawn. Leaving them out of this enum is what makes
 * that impossible rather than merely discouraged.
 */
export const listingVisibilityBody = z.object({
  visibility: z.enum(['active', 'hidden_by_provider']),
});

export const listingParams = z.object({ id: z.uuid() });
export const listingMediaParams = z.object({ id: z.uuid(), mediaId: z.uuid() });

/**
 * Requesting an upload target. The content type is what the client says it
 * will send; `finalise` checks the bytes and is the check that counts.
 */
export const createListingMediaBody = z.object({
  contentType: z.string().min(1).max(100),
});

export const listOwnListingsQuery = z
  .object({
    limit: z.coerce.number().int().min(1).max(50),
    cursor: z.string().max(256),
    /** My Services filters by state; the default is everything the provider still has. */
    status: z.enum(['draft', 'published']),
  })
  .partial();

export type CreateListingBody = z.infer<typeof createListingBody>;
export type UpdateListingBody = z.infer<typeof updateListingBody>;
export type ListOwnListingsQuery = z.infer<typeof listOwnListingsQuery>;
