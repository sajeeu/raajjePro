import type { BookingStatus } from '../../generated/prisma/enums.js';
import { isTerminal } from './transitions.js';

/**
 * When the `booking`-type thread is open, and who says so.
 *
 * ## The division of labour, from §Phase 17.2's Done-when
 *
 * "the `booking`-type chat **opens at `quote_offered`**, not at `accepted`
 * (§0.0 item 7) — **17.2 owns the state, §Phase 18 owns the thread**." So this
 * file computes the state and §Phase 18 reads it to decide whether a send is
 * allowed; there is no `Conversation` row here and nothing here sends a
 * message.
 *
 * ## Why it is derived and not a stamped column
 *
 * Every input is already on the booking — the status, `quoteOfferedAt`,
 * `amountSetAt` and `completedAt`. A `chatOpenedAt` column would be a second
 * copy of a fact those already carry, and the two could then disagree. This is
 * the posture §1a takes for provider visibility: derived by one shared helper
 * that every consumer calls, never stored.
 */
export type BookingChatState =
  /** No thread yet. §1c step 2's accept prompt is "job details and the customer's name only, and **no chat yet**". */
  | 'not_open'
  /** Open to both parties. */
  | 'open'
  /** Round 27: the history stays readable and takes no new messages. */
  | 'locked';

/**
 * Round 27, §1c: the thread "stays open for the life of the booking and **for
 * 7 days after completion — the callback-guarantee window — then locks
 * read-only**".
 */
export const CHAT_LOCK_AFTER_COMPLETION_DAYS = 7;

/** What this helper needs off a booking. Nothing else, and nothing that could carry a phone number. */
export interface ChatStateInput {
  status: BookingStatus;
  /** §Phase 17.2 stamps this when a quote is sent — the request path's opening door. */
  quoteOfferedAt: Date | null;
  /** Stamped at `accepted` — the slot and emergency paths' opening door. */
  amountSetAt: Date | null;
  completedAt: Date | null;
}

/**
 * The one place the rule is written.
 *
 * Two doors open the thread, and which applies is the path the booking took
 * rather than its mode:
 *  - **a quote was offered** (`quoteOfferedAt`) — §0.0 item 7 and §1c's
 *    request-based flow: "the `booking`-type chat opens the moment a quote is
 *    offered, not at `accepted`. This is the one window where negotiation is
 *    most likely to be needed." `Propose Time and Price.dc.html` states it to
 *    the provider as they send: "Sending opens the chat with Mariyam right
 *    away."
 *  - **the booking was accepted** (`amountSetAt`) — §1c, unchanged, and the
 *    only door a `slot` or `emergency` booking has.
 *
 * Reading the two stamps rather than the status is what lets a *terminal*
 * booking be answered correctly: a request cancelled at `awaiting_quote` never
 * had a thread, and one cancelled after a quote did, and both are `cancelled`.
 */
export function bookingChatState(booking: ChatStateInput, now: Date): BookingChatState {
  const opened = booking.quoteOfferedAt !== null || booking.amountSetAt !== null;
  if (!opened) return 'not_open';

  const { status } = booking;

  // §1c: "a dispute reopens the thread until resolved", and §Phase 18:
  // "`payment_unresolved` is non-terminal and never locks".
  if (status === 'disputed' || status === 'payment_unresolved') return 'open';

  // Round 27's tail. A completion with no stamp is not a thing the machine
  // produces, and treating it as still-open is the safe way to be wrong.
  if (status === 'completed') {
    if (booking.completedAt === null) return 'open';
    const locksAt =
      booking.completedAt.getTime() + CHAT_LOCK_AFTER_COMPLETION_DAYS * 24 * 60 * 60_000;
    return now.getTime() >= locksAt ? 'locked' : 'open';
  }

  // Every other ending — cancelled, declined, a resolved dispute. History
  // stays readable (§Phase 18 renders it) and no new message is accepted.
  return isTerminal(status) ? 'locked' : 'open';
}
