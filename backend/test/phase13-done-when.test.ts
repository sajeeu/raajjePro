import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { PublicProviderProfileDto } from '../src/modules/public-listings/types.js';
import type { ReviewTagDto } from '../src/modules/reviews/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { addRule, ownSlots, providerWithSlotListing } from './helpers/availability.js';
import {
  actOk,
  bookSlot,
  emergencyProvider,
  requestListing,
  verifiedCustomer,
} from './helpers/bookings.js';
import { categoryByName, completeDraft } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/**
 * §Phase 13 — **Done when:** "renders for a visible provider; returns a
 * proper not-found state for a drafts-only provider's id; no contact data in
 * the response regardless of viewer."
 *
 * Alongside, the two §1f rules this page is the first to render publicly:
 * conduct is numbers or nothing, and a tag shows only once three different
 * customers applied it — counted per provider, not per category.
 */
describe.skipIf(databaseUrl === undefined)('Phase 13 — Done when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
  });
  afterAll(async () => {
    await app.close();
  });

  function getProfile(providerProfileId: string, viewer?: RegisteredUser) {
    return app.inject({
      method: 'GET',
      url: `/v1/providers/${providerProfileId}/public`,
      remoteAddress: freshIp(),
      ...(viewer === undefined ? {} : { headers: viewer.headers }),
    });
  }

  async function profileOf(providerProfileId: string): Promise<PublicProviderProfileDto> {
    const res = await getProfile(providerProfileId);
    expect(res.statusCode, res.body).toBe(200);
    return res.json<Envelope<PublicProviderProfileDto>>().data;
  }

  async function profileIdOf(user: RegisteredUser): Promise<string> {
    const row = await app.deps.prisma.providerProfile.findUniqueOrThrow({
      where: { userId: user.userId },
      select: { id: true },
    });
    return row.id;
  }

  /** A slot provider whose next free slot `completedBooking` books and drives to `completed`. */
  async function slotProvider(categoryName = 'Cleaning') {
    const p = await providerWithSlotListing(app, { categoryName });
    await addRule(app, p.user, p.listingId);
    const slots = await ownSlots(app, p.user, p.listingId);
    let next = 0;
    return {
      ...p,
      async completedBooking(customer: RegisteredUser) {
        const slot = slots[next++];
        if (slot === undefined) throw new Error('fixture ran out of slots');
        const booking = await bookSlot(app, customer, p.listingId, slot.id);
        await actOk(app, p.user, booking.id, 'accept');
        await actOk(app, customer, booking.id, 'claim-payment');
        await actOk(app, p.user, booking.id, 'confirm-payment-received');
        return actOk(app, p.user, booking.id, 'complete');
      },
    };
  }

  async function review(customer: RegisteredUser, bookingId: string, tagIds: string[]) {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/bookings/${bookingId}/review`,
      headers: { ...customer.headers, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      payload: { rating: 5, tagIds },
    });
    expect(res.statusCode, res.body).toBe(201);
  }

  async function tagIdIn(categoryName: string, key: string): Promise<string> {
    const category = await categoryByName(app.deps.prisma, categoryName);
    const res = await app.inject({
      method: 'GET',
      url: `/v1/categories/${category.id}/review-tags`,
      remoteAddress: freshIp(),
    });
    const tag = res.json<Envelope<ReviewTagDto[]>>().data.find((t) => t.key === key);
    if (tag === undefined) throw new Error(`no ${key} in ${categoryName}`);
    return tag.id;
  }

  describe('renders for a visible provider', () => {
    it('returns the header, conduct, rating and the published listing as a card', async () => {
      const p = await slotProvider();
      const profile = await profileOf(p.providerProfileId);

      expect(profile.provider.id).toBe(p.providerProfileId);
      expect(profile.provider.businessName).toBe('Test Trade');
      expect(profile.provider.verificationTier).toBe('none');
      expect(profile.rating).toEqual({ reviewCount: 0, averageRating: null });
      expect(profile.tags).toEqual([]);

      expect(profile.listings).toHaveLength(1);
      const [card] = profile.listings;
      expect(card).toMatchObject({
        id: p.listingId,
        name: 'Wiring & Fault Repair',
        bookingMode: 'slot',
        callbackGuarantee: false,
        rating: { reviewCount: 0, averageRating: null },
      });
      expect(card?.category.name).toBe('Cleaning');
      expect(card?.cover?.url).toBeTruthy();
      expect(card?.serviceAreas).toHaveLength(1);
      // The card's second signal is the listing page's, from one definition.
      expect(card?.secondSignal.kind).toBe('next_open');
    });

    it('conduct is numbers or nothing: below the floor the rates are null and the job count stands', async () => {
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      await p.completedBooking(customer);
      await app.conduct.recompute(p.providerProfileId, new Date());

      const { provider } = await profileOf(p.providerProfileId);
      expect(provider.conduct).toEqual({
        jobsCompletedCount: 1,
        metricsBelowFloor: true,
        metrics: null,
      });
      // No field anywhere could carry an editorial label (§1f).
      const body = (await getProfile(p.providerProfileId)).body;
      expect(body).not.toMatch(/prone|hiking|unreliable|warning|label/i);
    });

    it('lists only published, active listings — a draft or a hidden one never appears', async () => {
      const p = await slotProvider();
      const draft = await completeDraft(app, p.user.headers, { categoryName: 'Cleaning' });

      const profile = await profileOf(p.providerProfileId);
      expect(profile.listings.map((l) => l.id)).toEqual([p.listingId]);
      expect(profile.listings.map((l) => l.id)).not.toContain(draft.id);
    });

    it('a request listing carries the response-time signal, hidden below the floor', async () => {
      const { provider } = await requestListing(app);
      const profile = await profileOf(await profileIdOf(provider));
      expect(profile.listings[0]?.bookingMode).toBe('request');
      expect(profile.listings[0]?.secondSignal).toEqual({
        kind: 'response_time',
        medianResponseSeconds: null,
      });
    });

    it('a posted review moves the provider rating and the card rating together', async () => {
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      await review(customer, booking.id, []);

      const profile = await profileOf(p.providerProfileId);
      expect(profile.rating).toEqual({ reviewCount: 1, averageRating: 5 });
      expect(profile.listings[0]?.rating).toEqual({ reviewCount: 1, averageRating: 5 });
    });
  });

  describe('tags count per provider, not per category', () => {
    it('merges one key across categories into one entry, judged on distinct customers', async () => {
      const p = await slotProvider('Cleaning');
      const [a, b, c] = [
        await verifiedCustomer(app),
        await verifiedCustomer(app),
        await verifiedCustomer(app),
      ];
      const cleaningOnTime = await tagIdIn('Cleaning', 'on_time');
      await review(a, (await p.completedBooking(a)).id, [cleaningOnTime]);
      await review(b, (await p.completedBooking(b)).id, [cleaningOnTime]);

      // Two customers so far: under the threshold, so nothing shows.
      expect((await profileOf(p.providerProfileId)).tags).toEqual([]);

      // The same provider now working in a second category — fixture shortcut
      // for a provider with listings in two categories, whose tag rows differ
      // by id and share a key.
      const fitness = await categoryByName(app.deps.prisma, 'Fitness');
      await app.deps.prisma.listing.update({
        where: { id: p.listingId },
        data: { categoryId: fitness.id },
      });
      const fitnessOnTime = await tagIdIn('Fitness', 'on_time');
      expect(fitnessOnTime).not.toBe(cleaningOnTime);

      // Customer A again, in the second category: still two distinct customers.
      await review(a, (await p.completedBooking(a)).id, [fitnessOnTime]);
      expect((await profileOf(p.providerProfileId)).tags).toEqual([]);

      // A third customer crosses the threshold, and the tag appears once with
      // every application counted.
      await review(c, (await p.completedBooking(c)).id, [fitnessOnTime]);
      const { tags } = await profileOf(p.providerProfileId);
      expect(tags).toEqual([{ key: 'on_time', label: 'On time', sentiment: 'positive', count: 4 }]);
    });
  });

  describe('a proper not-found for anyone §1a does not show', () => {
    it("a drafts-only provider's id is a 404, identical to an id that never existed", async () => {
      const owner = await registerUser(app, { role: 'provider' });
      await completeDraft(app, owner.headers);
      const draftsOnly = await getProfile(await profileIdOf(owner));
      expect(draftsOnly.statusCode).toBe(404);

      const missing = await getProfile(randomUUID());
      expect(missing.statusCode).toBe(404);
      expect(draftsOnly.json<{ error: unknown }>().error).toEqual(
        missing.json<{ error: unknown }>().error,
      );
    });

    it('is a 404 for the owner too — the page is the public one, not a preview of it', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      await completeDraft(app, owner.headers);
      expect((await getProfile(await profileIdOf(owner), owner)).statusCode).toBe(404);
    });

    it('a provider whose only listing is hidden, and a suspended provider, are both not found', async () => {
      const hidden = await slotProvider();
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/providers/me/listings/${hidden.listingId}/visibility`,
        headers: hidden.user.headers,
        remoteAddress: freshIp(),
        payload: { visibility: 'hidden_by_provider' },
      });
      expect(res.statusCode, res.body).toBe(200);
      expect((await getProfile(hidden.providerProfileId)).statusCode).toBe(404);

      const suspended = await slotProvider();
      await app.deps.prisma.providerProfile.update({
        where: { id: suspended.providerProfileId },
        data: { suspendedAt: new Date(), suspendedReason: 'test' },
      });
      expect((await getProfile(suspended.providerProfileId)).statusCode).toBe(404);
    });

    it('rejects a malformed id', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/not-a-uuid/public',
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('no contact data in the response, regardless of viewer', () => {
    it('carries no phone, email or bank detail for a guest, a customer, a stranger or the owner', async () => {
      const slot = await slotProvider();
      const emergency = await emergencyProvider(app, {
        categoryName: 'Plumbing',
        island: { atollAbbr: 'K', name: "Male'" },
      });
      const customer = await verifiedCustomer(app);
      const stranger = await registerUser(app, { role: 'provider' });

      for (const { user, providerProfileId } of [
        { user: slot.user, providerProfileId: slot.providerProfileId },
        { user: emergency.provider, providerProfileId: emergency.providerProfileId },
      ]) {
        const patched = await app.inject({
          method: 'PATCH',
          url: '/v1/providers/me',
          headers: user.headers,
          remoteAddress: freshIp(),
          payload: {
            bankName: 'Bank of Maldives',
            bankAccountName: 'Test Trade Pvt Ltd',
            bankAccountNumber: '7700 1234 5678 9',
            transferInstructions: 'Use the booking reference',
          },
        });
        expect(patched.statusCode, patched.body).toBe(200);
        const secrets = [
          '7700 1234 5678 9',
          'Bank of Maldives',
          'Test Trade Pvt Ltd',
          'Use the booking reference',
          user.phone,
          `+960${user.phone}`,
          user.email,
          customer.phone,
          customer.email,
        ];

        for (const viewer of [undefined, customer, stranger, user]) {
          const res = await getProfile(providerProfileId, viewer);
          expect(res.statusCode, res.body).toBe(200);
          for (const secret of secrets) expect(res.body).not.toContain(secret);
          // Structurally: no key that could hold one, at any depth.
          expect(res.body).not.toMatch(
            /"(phone|phoneE164|phoneDialCode|email|bank\w*|paymentDetails|transferInstructions|userId|fullName)"/,
          );
        }

        // And the same bytes whoever asks: nothing here reads the viewer.
        const asGuest = (await getProfile(providerProfileId)).json<Envelope<unknown>>().data;
        const asOwner = (await getProfile(providerProfileId, user)).json<Envelope<unknown>>().data;
        expect(withoutSignedUrls(asOwner)).toEqual(withoutSignedUrls(asGuest));
      }
    });
  });
});

/** Media URLs are re-signed on every read, so two reads differ there and nowhere else. */
function withoutSignedUrls(value: unknown): unknown {
  return JSON.parse(JSON.stringify(value), (key, v: unknown) => (key === 'url' ? '<url>' : v));
}
