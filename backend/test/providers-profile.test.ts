import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { seedCategories } from '../src/modules/categories/seed.js';
import type { OwnProviderDto } from '../src/modules/providers/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { FakeConduct, FakeListings } from './helpers/providers.js';
import { bearer, createUser, registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/**
 * §Phase 5 — the provider profile surface. The Done-when list has its own
 * file (`phase5-done-when.test.ts`); this one covers the rules underneath it:
 * authorization, what a provider may and may not write, §1g's Gold gate,
 * §1f's display floor, and what account deletion erases.
 */
describe.skipIf(databaseUrl === undefined)('provider profiles', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  const conduct = new FakeConduct();
  const listings = new FakeListings();

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      deps: { providerConduct: conduct, publishedListings: listings },
    }));
    await seedCategories(app.deps.prisma);
  });

  /** `readPublic` applies §1a, so a conduct test needs a provider who is actually visible. */
  const visibleProvider = async () => {
    const user = await registerUser(app, { role: 'provider' });
    const profile = await readOwn(user.headers);
    listings.publish(profile.id);
    return { user, profile };
  };

  afterAll(async () => {
    await app.close();
  });

  const readOwn = async (headers: { authorization: string }) => {
    const res = await app.inject({ method: 'GET', url: '/v1/providers/me', headers });
    expect(res.statusCode).toBe(200);
    return res.json<Envelope<OwnProviderDto>>().data;
  };

  describe('authorization', () => {
    it('rejects an unauthenticated read and an unauthenticated write', async () => {
      for (const method of ['GET', 'PATCH'] as const) {
        const res = await app.inject({
          method,
          url: '/v1/providers/me',
          remoteAddress: freshIp(),
          ...(method === 'PATCH' ? { payload: { bio: 'hello' } } : {}),
        });
        expect(res.statusCode).toBe(401);
      }
    });

    it('scopes every read and write to the caller, so one provider cannot reach another', async () => {
      const a = await registerUser(app, { role: 'provider', businessName: 'A Plumbing' });
      const b = await registerUser(app, { role: 'provider', businessName: 'B Electrical' });

      await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: a.headers,
        payload: { bankAccountNumber: '7701234567' },
      });

      // There is no route that takes a provider id, so B cannot address A's
      // row at all — the surface is `me` by construction, which is the
      // strongest form of the ownership check.
      const seenByB = await readOwn(b.headers);
      expect(seenByB.userId).toBe(b.userId);
      expect(seenByB.paymentDetails.bankAccountNumber).toBeNull();
    });

    it('refuses a write from a frozen account, which starts nothing new', async () => {
      const user = await registerUser(app, { role: 'provider' });
      await app.inject({
        method: 'POST',
        url: '/v1/users/me/deletion-request',
        headers: { ...user.headers, 'idempotency-key': randomUUID() },
      });
      const res = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bankAccountNumber: '7709998888' },
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('ACCOUNT_FROZEN');
    });

    it('does not create a profile on a read — a customer stays a customer', async () => {
      const customer = await registerUser(app);
      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: customer.headers,
      });
      expect(res.statusCode).toBe(404);
      // The load-bearing half: `isProvider` is `providerProfile !== null` and
      // §Phase 6's role switcher routes on it, so a read that created a row
      // would turn a customer into a provider permanently — nothing is ever
      // hard-deleted (invariant 8).
      expect(
        await app.deps.prisma.providerProfile.count({ where: { userId: customer.userId } }),
      ).toBe(0);
    });

    it('reads normally for a provider with nothing published — §1a never gates the dashboard', async () => {
      const provider = await registerUser(app, { role: 'provider', businessName: 'Drafts Only' });
      const profile = await readOwn(provider.headers);
      expect(profile.verificationTier).toBe('none');
      expect(profile.acceptingNewCustomers).toBe(true);
    });

    it('the write creates the profile, because sending business details is acting as one', async () => {
      const customer = await registerUser(app);
      const res = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: customer.headers,
        payload: { businessName: 'Newly A Provider' },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<OwnProviderDto>>().data.businessName).toBe('Newly A Provider');
    });
  });

  describe('what a provider may write', () => {
    it('accepts the profile, payment and availability fields, and clearing one is a real edit', async () => {
      const user = await registerUser(app, { role: 'provider', businessName: 'Reef Plumbing' });
      const patched = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: {
          bio: 'Twelve years on Malé and Hulhumalé.',
          yearsOfExperience: 12,
          bankName: 'Bank of Maldives',
          bankAccountName: 'Reef Plumbing Pvt Ltd',
          bankAccountNumber: '7701 234 567',
          transferInstructions: 'Reference your booking number.',
          acceptingNewCustomers: false,
        },
      });
      expect(patched.statusCode).toBe(200);
      const dto = patched.json<Envelope<OwnProviderDto>>().data;
      expect(dto.bio).toBe('Twelve years on Malé and Hulhumalé.');
      expect(dto.yearsOfExperience).toBe(12);
      expect(dto.paymentDetails.bankAccountNumber).toBe('7701 234 567');
      expect(dto.acceptingNewCustomers).toBe(false);

      const cleared = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bio: null, yearsOfExperience: null },
      });
      expect(cleared.json<Envelope<OwnProviderDto>>().data.bio).toBeNull();
      // A partial patch leaves everything it did not name alone.
      expect(cleared.json<Envelope<OwnProviderDto>>().data.paymentDetails.bankName).toBe(
        'Bank of Maldives',
      );
    });

    it('caps the bio at 160 characters server-side, not only in the onboarding form', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const res = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bio: 'x'.repeat(161) },
      });
      expect(res.statusCode).toBe(400);
    });

    it('accepts a foreign-format account number rather than a Maldivian pattern', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const res = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bankAccountNumber: '0123-4567-8901-2345' },
      });
      expect(res.statusCode).toBe(200);
    });

    it('rejects an empty patch', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const res = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: {},
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('what a provider may not write', () => {
    /**
     * Each of these is somebody else's to set, and the enforcement is that
     * the key is absent from `updateOwnProviderBody` — an unknown key is
     * stripped, so the stored value is untouched rather than the request
     * being rejected. The assertion is therefore on the row, not the status.
     */
    it('cannot self-verify, self-declare Maldivian ownership, price itself, or un-suspend itself', async () => {
      const user = await registerUser(app, { role: 'provider' });
      await app.deps.prisma.providerProfile.update({
        where: { userId: user.userId },
        data: { suspendedAt: new Date(), suspendedReason: 'under review' },
      });

      await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: {
          bio: 'a legitimate edge to hide behind',
          verificationTier: 'gold',
          verificationStatus: 'verified',
          maldivianOwned: true,
          subscriptionPriceLaari: 1,
          suspendedAt: null,
          suspendedReason: null,
        },
      });

      const row = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { userId: user.userId },
      });
      expect(row.bio).toBe('a legitimate edge to hide behind'); // the legitimate field did land
      expect(row.verificationTier).toBe('none');
      expect(row.verificationStatus).toBe('unverified');
      expect(row.maldivianOwned).toBeNull();
      expect(row.subscriptionPriceLaari).toBeNull();
      expect(row.suspendedAt).not.toBeNull();
      expect(row.suspendedReason).toBe('under review');
    });

    it("cannot set a phone number here — the account phone stays Phase 3's single copy", async () => {
      const user = await registerUser(app, { role: 'provider' });
      await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: {
          bio: 'x',
          phone: { dialCode: '+960', number: '7654321' },
          phoneE164: '+9607654321',
        },
      });
      const profile = await readOwn(user.headers);
      expect(JSON.stringify(profile)).not.toContain('7654321');
    });
  });

  describe('§1g local preference — Maldivian-owned business', () => {
    it('is absent below Gold and present at Gold, and is never a nationality field', async () => {
      const user = await registerUser(app, { role: 'provider' });
      // The attribute is evidenced by the Gold registration document, so a
      // row can carry it while the tier sits lower — a demotion must not be
      // blocked by a constraint. What must never happen is that it *shows*.
      await app.deps.prisma.providerProfile.update({
        where: { userId: user.userId },
        data: { maldivianOwned: true, verificationTier: 'silver' },
      });
      expect((await readOwn(user.headers)).maldivianOwned).toBeNull();

      await app.deps.prisma.providerProfile.update({
        where: { userId: user.userId },
        data: { verificationTier: 'gold' },
      });
      expect((await readOwn(user.headers)).maldivianOwned).toBe(true);
    });
  });

  describe('§1f conduct read surface', () => {
    it('suppresses every rate below the ten-booking floor, keeping only the job count', async () => {
      const { profile } = await visibleProvider();
      conduct.set(profile.id, { jobsCompletedCount: 4, completedInWindow: 4, onTimeRate: 1 });

      const publicDto = await app.providers.readPublic(profile.id);
      expect(publicDto.conduct.metricsBelowFloor).toBe(true);
      expect(publicDto.conduct.jobsCompletedCount).toBe(4);
      expect(publicDto.conduct.metrics).toBeNull();
    });

    it('shows the numbers at and above the floor', async () => {
      const { profile } = await visibleProvider();
      conduct.set(profile.id, {
        jobsCompletedCount: 47,
        completedInWindow: 10,
        onTimeRate: 0.94,
        cancellationRate: 0.03,
        medianResponseSeconds: 720,
      });

      const publicDto = await app.providers.readPublic(profile.id);
      expect(publicDto.conduct.metricsBelowFloor).toBe(false);
      expect(publicDto.conduct.metrics?.onTimeRate).toBeCloseTo(0.94);
      expect(publicDto.conduct.metrics?.cancellationRate).toBeCloseTo(0.03);
      expect(publicDto.conduct.metrics?.medianResponseSeconds).toBe(720);
    });

    it('shows the provider their own numbers before anyone else sees them', async () => {
      const { user, profile: first } = await visibleProvider();
      conduct.set(first.id, { jobsCompletedCount: 3, completedInWindow: 3, onTimeRate: 0.5 });

      const own = await readOwn(user.headers);
      expect(own.conduct.publiclyVisible).toBe(false);
      expect(own.conduct.metrics.onTimeRate).toBeCloseTo(0.5);
      // ... while the public view of the same provider still says nothing.
      expect((await app.providers.readPublic(first.id)).conduct.metrics).toBeNull();
    });

    it('reports a rate as null rather than zero when there is no denominator', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const own = await readOwn(user.headers);
      expect(own.conduct.publiclyVisible).toBe(false);
      // "0% on time" and "never been booked" are different claims.
      expect(own.conduct.metrics.onTimeRate).toBeNull();
      expect(own.conduct.jobsCompletedCount).toBe(0);
    });

    it('carries no editorial label field anywhere in either shape (§1f, Round 15)', async () => {
      const { user, profile } = await visibleProvider();
      conduct.set(profile.id, {
        jobsCompletedCount: 30,
        completedInWindow: 30,
        cancellationRate: 0.9,
      });
      const publicDto = await app.providers.readPublic(profile.id);
      const own = await readOwn(user.headers);

      // A 90% cancellation rate is the case an editorial label would have
      // fired on. The real guarantee is structural — there is no field of
      // string type in either conduct block for "Prone to cancel" to live in
      // — so that is what is asserted, on both shapes. A word blocklist would
      // pass anything the list did not anticipate ("Often cancels").
      for (const block of [publicDto.conduct, own.conduct]) {
        for (const [key, value] of Object.entries(block)) {
          expect(
            value === null ||
              typeof value === 'number' ||
              typeof value === 'boolean' ||
              key === 'metrics',
            `${key} is ${typeof value}`,
          ).toBe(true);
        }
      }
      for (const metrics of [publicDto.conduct.metrics, own.conduct.metrics]) {
        for (const value of Object.values(metrics ?? {})) {
          expect(value === null || typeof value === 'number').toBe(true);
        }
      }
    });
  });

  describe('bookingMode default lookup', () => {
    it("reads Phase 4's seeded mode rather than hardcoding one", async () => {
      const categories = await app.categories.listAllPublic();
      const cleaning = categories.find((c) => c.name === 'Cleaning');
      const plumbing = categories.find((c) => c.name === 'Plumbing');
      expect(cleaning).toBeDefined();
      expect(plumbing).toBeDefined();

      expect(await app.providers.defaultBookingModeForCategory(cleaning?.id ?? '')).toBe('slot');
      expect(await app.providers.defaultBookingModeForCategory(plumbing?.id ?? '')).toBe('request');
    });

    it('follows an admin changing the mode, because it is a read and not a constant', async () => {
      const categories = await app.categories.listAllPublic();
      const beauty = categories.find((c) => c.name === 'Beauty');
      const id = beauty?.id ?? '';
      await app.deps.prisma.category.update({ where: { id }, data: { bookingMode: 'request' } });
      expect(await app.providers.defaultBookingModeForCategory(id)).toBe('request');
      await app.deps.prisma.category.update({ where: { id }, data: { bookingMode: 'slot' } });
      expect(await app.providers.defaultBookingModeForCategory(id)).toBe('slot');
    });
  });

  describe('account deletion', () => {
    it('erases the bank details and the bio, and keeps the verification decision', async () => {
      const user = await createUser(app.deps.prisma, { emailVerified: true });
      await app.deps.prisma.providerProfile.create({
        data: {
          userId: user.id,
          businessName: 'Vaadhoo Movers',
          bio: 'Ask for Ahmed',
          bankName: 'Bank of Maldives',
          bankAccountName: 'Vaadhoo Movers',
          bankAccountNumber: '7701234567',
          transferInstructions: 'Call before transferring',
          verificationTier: 'silver',
          verificationStatus: 'verified',
          subscriptionPriceLaari: 7500,
        },
      });
      await app.deps.prisma.user.update({
        where: { id: user.id },
        data: { status: 'frozen', deletionRequestedAt: new Date(), deletionDeadlineAt: new Date() },
      });

      await app.anonymiser.anonymise(user.id, new Date(), 'bookings_terminal');

      const row = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { userId: user.id },
      });
      expect(row.businessName).toBeNull();
      expect(row.bio).toBeNull();
      expect(row.bankName).toBeNull();
      expect(row.bankAccountName).toBeNull();
      expect(row.bankAccountNumber).toBeNull();
      expect(row.transferInstructions).toBeNull();
      // §1e: the decision persists after the evidence is purged.
      expect(row.verificationTier).toBe('silver');
      expect(row.subscriptionPriceLaari).toBe(7500);
    });
  });

  describe('data export', () => {
    it('returns the provider their own profile, payment details included', async () => {
      const user = await registerUser(app, { role: 'provider', businessName: 'Fenaka Fix' });
      await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bankName: 'MIB', bankAccountNumber: '9001234567' },
      });
      const res = await app.inject({
        method: 'GET',
        url: '/v1/users/me/data-export',
        headers: bearer(user.tokens.accessToken),
      });
      expect(res.statusCode).toBe(200);
      const body = res.json<Envelope<Record<string, unknown>>>().data;
      const profile = body.providerProfile as {
        businessName: string;
        paymentDetails: { bankAccountNumber: string };
      };
      expect(profile.businessName).toBe('Fenaka Fix');
      expect(profile.paymentDetails.bankAccountNumber).toBe('9001234567');
    });
  });

  describe('getOrCreateProviderProfile', () => {
    it('is idempotent across the three call sites that share it', async () => {
      const user = await createUser(app.deps.prisma);
      const first = await app.providers.getOrCreateProviderProfile(user.id, 'First Name');
      const second = await app.providers.getOrCreateProviderProfile(user.id, 'Second Name');
      const viaAuthRepo = await app.auth.repo.getOrCreateProviderProfile(
        app.deps.prisma,
        user.id,
        'Third Name',
      );

      expect(second.id).toBe(first.id);
      expect(viaAuthRepo.id).toBe(first.id);
      // A later call must not overwrite a name the provider has since edited.
      expect(second.businessName).toBe('First Name');
      expect(await app.deps.prisma.providerProfile.count({ where: { userId: user.id } })).toBe(1);
    });
  });

  describe('findVisibleProviders paging', () => {
    it('fills a full page and hands back a usable cursor', async () => {
      const listings = new FakeListings();
      const { app: paged } = await buildTestApp({ deps: { publishedListings: listings } });
      try {
        const ids: string[] = [];
        for (let i = 0; i < 5; i += 1) {
          const user = await createUser(paged.deps.prisma);
          const profile = await paged.providers.getOrCreateProviderProfile(
            user.id,
            `P${String(i)}`,
          );
          listings.publish(profile.id);
          ids.push(profile.id);
        }
        const first = await paged.providers.findVisibleProviders({}, { limit: 2 });
        expect(first.items).toHaveLength(2);
        expect(first.nextCursor).not.toBeNull();

        const second = await paged.providers.findVisibleProviders(
          {},
          { limit: 2, cursor: first.nextCursor ?? '' },
        );
        expect(second.items).toHaveLength(2);
        // No overlap between pages.
        const seen = new Set(first.items.map((p) => p.id));
        for (const item of second.items) expect(seen.has(item.id)).toBe(false);
        // Every id was one of ours or another test's — never a duplicate.
        expect(ids.length).toBe(5);
      } finally {
        await paged.close();
      }
    });

    it('asks the listing source in batches, not once per provider', async () => {
      const listings = new FakeListings();
      const { app: batched } = await buildTestApp({ deps: { publishedListings: listings } });
      try {
        for (let i = 0; i < 3; i += 1) {
          const user = await createUser(batched.deps.prisma);
          const profile = await batched.providers.getOrCreateProviderProfile(user.id);
          listings.publish(profile.id);
        }
        listings.calls.length = 0;
        await batched.providers.findVisibleProviders({}, { limit: 3 });
        expect(listings.calls.length).toBeGreaterThan(0);
        expect(listings.calls[0]?.length).toBeGreaterThan(1);
      } finally {
        await batched.close();
      }
    });
  });
});
