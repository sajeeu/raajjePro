/**
 * §1b's clock arithmetic — the billing anchor, the trial length, the grace
 * period and the pause budget. All of it in one file, all of it pure, so
 * every rule is testable by moving a `Date` rather than by waiting.
 *
 * 🔧 **The anchor is explicitly not a calendar month** (§1b, §0.5): "a
 * subscription bills every 30 days from an anchor date set at first confirmed
 * payment. **Pausing shifts the anchor by the paused duration.**" Calendar
 * billing and resume-remaining-time are incompatible — a provider who pauses
 * four days is no longer billed on the 1st — so nothing here reads a month,
 * a month boundary, or a day-of-month, and no copy anywhere may imply one.
 */

export const DAY_MS = 24 * 60 * 60 * 1000;

/** §1b's billing period: 30 days from the anchor, not a month. */
export const BILLING_PERIOD_DAYS = 30;

/**
 * §1b, Round 12: "Trial — full premium access, **30 calendar days**".
 *
 * §0.4 says 60. It is the older statement — §0.0 item 5 and §1b both say 30 —
 * and §0.0's precedence rule ("where §0.1–0.3 conflict with a later section,
 * the later section wins") settles it at 30.
 */
export const TRIAL_DAYS = 30;

/** §1b: "**Grace:** 7 days after expiry with nothing changing, then downgrade to free." */
export const GRACE_DAYS = 7;

/** §1b: "**Warning** 7 days before trial or subscription period end." */
export const ENDING_NOTICE_DAYS = 7;

/** §1b's third trial trigger fires 7 days after the provider's first published listing (§Phase 8a). */
export const PROACTIVE_TRIAL_PROMPT_DAYS = 7;

/** §1b's win-back notifications, "at 7 and 30 days post-downgrade". */
export const WINBACK_DAY_7 = 7;
export const WINBACK_DAY_30 = 30;

/**
 * §1b's pause cap — "capped at **10 cumulative days**" — held in minutes.
 *
 * 🔧 The unit is the deviation `ProviderSubscription.cumulativePausedMinutes`
 * explains: a whole-day counter lets a provider pause for 23 hours, resume,
 * and repeat indefinitely, because each pause rounds to zero days spent. One
 * budget, spent at whatever granularity the provider actually pauses at. The
 * API still speaks in days.
 */
export const PAUSE_ALLOWANCE_DAYS = 10;
export const PAUSE_ALLOWANCE_MINUTES = PAUSE_ALLOWANCE_DAYS * 24 * 60;

export function addDays(from: Date, days: number): Date {
  return new Date(from.getTime() + days * DAY_MS);
}

export function addMinutes(from: Date, minutes: number): Date {
  return new Date(from.getTime() + minutes * 60_000);
}

/** Whole minutes between two instants, floored — the unit the pause budget is spent in. */
export function minutesBetween(from: Date, to: Date): number {
  return Math.max(0, Math.floor((to.getTime() - from.getTime()) / 60_000));
}

/**
 * Where the next 30-day period ends when a payment is confirmed.
 *
 * From the later of the current period end and now, so that:
 *
 *  - a provider who pays **early** keeps the days they already paid for
 *    rather than losing the remainder of the period, and
 *  - a provider who pays **after lapsing** starts a full period from today
 *    rather than being billed for the weeks they were not subscribed.
 *
 * Both fall out of one `max`, which is why this is one function and not two
 * branches at the call site.
 */
export function nextPeriodEnd(currentPeriodEnd: Date | null, now: Date): Date {
  const from = currentPeriodEnd !== null && currentPeriodEnd > now ? currentPeriodEnd : now;
  return addDays(from, BILLING_PERIOD_DAYS);
}

/** The period a confirmed payment covers, for the invoice §1b step 6 generates. */
export function periodFor(currentPeriodEnd: Date | null, now: Date): { start: Date; end: Date } {
  const start = currentPeriodEnd !== null && currentPeriodEnd > now ? currentPeriodEnd : now;
  return { start, end: addDays(start, BILLING_PERIOD_DAYS) };
}

/** Days remaining, rounded up so a trial with four hours left reads "1 day" rather than "0". */
export function daysUntil(deadline: Date, now: Date): number {
  return Math.max(0, Math.ceil((deadline.getTime() - now.getTime()) / DAY_MS));
}
