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
 * Where an emergency is, from the screen's point of view. Derived from the
 * status and the stored clocks, so the app never works out a phase from
 * timestamps of its own.
 *
 *  - `waiting` — broadcast, nobody has answered yet this round
 *  - `collecting` — the first answer opened the 90-second window
 *  - `choosing` — the window closed; up to three offers, five minutes to pick
 *  - `matched` — an offer was selected; the job is on
 *  - `closed` — the request ended without a match, or the booking is over
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
  state: 'owed' | 'submitted' | 'confirmed' | 'rejected';
}

export interface EmergencyDetailsDto {
  phase: EmergencyPhase;
  /** The overall answer window — the category's `emergencyAcceptWindowMinutes`, never a literal. */
  windowEndsAt: string | null;
  /** When the current 90-second collection window closes. */
  collectionClosesAt: string | null;
  /** When the customer's five minutes to choose run out. */
  choiceEndsAt: string | null;
  /** How many answers this round, shown during collection ("2 providers have answered"). */
  offersReceived: number;
  /**
   * The offers themselves. **To the customer only**, and only once the
   * collection window has closed — §1c: "at the end of it the customer is
   * shown up to three offers". After selection, the selected one alone.
   */
  offers: EmergencyOfferDto[];
  /** Round 22's presets for this category, for the provider's accept screen. */
  etaPresetsMinutes: number[];
  /** The fee incurred on selection. To the customer only; null until then. */
  dispatchFee: EmergencyDispatchFeeDto | null;
  /**
   * When "provider has not arrived" becomes available — the category's
   * answer window after selection (Round 15). Null before selection.
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
 * and at that point the booking is theirs and the ordinary detail read
 * carries it.
 */
export interface EmergencyBroadcastDto {
  bookingId: string;
  categoryName: string;
  customerFirstName: string;
  jobNotes: string | null;
  islandDisplayName: string | null;
  createdAt: string;
  windowEndsAt: string | null;
  collectionClosesAt: string | null;
  choiceEndsAt: string | null;
  etaPresetsMinutes: number[];
  /**
   * What happened to this provider's own offer this round, if they made one —
   * so the unselected are "released immediately rather than left on a
   * spinner" and the chosen one knows the job is theirs.
   */
  myOffer: {
    id: string;
    state: EmergencyOfferState;
    calloutFeeLaari: number;
    etaMinutes: number;
    createdAt: string;
  } | null;
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
