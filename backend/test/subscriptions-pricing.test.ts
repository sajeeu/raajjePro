import { describe, expect, it } from 'vitest';

import {
  INTRODUCTORY_COHORT_SIZE,
  INTRODUCTORY_PRICE_LAARI,
  STANDARD_PRICE_LAARI,
  generateReferenceCode,
  resolvePrice,
} from '../src/modules/subscriptions/pricing.js';

/**
 * §1b's price rule at its boundaries.
 *
 * The boundary is the part worth asserting and the one a shared database
 * cannot be positioned on: this suite's rows are never deleted
 * (`test/setup.ts`), so the hundredth priced provider is somewhere in its
 * history and every later run is past the cohort for good. Hence the pure
 * function — the integration is asserted in `test/phase8a-done-when.test.ts`,
 * which checks the quote, the write and that nothing later moves it.
 */
describe('§1b subscription pricing', () => {
  it('gives the introductory rate to the first 100 providers and the standard rate after', () => {
    // §1b, Round 14: "the **first 100 providers** are set to the introductory
    // rate of MVR 75 = 7500 laari (half the standard MVR 150); everyone after
    // them takes the standard rate."
    expect(resolvePrice({ settledLaari: null, pricedProviderCount: 0 })).toEqual({
      amountLaari: INTRODUCTORY_PRICE_LAARI,
      introductory: true,
    });
    expect(
      resolvePrice({ settledLaari: null, pricedProviderCount: INTRODUCTORY_COHORT_SIZE - 1 }),
    ).toEqual({ amountLaari: INTRODUCTORY_PRICE_LAARI, introductory: true });
    // The hundredth provider closes the cohort: the hundred-and-first pays
    // the standard rate.
    expect(
      resolvePrice({ settledLaari: null, pricedProviderCount: INTRODUCTORY_COHORT_SIZE }),
    ).toEqual({ amountLaari: STANDARD_PRICE_LAARI, introductory: false });
  });

  it('honours a settled price whatever the cohort has since done', () => {
    // §1b: "**the cohort boundary is the field's value, not a rule evaluated
    // later** — a provider's price never changes because of someone else's
    // signup." So a provider inside the cohort keeps MVR 75 after ten
    // thousand more sign up, and a provider outside it is not retroactively
    // given the discount if earlier rows are somehow removed.
    expect(
      resolvePrice({ settledLaari: INTRODUCTORY_PRICE_LAARI, pricedProviderCount: 10_000 }),
    ).toEqual({ amountLaari: INTRODUCTORY_PRICE_LAARI, introductory: true });
    expect(resolvePrice({ settledLaari: STANDARD_PRICE_LAARI, pricedProviderCount: 0 })).toEqual({
      amountLaari: STANDARD_PRICE_LAARI,
      introductory: false,
    });
  });

  it('honours a price that is neither of the two published rates', () => {
    // The field is the source of truth, not a two-valued enum: §1b's whole
    // reason for putting the price on the provider is that the plan expects
    // to test other price points ("options if trial-to-paid conversion
    // disappoints: price lower for v1 and raise later"). A third value must
    // therefore be honoured and must not read as introductory.
    expect(resolvePrice({ settledLaari: 12_000, pricedProviderCount: 5 })).toEqual({
      amountLaari: 12_000,
      introductory: false,
    });
  });

  it('keeps money as integer laari, never a float (invariant 7)', () => {
    // MVR 150 = 15000 laari; MVR 75 = 7500.
    expect(STANDARD_PRICE_LAARI).toBe(15_000);
    expect(INTRODUCTORY_PRICE_LAARI).toBe(7_500);
    expect(INTRODUCTORY_PRICE_LAARI * 2).toBe(STANDARD_PRICE_LAARI);
    for (const value of [STANDARD_PRICE_LAARI, INTRODUCTORY_PRICE_LAARI]) {
      expect(Number.isInteger(value)).toBe(true);
    }
  });

  it('generates a reference code a human can copy off a phone into a bank app', () => {
    // §1b step 2: the provider writes this on their transfer and §Phase 10a's
    // receipt analysis reads it back off a photo of a bank-app screen. So no
    // 0/O, no 1/I, no 5/S, and a hyphen every four characters. It is not a
    // secret — it authorizes nothing — but it must not be guessable across
    // providers either.
    const codes = new Set<string>();
    for (let i = 0; i < 500; i++) {
      const code = generateReferenceCode();
      expect(code).toMatch(
        /^RP-[ABCDEFGHJKLMNPQRTUVWXY2346789]{4}-[ABCDEFGHJKLMNPQRTUVWXY2346789]{4}$/,
      );
      expect(code).not.toMatch(/[0OI1S5]/);
      codes.add(code);
    }
    // 29^8 possibilities, so 500 draws colliding would mean the generator is
    // not drawing at random.
    expect(codes.size).toBe(500);
  });
});
