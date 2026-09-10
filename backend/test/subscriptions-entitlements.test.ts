import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { FREE_TIER_ACTIVE_LISTING_CAP } from '../src/modules/listings/entitlements.js';
import {
  PREMIUM_ACTIVE_LISTING_CAP,
  getProviderEntitlements,
  providerEntitlementReader,
} from '../src/modules/subscriptions/entitlements.js';
import { databaseUrl } from './helpers/app.js';

/**
 * §Phase 8a: "`getProviderEntitlements(providerId)` — **the single source of
 * tier truth**, live DB read every call, no caching, nothing granted on a
 * `pending` submission."
 *
 * Asserted here at the function, over real rows, because the three properties
 * that matter are properties of the *read* rather than of any endpoint: what a
 * missing row means, which statuses carry premium, and the structural
 * impossibility of a pending payment granting anything.
 */
describe.skipIf(databaseUrl === undefined)('getProviderEntitlements', () => {
  let prisma: PrismaClient;

  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  async function providerProfile() {
    const user = await prisma.user.create({
      data: {
        email: `u-${randomUUID()}@example.test`,
        passwordHash: 'x',
        fullName: 'Test',
        termsAcceptedAt: new Date(),
      },
    });
    return prisma.providerProfile.create({ data: { userId: user.id } });
  }

  it('answers the free tier for a provider with no subscription row at all', async () => {
    // §1b's free tier is "1 active listing, full search visibility (**never**
    // paywalled), no analytics", and a provider with no row is on it by
    // definition — there is no table for them to be in. So this is not a
    // default standing in for a real answer; for most providers it *is* the
    // answer.
    const profile = await providerProfile();
    expect(await getProviderEntitlements(prisma, profile.id)).toEqual({
      providerProfileId: profile.id,
      tier: 'free',
      status: 'free',
      activeListingCap: FREE_TIER_ACTIVE_LISTING_CAP,
      analytics: false,
      priorityPlacement: false,
    });
  });

  it('grants nothing at all for a pending submission, however many there are', async () => {
    // §1b: "**nothing is granted on submission.** A `pending` submission
    // produces entitlements identical to no payment at all."
    //
    // Structural rather than conditional: this function reads
    // `provider_subscription` and cannot see `payment_submission`, so there is
    // no branch to get wrong. The assertion is that adding submissions
    // changes the answer not at all.
    const profile = await providerProfile();
    const before = await getProviderEntitlements(prisma, profile.id);
    for (let i = 0; i < 3; i++) {
      await prisma.paymentSubmission.create({
        data: {
          payerId: profile.userId,
          purpose: 'subscription',
          amountLaari: 15_000,
          referenceCode: `RP-${randomUUID().slice(0, 8).toUpperCase()}`,
          status: 'pending',
          submittedAt: new Date(),
        },
      });
    }
    expect(await getProviderEntitlements(prisma, profile.id)).toEqual(before);
  });

  it('carries premium through trialing, active, paused and the grace period', async () => {
    // `expired` is §1b's grace: "7 days after expiry **with nothing
    // changing**, then downgrade to free". If `expired` dropped the tier
    // there would be no grace, only a downgrade with a seven-day delay before
    // the notification. `paused` carries it because pausing stops the billing
    // clock and is never described as a downgrade.
    const profile = await providerProfile();
    await prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, tier: 'premium', status: 'trialing' },
    });

    for (const status of ['trialing', 'active', 'paused', 'expired'] as const) {
      await prisma.providerSubscription.update({
        where: { providerProfileId: profile.id },
        data: { status },
      });
      const entitlements = await getProviderEntitlements(prisma, profile.id);
      expect(entitlements.tier).toBe('premium');
      expect(entitlements.status).toBe(status);
      expect(entitlements.activeListingCap).toBe(PREMIUM_ACTIVE_LISTING_CAP);
      expect(entitlements.analytics).toBe(true);
      expect(entitlements.priorityPlacement).toBe(true);
    }

    // …and `free` is the one status that does not, whatever the stored tier
    // says. A row left `premium`/`free` by a partial write reads as free,
    // because the status is the lifecycle and the downgrade is what happened.
    await prisma.providerSubscription.update({
      where: { providerProfileId: profile.id },
      data: { status: 'free' },
    });
    const downgraded = await getProviderEntitlements(prisma, profile.id);
    expect(downgraded.tier).toBe('free');
    expect(downgraded.activeListingCap).toBe(FREE_TIER_ACTIVE_LISTING_CAP);
    expect(downgraded.analytics).toBe(false);
  });

  it('reads the database on every call, with nothing cached between them', async () => {
    // §Phase 8a requires this in as many words. §1b's downgrade and restore
    // are supposed to take effect at once — "any confirmed payment restores
    // everything" — and a cache is how a provider pays and then waits for
    // something to expire.
    const profile = await providerProfile();
    expect((await getProviderEntitlements(prisma, profile.id)).tier).toBe('free');
    await prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, tier: 'premium', status: 'active' },
    });
    expect((await getProviderEntitlements(prisma, profile.id)).tier).toBe('premium');
    await prisma.providerSubscription.update({
      where: { providerProfileId: profile.id },
      data: { tier: 'free', status: 'free' },
    });
    expect((await getProviderEntitlements(prisma, profile.id)).tier).toBe('free');
  });

  it('fills §Phase 8’s cap seam without changing its interface', async () => {
    // 🔧 §Phase 8 defined `ProviderEntitlementReader` — one method, one
    // number — and shipped `FREE_TIER_ONLY`, which answered the free-tier cap
    // for everybody because with no subscription table every provider was on
    // it. This phase replaces the *implementation* and the interface is
    // untouched, which is the whole point of the pattern.
    const profile = await providerProfile();
    const reader = providerEntitlementReader(prisma);
    expect(await reader.activeListingCap(profile.id)).toBe(FREE_TIER_ACTIVE_LISTING_CAP);

    await prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, tier: 'premium', status: 'active' },
    });
    // 🔧 Premium's cap is unlimited: §1b says premium "unlocks multiple
    // active listings" and names no number, so inventing one would put a
    // limit in the product that no section asked for.
    expect(await reader.activeListingCap(profile.id)).toBe(Number.POSITIVE_INFINITY);
  });

  it('never reads or writes the verification tier', async () => {
    // §1b and §1e: "**the badge is gated by `verificationTier` alone, never
    // by subscription state.**" There is no field on the entitlement shape an
    // accidental gate could hang from, and a lapsing subscription leaves the
    // provider's tier exactly where it was.
    const profile = await providerProfile();
    await prisma.providerProfile.update({
      where: { id: profile.id },
      data: { verificationTier: 'gold', verificationStatus: 'verified' },
    });
    await prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, tier: 'free', status: 'free' },
    });
    const entitlements = await getProviderEntitlements(prisma, profile.id);
    expect(Object.keys(entitlements).sort()).toEqual([
      'activeListingCap',
      'analytics',
      'priorityPlacement',
      'providerProfileId',
      'status',
      'tier',
    ]);
    const after = await prisma.providerProfile.findUniqueOrThrow({ where: { id: profile.id } });
    expect(after.verificationTier).toBe('gold');
  });

  it('stores no derived entitlement anywhere in the schema', async () => {
    // §1a's argument, applied to this phase: a stored copy of a derived
    // answer drifts. There is no `is_premium`, no `entitlement_tier` and no
    // `active_listing_cap` column — the tier lives on the subscription row as
    // its lifecycle state, and everything else is computed from it on every
    // read. (The same check that keeps `lifecycle_status` out of
    // `provider_profile`, in `test/listings-visibility.test.ts`.)
    const columns = await prisma.$queryRaw<{ table_name: string; column_name: string }[]>`
      SELECT table_name, column_name FROM information_schema.columns
      WHERE table_schema = 'public'
        AND column_name IN (
          'is_premium', 'entitlement_tier', 'active_listing_cap', 'listing_cap',
          'has_analytics', 'is_paused', 'cumulative_paused_days'
        )
    `;
    expect(columns).toEqual([]);
  });
});
