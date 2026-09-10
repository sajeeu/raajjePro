import type { SubscriptionStatus } from '../../generated/prisma/enums.js';
import { TRIAL_DAYS, addDays } from './period.js';

/**
 * §1b's trial, and the one function every trigger goes through.
 *
 * > **Trial** — full premium access, 🔧 **30 calendar days** (Round 12 — was
 * > 60). **Starts on the first booking reaching `confirmed`, or on an explicit
 * > "Try Premium" request, whichever comes first** (§0.4).
 *
 * ## The triggers, after the 2026-09-10 correction
 *
 * **Two start a trial and one nudges toward the second** (§Phase 8a):
 *
 *  1. **A booking's transition into `confirmed`**, where it is this provider's
 *     first — hooked on the *transition*, not on one endpoint, so an admin
 *     resolving `payment_unresolved` to `confirmed` fires it too. Not
 *     reachable in this phase: there is no `Booking` until §Phase 17.1, so the
 *     hook is built, tested against a fake and left for 17.1 to call
 *     (`bookings.ts`, ledger row **P8A-2**).
 *  2. **`POST /v1/providers/me/subscription/start-trial`** — the explicit
 *     "Try Premium".
 *  3. **The 7-day prompt.** A job, 7 days after the provider's first published
 *     listing, if no booking has landed and no trial has started. 🔧 It
 *     **prompts and does not start**: a trial is one per account and
 *     non-renewable, and this fires precisely when no booking has landed, so
 *     starting it there would spend the provider's only trial when premium is
 *     worth least. It calls the notifier, never this file.
 *
 * ## One trial per account, forever
 *
 * `startTrial` "is a no-op if a trial has ever run for that account", which is
 * §1b's abuse prevention: "one trial per user account, **not tied to phone
 * number** — a provider who changes phone keeps their remaining trial". The
 * check is `trialStartedAt !== null` on a column nothing ever clears, so a
 * trial that started, ended and downgraded still blocks a second one. Keying
 * it on a phone number would also be keying it on a value nothing verifies
 * (§1c) and that a provider may legitimately change.
 */

/** Why a trial started. Recorded in the audit entry, not as a column — the log already answers "how did this happen?". */
export type TrialTrigger = 'explicit_request' | 'first_confirmed_booking';

export interface TrialStartResult {
  started: boolean;
  /** Why not, when it did not. `already_used` covers a trial that is running *and* one long finished. */
  reason?: 'already_used' | 'paid_subscription_active';
  trialEndsAt?: Date;
}

/** The row shape `startTrial` decides against — enough to answer "has a trial ever run?" and "is this provider paying?". */
export interface TrialCandidate {
  trialStartedAt: Date | null;
  /** Null where the provider has no subscription row at all, which is most of them. */
  status: SubscriptionStatus | null;
}

/**
 * Decides, without writing. The service performs the write, so this stays
 * assertable by passing a row in and reading a decision out.
 */
export function decideTrialStart(candidate: TrialCandidate, now: Date): TrialStartResult {
  if (candidate.trialStartedAt !== null) return { started: false, reason: 'already_used' };
  // A provider who is already paying does not need a trial, and giving them
  // one would hand a paying customer 30 free days and consume the trial they
  // never used. §1b never contemplates the case because the trial is meant to
  // precede payment; the honest answer is to decline and say why.
  if (candidate.status === 'active' || candidate.status === 'paused') {
    return { started: false, reason: 'paid_subscription_active' };
  }
  return { started: true, trialEndsAt: addDays(now, TRIAL_DAYS) };
}
