import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { FREE_TIER_ACTIVE_LISTING_CAP } from '../src/modules/listings/entitlements.js';
import { PREMIUM_ACTIVE_LISTING_CAP } from '../src/modules/subscriptions/entitlements.js';
import { applyEntitlementVisibility } from '../src/modules/subscriptions/downgrade.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';
import { completeDraft, ensureCategoriesSeeded, publish } from './helpers/listings.js';
import { ensureIslandsSeeded } from './helpers/islands.js';
import { FakeBookings } from './helpers/subscriptions.js';
import { registerUser } from './helpers/users.js';

/**
 * §1b's downgrade rule, over real listings and against the booking seam.
 *
 * > **Downgrade is non-destructive and reversible.** Listings beyond the
 * > free-tier cap are hidden (`visibility: 'hidden_over_cap'`), never
 * > deleted… **Protected listings:** a listing with a booking in `accepted`,
 * > `awaiting_payment`, `payment_claimed`, `payment_unresolved`, or
 * > `confirmed` status and a future `scheduledFor` **stays visible regardless
 * > of cap**… 🔧 **Among unprotected listings, keep the highest-performing
 * > one visible** — ranked by confirmed bookings over the trailing 90 days,
 * > falling back to listing views where booking counts tie, and only to
 * > recency where a provider has neither.
 */
describe.skipIf(databaseUrl === undefined)('§1b downgrade and restore', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  const bookings = new FakeBookings();

  beforeAll(async () => {
    ({ app } = await buildTestApp({ deps: { subscriptionBookings: bookings } }));
    await ensureCategoriesSeeded(app.deps.prisma);
    await ensureIslandsSeeded(app.deps.prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  /**
   * A provider holding `count` published listings.
   *
   * They are given a premium subscription first, because the free cap of one
   * is exactly the rule under test — the fixture has to be able to exceed it,
   * and it does so through the same entitlement the real publish gate reads
   * rather than by writing `visibility` directly.
   */
  async function providerWithPublishedListings(count: number) {
    const user = await registerUser(app, { role: 'provider' });
    const draft = await completeDraft(app, user.headers);
    const profile = await app.providers.repo.findByUserId(user.userId);
    if (profile === null) throw new Error('no provider profile');
    await app.deps.prisma.providerSubscription.create({
      data: { providerProfileId: profile.id, tier: 'premium', status: 'active' },
    });

    const ids: string[] = [];
    for (const listing of [draft, ...(await drafts(user, count - 1))]) {
      const res = await publish(app, user.headers, listing.id);
      expect(res.statusCode).toBe(200);
      ids.push(listing.id);
    }
    return { user, profileId: profile.id, listingIds: ids };
  }

  async function drafts(user: Awaited<ReturnType<typeof registerUser>>, count: number) {
    const made = [];
    for (let i = 0; i < count; i++) made.push(await completeDraft(app, user.headers));
    return made;
  }

  function visibilityOf(id: string) {
    return app.deps.prisma.listing
      .findUniqueOrThrow({ where: { id }, select: { visibility: true, status: true } })
      .then((row) => row);
  }

  it('hides everything over the cap, keeps the row published, and restores exactly what it hid', async () => {
    const { profileId, listingIds } = await providerWithPublishedListings(3);
    const now = new Date();

    const down = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      now,
    );
    expect(down.hidden).toHaveLength(2);
    expect(down.keptVisible).toHaveLength(1);

    // Non-destructive: `status` stays `published`, nothing is deleted, and
    // the value used is the entitlement system's own — never
    // `hidden_by_provider`, which would be indistinguishable from a listing
    // the provider took down themselves (§1b, Round 17).
    for (const id of down.hidden) {
      expect(await visibilityOf(id)).toEqual({
        visibility: 'hidden_over_cap',
        status: 'published',
      });
    }

    // "Any confirmed payment restores everything" — the same function, run
    // with the premium cap, brings back exactly the two it hid.
    const up = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      PREMIUM_ACTIVE_LISTING_CAP,
      now,
    );
    expect(up.restored.sort()).toEqual(down.hidden.sort());
    for (const id of listingIds) {
      expect((await visibilityOf(id)).visibility).toBe('active');
    }
  });

  it('never resurrects a listing the provider hid themselves', async () => {
    // §1b, Round 17: "`hidden_over_cap` is set and cleared **only** by the
    // entitlement system; `hidden_by_provider` **only** by the provider…
    // under a single `hidden` value the two are indistinguishable and a paid
    // upgrade would silently republish something the provider had
    // deliberately withdrawn."
    const { profileId, listingIds } = await providerWithPublishedListings(2);
    const [first] = listingIds;
    if (first === undefined) throw new Error('fixture');
    await app.deps.prisma.listing.update({
      where: { id: first },
      data: { visibility: 'hidden_by_provider' },
    });

    const up = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      PREMIUM_ACTIVE_LISTING_CAP,
      new Date(),
    );
    expect(up.restored).not.toContain(first);
    expect((await visibilityOf(first)).visibility).toBe('hidden_by_provider');
  });

  it('protects a listing with a committed future job, and hides it once that job ends', async () => {
    // §Phase 8a's Done-when: "a downgrade skips hiding any listing with a
    // confirmed future booking and hides it the moment that booking
    // completes."
    const { profileId, listingIds } = await providerWithPublishedListings(2);
    const [protectedListing, other] = listingIds;
    if (protectedListing === undefined || other === undefined) throw new Error('fixture');
    bookings.commit(protectedListing);

    const down = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      new Date(),
    );
    expect(down.protectedFromHiding).toEqual([protectedListing]);
    expect(down.hidden).toEqual([other]);
    expect((await visibilityOf(protectedListing)).visibility).toBe('active');

    // The booking terminates. The protection goes with it, and the next
    // reconcile hides the listing — which is why the rule is re-asked every
    // sweep rather than decided once at downgrade.
    bookings.complete(protectedListing);
    const after = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      new Date(),
    );
    expect(after.hidden).toEqual([protectedListing]);
    expect((await visibilityOf(protectedListing)).visibility).toBe('hidden_over_cap');
  });

  it('keeps every protected listing even when they exceed the cap on their own', async () => {
    // "Stays visible **regardless of cap**". Two committed jobs on a
    // one-listing cap means two visible listings, because hiding a listing
    // out from under a customer who has a confirmed booking against it breaks
    // a commitment the platform vouched for.
    const { profileId, listingIds } = await providerWithPublishedListings(3);
    const [a, b, c] = listingIds;
    if (a === undefined || b === undefined || c === undefined) throw new Error('fixture');
    bookings.commit(a);
    bookings.commit(b);

    const down = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      new Date(),
    );
    expect(down.hidden).toEqual([c]);
    expect((await visibilityOf(a)).visibility).toBe('active');
    expect((await visibilityOf(b)).visibility).toBe('active');
  });

  it('keeps the listing with the most confirmed bookings in the last 90 days', async () => {
    // 🔧 The ranking, and the reason it is not "most recently updated": that
    // rule "a provider who knew the rule could game by touching their
    // preferred listing more often than the others, regardless of which
    // actually performed".
    const { profileId, listingIds } = await providerWithPublishedListings(3);
    const [oldest, middle, newest] = listingIds;
    if (oldest === undefined || middle === undefined || newest === undefined) {
      throw new Error('fixture');
    }
    const now = new Date();
    const events = (listingId: string, kind: 'booking' | 'view', count: number, daysAgo: number) =>
      app.deps.prisma.listingEvent.createMany({
        data: Array.from({ length: count }, () => ({
          listingId,
          kind,
          occurredAt: new Date(now.getTime() - daysAgo * 24 * 60 * 60 * 1000),
        })),
      });

    // The oldest listing performs; the newest is merely new.
    await events(oldest, 'booking', 2, 10);
    await events(newest, 'view', 500, 10);

    const down = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      now,
    );
    expect(down.keptVisible).toEqual([oldest]);

    // A booking outside the 90-day window does not count — the window is
    // what makes this a performance measure rather than a history one.
    await app.deps.prisma.listing.updateMany({
      where: { id: { in: listingIds } },
      data: { visibility: 'active' },
    });
    await app.deps.prisma.listingEvent.deleteMany({ where: { listingId: oldest } });
    await events(oldest, 'booking', 5, 120);
    await events(middle, 'booking', 1, 5);
    const again = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      now,
    );
    expect(again.keptVisible).toEqual([middle]);
  });

  it('falls back to views, then to first-publication recency', async () => {
    const { profileId, listingIds } = await providerWithPublishedListings(3);
    const [first, second, third] = listingIds;
    if (first === undefined || second === undefined || third === undefined) {
      throw new Error('fixture');
    }
    const now = new Date();

    // No bookings anywhere — which is the whole platform today — so views
    // decide.
    await app.deps.prisma.listingEvent.createMany({
      data: Array.from({ length: 3 }, () => ({ listingId: second, kind: 'view' as const })),
    });
    const byViews = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      now,
    );
    expect(byViews.keptVisible).toEqual([second]);

    // Nothing at all: recency decides, and it reads `firstPublishedAt` —
    // written once and never cleared — rather than `updatedAt`, which a
    // provider can bump at will.
    await app.deps.prisma.listing.updateMany({
      where: { id: { in: listingIds } },
      data: { visibility: 'active' },
    });
    await app.deps.prisma.listingEvent.deleteMany({ where: { listingId: second } });
    await app.deps.prisma.listing.update({
      where: { id: third },
      data: { firstPublishedAt: new Date(now.getTime() + 60_000) },
    });
    // The gameable field is moved on a *different* listing, and must not win.
    await app.deps.prisma.listing.update({
      where: { id: first },
      data: { updatedAt: new Date(now.getTime() + 120_000) },
    });
    const byRecency = await applyEntitlementVisibility(
      app.deps.prisma,
      bookings,
      profileId,
      FREE_TIER_ACTIVE_LISTING_CAP,
      now,
    );
    expect(byRecency.keptVisible).toEqual([third]);
  });
});
