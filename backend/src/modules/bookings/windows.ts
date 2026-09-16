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
