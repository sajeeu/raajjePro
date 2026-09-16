import { BusinessRuleError } from '../../core/errors.js';
import type { AmountKind, PricingModel } from '../../generated/prisma/enums.js';

/**
 * Round 17's `amountKind` table — "**derived, never separately set** — one
 * value per path that can produce an `agreedAmount` (§Phase 8's
 * `pricingModel`)".
 *
 * | `amountKind`  | Produced by                                     |
 * |---------------|-------------------------------------------------|
 * | `fixed_price` | `pricingModel: fixed`                           |
 * | `hourly_total`| `hourly` × slot duration, or a quote in hours   |
 * | `daily_total` | `daily` × duration, or a quote in days          |
 * | `quoted`      | an accepted quote (§Phase 17.2)                 |
 * | `callout_fee` | emergency acceptance (§Phase 17.3)              |
 *
 * This file owns the first three, which are the ones a **slot** booking can
 * reach: the time is published, so the duration is known and the amount is
 * arithmetic. The last two are set by the slice that produces them, and they
 * are still derived — from the quote, and from the offer's callout fee.
 *
 * The customer-facing **labels** are deliberately not here. They are copy, one
 * per kind, and they live once in the Flutter app; duplicating them server-side
 * would be a second place for "The final bill may differ" to drift out of.
 */

/**
 * Raised when a listing's pricing cannot produce a bookable number by itself.
 *
 * A distinct class rather than a bare `BusinessRuleError` so a caller — and a
 * test — can say "this listing needs a quote" without matching on a string.
 */
export class AmountNotDerivableError extends BusinessRuleError {}

export interface DerivedAmount {
  amountLaari: number;
  amountKind: AmountKind;
}

/**
 * The amount a **slot** booking is accepted at (§1c step 3: "from the listing
 * price for `fixed` pricing, from rate × slot duration for `hourly` and
 * `daily` in slot mode").
 *
 * @param durationMinutes the published slot's own length. Never a number the
 *   client sent: the slot row is the source, so a customer cannot shorten the
 *   booking to shorten the bill.
 */
export function deriveSlotAmount(
  listing: { pricingModel: PricingModel | null; priceLaari: number | null },
  durationMinutes: number,
): DerivedAmount {
  if (listing.pricingModel === null) {
    // Unreachable through publish — `assertPublishable` requires a pricing
    // model — but a booking is money and this is not the place to assume.
    throw new AmountNotDerivableError(
      'LISTING_HAS_NO_PRICE',
      'This service has no price set and cannot be booked',
    );
  }

  // §1c step 3, Round 16: "`range` and `quote` listings can only be
  // request-based, so their `agreedAmount` always comes from the accepted
  // quote — a range is advertising, never a bookable amount."
  if (listing.pricingModel === 'range' || listing.pricingModel === 'quote') {
    throw new AmountNotDerivableError(
      'LISTING_PRICE_NEEDS_A_QUOTE',
      'This service is priced by quote — the provider proposes the amount',
    );
  }

  const rate = listing.priceLaari;
  if (rate === null || rate <= 0) {
    throw new AmountNotDerivableError(
      'LISTING_HAS_NO_PRICE',
      'This service has no price set and cannot be booked',
    );
  }

  switch (listing.pricingModel) {
    case 'fixed':
      return { amountLaari: rate, amountKind: 'fixed_price' };

    case 'hourly':
      // Integer laari throughout (invariant 7). The rounding only bites on a
      // slot whose length is not a whole number of hours, and a half-laari is
      // not a thing that exists.
      return {
        amountLaari: Math.round((rate * durationMinutes) / 60),
        amountKind: 'hourly_total',
      };

    case 'daily':
      // 🔧 **A judgment call, recorded rather than buried.** Round 17 says
      // `daily` × duration and the plan never says what a *sub-day slot* at a
      // day rate costs. Whole days, rounded up, minimum one: the provider
      // advertised a day rate and the customer read "/day" on the card, so
      // charging a fraction of it would surprise the provider and charging
      // two would surprise the customer. Refusing the combination outright
      // was the other candidate and was rejected for the reason ledger row
      // **P8-1** already records — a narrowing invented here would silently
      // block a legitimate provider at booking time.
      // `docs/decisions/28-phase-17-1-bookings.md` carries it.
      return {
        amountLaari: rate * Math.max(1, Math.ceil(durationMinutes / (24 * 60))),
        amountKind: 'daily_total',
      };
  }
}

/** Whole minutes between two instants. The slot row supplies both. */
export function durationMinutes(startsAt: Date, endsAt: Date): number {
  return Math.round((endsAt.getTime() - startsAt.getTime()) / 60_000);
}
