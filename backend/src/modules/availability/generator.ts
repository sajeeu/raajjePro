import {
  addMaldivesDays,
  atMaldives,
  isoWeekdayOf,
  maldivesDateRange,
  minutesOfDay,
  type MaldivesDate,
  type WallClock,
} from '../../core/maldives-time.js';

/**
 * §Phase 9a's rolling window. Sixty Maldives days, starting with today — so
 * the horizon moves forward one day at a time and a provider always has two
 * months of bookable time in front of them without anyone regenerating
 * anything.
 */
export const SLOT_WINDOW_DAYS = 60;

/** What the expansion needs from an `AvailabilityRule`. */
export interface RulePattern {
  weekdays: number[];
  startTime: WallClock;
  endTime: WallClock;
  slotDurationMinutes: number;
}

/** What it needs from an `AvailabilityException` — "modified hours". */
export interface ExceptionPattern {
  startDate: MaldivesDate;
  endDate: MaldivesDate;
  startTime: WallClock;
  endTime: WallClock;
  /** Null keeps each rule's own visit length; see the schema comment. */
  slotDurationMinutes: number | null;
}

/** What it needs from a `ProviderTimeOff` — all-day, provider-wide. */
export interface TimeOffPattern {
  startDate: MaldivesDate;
  endDate: MaldivesDate;
}

export interface DesiredSlot {
  startsAt: Date;
  endsAt: Date;
}

export interface ExpandInput {
  rules: RulePattern[];
  exceptions: ExceptionPattern[];
  timeOff: TimeOffPattern[];
  /** First Maldives day of the window — today, in practice. */
  from: MaldivesDate;
  days: number;
  /**
   * Nothing at or before this instant is produced. Generation only ever
   * writes the future (§Phase 9a: "regenerates future unreserved slots
   * only"), so a slot earlier today is neither created nor, by the same
   * boundary, removed.
   */
  notBefore: Date;
}

/**
 * The whole availability model as a pure function: rules, exceptions and time
 * off in, the exact set of bookable instants out.
 *
 * Pure on purpose. This is the part with the calendar reasoning in it, and a
 * function with no database underneath can be tested at its awkward edges —
 * a window that does not divide evenly, an exception that starts mid-week, a
 * trip that swallows a Friday — in milliseconds and without a fixture.
 *
 * **Three rules a reader should not have to derive:**
 *
 * 1. **Time off wins outright.** A covered day produces nothing, whatever the
 *    weekly rules or an exception say. `My Calendar.dc.html`: "Where you
 *    publish time slots, times on these dates are removed."
 * 2. **An exception modifies; it never creates.** On a day the weekly rules do
 *    not work, an exception covering that date still produces nothing —
 *    otherwise "Ramadan hours" would quietly add Fridays to a Sunday-to-
 *    Thursday week.
 * 3. **A trailing remainder is not a slot.** 09:00–17:00 at three hours each
 *    gives 09:00, 12:00 and 15:00 — the 45 minutes left over is not a
 *    three-quarter-length visit.
 */
export function expandSlots(input: ExpandInput): DesiredSlot[] {
  const { rules, exceptions, timeOff, from, days, notBefore } = input;
  if (rules.length === 0) return [];

  const slots: DesiredSlot[] = [];
  // The unique index is `(listingId, startsAt)`, so two rules that overlap on
  // a day must not both produce the same start. First one wins, which is
  // stable because the caller reads rules in a deterministic order.
  const seen = new Set<number>();

  for (const date of maldivesDateRange(from, days)) {
    if (timeOff.some((off) => covers(off, date))) continue;

    const weekday = isoWeekdayOf(date);
    const exception = exceptions.find((e) => covers(e, date));

    for (const rule of rules) {
      if (!rule.weekdays.includes(weekday)) continue;

      const windowStart = minutesOfDay(exception?.startTime ?? rule.startTime);
      const windowEnd = minutesOfDay(exception?.endTime ?? rule.endTime);
      const duration = exception?.slotDurationMinutes ?? rule.slotDurationMinutes;
      if (duration <= 0 || windowEnd <= windowStart) continue;

      for (let at = windowStart; at + duration <= windowEnd; at += duration) {
        const startsAt = atMaldives(date, at);
        if (startsAt.getTime() <= notBefore.getTime()) continue;
        if (seen.has(startsAt.getTime())) continue;
        seen.add(startsAt.getTime());
        slots.push({ startsAt, endsAt: atMaldives(date, at + duration) });
      }
    }
  }

  slots.sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime());
  return slots;
}

/** The exclusive end of the window that starts on `from` — what `generatedThrough` records. */
export function windowEnd(from: MaldivesDate, days: number): Date {
  return atMaldives(addMaldivesDays(from, days), 0);
}

function covers(range: { startDate: MaldivesDate; endDate: MaldivesDate }, date: MaldivesDate) {
  // Both bounds inclusive, and an ISO date string compares lexicographically
  // in calendar order — which is the whole reason the type is a string.
  return range.startDate <= date && date <= range.endDate;
}
