import type { PrismaClient } from '../../generated/prisma/client.js';
import type { SubscriptionStatus, SubscriptionTier } from '../../generated/prisma/enums.js';
import {
  FREE_TIER_ACTIVE_LISTING_CAP,
  type ProviderEntitlementReader,
} from '../listings/entitlements.js';

/**
 * §Phase 8a: "`getProviderEntitlements(providerId)` — **the single source of
 * tier truth**, live DB read every call, no caching, nothing granted on a
 * `pending` submission."
 *
 * ## The three properties that are the whole point
 *
 * 1. **Live read, never cached.** No memo, no TTL, no request-scoped
 *    stash. §1b's downgrade and restore are supposed to take effect at once
 *    — "any confirmed payment restores everything" — and a cache is how a
 *    provider pays and then waits for something to expire.
 * 2. **Nothing is granted on submission.** This function reads
 *    `provider_subscription` and nothing else. It cannot see
 *    `payment_submission`, so a `pending` row is structurally incapable of
 *    unlocking anything: "a `pending` submission produces entitlements
 *    identical to no payment at all" (§1b).
 * 3. **A missing row means the free tier**, not an error and not unknown. No
 *    row is created at signup, so this is the state most providers are in.
 *
 * ## What is deliberately not here
 *
 * The **badge**. §1b and §1e are explicit that `verificationTier` is
 * unaffected by subscription state — "a lapsed-but-verified provider keeps
 * their tier; it is a safety signal, not a payment status" — so nothing in
 * this file reads or returns it, and a caller cannot accidentally gate a
 * badge on a subscription because there is no field here to gate on.
 *
 * **Suspension**, likewise: §1a makes it an input to `findVisibleProviders`,
 * not a second filter reimplemented per query, and an entitlement is not a
 * visibility rule.
 */

/**
 * §1b: premium "unlocks multiple active listings", and names no number.
 *
 * So the cap is **not a number** — it is the absence of one. Inventing a
 * figure (five? ten?) would put a limit in the product that no section of the
 * plan asked for, and a provider would hit it with no rule to point at. The
 * DTO renders this as `null`, meaning "no limit", because `Infinity` is not
 * representable in JSON.
 */
export const PREMIUM_ACTIVE_LISTING_CAP = Number.POSITIVE_INFINITY;

export interface ProviderEntitlements {
  providerProfileId: string;
  /** What is unlocked. Never `verificationTier` — see the note above. */
  tier: SubscriptionTier;
  /** Where in the lifecycle this provider is. `free` for a provider with no row at all. */
  status: SubscriptionStatus;
  /** How many listings may be `published` + `active` at once (§1b). `Infinity` on premium. */
  activeListingCap: number;
  /** §1b: the analytics dashboard and weekly digest are premium. Phase 19 reads this. */
  analytics: boolean;
  /** §1b: premium places higher in search. Phases 15 and 16 read this. */
  priorityPlacement: boolean;
}

/**
 * Which statuses carry premium.
 *
 * `expired` is in the list and that is §1b's grace period working as
 * specified: "7 days after expiry **with nothing changing**, then downgrade to
 * free". If `expired` dropped the tier immediately there would be no grace,
 * only a downgrade with a seven-day delay before the notification.
 *
 * `paused` is in the list because pausing stops the billing clock, and §1b
 * never describes it as a downgrade — the provider has simply stopped taking
 * new customers for a few days.
 */
function tierFor(status: SubscriptionStatus, stored: SubscriptionTier): SubscriptionTier {
  return status === 'free' ? 'free' : stored;
}

export function freeTierEntitlements(providerProfileId: string): ProviderEntitlements {
  return {
    providerProfileId,
    tier: 'free',
    status: 'free',
    // §1b's free tier: "1 active listing, full search visibility (**never**
    // paywalled), no analytics". Imported rather than re-typed, so the number
    // the cap enforces and the number Phase 8's publish gate reads are the
    // same constant.
    activeListingCap: FREE_TIER_ACTIVE_LISTING_CAP,
    analytics: false,
    // Never true on free — and note what is *not* gated: §1b's "full search
    // visibility (never paywalled)". Free listings are found; paid ones are
    // found sooner.
    priorityPlacement: false,
  };
}

export async function getProviderEntitlements(
  prisma: PrismaClient,
  providerProfileId: string,
): Promise<ProviderEntitlements> {
  const row = await prisma.providerSubscription.findUnique({
    where: { providerProfileId },
    select: { tier: true, status: true },
  });
  if (row === null) return freeTierEntitlements(providerProfileId);

  const tier = tierFor(row.status, row.tier);
  if (tier === 'free') {
    return { ...freeTierEntitlements(providerProfileId), status: row.status };
  }
  return {
    providerProfileId,
    tier,
    status: row.status,
    activeListingCap: PREMIUM_ACTIVE_LISTING_CAP,
    analytics: true,
    priorityPlacement: true,
  };
}

/**
 * 🔧 **The seam §Phase 8 opened, filled** (§Phase 8's publish bullet, and the
 * brief for this phase: "replace the default with `getProviderEntitlements`
 * and change no caller").
 *
 * `ProviderEntitlementReader` is Phase 8's own narrow interface — one method,
 * one number — and it is unchanged. Phase 8's `FREE_TIER_ONLY` returned the
 * free-tier cap for everyone because with no `provider_subscription` table
 * every provider was on the free tier; this returns the live answer for each
 * provider, and `ListingService` does not know the difference.
 */
export function providerEntitlementReader(prisma: PrismaClient): ProviderEntitlementReader {
  return {
    async activeListingCap(providerProfileId: string): Promise<number> {
      return (await getProviderEntitlements(prisma, providerProfileId)).activeListingCap;
    },
  };
}
