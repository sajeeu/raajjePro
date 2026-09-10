import { BusinessRuleError } from '../../core/errors.js';
import type { SubscriptionStatus, SubscriptionTier } from '../../generated/prisma/enums.js';
import {
  PAUSE_ALLOWANCE_DAYS,
  PAUSE_ALLOWANCE_MINUTES,
  addMinutes,
  minutesBetween,
} from './period.js';

/**
 * §1b's pause, written once.
 *
 * > **Pause:** capped at **10 cumulative days**. Resuming manually within the
 * > cap preserves the remaining paused allowance for later use. At the cap,
 * > pause auto-ends and the clock forcibly resumes. **The identical mechanism
 * > applies to the trial period** — one function, one cap, one resume rule,
 * > shared by `trialing` and `active`. Pause keys off the provider-level
 * > `acceptingNewCustomers` toggle (§Phase 5).
 *
 * "One function, one cap, one resume rule" is not a description of an
 * implementation choice — it is the requirement, and §Phase 8a repeats it
 * ("**pause logic shared between `trialing` and `active`** … applied
 * identically regardless of state"). So there is no `pauseTrial` and no
 * `pauseSubscription`, and nothing below branches on which of the two states
 * it was called in. The only place the state appears at all is in deciding
 * what to resume *into*, and that is one derivation for both.
 *
 * ## Pure on purpose
 *
 * Every function here takes a snapshot and returns a patch. The service
 * writes it, and the tests move a clock through a ten-day pause without a
 * database. The alternative — a method that reads, decides and writes — makes
 * "does a 23-hour pause spend any of the allowance?" a question you can only
 * answer by running the job.
 */

export interface PauseSnapshot {
  status: SubscriptionStatus;
  tier: SubscriptionTier;
  pausedAt: Date | null;
  cumulativePausedMinutes: number;
  trialEndsAt: Date | null;
  currentPeriodEnd: Date | null;
  billingAnchorAt: Date | null;
}

/** The columns a pause or resume writes. Nothing else is touched — in particular never `tier`. */
export interface PausePatch {
  status?: SubscriptionStatus;
  pausedAt?: Date | null;
  cumulativePausedMinutes?: number;
  trialEndsAt?: Date | null;
  currentPeriodEnd?: Date | null;
  billingAnchorAt?: Date | null;
}

export interface PauseOutcome {
  /** False when the call was a no-op — already paused, or not paused. */
  changed: boolean;
  patch: PausePatch;
  /** How much of the 10-day budget this resume actually spent. */
  spentMinutes: number;
}

/**
 * §1b's two pausable states, and the reason the list is short: pausing stops
 * a *running* clock. `free` has no clock, and `expired` is already counting
 * down §1b's grace period — pausing that would silently extend the seven days
 * "with nothing changing" into something else.
 */
const PAUSABLE: readonly SubscriptionStatus[] = ['trialing', 'active'];

export function remainingPauseMinutes(snapshot: { cumulativePausedMinutes: number }): number {
  return Math.max(0, PAUSE_ALLOWANCE_MINUTES - snapshot.cumulativePausedMinutes);
}

/**
 * The two day-counts the API and §Phase 10a's billing screen speak in
 * (§Phase 8a names both as fields).
 *
 * 🔧 Rounded in opposite directions **so neither number can overstate the
 * provider's position**: whatever is spent is rounded up, whatever is left is
 * rounded down. A 23-hour pause reads as one day used and nine left, rather
 * than zero used and ten left — which is the reading a whole-day counter gives
 * and the one that makes the cap unenforceable.
 */
export function pauseDays(snapshot: { cumulativePausedMinutes: number }): {
  cumulativePausedDays: number;
  remainingPauseAllowanceDays: number;
} {
  const minutesPerDay = 24 * 60;
  return {
    cumulativePausedDays: Math.ceil(snapshot.cumulativePausedMinutes / minutesPerDay),
    remainingPauseAllowanceDays: Math.floor(remainingPauseMinutes(snapshot) / minutesPerDay),
  };
}

/**
 * Start a pause.
 *
 * Idempotent: pausing an already-paused subscription is not an error, because
 * §1b keys pause off a toggle and a toggle can be set to the value it already
 * has (a replayed request on a weak connection, or a provider tapping twice).
 *
 * Refuses only two things, each with its own code so §Phase 10a's billing
 * screen can say which: there is nothing running to pause, or the ten days
 * are gone.
 */
export function pause(snapshot: PauseSnapshot, now: Date): PauseOutcome {
  if (snapshot.status === 'paused') return unchanged();
  if (!PAUSABLE.includes(snapshot.status)) {
    throw new BusinessRuleError(
      'SUBSCRIPTION_NOT_PAUSABLE',
      snapshot.status === 'free'
        ? 'There is no subscription or trial to pause'
        : 'A subscription can only be paused during a trial or a paid period',
      { status: snapshot.status },
    );
  }
  if (remainingPauseMinutes(snapshot) <= 0) {
    throw new BusinessRuleError(
      'PAUSE_ALLOWANCE_EXHAUSTED',
      `You have used all ${String(PAUSE_ALLOWANCE_DAYS)} days of pause on this subscription`,
      pauseDays(snapshot),
    );
  }
  return {
    changed: true,
    // `tier` is untouched: pausing is not a downgrade, and the badge is not
    // affected by any of this either (§1e).
    patch: { status: 'paused', pausedAt: now },
    spentMinutes: 0,
  };
}

/**
 * End a pause and shift the clock.
 *
 * §1b: "**pausing shifts the anchor by the paused duration**" and resuming
 * "preserves the remaining paused allowance for later use". So every deadline
 * the subscription carries moves forward by exactly what was spent — the trial
 * end, the period end and the billing anchor — and the allowance is a budget
 * that survives across pauses rather than a per-pause limit.
 *
 * **The forced resume at the cap is this same function.** `spent` is capped at
 * whatever is left of the ten days, so a pause the job notices late shifts the
 * clock by the *allowed* duration, not by however long the job took to get
 * there. Which is what "at the cap, pause auto-ends" has to mean: the pause
 * ended at the cap whether or not anything was watching.
 */
export function resume(snapshot: PauseSnapshot, now: Date): PauseOutcome {
  if (snapshot.status !== 'paused' || snapshot.pausedAt === null) return unchanged();

  const elapsed = minutesBetween(snapshot.pausedAt, now);
  const spent = Math.min(elapsed, remainingPauseMinutes(snapshot));

  const trialEndsAt = shift(snapshot.trialEndsAt, spent);
  const currentPeriodEnd = shift(snapshot.currentPeriodEnd, spent);

  return {
    changed: true,
    patch: {
      // One derivation for both pausable states, which is what makes the
      // mechanism genuinely shared: resume into whichever clock still has
      // time left on it after the shift, and into `expired` if neither does
      // — the grace period then runs from the lifecycle job as usual.
      status: statusAfterResume(trialEndsAt, currentPeriodEnd, now),
      pausedAt: null,
      cumulativePausedMinutes: snapshot.cumulativePausedMinutes + spent,
      trialEndsAt,
      currentPeriodEnd,
      billingAnchorAt: shift(snapshot.billingAnchorAt, spent),
    },
    spentMinutes: spent,
  };
}

/**
 * When the forced resume is due — `pausedAt` plus whatever was left of the
 * allowance. Null when this subscription is not paused, so the lifecycle job's
 * scan reads one field rather than repeating the arithmetic.
 */
export function forcedResumeDueAt(snapshot: PauseSnapshot): Date | null {
  if (snapshot.status !== 'paused' || snapshot.pausedAt === null) return null;
  return addMinutes(snapshot.pausedAt, remainingPauseMinutes(snapshot));
}

function statusAfterResume(
  trialEndsAt: Date | null,
  currentPeriodEnd: Date | null,
  now: Date,
): SubscriptionStatus {
  if (trialEndsAt !== null && trialEndsAt > now) return 'trialing';
  if (currentPeriodEnd !== null && currentPeriodEnd > now) return 'active';
  return 'expired';
}

function shift(date: Date | null, minutes: number): Date | null {
  return date === null ? null : addMinutes(date, minutes);
}

function unchanged(): PauseOutcome {
  return { changed: false, patch: {}, spentMinutes: 0 };
}
