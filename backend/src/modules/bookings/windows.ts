/**
 * Every clock §Phase 17.1 runs on, in one file with the line of the plan that
 * sets it.
 *
 * ## The rule about hardcoding, and what it actually forbids
 *
 * Root `CLAUDE.md` and this slice's own brief say never to hardcode 30
 * minutes, 24 hours or 72 hours. Those three are **per-category** values and
 * are read from the `Category` row — `emergencyAcceptWindowMinutes` (§Phase
 * 17.3), `quoteExpiryMinutes` and `quoteApprovalMinutes` (§Phase 17.2). None
 * of them appears in this file and none of them may.
 *
 * What is here is the set §1c states **flat, for every category**: the
 * slot/request accept window, the provider's silence window on a payment
 * claim, and the two halves of the completion timeout. No `Category` column
 * holds any of them, no section of the plan varies them by category, and
 * inventing three columns so they could vary would be configuration nobody
 * asked for. They are constants with their citation beside them, in one place,
 * so a later change is one edit rather than a search.
 */

/**
 * §1c step 4: "**Slot and request-based: 24 hours** → auto-decline, release
 * the slot or reservation, notify the customer to look elsewhere."
 *
 * 🔧 Not the emergency window. That is 30 minutes for all four capable
 * categories (Round 22) and is read from `Category.emergencyAcceptWindowMinutes`
 * by §Phase 17.3 — never from here, and never as a literal.
 */
export const ACCEPT_WINDOW_MINUTES = 24 * 60;

/**
 * §1c step 9: "If the provider neither confirms nor disputes **within 7
 * days** → `payment_unresolved`, not `confirmed`."
 */
export const PAYMENT_SILENCE_DAYS = 7;

/**
 * §1c step 10: "If the provider doesn't mark the job complete **within 7 days
 * of `scheduledFor`**, the customer is prompted."
 */
export const COMPLETION_PROMPT_AFTER_DAYS = 7;

/**
 * §1c step 10: "**No response after a further 3-day grace** → auto-completes,
 * tagged `completedVia: 'unconfirmed'`."
 *
 * Measured from the prompt, not from `scheduledFor` — a prompt that fired late
 * must not hand the customer a shorter window than the plan gives them.
 */
export const COMPLETION_GRACE_DAYS = 3;

export function minutesFrom(at: Date, minutes: number): Date {
  return new Date(at.getTime() + minutes * 60_000);
}

export function daysBefore(at: Date, days: number): Date {
  return new Date(at.getTime() - days * 24 * 60 * 60_000);
}

// -- §Phase 17.3's flat emergency numbers --------------------------------------
//
// The same rule as the constants above: these are stated **flat, for every
// emergency category**, and no `Category` column holds them. The per-category
// emergency numbers — the 30-minute answer window, the tier bar, the arrival
// presets — are read from the row and appear nowhere in this file.

/**
 * §1c, Round 15: "the first acceptance opens a **90-second collection
 * window** during which every other eligible provider may also accept".
 */
export const OFFER_COLLECTION_SECONDS = 90;

/**
 * §1c: "the customer is shown **up to three offers** side by side".
 *
 * 🔧 A **display** cap, not an admission cap (owner's decision, 2026-09-28):
 * "every other eligible provider may also accept", and the customer is shown
 * the best three. `emergency.ts`'s `shownOffers` states the ranking.
 */
export const MAX_OFFERS_SHOWN = 3;

/**
 * §1c: "**Customer silence** → the offer expires after **5 minutes**,
 * releases the provider, and re-broadcasts", and §Phase 17 item 4 measures it
 * from the window closing: "a collection window whose customer has not
 * responded 5 minutes after it closes".
 */
export const OFFER_CHOICE_MINUTES = 5;

/**
 * §1c: "RaajjePro charges the **customer** MVR 200 (20000 laari) per emergency
 * dispatch." Integer laari (invariant 7).
 */
export const EMERGENCY_DISPATCH_FEE_LAARI = 20_000;

/**
 * §1c: "**Rate limit:** 3 emergency requests per customer per 24 hours, 10
 * per 7 days." Counted over *requests*: "rejections do not consume the
 * customer's rate limit. The limit applies to requests, not to offers within
 * one."
 */
export const EMERGENCY_REQUESTS_PER_DAY = 3;
export const EMERGENCY_REQUESTS_PER_WEEK = 10;

/**
 * §1c's sixth reveal condition: "The reveal **expires 24 hours after the
 * booking reaches a terminal state**, after which the endpoint returns nothing
 * for that booking."
 */
export const CONTACT_REVEAL_AFTER_TERMINAL_HOURS = 24;

export function secondsFrom(at: Date, seconds: number): Date {
  return new Date(at.getTime() + seconds * 1000);
}

// -- §Phase 17.4 -----------------------------------------------------------------
//
// Flat for every category, like the rest of this file. The per-category
// callback rule is **eligibility** (`Category.callbackEligible`, Round 28),
// never the length of the window.

/**
 * §1h: "A provider commits to **return free within 7 days** if the same issue
 * recurs." Measured from `completedAt` — the job has to have been done before
 * it can come back.
 */
export const CALLBACK_WINDOW_DAYS = 7;

/** §1c: "A `RecurringSeries` links a customer, provider, and listing to a **weekly** cadence." */
export const RECURRING_CADENCE_DAYS = 7;

/**
 * §1c: "**Three consecutive missed occurrences** pause the series and notify
 * the customer to reconfirm."
 */
export const RECURRING_PAUSE_AFTER_MISSES = 3;

export function daysFrom(at: Date, days: number): Date {
  return new Date(at.getTime() + days * 24 * 60 * 60_000);
}
