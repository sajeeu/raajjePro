import { describe, expect, it } from 'vitest';

import {
  AmountNotDerivableError,
  deriveSlotAmount,
  durationMinutes,
} from '../src/modules/bookings/pricing.js';
import {
  assertTransition,
  EDGES,
  isTerminal,
  TERMINAL_STATUSES,
} from '../src/modules/bookings/transitions.js';

/**
 * Round 17's `amountKind` derivation, and the machine's edge table. Both are
 * pure, so both are tested without a database — and both are the kind of rule
 * a wrong implementation would still pass an end-to-end happy path with.
 */
describe('Phase 17.1 — deriving the amount (Round 17)', () => {
  const twoHours = durationMinutes(
    new Date('2026-09-14T04:00:00Z'),
    new Date('2026-09-14T06:00:00Z'),
  );

  it('takes a fixed price as it stands', () => {
    expect(deriveSlotAmount({ pricingModel: 'fixed', priceLaari: 15000 }, twoHours)).toEqual({
      amountLaari: 15000,
      amountKind: 'fixed_price',
    });
  });

  it('multiplies an hourly rate by the slot’s own length, in integer laari', () => {
    expect(deriveSlotAmount({ pricingModel: 'hourly', priceLaari: 10000 }, twoHours)).toEqual({
      amountLaari: 20000,
      amountKind: 'hourly_total',
    });
    // 90 minutes at MVR 100/hour is MVR 150 — never 150.00, never a float.
    const ninety = deriveSlotAmount({ pricingModel: 'hourly', priceLaari: 10000 }, 90);
    expect(ninety.amountLaari).toBe(15000);
    expect(Number.isInteger(ninety.amountLaari)).toBe(true);
  });

  it('charges a whole day at a daily rate, rounded up, never a fraction of one', () => {
    // The judgment call recorded in `pricing.ts` and in
    // docs/decisions/28-phase-17-1-bookings.md: the provider advertised a day
    // rate and the customer read "/day".
    expect(deriveSlotAmount({ pricingModel: 'daily', priceLaari: 100000 }, twoHours)).toEqual({
      amountLaari: 100000,
      amountKind: 'daily_total',
    });
    expect(
      deriveSlotAmount({ pricingModel: 'daily', priceLaari: 100000 }, 26 * 60).amountLaari,
    ).toBe(200000);
  });

  it('refuses a range or quote listing, which §1c says is never a bookable amount', () => {
    for (const pricingModel of ['range', 'quote'] as const) {
      expect(() => deriveSlotAmount({ pricingModel, priceLaari: 5000 }, twoHours)).toThrow(
        AmountNotDerivableError,
      );
    }
  });

  it('refuses a listing with no price rather than booking it at zero', () => {
    expect(() => deriveSlotAmount({ pricingModel: 'fixed', priceLaari: null }, twoHours)).toThrow(
      AmountNotDerivableError,
    );
    expect(() => deriveSlotAmount({ pricingModel: null, priceLaari: 5000 }, twoHours)).toThrow(
      AmountNotDerivableError,
    );
  });
});

describe('Phase 17.1 — the status machine, at its edges', () => {
  it('names the four terminal statuses and excludes the two an admin still owes', () => {
    expect([...TERMINAL_STATUSES].sort()).toEqual([
      'cancelled',
      'completed',
      'declined',
      'dispute_resolved',
    ]);
    // §1c: both of these read like endings and are not.
    expect(isTerminal('payment_unresolved')).toBe(false);
    expect(isTerminal('disputed')).toBe(false);
  });

  it('allows the withdrawal edge to run backwards, and only for the customer', () => {
    expect(assertTransition('withdraw-payment-claim', 'payment_claimed', 'customer').to).toBe(
      'awaiting_payment',
    );
    expect(() => assertTransition('withdraw-payment-claim', 'payment_claimed', 'provider')).toThrow(
      /cannot/,
    );
  });

  it('refuses a completed booking being cancelled, by either party', () => {
    for (const actor of ['customer', 'provider'] as const) {
      expect(() =>
        assertTransition(actor === 'customer' ? 'cancel' : 'provider-cancel', 'completed', actor),
      ).toThrow(/cannot be/);
    }
  });

  it('has no edge into the three statuses later slices own', () => {
    // The vocabulary is complete; the edges are not, and that is the slice
    // boundary rather than an omission.
    const reachable = new Set(EDGES.map((e) => e.to));
    expect(reachable.has('awaiting_quote')).toBe(false);
    expect(reachable.has('quote_offered')).toBe(false);
    expect(reachable.has('emergency_offered')).toBe(false);
  });

  it('reports a state problem before an actor problem', () => {
    // A customer tapping a provider's action on a booking that has also moved
    // on is told the more useful of the two truths.
    expect(() => assertTransition('accept', 'completed', 'customer')).toThrow(
      /cannot be accept while it is completed/,
    );
  });
});
