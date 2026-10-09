import type { BookingChatState } from './chat.js';
import type {
  AmountKind,
  BookingActorRole,
  BookingAmendmentStatus,
  BookingCompletedVia,
  BookingKind,
  BookingStatus,
  DisputeOutcome,
  EmergencyOfferState,
  VerificationTier,
} from '../../generated/prisma/enums.js';

/**
 * ## No shape in this file has a field for a phone number, and none ever may
 *
 * §1c: "**There is exactly one endpoint in this entire system that returns a
 * phone number to another user**: `POST /v1/bookings/:id/reveal-contact`"
 * (§Phase 17.3). §Phase 17's Done-when asks this to be verified "by inspecting
 * **every** response shape in the module, not just the ones expected to carry
 * it", which is why the exclusion is structural rather than remembered: there
 * is no `phone` field to forget to omit, and `test/phase17-1-done-when.test.ts`
 * asserts it over the built route table as well.
 *
 * The same goes for WhatsApp and Viber handles, which §Phase 5 does not
 * collect anywhere and nothing can reveal.
 *
 * ## What a counterparty *is* allowed to see
 *
 * A name, because §1c's accept prompt is "job details and the customer's name
 * only". And, at the payment step and only there, the provider's **bank
 * transfer details** — §1c: "Payment details are not contact information. A
 * bank account number isn't a way to reach a person, and the off-platform
 * payment cannot physically happen without it."
 */

/** The counterparty, as the other side of a booking may see them. */
export interface BookingPartyDto {
  /** The user id, so the app can open the right chat thread (§Phase 18). */
  userId: string;
  /** Display name. A provider's business name where they have one. */
  name: string;
}

/** One row of §Phase 17's "status timeline showing when each transition happened and who caused it". */
export interface BookingStatusEventDto {
  id: string;
  fromStatus: BookingStatus | null;
  toStatus: BookingStatus;
  actorRole: BookingActorRole;
  transition: string;
  at: string;
}

/**
 * §1h's amendment, on the wire. Both the previous terms and the proposed ones,
 * because "the original terms and the amendment are both retained" and a
 * reader deciding whether to accept needs to see what is changing.
 */
export interface BookingAmendmentDto {
  id: string;
  status: BookingAmendmentStatus;
  proposedByRole: BookingActorRole;
  previousAmountLaari: number | null;
  previousScheduledFor: string | null;
  previousScopeNote: string | null;
  proposedAmountLaari: number | null;
  proposedScheduledFor: string | null;
  proposedScopeNote: string | null;
  reason: string | null;
  createdAt: string;
  respondedAt: string | null;
}

/**
 * Where a customer whose provider cancelled is dropped back to (§1h: "the
 * customer is dropped back into the booking flow with **service, date, time
 * and preferences pre-filled**, so rebooking is a confirmation rather than a
 * re-entry").
 *
 * Present only on a booking the **provider** cancelled. A customer who
 * cancelled their own booking is not offered a rebooking of it, and §1h is
 * explicit that normal bookings do not broadcast — this is a prefill, not a
 * dispatch.
 *
 * 🔧 Saved preferences are §Phase 17.4's and are absent here rather than
 * stubbed; the fields below are what §Phase 17.1 can truthfully supply.
 */
export interface ReplacementPrefillDto {
  listingId: string;
  bookingMode: BookingKind;
  /** The time that was booked, so the picker can open on that day. */
  scheduledFor: string | null;
  jobNotes: string | null;
  islandId: string | null;
  addressDetail: string | null;
  occasion: string | null;
}

/**
 * The provider's registered bank transfer details, shown at the payment step
 * of every booking and nowhere else (§1c, §Phase 5).
 *
 * Deliberately a separate shape rather than fields on the booking: it is
 * attached only when the booking is actually at a status where the customer is
 * being asked to pay, so a booking list never carries it.
 */
export interface PaymentDetailsDto {
  bankName: string | null;
  accountName: string | null;
  accountNumber: string | null;
}

export interface BookingDto {
  id: string;
  reference: string;
  listingId: string;
  listingName: string | null;
  categoryName: string | null;
  bookingMode: BookingKind;
  status: BookingStatus;

  /** The other side of this booking, from the caller's point of view. */
  customer: BookingPartyDto;
  provider: BookingPartyDto;

  agreedAmountLaari: number | null;
  amountKind: AmountKind | null;
  quotedAmountLaari: number | null;
  finalAmountLaari: number | null;

  scheduledFor: string | null;
  timeSlotId: string | null;
  durationMinutes: number | null;

  preferredWindowText: string | null;
  /**
   * §Phase 17.2. The chip's resolved range where the customer tapped one, null
   * where they typed instead — a preference, never a constraint (§1c: "this is
   * a preference, not a slot"). The provider's proposed time is what every
   * clock downstream uses.
   */
  preferredWindowFrom: string | null;
  preferredWindowTo: string | null;
  occasion: string | null;

  // -- §Phase 17.2's quote, as both parties see it --------------------------

  /**
   * When the provider must have quoted by — the deadline
   * `Request a Time.dc.html` renders as "until 12:30 today". Null once they
   * have, and null on every mode but `request`.
   */
  quoteDueAt: string | null;
  /** When the live quote was sent. Non-null is what "the chat has opened" means (§0.0 item 7). */
  quoteOfferedAt: string | null;
  /**
   * When the customer's approval window closes — what
   * `Quote Received.dc.html` counts down to. Read from the category's
   * `quoteApprovalMinutes`, never a flat 72 hours (invariant 13).
   */
  quoteExpiresAt: string | null;
  /** The provider's note on the quote — "Ibrahim's note", and the agreed scope once approved. */
  quoteNote: string | null;

  /**
   * Whether the `booking`-type thread takes messages right now.
   *
   * §Phase 17.2 owns this state and §Phase 18 owns the thread itself. It is
   * **derived** (`chat.ts`), so nothing can stamp it into disagreement with
   * the status: `open` from the moment a quote is offered on the request path
   * and from `accepted` on the others, `locked` seven days after completion
   * (Round 27), and `not_open` before either door.
   */
  chatState: BookingChatState;
  jobNotes: string | null;
  islandId: string | null;
  /** §0.0 item 12's convention, rendered server-side: `Dh. Meedhoo` or `Kulhudhuffushi`. */
  islandDisplayName: string | null;
  addressDetail: string | null;

  paymentClaimedAt: string | null;
  paymentClaimWithdrawnAt: string | null;
  paymentAttestedAt: string | null;
  completedAt: string | null;
  completedVia: BookingCompletedVia | null;
  completionPromptedAt: string | null;
  cancelledAt: string | null;
  cancelledByRole: BookingActorRole | null;
  cancellationReason: string | null;
  disputedAt: string | null;
  disputeOutcome: DisputeOutcome | null;

  createdAt: string;

  // -- §Phase 17.4 ----------------------------------------------------------

  /** When the customer last moved this booking before the provider answered. */
  rescheduledAt: string | null;
  /** §1h's callback guarantee as it applies to this booking. */
  callback: BookingCallbackDto;
  /** On a callback booking: the completed booking whose guarantee it honours. */
  callbackForBookingId: string | null;
  /** The weekly series this booking is one week of, where it is. */
  recurringSeriesId: string | null;

  /** §1h. Every attempt, accepted or not — newest first. */
  amendments: BookingAmendmentDto[];
  /** Omitted from list responses; present on the detail read. */
  statusHistory?: BookingStatusEventDto[];
  /** Present only at `awaiting_payment`, and only for the customer. */
  paymentDetails?: PaymentDetailsDto;
  /** Present only on a provider-cancelled booking, and only for the customer. */
  replacement?: ReplacementPrefillDto;
  /**
   * §Phase 17.3. Present on the **detail** read of an emergency booking, for
   * either party. Absent from list responses and from every other mode.
   */
  emergency?: EmergencyDetailsDto;
}

// ---------------------------------------------------------------------------
// §Phase 17.3 — emergency dispatch
// ---------------------------------------------------------------------------

/**
 * One offer, as the customer compares it (§1c: "provider, tier, rating,
 * distance and callout fee", plus Round 22's arrival estimate).
 *
 * **No phone number, and no way to reach the provider** — an offer is a bid,
 * not an introduction. The provider's name is what the card shows.
 */
export interface EmergencyOfferDto {
  id: string;
  providerName: string;
  /** What `VerificationBadge` renders. Never a boolean "verified". */
  verificationTier: VerificationTier;
  /**
   * §Phase 11 builds reviews; until it does there is no rating to show, and
   * a number here would be invented. Null, and the card says so.
   */
  ratingAverage: number | null;
  calloutFeeLaari: number;
  /** The provider's own estimate — "part of what you're accepting", never a platform promise. */
  etaMinutes: number;
  state: EmergencyOfferState;
  createdAt: string;
}

/**
 * Where an emergency request is, from the screen's point of view. Derived from
 * the request's status and stored clocks, so the app never works out a phase
 * from timestamps of its own.
 *
 *  - `waiting` — broadcast, nobody has answered yet this round
 *  - `collecting` — the first answer opened the 90-second window
 *  - `choosing` — the window closed; up to three offers, five minutes to pick
 *  - `matched` — an offer was selected; its booking is live
 *  - `closed` — the request ended without a match
 */
export type EmergencyPhase = 'waiting' | 'collecting' | 'choosing' | 'matched' | 'closed';

/**
 * Whether `POST /v1/bookings/:id/reveal-contact` would answer right now, and
 * if not, why — without returning a number. `Reveal Contact.dc.html` renders
 * one state per value, including the kill switch's "Number sharing is paused
 * right now".
 */
export type ContactRevealState =
  /** Not an emergency, or not yet accepted. The control does not render. */
  | 'not_available'
  /** The customer may start it. For the provider: waiting on the customer. */
  | 'available'
  /** Started; either party's call returns both numbers. */
  | 'revealed'
  /** 24 hours past a terminal state. The endpoint returns nothing. */
  | 'expired'
  /** §Phase 10b's kill switch is engaged. Checked before everything else. */
  | 'paused';

export interface EmergencyDispatchFeeDto {
  submissionId: string;
  amountLaari: number;
  referenceCode: string;
  /** `owed` and `rejected` block new bookings; `waived` never does (§0.0 item 24). */
  state: 'owed' | 'submitted' | 'confirmed' | 'rejected' | 'waived';
}

/**
 * One emergency request as its **customer** sees it — `Emergency Flow.dc.html`
 * from the tap to the match. `GET /v1/emergency-requests/:id`.
 *
 * Every clock is the server's: the overall window is the category's
 * `emergencyAcceptWindowMinutes` (never a literal), and the collection and
 * choice deadlines are stamped when they begin.
 */
export interface EmergencyRequestDto {
  id: string;
  status: 'requested' | 'emergency_offered' | 'matched' | 'declined' | 'cancelled';
  phase: EmergencyPhase;
  categoryId: string;
  categoryName: string;
  /** The category's bar — "Goes to every Gold-verified Plumbing provider". */
  minimumTier: VerificationTier | null;
  /** The category's answer window, for the copy that states it. */
  windowMinutes: number | null;
  islandId: string;
  /** §0.0 item 12's convention: `Dh. Meedhoo` or `Kulhudhuffushi`. */
  islandDisplayName: string;
  jobNotes: string;
  addressDetail: string | null;
  windowEndsAt: string;
  collectionClosesAt: string | null;
  choiceEndsAt: string | null;
  /** How many providers the request reaches right now — "Sent to 4 providers". */
  broadcastCount: number;
  /** Every answer this round, shown during collection ("2 providers have answered"). */
  offersReceived: number;
  /**
   * The offers the customer chooses between — **at most three**, and only once
   * the collection window has closed (§1c). Ranked cheapest first, then the
   * soonest arrival estimate; see `emergency.ts`'s `shownOffers`.
   */
  offers: EmergencyOfferDto[];
  /** The live booking once an offer is selected. */
  bookingId: string | null;
  /** The fee, once incurred. */
  dispatchFee: EmergencyDispatchFeeDto | null;
  createdAt: string;
}

/**
 * The `emergency` block on an emergency **booking's** detail read, for either
 * party.
 */
export interface EmergencyDetailsDto {
  /** The request this booking was dispatched from. */
  requestId: string | null;
  /** The chosen provider's own arrival estimate — "their estimate", never a guarantee. */
  etaMinutes: number | null;
  /** To the customer only: the MVR 200 fee and whether it still blocks. */
  dispatchFee: EmergencyDispatchFeeDto | null;
  /**
   * When "provider has not arrived" becomes available — the category's answer
   * window after selection (Round 15). Null where it cannot be used.
   */
  notArrivedAvailableAt: string | null;
  contactReveal: ContactRevealState;
}

/**
 * An open emergency as a **broadcast recipient** sees it — `Provider
 * Emergency.dc.html` before the provider has been chosen.
 *
 * §1c step 2's accept prompt: "job details and the customer's name only,
 * **no contact details of any kind**". The exact address is withheld too:
 * the artboard says "Exact address is shared if the customer picks you",
 * and at that point there is a booking and its ordinary detail read carries it.
 */
export interface EmergencyBroadcastDto {
  requestId: string;
  categoryName: string;
  customerFirstName: string;
  jobNotes: string | null;
  islandDisplayName: string | null;
  createdAt: string;
  windowEndsAt: string;
  collectionClosesAt: string | null;
  choiceEndsAt: string | null;
  etaPresetsMinutes: number[];
  /**
   * What happened to this provider's own offer, if they made one — so the
   * unselected are "released immediately rather than left on a spinner" and
   * the chosen one lands on their new booking.
   */
  myOffer: {
    id: string;
    state: EmergencyOfferState;
    calloutFeeLaari: number;
    etaMinutes: number;
    /** Set once this offer was chosen: the booking the provider now has. */
    bookingId: string | null;
    createdAt: string;
  } | null;
  /** This provider passed on it. Recorded, never counted (owner, 2026-09-28). */
  passed: boolean;
  /** True while this provider may still send an offer. */
  canOffer: boolean;
}

/**
 * `POST /v1/bookings/:id/reveal-contact` — **the only response shape in this
 * system that carries a phone number** (§1c). Both numbers, or an error and
 * neither: "Both parties see each other's number, or neither does."
 *
 * No WhatsApp or Viber handle, here or anywhere — §Phase 5 collects neither.
 */
export interface ContactRevealDto {
  bookingId: string;
  customer: { name: string; phone: string };
  provider: {
    name: string;
    phone: string;
    /**
     * Round 11: "the reveal UI states that the number was confirmed at
     * verification, never that it is 'verified' as a live property." The
     * tier is what lets the screen say so truthfully.
     */
    verificationTier: VerificationTier;
  };
  /** When the customer started it — the moment the provider was told. */
  revealedAt: string;
  /** 24 hours after the booking went terminal; null while it is still live. */
  expiresAt: string | null;
}

// ---------------------------------------------------------------------------
// §Phase 17.4 — callback, Book Again, recurring series
// ---------------------------------------------------------------------------

/**
 * §1h: "A provider commits to return free within 7 days if the same issue
 * recurs." Derived on every read from the booking's snapshot and its
 * completion, so no stored flag can disagree with the clock.
 */
export interface BookingCallbackDto {
  /** The listing offered the guarantee when this booking was made. The badge. */
  guaranteed: boolean;
  /** Seven days after completion; null until completed, or where not guaranteed. */
  claimableUntil: string | null;
  /** The callback booking already claimed against this one. */
  claimBookingId: string | null;
  /** All of: guaranteed, completed, inside the window, not yet claimed. */
  canClaim: boolean;
}

/**
 * `GET /v1/bookings/:id/book-again` — `Book Again.dc.html`.
 *
 * §Phase 17 frontend item 13: "pre-fills a new booking request against the
 * same provider and listing, **routed by that listing's current
 * `bookingMode`**". So `bookingMode` here is the listing's mode *now*, and
 * `modeChanged` is what draws the artboard's "Since your last booking,
 * Mariyam switched from open slots to requests" note.
 *
 * §1h: "Book Again carries the saved preferences forward" — the address from
 * the job it repeats, and the customer's standing instructions and first
 * preferred window from Saved Preferences.
 */
export interface BookAgainDto {
  fromBookingId: string;
  listingId: string;
  listingName: string | null;
  categoryName: string | null;
  providerName: string;
  /** What `VerificationBadge` renders beside the name. Never a boolean "verified". */
  providerVerificationTier: VerificationTier;
  /** False when the listing is no longer bookable — the artboard's "no longer offered" state. */
  available: boolean;
  /** The listing's mode now. Null only when `available` is false. */
  bookingMode: 'slot' | 'request' | null;
  modeChanged: boolean;
  /** What the listing advertises now, for the "Service" row. */
  pricingModel: string | null;
  priceLaari: number | null;
  lastDoneAt: string | null;
  jobNotes: string | null;
  islandId: string | null;
  islandDisplayName: string | null;
  addressDetail: string | null;
  occasion: string | null;
  standingInstructions: string | null;
  /** The customer's first saved window's label — "Tuesday afternoons". */
  preferredWindowLabel: string | null;
}

export type RecurringSeriesStatusDto = 'active' | 'paused' | 'ended';

export interface RecurringOccurrenceDto {
  id: string;
  occursAt: string;
  state: 'asked' | 'accepted' | 'missed' | 'skipped' | 'withdrawn';
  /**
   * 🔧 `could_not_ask` is no longer written — it was split into
   * `provider_unavailable` and `customer_blocked` — but stays in the type for
   * rows made before the split.
   */
  missReason:
    | 'declined'
    | 'timed_out'
    | 'no_open_slot'
    | 'could_not_ask'
    | 'provider_unavailable'
    | 'customer_blocked'
    | null;
  bookingId: string | null;
  bookingStatus: BookingStatus | null;
}

/**
 * One series — `Recurring Booking.dc.html`'s "Tuesdays · 14:00" screen.
 *
 * `nextOccurrenceAt` is the week that has not been asked for yet (the
 * artboard's "The ask goes out on Tue 8 Sep"); it is skippable ahead of time.
 */
export interface RecurringSeriesDto {
  id: string;
  status: RecurringSeriesStatusDto;
  listingId: string;
  listingName: string | null;
  customer: BookingPartyDto;
  provider: BookingPartyDto;
  /** The origin booking's slot length; null where it no longer sits on a slot. */
  durationMinutes: number | null;
  /** What one visit costs at the listing's price now — "MVR 450 a visit". */
  pricePerVisitLaari: number | null;
  nextOccurrenceAt: string | null;
  nextAskAt: string | null;
  /** True when the next week has already been skipped by the customer. */
  nextOccurrenceSkipped: boolean;
  consecutiveMisses: number;
  pausedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  /**
   * Whose the three misses that paused the series were; null unless paused.
   * `provider` only when all three were the provider's — the app names the
   * provider in the paused banner on that value and no other.
   */
  pauseCause: RecurringPauseCauseDto | null;
  /** The most recent weeks, newest last. */
  occurrences: RecurringOccurrenceDto[];
}

export type RecurringPauseCauseDto = 'provider' | 'customer' | 'mixed';
