import { describe, expect, it } from 'vitest';

import { maldivesDateOf } from '../src/core/maldives-time.js';
import {
  chipLabel,
  QuoteWindowsMissingError,
  readQuoteWindows,
  resolveWindowChip,
  WINDOW_CHIPS,
  type WindowChip,
} from '../src/modules/bookings/quotes.js';

/**
 * §Phase 17.2's pure logic — the two per-category clocks and §1c's four window
 * chips.
 *
 * The chips are resolved **server-side** (invariant 4: two clients would
 * otherwise answer "this weekend" two ways), against the **Maldives** calendar
 * day, and the Maldivian week is what makes them worth a test of their own:
 * the weekend is **Friday and Saturday** and Sunday is a working day, so the
 * arithmetic wraps in a direction a Saturday-Sunday assumption gets wrong.
 */
describe('Phase 17.2 — the quote windows', () => {
  describe('readQuoteWindows', () => {
    it('reads both clocks off the category', () => {
      expect(readQuoteWindows({ quoteExpiryMinutes: 120, quoteApprovalMinutes: 240 })).toEqual({
        expiryMinutes: 120,
        approvalMinutes: 240,
      });
    });

    it('refuses a category with no clock rather than defaulting to the old flat one', () => {
      // A default here would be the pre-Round-15 24h/72h reappearing through a
      // fallback, which is the failure invariant 13 exists to prevent.
      for (const category of [
        { quoteExpiryMinutes: null, quoteApprovalMinutes: 240 },
        { quoteExpiryMinutes: 120, quoteApprovalMinutes: null },
        { quoteExpiryMinutes: 0, quoteApprovalMinutes: 240 },
      ]) {
        expect(() => readQuoteWindows(category)).toThrow(QuoteWindowsMissingError);
      }
    });
  });

  describe('the window chips', () => {
    it('names §1c’s four, and no others', () => {
      expect([...WINDOW_CHIPS]).toEqual([
        'tomorrow_morning',
        'tomorrow_afternoon',
        'this_week',
        'this_weekend',
      ]);
      expect(WINDOW_CHIPS.map((c) => chipLabel(c))).toEqual([
        'Tomorrow morning',
        'Tomorrow afternoon',
        'This week',
        'This weekend',
      ]);
    });

    it('resolves tomorrow against the Maldives day, not the UTC one', () => {
      // 20:30 UTC on the 14th is 01:30 Malé on the **15th**, so "tomorrow" is
      // the 16th. Resolving against the UTC date would have said the 15th —
      // the day the customer is already living in.
      const lateNight = new Date('2026-09-14T20:30:00Z');
      expect(maldivesDateOf(lateNight)).toBe('2026-09-15');

      const { from, to } = resolveWindowChip('tomorrow_morning', lateNight);
      // 08:00–12:00 Malé on the 16th is 03:00–07:00Z.
      expect(from.toISOString()).toBe('2026-09-16T03:00:00.000Z');
      expect(to.toISOString()).toBe('2026-09-16T07:00:00.000Z');
    });

    it('puts the afternoon after the morning, on the same day', () => {
      const now = new Date('2026-09-14T06:00:00Z');
      const morning = resolveWindowChip('tomorrow_morning', now);
      const afternoon = resolveWindowChip('tomorrow_afternoon', now);
      expect(afternoon.from.getTime()).toBe(morning.to.getTime());
      expect(afternoon.to.getTime()).toBeGreaterThan(afternoon.from.getTime());
    });

    it('opens “this week” now and runs a week, never shrinking to nothing', () => {
      // A window that ended at the working week's close would be empty when
      // tapped on a Thursday evening, and the provider would read an empty
      // preference.
      for (const day of ['2026-09-14', '2026-09-17', '2026-09-19']) {
        const now = new Date(`${day}T14:00:00Z`);
        const { from, to } = resolveWindowChip('this_week', now);
        expect(from.getTime()).toBe(now.getTime());
        expect(to.getTime()).toBeGreaterThan(now.getTime());
      }
    });

    describe('“this weekend” — Friday and Saturday, and Sunday is a working day', () => {
      /** The Maldives date each resolved weekend opens on. */
      function weekendFrom(iso: string): string {
        return maldivesDateOf(resolveWindowChip('this_weekend', new Date(iso)).from);
      }

      it('points a weekday at the coming Friday', () => {
        // 2026-09-14 is a Monday; the Friday of that week is the 18th.
        expect(weekendFrom('2026-09-14T06:00:00Z')).toBe('2026-09-18');
        // Thursday the 17th — still the 18th, one day out.
        expect(weekendFrom('2026-09-17T06:00:00Z')).toBe('2026-09-18');
      });

      it('means the weekend the customer is already in, on a Friday or Saturday', () => {
        expect(weekendFrom('2026-09-18T06:00:00Z')).toBe('2026-09-18');
        expect(weekendFrom('2026-09-19T06:00:00Z')).toBe('2026-09-19');
      });

      it('sends a **Sunday** forward five days, not back two', () => {
        // The case a Saturday–Sunday assumption gets wrong. Sunday is ISO 7,
        // the start of the Maldivian working week — so "this weekend" is the
        // Friday ahead (the 25th), never the one that has already gone.
        expect(weekendFrom('2026-09-20T06:00:00Z')).toBe('2026-09-25');
      });

      it('covers Friday and Saturday and stops at Sunday midnight', () => {
        const { from, to } = resolveWindowChip('this_weekend', new Date('2026-09-14T06:00:00Z'));
        // Friday 00:00 Malé through Sunday 00:00 Malé — two whole days.
        expect(from.toISOString()).toBe('2026-09-17T19:00:00.000Z');
        expect(to.toISOString()).toBe('2026-09-19T19:00:00.000Z');
        expect(to.getTime() - from.getTime()).toBe(2 * 24 * 60 * 60_000);
      });

      it('never returns a range that has already ended', () => {
        // Every day of one week, from a mid-afternoon moment.
        for (let day = 14; day <= 20; day += 1) {
          const now = new Date(`2026-09-${String(day)}T09:00:00Z`);
          const { from, to } = resolveWindowChip('this_weekend', now);
          expect(to.getTime()).toBeGreaterThan(now.getTime());
          expect(to.getTime()).toBeGreaterThan(from.getTime());
        }
      });
    });

    it('returns a forward-running range for every chip, on every day of a week', () => {
      for (let day = 14; day <= 20; day += 1) {
        const now = new Date(`2026-09-${String(day)}T09:00:00Z`);
        for (const chip of WINDOW_CHIPS as readonly WindowChip[]) {
          const { from, to } = resolveWindowChip(chip, now);
          expect(to.getTime()).toBeGreaterThan(from.getTime());
        }
      }
    });
  });
});
