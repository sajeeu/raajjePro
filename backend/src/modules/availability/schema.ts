import { z } from 'zod';

import { SLOT_WINDOW_DAYS } from './generator.js';

/**
 * Request validation for §Phase 9a.
 *
 * Two shapes recur and are defined once: a Maldives wall-clock `HH:MM` and a
 * Maldives calendar date `YYYY-MM-DD`. Both are strings on the wire rather
 * than instants, for the reason `core/maldives-time.ts` sets out — a
 * recurring time with no date and a calendar day with no time are not
 * instants, and accepting an ISO timestamp for either would invite a client
 * to send one in its own timezone.
 */

/** `HH:MM`, 24-hour, Maldives wall clock. The same pattern §Phase 8 uses for the wizard's window. */
const clockTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:MM, 24-hour');

/** `YYYY-MM-DD`, a Maldives calendar day. `.date()` rejects 2026-02-30 as well as the wrong shape. */
const calendarDate = z.iso.date();

/**
 * ISO weekday numbers, 1 = Monday — matching `Listing.workingDays`, so no
 * reader ever has to ask which Sunday is zero. At least one, each at most
 * once: a rule for no days generates nothing and a rule naming Tuesday twice
 * is a client bug worth naming rather than silently collapsing.
 */
const weekdays = z
  .array(z.int().min(1).max(7))
  .min(1, 'Choose at least one day')
  .max(7)
  .refine((days) => new Set(days).size === days.length, 'A day cannot appear twice');

/**
 * "Each visit" on `Availability.dc.html` — 1, 1.5, 2, 3 or 4 hours there, but
 * validated as a range rather than that list, because the list is a
 * convenience the designer chose and not a rule the plan states. Fifteen
 * minutes is the shortest appointment anyone sells; twelve hours is longer
 * than any single working window a rule can express.
 */
const slotDuration = z
  .int()
  .min(15)
  .max(12 * 60);

export const listingParams = z.object({ listingId: z.uuid() });
export const ruleParams = z.object({ listingId: z.uuid(), ruleId: z.uuid() });
export const exceptionParams = z.object({ listingId: z.uuid(), exceptionId: z.uuid() });
export const slotParams = z.object({ slotId: z.uuid() });
export const timeOffParams = z.object({ timeOffId: z.uuid() });
export const publicListingParams = z.object({ id: z.uuid() });

export const availabilityRuleBody = z.object({
  weekdays,
  startTime: clockTime,
  endTime: clockTime,
  slotDurationMinutes: slotDuration,
});

/** A rule edit replaces the whole rule, exactly as the editor sheet does — it opens with every field filled. */
export const updateAvailabilityRuleBody = availabilityRuleBody;

export const availabilityExceptionBody = z.object({
  name: z.string().trim().min(1).max(80),
  startDate: calendarDate,
  endDate: calendarDate,
  startTime: clockTime,
  endTime: clockTime,
  /** Null, or absent, keeps each rule's own visit length. */
  slotDurationMinutes: slotDuration.nullish(),
});

export const timeOffBody = z.object({
  name: z.string().trim().min(1).max(80),
  startDate: calendarDate,
  endDate: calendarDate,
});

/**
 * A date window, both ends optional.
 *
 * Server-side bounded rather than paged: the set can never exceed one
 * listing's slots inside the 60-day horizon, because `to` is clamped to it.
 * Absent, the range is the whole horizon — which is what the provider's grid
 * and the picker's date rail both want.
 */
export const slotRangeQuery = z.object({
  from: calendarDate.optional(),
  to: calendarDate.optional(),
});

export const MAX_SLOT_RANGE_DAYS = SLOT_WINDOW_DAYS;
