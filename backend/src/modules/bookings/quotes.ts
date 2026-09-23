import { BusinessRuleError } from '../../core/errors.js';
import {
  addMaldivesDays,
  atMaldives,
  isoWeekdayOf,
  maldivesDateOf,
  type MaldivesDate,
} from '../../core/maldives-time.js';

/**
 * §Phase 17.2's two clocks and the request form's window chips.
 *
 * ## Why this file exists rather than three constants in `windows.ts`
 *
 * `windows.ts` holds the windows §1c states **flat for every category** and
 * says plainly that no per-category value may appear in it. Both clocks here
 * are per-category (invariant 13, Round 15) and are read from the `Category`
 * row every time:
 *
 * | Category group                                                            | quote | approve |
 * |---------------------------------------------------------------------------|-------|---------|
 * | Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control, Home Repairs | 120   | 240     |
 * | Photography, Moving, Boat Charter                                         | 1440  | 4320    |
 *
 * The numbers above are documentation of what §Phase 4 seeded. **Nothing in
 * this file contains either of them** — `readQuoteWindows` reads the columns,
 * and a category with them unset is refused rather than defaulted, because a
 * default would silently reinstate the flat 24h/72h that Round 15 removed.
 */

export interface QuoteWindows {
  /** `Category.quoteExpiryMinutes` — how long the provider has to send a quote. */
  expiryMinutes: number;
  /** `Category.quoteApprovalMinutes` — how long the customer then has to approve it. */
  approvalMinutes: number;
}

/**
 * How long the provisional hold covers, from the proposed start.
 *
 * 🔧 **A judgment call, recorded rather than buried** — the same treatment
 * `pricing.ts` gives the `daily` rate on a sub-day slot.
 *
 * §1c requires the hold ("Offering a quote creates a provisional reservation
 * **on the proposed time**"), the constraint it feeds is a *range*
 * (`tstzrange(startsAt, endsAt)`), and the plan gives request-based work no
 * duration anywhere — by design, since the whole reason these categories are
 * `request` is that "duration depends on diagnosis, property, negotiation, or
 * trip type". `Propose Time and Price.dc.html` asks the provider for a date, a
 * departure time, a price and a note, and for no length.
 *
 * So the hold is two hours, which is the length the schema's own example of a
 * request-based hold uses ("a plumbing quote for 11:00–13:00"). A zero-length
 * range was the alternative and is not one: an empty `tstzrange` overlaps
 * nothing, so the hold would hold nothing and the provider could sell the time
 * twice — the exact failure §1c created the provisional reservation to prevent.
 *
 * It is a **hold**, not a promise about how long the job takes: nothing is
 * shown to either party, and `agreedAmount` comes from the quote rather than
 * from any duration. §Phase 17.4's reschedule moves it like any other.
 */
export const REQUEST_HOLD_MINUTES = 120;

/**
 * Raised when a listing's category carries no quote clock.
 *
 * Unreachable through the seeded catalogue — every `request` category has both
 * columns — but a category an admin creates in §Phase 10b could omit them, and
 * the honest answer then is that the listing cannot take a request yet. The
 * alternative, defaulting to 24h/72h, is the pre-Round-15 rule reappearing
 * through a fallback.
 */
export class QuoteWindowsMissingError extends BusinessRuleError {
  constructor() {
    super(
      'CATEGORY_HAS_NO_QUOTE_WINDOW',
      'This service cannot take requests yet — its category has no quote window set',
    );
  }
}

export function readQuoteWindows(category: {
  quoteExpiryMinutes: number | null;
  quoteApprovalMinutes: number | null;
}): QuoteWindows {
  const { quoteExpiryMinutes, quoteApprovalMinutes } = category;
  if (
    quoteExpiryMinutes === null ||
    quoteApprovalMinutes === null ||
    quoteExpiryMinutes <= 0 ||
    quoteApprovalMinutes <= 0
  ) {
    throw new QuoteWindowsMissingError();
  }
  return { expiryMinutes: quoteExpiryMinutes, approvalMinutes: quoteApprovalMinutes };
}

// ---------------------------------------------------------------------------
// The request form's window chips
// ---------------------------------------------------------------------------

/**
 * §1c: "**The window picker leads with quick-pick chips** — 'Tomorrow
 * morning,' 'Tomorrow afternoon,' 'This week,' 'This weekend' — covering the
 * common cases in one tap, with free text available underneath for anything
 * more specific."
 *
 * The four labels are the plan's, exactly. Resolving them to instants is
 * **this file's judgment call**, because the plan gives the labels and not
 * their hours, and it is made here rather than in the client for invariant 4's
 * reason: the client may not be the only place a rule lives, and two clients
 * would resolve "this weekend" two ways.
 *
 * What the resolution is *for* matters to how exact it needs to be. A
 * preferred window is a **preference the provider reads**, not a constraint
 * anything computes on: the provider answers with a concrete time, and that
 * concrete time is what the hold, the agreement and every clock downstream
 * use. So the stored range is a machine-readable restatement of the label for
 * a later provider-side calendar view, and the label itself is what a human
 * ever sees.
 */
export const WINDOW_CHIPS = [
  'tomorrow_morning',
  'tomorrow_afternoon',
  'this_week',
  'this_weekend',
] as const;

export type WindowChip = (typeof WINDOW_CHIPS)[number];

/** The label each chip renders as, and what is stored when no free text was typed. */
const CHIP_LABELS: Record<WindowChip, string> = {
  tomorrow_morning: 'Tomorrow morning',
  tomorrow_afternoon: 'Tomorrow afternoon',
  this_week: 'This week',
  this_weekend: 'This weekend',
};

export function chipLabel(chip: WindowChip): string {
  return CHIP_LABELS[chip];
}

/** Maldives wall-clock boundaries, in minutes from midnight. */
const MORNING = { from: 8 * 60, to: 12 * 60 };
const AFTERNOON = { from: 12 * 60, to: 18 * 60 };

/**
 * The Maldivian weekend is **Friday and Saturday**; the working week is Sunday
 * to Thursday. ISO weekdays, so Friday is 5 and Saturday 6 — and **Sunday is
 * 7, which is a working day here and the start of the week**, not part of the
 * weekend it numerically follows.
 */
const FRIDAY = 5;
const SATURDAY = 6;
const DAYS_IN_WEEK = 7;

/**
 * A chip as a concrete Maldives-time range.
 *
 * Every boundary resolves against the **Maldives** calendar day
 * (`core/maldives-time.ts`), never the UTC one: "tomorrow morning" asked for
 * at 01:00 Malé is a request about the day the customer is going to wake up
 * on, and the UTC date at that moment is still yesterday.
 */
export function resolveWindowChip(chip: WindowChip, now: Date): { from: Date; to: Date } {
  const today = maldivesDateOf(now);

  switch (chip) {
    case 'tomorrow_morning':
      return dayRange(addMaldivesDays(today, 1), MORNING);

    case 'tomorrow_afternoon':
      return dayRange(addMaldivesDays(today, 1), AFTERNOON);

    /**
     * From now to the end of the seventh day ahead. "This week" is read by
     * customers as "the next few days" rather than as "before Sunday", and a
     * window that shrinks to nothing when tapped on a Thursday evening would
     * be worse than useless — the provider would read an empty preference.
     */
    case 'this_week':
      return { from: now, to: atMaldives(addMaldivesDays(today, 7), 0) };

    /**
     * The coming Friday and Saturday — the Maldivian weekend, not the
     * Saturday–Sunday one. Tapped *during* a weekend it means the one the
     * customer is in, so the range opens at `now` rather than skipping a week.
     */
    case 'this_weekend': {
      const weekday = isoWeekdayOf(today);
      const inWeekend = weekday === FRIDAY || weekday === SATURDAY;
      // Days forward to the coming Friday, wrapped — **Sunday must go forward
      // five days, not back two**. `FRIDAY - weekday` alone is negative on a
      // Sunday and would have named the Friday that has already gone.
      const untilFriday = (FRIDAY - weekday + DAYS_IN_WEEK) % DAYS_IN_WEEK;
      const friday = inWeekend
        ? addMaldivesDays(today, -(weekday - FRIDAY))
        : addMaldivesDays(today, untilFriday);
      const opens = atMaldives(friday, 0);
      return {
        // Tapped during the weekend it means the one the customer is in, so
        // the range opens now rather than at a midnight already past.
        from: inWeekend && now > opens ? now : opens,
        // Exclusive: midnight opening Sunday, so the whole of Saturday is in.
        to: atMaldives(addMaldivesDays(friday, 2), 0),
      };
    }
  }
}

function dayRange(
  date: MaldivesDate,
  hours: { from: number; to: number },
): { from: Date; to: Date } {
  return { from: atMaldives(date, hours.from), to: atMaldives(date, hours.to) };
}
