import { describe, expect, it } from 'vitest';

import {
  addMaldivesDays,
  atMaldives,
  isoWeekdayOf,
  maldivesDateOf,
  maldivesDateOfColumn,
  MALDIVES_OFFSET_MINUTES,
  minutesOfDay,
  startOfMaldivesDay,
  startOfNextMaldivesDay,
  wallClockOf,
} from '../src/core/maldives-time.js';

/**
 * §Phase 9a: "all times stored UTC, presented in Maldives time (UTC+5).
 * Document the convention; a single-timezone market makes this simple, but
 * **boundary days still need a stated rule**."
 *
 * The rule is stated in `core/maldives-time.ts`; these are the boundary cases
 * it has to get right, and every one of them is a case where using the UTC
 * date instead would file an appointment under the wrong day.
 */
describe('the Maldives day boundary', () => {
  it('is UTC+5 with no DST — the same offset in January and in July', () => {
    expect(MALDIVES_OFFSET_MINUTES).toBe(300);
    expect(atMaldives('2027-01-15', minutesOfDay('09:00')).toISOString()).toBe(
      '2027-01-15T04:00:00.000Z',
    );
    expect(atMaldives('2027-07-15', minutesOfDay('09:00')).toISOString()).toBe(
      '2027-07-15T04:00:00.000Z',
    );
  });

  it('files a late-evening Malé time under the day the provider means, not the next UTC day', () => {
    // 21:00 in Malé is 16:00Z the same day — unremarkable.
    expect(maldivesDateOf(new Date('2026-10-01T16:00:00Z'))).toBe('2026-10-01');
    // 02:00 in Malé is 21:00Z the PREVIOUS day. Grouping by UTC date would put
    // it on 30 September, a day the provider may not even work.
    expect(maldivesDateOf(new Date('2026-09-30T21:00:00Z'))).toBe('2026-10-01');
  });

  it('opens a day at 19:00Z the evening before', () => {
    expect(startOfMaldivesDay('2026-10-01').toISOString()).toBe('2026-09-30T19:00:00.000Z');
  });

  it('wakes the generator at the next Maldives midnight, not the next UTC one', () => {
    // 23:30 Malé on 1 October = 18:30Z. The next UTC midnight is four and a
    // half hours away; the next *Maldives* midnight is half an hour away.
    expect(startOfNextMaldivesDay(new Date('2026-10-01T18:30:00Z')).toISOString()).toBe(
      '2026-10-01T19:00:00.000Z',
    );
  });

  it('reads an ISO weekday the same way `Listing.workingDays` writes one — 1 is Monday', () => {
    expect(isoWeekdayOf('2026-09-14')).toBe(1);
    expect(isoWeekdayOf('2026-10-01')).toBe(4);
    // Sunday is 7, never 0. The whole reason the helper exists.
    expect(isoWeekdayOf('2026-10-04')).toBe(7);
  });

  it('takes the weekday from the Maldives date, so a 23:00 Sunday slot is not a Monday one', () => {
    const lateSunday = new Date('2026-10-04T18:00:00Z'); // 23:00 Malé, Sunday
    expect(maldivesDateOf(lateSunday)).toBe('2026-10-04');
    expect(isoWeekdayOf(maldivesDateOf(lateSunday))).toBe(7);
  });

  it('crosses a month and a year without special-casing either', () => {
    expect(addMaldivesDays('2026-10-31', 1)).toBe('2026-11-01');
    expect(addMaldivesDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addMaldivesDays('2026-03-01', -1)).toBe('2026-02-28');
    // 60 days forward from a late-December day — the rolling horizon's own case.
    expect(addMaldivesDays('2026-12-15', 60)).toBe('2027-02-13');
  });

  it('round-trips a wall clock, including the exclusive midnight boundary', () => {
    expect(wallClockOf(minutesOfDay('09:30'))).toBe('09:30');
    expect(wallClockOf(minutesOfDay('00:00'))).toBe('00:00');
    // 24:00 is expressible as an end boundary and normalises to the next
    // day's midnight rather than throwing.
    expect(atMaldives('2026-10-01', 24 * 60).toISOString()).toBe('2026-10-01T19:00:00.000Z');
  });

  it('reads a `@db.Date` column as the date it holds, without shifting it five hours', () => {
    // Prisma hands a date column back at UTC midnight. Passing that through
    // the instant conversion would be a different operation that happens to
    // agree; these two say plainly that a date column carries a date.
    expect(maldivesDateOfColumn(new Date('2026-10-01T00:00:00Z'))).toBe('2026-10-01');
  });
});
