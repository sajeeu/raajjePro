import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { ENDING_NOTICE_DAYS, addDays } from '../src/modules/subscriptions/period.js';
import { SubscriptionRepository } from '../src/modules/subscriptions/repository.js';
import { buildTestApp, controllableClock } from './helpers/app.js';
import { registerUser } from './helpers/users.js';
import { completeDraft, ensureCategoriesSeeded, publish } from './helpers/listings.js';
import { ensureIslandsSeeded } from './helpers/islands.js';

/**
 * §1b's lifecycle sweep reads only rows it could act on.
 *
 * This is a cost property, and it is asserted as a *set* rather than by
 * counting queries, because the set is the thing that has to be right: the
 * sweep still re-checks every condition in TypeScript, so a row wrongly
 * included costs a no-op, while a row wrongly excluded silently stops billing
 * someone.
 *
 * It matters because the query it replaced listed all five statuses — the
 * whole enum — so an hourly job read every subscription ever created and then
 * decided almost none of them had anything to do. On a test database holding
 * a thousand accumulated rows that crossed five seconds, which is how it was
 * found; in production it is §Phase 21's wall-clock budget.
 */

const NOW = new Date('2026-09-14T08:00:00.000Z');
const time = controllableClock(NOW);
let app: Awaited<ReturnType<typeof buildApp>>;
let repo: SubscriptionRepository;

/** A provider with a subscription row in whatever state the caller needs. */
async function providerWith(
  data: Parameters<typeof buildRow>[0],
  options: { withListing?: boolean } = {},
): Promise<string> {
  const user = await registerUser(app, { role: 'provider' });
  const profile = await app.providers.getOrCreateProviderProfile(user.userId);
  if (options.withListing === true) {
    const listing = await completeDraft(app, user.headers);
    await publish(app, user.headers, listing.id);
  }
  await app.deps.prisma.providerSubscription.create({
    data: { providerProfileId: profile.id, ...buildRow(data) },
  });
  return profile.id;
}

function buildRow(data: Record<string, unknown>): Record<string, unknown> {
  return data;
}

beforeAll(async () => {
  ({ app } = await buildTestApp({ clock: time.clock }));
  repo = new SubscriptionRepository(app.deps.prisma);
  await ensureCategoriesSeeded(app.deps.prisma);
  await ensureIslandsSeeded(app.deps.prisma);
});

afterAll(async () => {
  await app.close();
});

describe('the lifecycle sweep reads only what it could act on', () => {
  it('skips the rows that can do nothing and keeps every row that can', async () => {
    const [
      freeNoListings,
      freeWithListing,
      trialingFarOff,
      trialingNearingEnd,
      activeFarOff,
      activeNearingEnd,
      paused,
      expired,
      downgradedAwaitingWinback,
      downgradedFullyNotified,
    ] = await Promise.all([
      // Nothing to reconcile: free, and no listing to hide or restore. This
      // is the row the old query read a thousand times for nothing.
      providerWith({ status: 'free' }),
      providerWith({ status: 'free' }, { withListing: true }),
      providerWith({ status: 'trialing', trialEndsAt: addDays(NOW, ENDING_NOTICE_DAYS + 5) }),
      providerWith({ status: 'trialing', trialEndsAt: addDays(NOW, ENDING_NOTICE_DAYS - 1) }),
      providerWith({
        status: 'active',
        currentPeriodEnd: addDays(NOW, ENDING_NOTICE_DAYS + 5),
        billingAnchorAt: addDays(NOW, -25),
      }),
      providerWith({
        status: 'active',
        currentPeriodEnd: addDays(NOW, ENDING_NOTICE_DAYS - 1),
        billingAnchorAt: addDays(NOW, -29),
      }),
      providerWith({ status: 'paused', pausedAt: addDays(NOW, -2) }),
      providerWith({ status: 'expired', trialEndsAt: addDays(NOW, -1) }),
      providerWith({ status: 'free', downgradedAt: addDays(NOW, -8), winbackDay7At: null }),
      providerWith({
        status: 'free',
        downgradedAt: addDays(NOW, -40),
        winbackDay7At: addDays(NOW, -33),
        winbackDay30At: addDays(NOW, -10),
      }),
    ]);

    const ids = new Set(
      (await repo.findLifecycleCandidates(NOW)).map((row) => row.providerProfileId),
    );

    // Read, because each one has work waiting at this instant.
    expect(ids).toContain(freeWithListing);
    expect(ids).toContain(trialingNearingEnd);
    expect(ids).toContain(activeNearingEnd);
    expect(ids).toContain(paused);
    expect(ids).toContain(expired);
    expect(ids).toContain(downgradedAwaitingWinback);

    // Not read, because nothing in §1b's lifecycle applies to them now.
    expect(ids).not.toContain(freeNoListings);
    expect(ids).not.toContain(trialingFarOff);
    expect(ids).not.toContain(activeFarOff);
    expect(ids).not.toContain(downgradedFullyNotified);
  });

  it('reads a trial the moment it crosses the notice horizon, not a day late', async () => {
    // The boundary, because an off-by-one here is a warning that never sends
    // rather than a warning that sends twice — the sweep stamps its notices.
    const profileId = await providerWith({
      status: 'trialing',
      trialEndsAt: addDays(NOW, ENDING_NOTICE_DAYS),
    });

    const ids = new Set(
      (await repo.findLifecycleCandidates(NOW)).map((row) => row.providerProfileId),
    );
    expect(ids).toContain(profileId);
  });
});
