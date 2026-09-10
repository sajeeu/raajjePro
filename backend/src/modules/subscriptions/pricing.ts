import { randomInt } from 'node:crypto';

import type { PrismaClient } from '../../generated/prisma/client.js';

/**
 * §1b's money, in one place.
 *
 * Every number here is **integer laari** (invariant 7): MVR × 100, never a
 * float, never a decimal-as-string, and never converted to one on the way
 * out.
 */

/**
 * The standard rate — MVR 150/month (§1b).
 *
 * 🔧 It is a **default for a provider whose price is not yet set**, not a
 * platform price. §Phase 8a: "`amount` reads the provider's
 * `subscriptionPriceLaari`, defaulting to MVR 150 = 15000 laari for anyone
 * outside the introductory cohort. Never a global constant and never a
 * range." Older documentation pinned one global price, and the conversion
 * measurement §Phase 10c exists to show depends on two price points
 * coexisting.
 */
export const STANDARD_PRICE_LAARI = 15_000;

/** §1b, Round 14: the introductory rate is MVR 75 — half the standard rate. */
export const INTRODUCTORY_PRICE_LAARI = 7_500;

/** §1b: "the **first 100 providers** are set to the introductory rate; everyone after them takes the standard rate." */
export const INTRODUCTORY_COHORT_SIZE = 100;

/** §1b: "the introductory rate is **honoured for 12 months from the billing anchor**, then converts to standard with 30 days' notice." */
export const INTRODUCTORY_MONTHS = 12;

/** How much warning §1b requires before the introductory rate converts. */
export const INTRODUCTORY_NOTICE_DAYS = 30;

export interface ResolvedPrice {
  amountLaari: number;
  /** True while this is §1b's introductory rate — what the 12-month honouring clock reads. */
  introductory: boolean;
}

/**
 * §1b's price rule, as a function of the only two things it depends on.
 *
 * > A **`subscriptionPriceLaari`** field lives on the provider record, set at
 * > their first confirmed payment and honoured on every renewal thereafter…
 * > The **first 100 providers** are set to the introductory rate of MVR 75;
 * > everyone after them takes the standard rate. **The cohort boundary is the
 * > field's value, not a rule evaluated later** — a provider's price never
 * > changes because of someone else's signup.
 *
 * Pure, because the boundary is the part worth asserting and a shared
 * database cannot be positioned on either side of it: this suite's rows are
 * never deleted (`test/setup.ts`), so the hundredth priced provider is
 * somewhere in its history and every later run is past the boundary for good.
 * The pure function is testable at 99 and at 100; `priceForProvider` below is
 * this plus one query.
 */
export function resolvePrice(input: {
  /** The provider's own `subscriptionPriceLaari`, or null if no payment has been confirmed yet. */
  settledLaari: number | null;
  /** How many providers already have a price written — §1b's cohort, counted by the field. */
  pricedProviderCount: number;
}): ResolvedPrice {
  if (input.settledLaari !== null) {
    return {
      amountLaari: input.settledLaari,
      introductory: input.settledLaari === INTRODUCTORY_PRICE_LAARI,
    };
  }
  return input.pricedProviderCount < INTRODUCTORY_COHORT_SIZE
    ? { amountLaari: INTRODUCTORY_PRICE_LAARI, introductory: true }
    : { amountLaari: STANDARD_PRICE_LAARI, introductory: false };
}

/**
 * What this provider pays for their next period — `resolvePrice` over the
 * live rows.
 *
 * The count is taken at **quote time** rather than at confirmation, so a
 * provider is charged what they were shown: §1b's honouring rule is about the
 * field, and the field is written from this quote when the payment is
 * confirmed.
 */
export async function priceForProvider(
  prisma: PrismaClient,
  providerProfileId: string,
): Promise<ResolvedPrice> {
  const profile = await prisma.providerProfile.findUnique({
    where: { id: providerProfileId },
    select: { subscriptionPriceLaari: true },
  });
  const settledLaari = profile?.subscriptionPriceLaari ?? null;
  return resolvePrice({
    settledLaari,
    // Skipped where the price is already settled: the count cannot change the
    // answer, and this runs on every read of the billing screen.
    pricedProviderCount:
      settledLaari !== null
        ? 0
        : await prisma.providerProfile.count({ where: { subscriptionPriceLaari: { not: null } } }),
  });
}

/**
 * The reference code the provider writes on their bank transfer and the admin
 * matches the receipt against (§1b step 2).
 *
 * Two properties matter and neither is cryptographic:
 *
 *  - **A human copies it by hand**, off a phone screen and into a bank app.
 *    So there is no `0`/`O`, no `1`/`I`, no `5`/`S`, and a hyphen every four
 *    characters. §Phase 10a's receipt analysis has to read it back off a photo
 *    of a bank-app screen, and its "couldn't read" outcome is common enough
 *    without an alphabet that invites transcription errors.
 *  - **It is not a secret.** It identifies a submission to an admin holding
 *    the bank statement; it authorizes nothing. `randomInt` rather than
 *    `Math.random` all the same, so codes cannot be predicted and enumerated
 *    across providers.
 */
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRTUVWXY2346789';

export function generateReferenceCode(): string {
  const body = Array.from({ length: 8 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join(
    '',
  );
  return `RP-${body.slice(0, 4)}-${body.slice(4)}`;
}
