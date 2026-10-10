import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { ProfileSummaryDto } from '../src/modules/account/dto.js';
import type {
  FavoriteListingDto,
  FavoriteProviderDto,
  FavoriteStatusDto,
} from '../src/modules/favorites/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { providerWithSlotListing } from './helpers/availability.js';
import { completeDraft } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

const BASE = '/v1/users/me/favorites';

/**
 * §Phase 14 — **Done when:** "tapping the heart anywhere persists via API; the
 * Saved Services screen reflects it immediately; Profile's count updates."
 *
 * The server's half of each clause: a save and an unsave persist and are
 * idempotent, for a listing and — Round 15 — for a provider; the lists the
 * Saved screen reads return exactly what was saved, newest first; and
 * `profile-summary`'s count moves with every save and unsave, by the same
 * visibility rule the lists use. Alongside: the §1c access tier (Registered),
 * the §1a gate on what can be saved and shown, the contact rule on every
 * shape, and invariant 8 (an unsave stamps; nothing is removed).
 */
describe.skipIf(databaseUrl === undefined)('Phase 14 — Done when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
  });
  afterAll(async () => {
    await app.close();
  });

  function call(method: 'GET' | 'PUT' | 'DELETE', url: string, user?: RegisteredUser) {
    return app.inject({
      method,
      url,
      remoteAddress: freshIp(),
      headers: user?.headers ?? {},
    });
  }

  async function ok<T>(method: 'GET' | 'PUT' | 'DELETE', url: string, user: RegisteredUser) {
    const res = await call(method, url, user);
    expect(res.statusCode, res.body).toBe(200);
    return res.json<Envelope<T>>();
  }

  const savedListings = async (user: RegisteredUser) =>
    (await ok<FavoriteListingDto[]>('GET', `${BASE}/listings?limit=50`, user)).data;
  const savedProviders = async (user: RegisteredUser) =>
    (await ok<FavoriteProviderDto[]>('GET', `${BASE}/providers?limit=50`, user)).data;
  const savedCount = async (user: RegisteredUser) =>
    (await ok<ProfileSummaryDto>('GET', '/v1/users/me/profile-summary', user)).data.saved;

  describe('1. tapping the heart persists via the API', () => {
    it('a saved listing persists, and unsaving it persists too', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);

      const saved = await ok<{ saved: boolean }>(
        'PUT',
        `${BASE}/listings/${p.listingId}`,
        customer,
      );
      expect(saved.data).toEqual({ saved: true });
      const status = await ok<FavoriteStatusDto>(
        'GET',
        `${BASE}/status?listingIds=${p.listingId}`,
        customer,
      );
      expect(status.data.listingIds).toEqual([p.listingId]);

      const unsaved = await ok<{ saved: boolean }>(
        'DELETE',
        `${BASE}/listings/${p.listingId}`,
        customer,
      );
      expect(unsaved.data).toEqual({ saved: false });
      const after = await ok<FavoriteStatusDto>(
        'GET',
        `${BASE}/status?listingIds=${p.listingId}`,
        customer,
      );
      expect(after.data.listingIds).toEqual([]);
    });

    it('a saved provider persists (Round 15), and unsaving it persists too', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);

      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, customer);
      expect(
        (
          await ok<FavoriteStatusDto>(
            'GET',
            `${BASE}/status?providerIds=${p.providerProfileId}`,
            customer,
          )
        ).data.providerIds,
      ).toEqual([p.providerProfileId]);

      await ok('DELETE', `${BASE}/providers/${p.providerProfileId}`, customer);
      expect(
        (
          await ok<FavoriteStatusDto>(
            'GET',
            `${BASE}/status?providerIds=${p.providerProfileId}`,
            customer,
          )
        ).data.providerIds,
      ).toEqual([]);
    });

    it('is idempotent both ways: a retried save or unsave lands on the same state, never toggles back', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);

      // Five concurrent saves — a double tap and its retries — leave exactly one row.
      const saves = await Promise.all(
        Array.from({ length: 5 }, () => call('PUT', `${BASE}/listings/${p.listingId}`, customer)),
      );
      expect(saves.map((r) => r.statusCode)).toEqual([200, 200, 200, 200, 200]);
      expect(
        await app.deps.prisma.favoriteListing.count({
          where: { userId: customer.userId, listingId: p.listingId },
        }),
      ).toBe(1);

      await ok('DELETE', `${BASE}/listings/${p.listingId}`, customer);
      await ok('DELETE', `${BASE}/listings/${p.listingId}`, customer);
      expect(await savedListings(customer)).toEqual([]);

      // Unsaving something never saved is not an error either.
      await ok('DELETE', `${BASE}/providers/${p.providerProfileId}`, customer);
    });

    it('an unsave stamps the row and a re-save revives it — nothing is removed (invariant 8)', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      const where = { userId: customer.userId, listingId: p.listingId };

      await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
      const first = await app.deps.prisma.favoriteListing.findFirstOrThrow({ where });
      await ok('DELETE', `${BASE}/listings/${p.listingId}`, customer);
      const stamped = await app.deps.prisma.favoriteListing.findFirstOrThrow({ where });
      expect(stamped.id).toBe(first.id);
      expect(stamped.deletedAt).not.toBeNull();

      await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
      const revived = await app.deps.prisma.favoriteListing.findFirstOrThrow({ where });
      expect(revived.id).toBe(first.id);
      expect(revived.deletedAt).toBeNull();
    });

    it('needs an account and nothing more — a guest is refused, an unverified email is not (§1c: Registered)', async () => {
      const p = await providerWithSlotListing(app);
      expect((await call('PUT', `${BASE}/listings/${p.listingId}`)).statusCode).toBe(401);
      expect((await call('PUT', `${BASE}/providers/${p.providerProfileId}`)).statusCode).toBe(401);
      expect((await call('GET', `${BASE}/listings`)).statusCode).toBe(401);

      // `registerUser` leaves the email unverified.
      const unverified = await registerUser(app);
      await ok('PUT', `${BASE}/listings/${p.listingId}`, unverified);
    });

    it('a frozen account cannot save — a deletion pending starts nothing new', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      await app.deps.prisma.user.update({
        where: { id: customer.userId },
        data: { status: 'frozen' },
      });
      const res = await call('PUT', `${BASE}/listings/${p.listingId}`, customer);
      expect(res.statusCode).toBe(422);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('ACCOUNT_FROZEN');
    });

    it('only what the public can see can be saved: a draft, a hidden listing, a drafts-only provider and an unknown id are all 404', async () => {
      const customer = await registerUser(app);

      const owner = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, owner.headers);
      const draftsOnly = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { userId: owner.userId },
      });
      expect((await call('PUT', `${BASE}/listings/${draft.id}`, customer)).statusCode).toBe(404);
      expect((await call('PUT', `${BASE}/providers/${draftsOnly.id}`, customer)).statusCode).toBe(
        404,
      );
      expect((await call('PUT', `${BASE}/listings/${randomUUID()}`, customer)).statusCode).toBe(
        404,
      );

      const suspended = await providerWithSlotListing(app);
      await app.deps.prisma.providerProfile.update({
        where: { id: suspended.providerProfileId },
        data: { suspendedAt: new Date(), suspendedReason: 'test' },
      });
      expect(
        (await call('PUT', `${BASE}/listings/${suspended.listingId}`, customer)).statusCode,
      ).toBe(404);
      expect(
        (await call('PUT', `${BASE}/providers/${suspended.providerProfileId}`, customer))
          .statusCode,
      ).toBe(404);
    });

    it("one customer's saves are invisible to another", async () => {
      const p = await providerWithSlotListing(app);
      const mine = await registerUser(app);
      const theirs = await registerUser(app);
      await ok('PUT', `${BASE}/listings/${p.listingId}`, mine);
      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, mine);

      expect(await savedListings(theirs)).toEqual([]);
      expect(await savedProviders(theirs)).toEqual([]);
      const status = await ok<FavoriteStatusDto>(
        'GET',
        `${BASE}/status?listingIds=${p.listingId}&providerIds=${p.providerProfileId}`,
        theirs,
      );
      expect(status.data).toEqual({ listingIds: [], providerIds: [] });

      // And unsaving through another account touches nothing of mine.
      await ok('DELETE', `${BASE}/listings/${p.listingId}`, theirs);
      expect(await savedListings(mine)).toHaveLength(1);
    });
  });

  describe('2. the Saved screen reflects it immediately', () => {
    it('lists saved services as cards beside their provider, newest saved first', async () => {
      const a = await providerWithSlotListing(app);
      const b = await providerWithSlotListing(app, { categoryName: 'Beauty' });
      const customer = await registerUser(app);

      await ok('PUT', `${BASE}/listings/${a.listingId}`, customer);
      await ok('PUT', `${BASE}/listings/${b.listingId}`, customer);

      const items = await savedListings(customer);
      expect(items.map((i) => i.listing.id)).toEqual([b.listingId, a.listingId]);
      const [first] = items;
      expect(first?.provider.id).toBe(b.providerProfileId);
      expect(first?.listing).toMatchObject({ bookingMode: 'slot', name: 'Wiring & Fault Repair' });
      expect(first?.listing.category.name).toBe('Beauty');
      expect(first?.listing.secondSignal.kind).toBe('next_open');
      expect(first?.listing.cover?.url).toBeTruthy();

      // Unsaving is reflected on the very next read.
      await ok('DELETE', `${BASE}/listings/${b.listingId}`, customer);
      expect((await savedListings(customer)).map((i) => i.listing.id)).toEqual([a.listingId]);
    });

    it('lists saved providers with their rating and what they offer', async () => {
      const p = await providerWithSlotListing(app, { categoryName: 'Plumbing' });
      const customer = await registerUser(app);
      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, customer);

      const [item, ...rest] = await savedProviders(customer);
      expect(rest).toEqual([]);
      expect(item?.provider).toMatchObject({
        id: p.providerProfileId,
        businessName: 'Test Trade',
        verificationTier: 'none',
      });
      expect(item?.rating).toEqual({ reviewCount: 0, averageRating: null });
      expect(item?.categories.map((c) => c.name)).toEqual(['Plumbing']);
    });

    it('a saved thing that stops being public leaves the list and comes back with it — the favourite is kept, not stamped', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, customer);

      const hide = (visibility: string) =>
        app.inject({
          method: 'PATCH',
          url: `/v1/providers/me/listings/${p.listingId}/visibility`,
          headers: p.user.headers,
          remoteAddress: freshIp(),
          payload: { visibility },
        });
      expect((await hide('hidden_by_provider')).statusCode).toBe(200);
      expect(await savedListings(customer)).toEqual([]);
      // Their only listing is hidden, so §1a no longer shows the provider either.
      expect(await savedProviders(customer)).toEqual([]);
      expect(await savedCount(customer)).toEqual({ services: 0, providers: 0 });

      expect((await hide('active')).statusCode).toBe(200);
      expect(await savedListings(customer)).toHaveLength(1);
      expect(await savedProviders(customer)).toHaveLength(1);
    });

    it('pages: a cursor walks every saved service once, in order', async () => {
      const customer = await registerUser(app);
      const ids: string[] = [];
      for (let i = 0; i < 3; i += 1) {
        const p = await providerWithSlotListing(app);
        await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
        ids.unshift(p.listingId);
      }

      const seen: string[] = [];
      let cursor: string | null = null;
      do {
        const query: string = cursor === null ? '' : `&cursor=${encodeURIComponent(cursor)}`;
        const page: Envelope<FavoriteListingDto[]> = await ok<FavoriteListingDto[]>(
          'GET',
          `${BASE}/listings?limit=2${query}`,
          customer,
        );
        expect(page.data.length).toBeLessThanOrEqual(2);
        seen.push(...page.data.map((i) => i.listing.id));
        cursor = page.meta?.nextCursor ?? null;
      } while (cursor !== null);
      expect(seen).toEqual(ids);

      // A malformed cursor reads as "from the start", never a 500.
      const bad = await call('GET', `${BASE}/listings?cursor=not-a-cursor`, customer);
      expect(bad.statusCode).toBe(200);
    });

    it('the status lookup is bounded to one screen of ids', async () => {
      const customer = await registerUser(app);
      const many = Array.from({ length: 101 }, () => randomUUID()).join(',');
      expect((await call('GET', `${BASE}/status?listingIds=${many}`, customer)).statusCode).toBe(
        400,
      );
    });
  });

  describe("3. Profile's count updates", () => {
    it('profile-summary counts saved services and providers, and moves with every save and unsave', async () => {
      const a = await providerWithSlotListing(app);
      const b = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      expect(await savedCount(customer)).toEqual({ services: 0, providers: 0 });

      await ok('PUT', `${BASE}/listings/${a.listingId}`, customer);
      await ok('PUT', `${BASE}/listings/${b.listingId}`, customer);
      await ok('PUT', `${BASE}/providers/${a.providerProfileId}`, customer);
      expect(await savedCount(customer)).toEqual({ services: 2, providers: 1 });

      await ok('DELETE', `${BASE}/listings/${a.listingId}`, customer);
      expect(await savedCount(customer)).toEqual({ services: 1, providers: 1 });

      // A repeat save does not count twice.
      await ok('PUT', `${BASE}/listings/${b.listingId}`, customer);
      expect(await savedCount(customer)).toEqual({ services: 1, providers: 1 });
    });
  });

  describe('the contact rule (§1c) holds on every shape', () => {
    it('no response from this module carries a phone number, an email or a bank detail', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, customer);

      const bodies = [
        (await call('GET', `${BASE}/listings`, customer)).body,
        (await call('GET', `${BASE}/providers`, customer)).body,
      ];
      const digits = p.user.phone.replace(/\D/g, '');
      for (const body of bodies) {
        expect(body).not.toContain(digits);
        expect(body).not.toContain(p.user.email);
        expect(body).not.toMatch(/"phone|"email|"bank|"accountNumber|"payment/i);
      }
    });
  });

  describe('account deletion and data export (§Phase 3)', () => {
    it('the export carries every live favourite; anonymisation stamps them all', async () => {
      const p = await providerWithSlotListing(app);
      const customer = await registerUser(app);
      await ok('PUT', `${BASE}/listings/${p.listingId}`, customer);
      await ok('PUT', `${BASE}/providers/${p.providerProfileId}`, customer);

      const exported = await ok<{ favorites: { listings: unknown[]; providers: unknown[] } }>(
        'GET',
        '/v1/users/me/data-export',
        customer,
      );
      expect(exported.data.favorites.listings).toEqual([
        expect.objectContaining({ listingId: p.listingId }),
      ]);
      expect(exported.data.favorites.providers).toEqual([
        expect.objectContaining({ providerId: p.providerProfileId }),
      ]);

      const hook = app.anonymisation.list().find(([name]) => name === 'favorites')?.[1];
      if (hook === undefined) throw new Error('no favorites anonymisation hook registered');
      await app.deps.prisma.$transaction((tx) => hook(tx, customer.userId, new Date()));
      expect(
        await app.deps.prisma.favoriteListing.count({
          where: { userId: customer.userId, deletedAt: null },
        }),
      ).toBe(0);
      expect(
        await app.deps.prisma.favoriteProvider.count({
          where: { userId: customer.userId, deletedAt: null },
        }),
      ).toBe(0);
      // Stamped, never removed.
      expect(
        await app.deps.prisma.favoriteListing.count({ where: { userId: customer.userId } }),
      ).toBe(1);
    });
  });
});
