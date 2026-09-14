import { describe, expect, it } from 'vitest';

import { maldivesDateOf } from '../src/core/maldives-time.js';
import { expandSlots, SLOT_WINDOW_DAYS, windowEnd } from '../src/modules/availability/generator.js';

/**
 * The availability model as a pure function — §Phase 9a's rules, exceptions
 * and time off in, bookable instants out.
 *
 * Tested without a database because this is where the calendar reasoning
 * lives, and the awkward cases (a window that does not divide evenly, an
 * exception starting mid-week, a trip swallowing a working day) are the ones
 * a fixture-heavy test would be least likely to cover.
 */

/** Monday 14 September 2026, 08:00 in Malé. */
const NOW = new Date('2026-09-14T03:00:00Z');
const MON_TO_THU = [1, 2, 3, 4];

function times(slots: { startsAt: Date; endsAt: Date }[], onDate: string): string[] {
  return slots
    .filter((s) => maldivesDateOf(s.startsAt) === onDate)
    .map(
      (s) =>
        `${s.startsAt.toISOString().slice(11, 16)}–${s.endsAt.toISOString().slice(11, 16)} UTC`,
    );
}

const base = {
  rules: [{ weekdays: MON_TO_THU, startTime: '09:00', endTime: '17:00', slotDurationMinutes: 120 }],
  exceptions: [],
  timeOff: [],
  from: '2026-09-14',
  days: 7,
  notBefore: NOW,
};

describe('expanding availability rules', () => {
  it('lays slots end to end from the start of the window', () => {
    const slots = expandSlots(base);
    // 09:00–17:00 at two hours each, in Malé — 04:00Z through 12:00Z.
    expect(times(slots, '2026-09-14')).toEqual([
      '04:00–06:00 UTC',
      '06:00–08:00 UTC',
      '08:00–10:00 UTC',
      '10:00–12:00 UTC',
    ]);
  });

  it('does not publish a trailing remainder as a short visit', () => {
    // 09:00–17:00 is eight hours; at three hours each that is 09:00 and
    // 12:00, and the two hours left at 15:00 are NOT a short visit — a
    // customer must never be sold two thirds of a job.
    const slots = expandSlots({
      ...base,
      rules: [
        { weekdays: MON_TO_THU, startTime: '09:00', endTime: '17:00', slotDurationMinutes: 180 },
      ],
    });
    expect(times(slots, '2026-09-14')).toEqual(['04:00–07:00 UTC', '07:00–10:00 UTC']);
  });

  it('publishes nothing on a weekday the rule does not name', () => {
    // Friday 18 and Saturday 19 September are outside Mon–Thu.
    const slots = expandSlots(base);
    expect(times(slots, '2026-09-18')).toEqual([]);
    expect(times(slots, '2026-09-19')).toEqual([]);
    expect(times(slots, '2026-09-17')).toHaveLength(4);
  });

  it('never produces a time at or before `notBefore` — generation only writes the future', () => {
    // 11:00 in Malé on the first day: the 09:00 slot is already gone.
    const midMorning = new Date('2026-09-14T06:00:00Z');
    const slots = expandSlots({ ...base, notBefore: midMorning });
    expect(times(slots, '2026-09-14')).toEqual(['08:00–10:00 UTC', '10:00–12:00 UTC']);
    // Tomorrow is untouched by where today's clock happens to be.
    expect(times(slots, '2026-09-15')).toHaveLength(4);
  });

  it('returns nothing at all when there are no rules', () => {
    expect(expandSlots({ ...base, rules: [] })).toEqual([]);
  });

  it('is deterministic and ordered, so reconciliation can compare sets', () => {
    const once = expandSlots(base).map((s) => s.startsAt.getTime());
    const twice = expandSlots(base).map((s) => s.startsAt.getTime());
    expect(once).toEqual(twice);
    expect([...once].sort((a, b) => a - b)).toEqual(once);
  });
});

describe('an exception modifies hours; it never creates a working day', () => {
  const ramadan = {
    startDate: '2026-09-15',
    endDate: '2026-09-16',
    startTime: '09:00',
    endTime: '13:00',
    slotDurationMinutes: null,
  };

  it('replaces the window on a day the rules already work', () => {
    const slots = expandSlots({ ...base, exceptions: [ramadan] });
    expect(times(slots, '2026-09-15')).toEqual(['04:00–06:00 UTC', '06:00–08:00 UTC']);
  });

  it('leaves days outside its range alone', () => {
    const slots = expandSlots({ ...base, exceptions: [ramadan] });
    expect(times(slots, '2026-09-14')).toHaveLength(4);
    expect(times(slots, '2026-09-17')).toHaveLength(4);
  });

  it('does not add a Friday the weekly rules never worked', () => {
    // The whole point of "modifies, never creates": otherwise "Ramadan hours"
    // would quietly extend a Sunday-to-Thursday week onto Friday.
    const slots = expandSlots({
      ...base,
      exceptions: [{ ...ramadan, startDate: '2026-09-14', endDate: '2026-09-20' }],
    });
    expect(times(slots, '2026-09-18')).toEqual([]);
  });

  it('keeps each rule’s own visit length unless the exception states one', () => {
    const inherited = expandSlots({ ...base, exceptions: [ramadan] });
    expect(times(inherited, '2026-09-15')[0]).toBe('04:00–06:00 UTC');

    const shortened = expandSlots({
      ...base,
      exceptions: [{ ...ramadan, slotDurationMinutes: 60 }],
    });
    expect(times(shortened, '2026-09-15')).toEqual([
      '04:00–05:00 UTC',
      '05:00–06:00 UTC',
      '06:00–07:00 UTC',
      '07:00–08:00 UTC',
    ]);
  });
});

describe('time off removes the day outright', () => {
  it('publishes nothing across the range, both ends inclusive', () => {
    const slots = expandSlots({
      ...base,
      timeOff: [{ startDate: '2026-09-15', endDate: '2026-09-16' }],
    });
    expect(times(slots, '2026-09-15')).toEqual([]);
    expect(times(slots, '2026-09-16')).toEqual([]);
    expect(times(slots, '2026-09-17')).toHaveLength(4);
  });

  it('wins over an exception covering the same day', () => {
    // A trip during Ramadan is still a trip. `My Calendar`: "times on these
    // dates are removed".
    const slots = expandSlots({
      ...base,
      exceptions: [
        {
          startDate: '2026-09-15',
          endDate: '2026-09-15',
          startTime: '09:00',
          endTime: '13:00',
          slotDurationMinutes: null,
        },
      ],
      timeOff: [{ startDate: '2026-09-15', endDate: '2026-09-15' }],
    });
    expect(times(slots, '2026-09-15')).toEqual([]);
  });
});

describe('the 60-day rolling window', () => {
  it('covers exactly sixty Maldives days and stops', () => {
    const slots = expandSlots({
      ...base,
      rules: [
        {
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          startTime: '09:00',
          endTime: '11:00',
          slotDurationMinutes: 120,
        },
      ],
      days: SLOT_WINDOW_DAYS,
    });
    const dates = new Set(slots.map((s) => maldivesDateOf(s.startsAt)));
    // Day one's 09:00 is still ahead of an 08:00 clock, so all sixty appear.
    expect(dates.size).toBe(SLOT_WINDOW_DAYS);
    expect([...dates].sort()[0]).toBe('2026-09-14');
    expect([...dates].sort().at(-1)).toBe('2026-11-12');
  });

  it('records the horizon as the exclusive end of the sixtieth day', () => {
    expect(windowEnd('2026-09-14', SLOT_WINDOW_DAYS).toISOString()).toBe(
      '2026-11-12T19:00:00.000Z',
    );
  });
});
