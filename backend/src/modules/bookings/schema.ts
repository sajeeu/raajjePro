import { z } from 'zod';

import { WINDOW_CHIPS } from './quotes.js';
import { BOOKING_STATUSES } from './transitions.js';

/**
 * Request validation for §Phases 17.1 and 17.2.
 *
 * **No shape here accepts an amount from the client on the slot path.** §1c
 * step 3 derives `agreedAmount` from the listing and the published slot's own
 * length, and invariant 4 puts every rule on the server — a client-supplied
 * price at creation would be a customer naming what they will pay. The one
 * place a number does arrive is §1h's amendment, which is a *proposal* the
 * other party has to accept, and §Phase 17's `complete`, where the provider
 * records what the job actually came to.
 */

const uuid = z.uuid();

export const bookingParams = z.object({ id: uuid });
export const listingParams = z.object({ id: uuid });
export const amendmentParams = z.object({ id: uuid, amendmentId: uuid });

/**
 * Integer laari (invariant 7). Never a float, never a decimal string — MVR 150
 * is 15000 and nothing in this system says 150.00.
 */
const laari = z.int().min(0).max(1_000_000_000);

/**
 * The lower half of `Pick a Time.dc.html`: what the customer adds once they
 * have chosen a time.
 *
 * `islandId` and never an island *name* (§0.0 item 12): fifteen names repeat
 * across atolls and `Meedhoo` exists in three, so a booking location keyed by
 * name is a booking at one of three islands.
 */
export const createSlotBookingBody = z.object({
  timeSlotId: uuid,
  jobNotes: z.string().trim().max(2000).optional(),
  islandId: uuid.optional(),
  addressDetail: z.string().trim().max(300).optional(),
});

/**
 * The upper half of `Request a Time.dc.html` — §Phase 17.2's creation body.
 *
 * **A window is required and the job description is not**, which is narrower
 * than the screen: its CTA reads "Add a window and the job" until both are
 * filled. The asymmetry is invariant 4 drawing the line where the plan draws
 * it. A request with no window is not a request — §1c's request-based flow
 * *is* "customer submits a preferred date/time window" and the provider has
 * nothing to answer without one. A request with no description is a thin
 * request, which is a matter for the screen to discourage and not for the
 * server to refuse: the plan states no such rule, and a refusal invented here
 * would reject a legitimate customer who put everything in the photos.
 *
 * `preferredWindowChip` and `preferredWindowText` are both accepted because
 * the screen offers both — chips first, free text underneath "for anything
 * more specific" (§1c) — and at least one must be present.
 */
export const createRequestBookingBody = z
  .object({
    preferredWindowChip: z.enum(WINDOW_CHIPS).optional(),
    preferredWindowText: z.string().trim().min(1).max(300).optional(),
    /**
     * Round 25, request mode only, "one of the category's `occasionPresets`"
     * — which the service checks against the seeded list, because a body
     * schema cannot see which category this listing is in.
     */
    occasion: z.string().trim().min(1).max(80).optional(),
    jobNotes: z.string().trim().max(2000).optional(),
    islandId: uuid.optional(),
    addressDetail: z.string().trim().max(300).optional(),
  })
  .refine(
    (body) => body.preferredWindowChip !== undefined || body.preferredWindowText !== undefined,
    { error: 'Say when suits you — pick a window or describe one', path: ['preferredWindowChip'] },
  );

/**
 * One route takes both creation shapes (`POST /v1/listings/:id/bookings`),
 * because one *listing* takes one of them and which one is the listing's fact
 * rather than the caller's. A union rather than a discriminator field: the
 * server already knows the mode from the listing, so asking the client to
 * declare it would create a second source of truth to disagree with.
 *
 * The slot shape is tried first, and it is the narrower of the two — it
 * requires `timeSlotId`, which the request shape does not accept. A body that
 * matches neither is refused with both branches' reasons, naming the missing
 * `timeSlotId` and the missing window.
 */
/**
 * §Phase 17.3 — `Emergency Flow.dc.html`'s form: "What's wrong?" and
 * "Where?". §1c: "Customer submits an ASAP request — no slot, no window —
 * with job details and location."
 *
 * **Both are required**, unlike the request form's job description, because
 * both are load-bearing here: the island is what the broadcast matches on
 * (by id, never by name — §0.0 item 12), and the description is the whole of
 * what a provider has to price a callout fee from before they answer. The
 * `emergency: true` literal is what routes the body; the listing still has to
 * be one that takes emergency requests, which the service checks.
 */
export const createEmergencyBookingBody = z.object({
  emergency: z.literal(true),
  jobNotes: z.string().trim().min(1).max(2000),
  islandId: uuid,
  addressDetail: z.string().trim().max(300).optional(),
});

/**
 * 🔧 Three shapes as of §Phase 17.3. The emergency shape is tried before the
 * request shape because it is the narrower of the two — it requires the
 * `emergency` literal, which the request shape would otherwise strip and then
 * refuse for having no window.
 */
export const createBookingBody = z.union([
  createSlotBookingBody,
  createEmergencyBookingBody,
  createRequestBookingBody,
]);

/**
 * `PATCH /v1/bookings/:id/emergency-accept` — `Provider Emergency.dc.html`:
 * "Your callout fee" and "When can you get there?".
 *
 * Both required, in one call (Round 22). `etaMinutes` is whatever the
 * provider chose — one of the category's presets or their own number — and
 * nothing is defaulted, because "no preset is preselected, and the offer
 * cannot be sent without a choice". The upper bound is a sanity bound on a
 * self-declared number, not a rule about arrival: a day covers the slowest
 * Moving preset many times over.
 */
export const emergencyAcceptBody = z.object({
  calloutFeeLaari: laari,
  etaMinutes: z
    .int()
    .min(1)
    .max(24 * 60),
});

/**
 * `PATCH /v1/bookings/:id/emergency-offer-response` — pick one offer, or
 * reject them all. Exactly one of the two.
 */
export const emergencyOfferResponseBody = z.union([
  z.object({ offerId: uuid }).strict(),
  z.object({ rejectAll: z.literal(true) }).strict(),
]);

export const dispatchFeeParams = z.object({ id: uuid });

/**
 * `PATCH /v1/bookings/:id/quote` — `Propose Time and Price.dc.html`.
 *
 * The provider's four fields, and the screen has no fifth: a date, a time, a
 * price, and a note. The hold's length is not among them (`quotes.ts`
 * `REQUEST_HOLD_MINUTES` records why), and neither is a duration for the job,
 * which is the one thing a `request` category by definition cannot state up
 * front.
 *
 * `amountLaari` is the one number a provider really does name — §1c: "the
 * provider responds with a proposed concrete date/time **and price**". It is
 * a proposal until the customer approves it, which is the same posture §1h's
 * amendment takes, and it is `min(1)` because a quote of nothing is not a
 * quote.
 */
export const offerQuoteBody = z.object({
  scheduledFor: z.iso.datetime(),
  amountLaari: laari.min(1),
  note: z.string().trim().max(2000).optional(),
});

/**
 * `.nullish()` and not `.optional()`: a PATCH sent with no body at all arrives
 * as `null`, not as `undefined`, and "Decline" is a button with nothing to
 * say. An optional-only schema rejects the commonest call this route takes.
 */
const optionalReason = z
  .object({ reason: z.string().trim().max(500).optional() })
  .nullish()
  .transform((v) => v ?? {});

export const declineBody = optionalReason;

/**
 * `Quote Received.dc.html`'s "Decline this quote". Same shape as a decline and
 * a different endpoint, for the reason §1c gives about decline and dispute:
 * separate endpoints, separate statuses, and here separate *actors* — this one
 * is the customer's and lands on `cancelled`, never `declined` (§1f).
 */
export const declineQuoteBody = optionalReason;

export const cancelBody = optionalReason;

/**
 * §Phase 17 item 13. Optional on every mode and **required on emergency**,
 * which the service enforces rather than the schema — the requirement depends
 * on the booking, and a body schema cannot see one.
 */
export const completeBody = z
  .object({ finalAmountLaari: laari.optional() })
  .nullish()
  .transform((v) => v ?? {});

/** §1c step 10's prompt, answered. */
export const completionAnswerBody = z.object({ happened: z.boolean() });

/**
 * §1h. At least one of the three changes must be present, which the service
 * refuses rather than the schema: "an amendment that changes nothing is not a
 * proposal" is a rule with a message, not a shape error.
 */
export const proposeAmendmentBody = z.object({
  amountLaari: laari.optional(),
  scheduledFor: z.iso.datetime().optional(),
  scopeNote: z.string().trim().max(2000).optional(),
  reason: z.string().trim().max(500).optional(),
});

export const respondToAmendmentBody = z.object({ accept: z.boolean() });

/**
 * §Phase 22's four **booking** reasons, Round 17's scoping applied at the
 * edge. `reports.ts` holds the same four as the runtime scoping map and
 * `assertReasonAllowed` re-checks them in the service, so a caller reaching
 * this rule by any other route is refused there too.
 */
export const disputeBody = z.object({
  reason: z.enum(['work_not_done', 'price_changed_on_site', 'unsafe_work', 'payment_dispute']),
  note: z.string().trim().max(1000).optional(),
});

/** §1c's fixed enumeration. v3 recorded "an outcome" and this is why it does not. */
export const resolveDisputeBody = z.object({
  outcome: z.enum([
    'resolved_for_customer',
    'resolved_for_provider',
    'inconclusive',
    'fraud_confirmed',
    'withdrawn',
  ]),
  /** Required only when the booking is `payment_unresolved`; the service says so. */
  unresolvedTo: z.enum(['confirmed', 'cancelled']).optional(),
  note: z.string().trim().max(500).optional(),
});

/**
 * `GET /v1/users/me/bookings?role=&status=` (§Phase 17 item 18).
 *
 * `status` repeats rather than taking a comma list, because the Bookings tab's
 * filter pills are a set — "Upcoming" is three statuses — and a comma list
 * would need parsing on both sides of the wire.
 */
export const listBookingsQuery = z.object({
  role: z.enum(['customer', 'provider']).default('customer'),
  status: z
    .union([z.enum(BOOKING_STATUSES), z.array(z.enum(BOOKING_STATUSES))])
    .optional()
    .transform((v) => (v === undefined ? undefined : Array.isArray(v) ? v : [v])),
  limit: z.coerce.number().int().min(1).max(50).default(20),
  cursor: z.string().max(200).optional(),
});
