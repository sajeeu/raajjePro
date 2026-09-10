import { describe, expect, it } from 'vitest';

import type { AppError } from '../src/core/errors.js';
import {
  forcedResumeDueAt,
  pause,
  pauseDays,
  remainingPauseMinutes,
  resume,
  type PauseSnapshot,
} from '../src/modules/subscriptions/pause.js';
import {
  PAUSE_ALLOWANCE_DAYS,
  PAUSE_ALLOWANCE_MINUTES,
  addDays,
  addMinutes,
} from '../src/modules/subscriptions/period.js';

/**
 * §1b's pause, asserted as a rule rather than through the database.
 *
 * The plan's requirement is "**one function, one cap, one resume rule, shared
 * by `trialing` and `active`** … applied identically regardless of state", so
 * the central assertion here is a *comparison*: the same sequence run from a
 * trial and from a paid period produces the same patch, field for field.
 * `test/phase8a-done-when.test.ts` runs the same rule over HTTP.
 */

const T0 = new Date('2026-09-10T08:00:00.000Z');

function trialing(overrides: Partial<PauseSnapshot> = {}): PauseSnapshot {
  return {
    status: 'trialing',
    tier: 'premium',
    pausedAt: null,
    cumulativePausedMinutes: 0,
    trialEndsAt: addDays(T0, 20),
    currentPeriodEnd: null,
    billingAnchorAt: null,
    ...overrides,
  };
}

function active(overrides: Partial<PauseSnapshot> = {}): PauseSnapshot {
  return {
    status: 'active',
    tier: 'premium',
    pausedAt: null,
    cumulativePausedMinutes: 0,
    trialEndsAt: null,
    currentPeriodEnd: addDays(T0, 20),
    billingAnchorAt: addDays(T0, -10),
    ...overrides,
  };
}

describe('§1b pause — one function, shared by trialing and active', () => {
  it('shifts every clock it has by the paused duration, in both states', () => {
    // §1b: "**pausing shifts the anchor by the paused duration**" and
    // resuming "preserves the remaining paused allowance for later use".
    const fourDays = 4 * 24 * 60;

    const trialPaused = pause(trialing(), T0);
    const trialResumed = resume({ ...trialing(), ...trialPaused.patch }, addMinutes(T0, fourDays));
    expect(trialResumed.patch.trialEndsAt).toEqual(addDays(T0, 24));
    expect(trialResumed.patch.status).toBe('trialing');

    const paidPaused = pause(active(), T0);
    const paidResumed = resume({ ...active(), ...paidPaused.patch }, addMinutes(T0, fourDays));
    expect(paidResumed.patch.currentPeriodEnd).toEqual(addDays(T0, 24));
    // The anchor moves by exactly the same four days — the clause that makes
    // "billing anchor, not calendar month" coherent with pause at all.
    expect(paidResumed.patch.billingAnchorAt).toEqual(addDays(T0, -6));
    expect(paidResumed.patch.status).toBe('active');

    // Identical, field for field, on everything the two states share.
    expect(trialResumed.spentMinutes).toBe(paidResumed.spentMinutes);
    expect(trialResumed.patch.cumulativePausedMinutes).toBe(
      paidResumed.patch.cumulativePausedMinutes,
    );
    expect(trialResumed.patch.pausedAt).toBeNull();
  });

  it('never touches the tier — a pause is not a downgrade', () => {
    // §1b's downgrade is a separate mechanism with its own trigger. And the
    // badge is untouched by any of it (§1e), which is why `pause` has no
    // access to a verification field at all.
    expect(pause(active(), T0).patch).not.toHaveProperty('tier');
    expect(
      resume({ ...active(), status: 'paused', pausedAt: T0 }, addDays(T0, 1)).patch,
    ).not.toHaveProperty('tier');
  });

  it('spends one 10-day budget across several pauses and then refuses', () => {
    // "Capped at **10 cumulative days**. Resuming manually within the cap
    // preserves the remaining paused allowance for later use." A budget, not
    // a per-pause limit.
    let row: PauseSnapshot = active();
    for (const days of [4, 4]) {
      const paused = pause(row, T0);
      row = { ...row, ...paused.patch, pausedAt: T0 };
      const resumed = resume(row, addDays(T0, days));
      row = { ...row, ...resumed.patch };
    }
    expect(pauseDays(row)).toEqual({
      cumulativePausedDays: 8,
      remainingPauseAllowanceDays: 2,
    });

    // The ninth and tenth days are still available…
    const third = pause(row, T0);
    expect(third.changed).toBe(true);
    row = { ...row, ...third.patch, pausedAt: T0 };
    row = { ...row, ...resume(row, addDays(T0, 2)).patch };
    expect(remainingPauseMinutes(row)).toBe(0);

    // …and the eleventh is not.
    let refusal: AppError | null = null;
    try {
      pause(row, T0);
    } catch (error) {
      refusal = error as AppError;
    }
    expect(refusal?.code).toBe('PAUSE_ALLOWANCE_EXHAUSTED');
    expect(refusal?.details).toEqual({
      cumulativePausedDays: PAUSE_ALLOWANCE_DAYS,
      remainingPauseAllowanceDays: 0,
    });
  });

  it('counts a sub-day pause against the budget', () => {
    // 🔧 The reason `cumulativePausedMinutes` is minutes where §Phase 8a's
    // field list says days: a whole-day counter rounds a 23-hour pause to
    // zero, so a provider could pause for 23 hours, resume, and repeat
    // forever. That is not a rounding nicety, it is a hole in the cap.
    let row: PauseSnapshot = { ...active(), status: 'paused', pausedAt: T0 };
    for (let i = 0; i < 11; i++) {
      const resumed = resume(row, addMinutes(T0, 23 * 60));
      row = { ...row, ...resumed.patch, status: 'paused', pausedAt: T0 };
    }
    // Eleven 23-hour pauses is 10.5 days of wall clock; the budget stops it
    // at ten, and the last resume spends only what was left.
    expect(row.cumulativePausedMinutes).toBe(PAUSE_ALLOWANCE_MINUTES);
  });

  it('forces the clock to resume at the cap, shifting by the allowed duration only', () => {
    // §1b: "at the cap, pause auto-ends and the clock forcibly resumes."
    // The pause ended at the cap whether or not anything was watching, so a
    // sweep that notices two days late still shifts by ten days — not twelve.
    const row: PauseSnapshot = { ...active(), status: 'paused', pausedAt: T0 };
    expect(forcedResumeDueAt(row)).toEqual(addDays(T0, PAUSE_ALLOWANCE_DAYS));

    const late = resume(row, addDays(T0, 12));
    expect(late.spentMinutes).toBe(PAUSE_ALLOWANCE_MINUTES);
    expect(late.patch.currentPeriodEnd).toEqual(addDays(T0, 30));
    expect(late.patch.billingAnchorAt).toEqual(addDays(T0, 0));
  });

  it('resumes into whichever clock still has time on it', () => {
    // One derivation for both states, which is what makes the mechanism
    // genuinely shared rather than two branches that happen to agree.
    const fromTrial = resume({ ...trialing(), status: 'paused', pausedAt: T0 }, addDays(T0, 3));
    expect(fromTrial.patch.status).toBe('trialing');

    // A trial that ran out during a forced pause lands in `expired`, where
    // §1b's seven days of grace start — not straight on the free tier.
    const overrun = resume(
      {
        ...trialing({ trialEndsAt: addDays(T0, 5) }),
        status: 'paused',
        pausedAt: T0,
        cumulativePausedMinutes: PAUSE_ALLOWANCE_MINUTES - 60,
      },
      addDays(T0, 30),
    );
    expect(overrun.patch.status).toBe('expired');
  });

  it('is idempotent in both directions', () => {
    // §1b keys pause off a toggle, and a toggle can be set to the value it
    // already holds — a replayed request on a weak connection, or a provider
    // tapping twice. Neither may spend allowance or throw.
    expect(pause({ ...active(), status: 'paused', pausedAt: T0 }, T0).changed).toBe(false);
    expect(resume(active(), T0).changed).toBe(false);
  });

  it('refuses to pause what is not running', () => {
    // `free` has no clock; `expired` is already counting down §1b's grace
    // period, and pausing that would silently extend the seven days "with
    // nothing changing" into something else.
    for (const status of ['free', 'expired'] as const) {
      let code: string | null = null;
      try {
        pause({ ...active(), status }, T0);
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).toBe('SUBSCRIPTION_NOT_PAUSABLE');
    }
  });
});
