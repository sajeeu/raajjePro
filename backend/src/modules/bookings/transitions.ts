import { BusinessRuleError } from '../../core/errors.js';
import type { BookingActorRole, BookingStatus } from '../../generated/prisma/enums.js';

/**
 * §1c's status machine, written once.
 *
 * ## Why a table rather than a chain of `if`s in the service
 *
 * §1c draws the machine as a diagram and then states six rules about it in
 * prose — three statuses that read terminal and are not, one edge that runs
 * *backwards* (Round 24's withdrawal), and three modes that each skip a
 * different part of it. Spread across nine endpoint handlers those rules
 * become nine half-copies, and the ninth is the one that lets a `completed`
 * booking be cancelled. Here every edge is one row, and an endpoint's whole
 * transition check is `assertTransition`.
 *
 * ## What is deliberately absent
 *
 * There is no edge into `awaiting_quote`, `quote_offered` or
 * `emergency_offered`. Those statuses exist (the enum is the machine's whole
 * vocabulary, §Phase 17's item 1) and §Phases 17.2 and 17.3 add the edges that
 * reach them. A slice adds rows to this table; it never adds a second table.
 */
export interface Edge {
  /** The machine's own name for this edge. Stored on every status event. */
  transition: string;
  from: readonly BookingStatus[];
  to: BookingStatus;
  /** Who may cause it. `system` means a scheduled job and nothing else. */
  actors: readonly BookingActorRole[];
}

/**
 * Every edge §Phase 17.1 builds.
 *
 * Read it as the diagram: creation lands at `requested`; the provider accepts
 * (which sets the amount, so `awaiting_payment` follows in the same
 * transaction) or declines; the customer pays off-platform and says so; the
 * provider confirms or disputes; the job completes. The two backwards edges
 * are Round 24's withdrawal and an admin resolving what a queue owns.
 */
export const EDGES: readonly Edge[] = [
  // -- Creation -------------------------------------------------------------
  {
    transition: 'create',
    from: [],
    to: 'requested',
    actors: ['customer'],
  },

  // -- The provider answers the accept prompt --------------------------------
  {
    transition: 'accept',
    from: ['requested'],
    to: 'accepted',
    actors: ['provider'],
  },
  {
    transition: 'decline',
    from: ['requested'],
    to: 'declined',
    actors: ['provider'],
  },
  /**
   * §1c step 4: "Slot and request-based: 24 hours → auto-decline, release the
   * slot or reservation, notify the customer to look elsewhere." Same status
   * as an explicit decline and a different actor — §1f counts explicit
   * responses in acceptance rate and timeouts in response rate, and the actor
   * is what tells them apart.
   */
  {
    transition: 'accept-timeout',
    from: ['requested'],
    to: 'declined',
    actors: ['system'],
  },

  // -- §1c step 3: no booking reaches awaiting_payment without an amount -----
  {
    transition: 'amount-set',
    from: ['accepted'],
    to: 'awaiting_payment',
    actors: ['provider', 'customer', 'system'],
  },

  // -- Payment attestation, both sides of it ---------------------------------
  {
    transition: 'claim-payment',
    from: ['awaiting_payment'],
    to: 'payment_claimed',
    actors: ['customer'],
  },
  /** Round 24. The one edge in the machine that runs backwards by design. */
  {
    transition: 'withdraw-payment-claim',
    from: ['payment_claimed'],
    to: 'awaiting_payment',
    actors: ['customer'],
  },
  {
    transition: 'confirm-payment-received',
    from: ['payment_claimed'],
    to: 'confirmed',
    actors: ['provider'],
  },
  /**
   * §1c step 9. Not `confirmed` — "an earlier revision auto-confirmed here,
   * recording an attestation that may never have happened."
   */
  {
    transition: 'payment-silence-timeout',
    from: ['payment_claimed'],
    to: 'payment_unresolved',
    actors: ['system'],
  },

  // -- Completion ------------------------------------------------------------
  {
    transition: 'complete',
    from: ['confirmed'],
    to: 'completed',
    actors: ['provider'],
  },
  /** §1c step 10, "Yes". A two-sided completion the provider never marked. */
  {
    transition: 'complete-customer-confirmed',
    from: ['confirmed'],
    to: 'completed',
    actors: ['customer'],
  },
  /**
   * §1c step 10, no response after the 3-day grace: `completedVia:
   * 'unconfirmed'`. "A provider must not be able to block reviews forever by
   * staying silent."
   */
  {
    transition: 'complete-unconfirmed',
    from: ['confirmed'],
    to: 'completed',
    actors: ['system'],
  },

  // -- Cancellation ----------------------------------------------------------
  /**
   * §Phase 17 item 15: "customer, pre-payment". The provider's own
   * cancellation is the separate edge below, because §1h's replacement rule
   * and §1f's cancellation rate both turn on which of the two it was.
   */
  {
    transition: 'cancel',
    from: ['requested', 'accepted', 'awaiting_payment'],
    to: 'cancelled',
    actors: ['customer'],
  },
  /**
   * §1h: "A confirmed provider cancelling is the moment a customer decides the
   * platform is unreliable. It must never dead-end." Allowed later than the
   * customer's own cancel, because a provider who cannot make it after the
   * customer has paid must still be able to say so — the alternative is a
   * no-show, which is worse for everyone.
   */
  {
    transition: 'provider-cancel',
    from: ['accepted', 'awaiting_payment', 'payment_claimed', 'confirmed'],
    to: 'cancelled',
    actors: ['provider'],
  },

  // -- Disputes --------------------------------------------------------------
  /**
   * §1c: "Either party may dispute." The provider's "Payment Not Received" is
   * this edge, and it is **not** decline — separate endpoints, separate
   * statuses, visually distinct in the UI.
   *
   * A late dispute is handled by `disputeLate` in the service rather than by
   * an edge: "a late dispute (post-`completed`) is accepted; the booking stays
   * completed and the dispute queues separately", so there is no transition to
   * make.
   */
  {
    transition: 'dispute',
    from: ['awaiting_payment', 'payment_claimed', 'confirmed', 'payment_unresolved'],
    to: 'disputed',
    actors: ['customer', 'provider'],
  },
  {
    transition: 'resolve-dispute',
    from: ['disputed'],
    to: 'dispute_resolved',
    actors: ['admin'],
  },
  /** §Phase 17 item 12: resolve-dispute "also resolves `payment_unresolved`". */
  {
    transition: 'resolve-unresolved-confirmed',
    from: ['payment_unresolved'],
    to: 'confirmed',
    actors: ['admin'],
  },
  {
    transition: 'resolve-unresolved-cancelled',
    from: ['payment_unresolved'],
    to: 'cancelled',
    actors: ['admin'],
  },
] as const;

/**
 * §1b's protected-listing rule, and the one place the list is written.
 *
 * §1b: "a listing with a booking in `accepted`, `awaiting_payment`,
 * `payment_claimed`, `payment_unresolved`, or `confirmed` status and a future
 * `scheduledFor` stays visible regardless of cap, until that booking reaches a
 * terminal state". §Phase 8a built the rule against a seam and named the
 * status list as this phase's to supply — `bookings.ts` in that module says
 * so explicitly.
 */
export const COMMITTED_STATUSES: readonly BookingStatus[] = [
  'accepted',
  'awaiting_payment',
  'payment_claimed',
  'payment_unresolved',
  'confirmed',
];

/**
 * A booking nobody is waiting on any more — §Phase 3's deletion pipeline
 * ("anonymisation executes automatically once non-terminal bookings
 * terminate") and §Phase 18's thread lock both read this.
 *
 * `payment_unresolved` and `disputed` are **not** here: §1c says both are
 * non-terminal and an admin resolves each. That is the whole reason this list
 * is written out rather than derived as "has no outgoing edge".
 */
export const TERMINAL_STATUSES: readonly BookingStatus[] = [
  'completed',
  'cancelled',
  'declined',
  'dispute_resolved',
];

export function isTerminal(status: BookingStatus): boolean {
  return TERMINAL_STATUSES.includes(status);
}

/**
 * Raised when an endpoint is called against a booking that is not in a state
 * the endpoint can act on — the replayed tap, the stale screen, the second
 * "I've Paid" after the provider already confirmed.
 *
 * 422 rather than 409, because the request is well-formed and the *rule* is
 * what refuses it; the code names the transition so the app can say which
 * action was too late rather than "something went wrong".
 */
export class IllegalTransitionError extends BusinessRuleError {
  constructor(transition: string, from: BookingStatus) {
    super(
      'BOOKING_TRANSITION_NOT_ALLOWED',
      `This booking cannot be ${describe(transition)} while it is ${from.replace(/_/g, ' ')}`,
      { transition, from },
    );
  }
}

/** Raised when the caller is on the wrong side of the booking for this edge. */
export class WrongActorError extends BusinessRuleError {
  constructor(transition: string, actor: BookingActorRole) {
    super('BOOKING_ACTOR_NOT_ALLOWED', `A ${actor} cannot ${describe(transition)} this booking`, {
      transition,
      actor,
    });
  }
}

/**
 * The single check every transition runs. Returns the edge so the caller
 * writes `to` from the table rather than restating it.
 *
 * Order matters: the actor is checked **after** the state, so a customer
 * tapping a provider's action on a booking that has also moved on is told the
 * more useful of the two truths.
 */
export function assertTransition(
  transition: string,
  from: BookingStatus,
  actor: BookingActorRole,
): Edge {
  const candidates = EDGES.filter((e) => e.transition === transition);
  if (candidates.length === 0) throw new Error(`no such transition: ${transition}`);

  const reachable = candidates.filter((e) => e.from.includes(from));
  if (reachable.length === 0) throw new IllegalTransitionError(transition, from);

  const edge = reachable.find((e) => e.actors.includes(actor));
  if (edge === undefined) throw new WrongActorError(transition, actor);
  return edge;
}

/** Turns an edge name into something readable inside an error message. */
function describe(transition: string): string {
  return transition.replace(/-/g, ' ');
}

/**
 * Every [BookingStatus] value, for the one place that has to validate a
 * client-supplied one: the Bookings tab's `?status=` filter.
 *
 * Written out rather than derived from the Prisma enum object so it is a
 * literal tuple Zod can build an enum from, and so a status added by a later
 * slice fails the type check here rather than silently becoming unfilterable.
 */
export const BOOKING_STATUSES = [
  'requested',
  'awaiting_quote',
  'quote_offered',
  'emergency_offered',
  'accepted',
  'awaiting_payment',
  'payment_claimed',
  'confirmed',
  'completed',
  'cancelled',
  'declined',
  'disputed',
  'dispute_resolved',
  'payment_unresolved',
] as const satisfies readonly BookingStatus[];
