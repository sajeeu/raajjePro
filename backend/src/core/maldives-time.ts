/**
 * Every UTC ⇄ Maldives conversion in the system, in one file (§Phase 9a:
 * "all times stored UTC, presented in Maldives time (UTC+5). Document the
 * convention; a single-timezone market makes this simple, but boundary days
 * still need a stated rule").
 *
 * ## Why there is no timezone library here
 *
 * Maldives Standard Time is **UTC+5, year round, and has never observed
 * DST**. There is one zone for the whole country. So the offset is a
 * constant, and a constant is both correct and far easier to reason about
 * than an IANA lookup that would return the same answer every time. If the
 * market ever stops being single-zone, this file is the one that changes.
 *
 * ## The boundary rule
 *
 * A **day** is a Maldives calendar day: `[date 00:00+05, date+1 00:00+05)`,
 * which in UTC is `[date-1 19:00Z, date 19:00Z)`. Everything day-shaped
 * resolves against that and never against the UTC date — a weekday, an
 * availability exception's range, a time-off range, the picker's date rail.
 * A 21:00 Malé appointment is 16:00Z the same day, but a 02:00 Malé one is
 * 21:00Z the *previous* UTC day, and grouping it by UTC date would file it
 * under the wrong heading on the provider's own calendar.
 */

/** Minutes east of UTC. Maldives Standard Time, constant — see above. */
export const MALDIVES_OFFSET_MINUTES = 5 * 60;

const MS_PER_MINUTE = 60_000;
const MS_PER_DAY = 24 * 60 * MS_PER_MINUTE;

/** `YYYY-MM-DD` in Maldives time — the only form a calendar day is ever passed around in. */
export type MaldivesDate = string;

/** `HH:MM`, 24-hour, Maldives wall clock. */
export type WallClock = string;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const WALL_CLOCK_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export function isMaldivesDate(value: string): value is MaldivesDate {
  return DATE_PATTERN.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

export function isWallClock(value: string): value is WallClock {
  return WALL_CLOCK_PATTERN.test(value);
}

/** Minutes since Maldives midnight. `'09:30'` → 570. Callers validate the shape first. */
export function minutesOfDay(time: WallClock): number {
  const [hours, minutes] = time.split(':');
  return Number(hours) * 60 + Number(minutes);
}

/** The inverse, for rendering a generated boundary back as a rule would state it. */
export function wallClockOf(minutes: number): WallClock {
  const h = Math.floor(minutes / 60) % 24;
  const m = minutes % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** The Maldives calendar date an instant falls on. */
export function maldivesDateOf(instant: Date): MaldivesDate {
  const shifted = new Date(instant.getTime() + MALDIVES_OFFSET_MINUTES * MS_PER_MINUTE);
  return shifted.toISOString().slice(0, 10);
}

/**
 * The UTC instant of a Maldives wall-clock time on a Maldives date.
 *
 * `atMaldives('2026-09-14', '09:00')` → `2026-09-14T04:00:00Z`. Minutes past
 * 24:00 are allowed and roll into the next day, which is how a rule's
 * exclusive end boundary at exactly midnight is expressed.
 */
export function atMaldives(date: MaldivesDate, minutesFromMidnight: number): Date {
  return new Date(
    Date.parse(`${date}T00:00:00Z`) +
      (minutesFromMidnight - MALDIVES_OFFSET_MINUTES) * MS_PER_MINUTE,
  );
}

/** Midnight opening the given Maldives day, as a UTC instant. */
export function startOfMaldivesDay(date: MaldivesDate): Date {
  return atMaldives(date, 0);
}

/** Midnight opening the Maldives day after the instant given. What the generator sets as its next wake-up. */
export function startOfNextMaldivesDay(instant: Date): Date {
  return startOfMaldivesDay(addMaldivesDays(maldivesDateOf(instant), 1));
}

/** Calendar arithmetic on a Maldives date. Days are always 24 hours here — no DST to shorten one. */
export function addMaldivesDays(date: MaldivesDate, days: number): MaldivesDate {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * MS_PER_DAY).toISOString().slice(0, 10);
}

/** ISO weekday of a Maldives date: 1 = Monday … 7 = Sunday, matching `Listing.workingDays`. */
export function isoWeekdayOf(date: MaldivesDate): number {
  const jsDay = new Date(`${date}T00:00:00Z`).getUTCDay();
  return jsDay === 0 ? 7 : jsDay;
}

/** Every Maldives date from `from` for `count` days, in order. */
export function maldivesDateRange(from: MaldivesDate, count: number): MaldivesDate[] {
  const dates: MaldivesDate[] = [];
  for (let i = 0; i < count; i += 1) dates.push(addMaldivesDays(from, i));
  return dates;
}

/**
 * A `@db.Date` column round-trips through Prisma as a `Date` at UTC midnight,
 * so reading one back as a Maldives date must **not** go through
 * `maldivesDateOf` — that would shift it five hours forward and, for any date,
 * still land on the same day, but the symmetry is accidental rather than
 * meant. These two say plainly that a date column carries a date.
 */
export function dateColumnOf(date: MaldivesDate): Date {
  return new Date(`${date}T00:00:00Z`);
}

export function maldivesDateOfColumn(column: Date): MaldivesDate {
  return column.toISOString().slice(0, 10);
}
