import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type {
  PublicListingDto,
  PublicProviderSummaryDto,
} from '../src/modules/public-listings/types.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import {
  actOk,
  bookableListing,
  bookSlot,
  emergencyProvider,
  requestListing,
  verifiedCustomer,
} from './helpers/bookings.js';
import { completeDraft, patchDraft, publish } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/**
 * §Phase 12 — **Done when:** "live data renders end-to-end; the Edit control
 * appears only for the owner; the raw API response contains no contact or
 * payment data under any circumstance; each booking mode routes to the correct
 * entry point."
 *
 * The last clause is the client's (the Flutter test asserts the route each
 * mode pushes); what the server owes it is a `bookingMode` and a
 * `secondSignal` that agree, which is asserted here.
 */
describe.skipIf(databaseUrl === undefined)('Phase 12 — Done when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
  });
  afterAll(async () => {
    await app.close();
  });

  function getPublic(listingId: string, user?: RegisteredUser) {
    return app.inject({
      method: 'GET',
      url: `/v1/listings/${listingId}/public`,
      remoteAddress: freshIp(),
      ...(user === undefined ? {} : { headers: user.headers }),
    });
  }

  async function publicOf(listingId: string, user?: RegisteredUser): Promise<PublicListingDto> {
    const res = await getPublic(listingId, user);
    expect(res.statusCode, res.body).toBe(200);
    return res.json<Envelope<PublicListingDto>>().data;
  }

  /** Gives a provider every private fact the exclusion has to hold against. */
  async function withPrivateFacts(provider: RegisteredUser) {
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/providers/me',
      headers: provider.headers,
      remoteAddress: freshIp(),
      payload: {
        bankName: 'Bank of Maldives',
        bankAccountName: 'Test Trade Pvt Ltd',
        bankAccountNumber: '7700 1234 5678 9',
        transferInstructions: 'Use the booking reference',
        bio: 'Fifteen years in the trade.',
      },
    });
    expect(res.statusCode, res.body).toBe(200);
    return [
      '7700 1234 5678 9',
      'Bank of Maldives',
      'Test Trade Pvt Ltd',
      'Use the booking reference',
    ];
  }

  describe('live data, end to end', () => {
    it('a guest reads a published slot listing with its real content', async () => {
      const { listingId, provider } = await bookableListing(app);
      const listing = await publicOf(listingId);

      expect(listing.id).toBe(listingId);
      expect(listing.name).toBe('Wiring & Fault Repair');
      expect(listing.category.name).toBe('Cleaning');
      expect(listing.pricing).toMatchObject({ model: 'fixed', priceLaari: 45_000, unit: 'visit' });
      expect(listing.serviceAreas).toHaveLength(1);
      expect(listing.cover?.url).toBeTruthy();
      expect(listing.provider.businessName).toBe('Test Trade');
      // A provider with no completed jobs shows the job count and no rates (§1f).
      expect(listing.provider.conduct.metricsBelowFloor).toBe(true);
      expect(listing.provider.conduct.metrics).toBeNull();
      expect(provider.userId).toBeTruthy();
    });

    it('a slot listing carries its next open time; a request listing carries response time, never both', async () => {
      const slot = await bookableListing(app);
      const slotListing = await publicOf(slot.listingId);
      expect(slotListing.bookingMode).toBe('slot');
      expect(slotListing.secondSignal.kind).toBe('next_open');
      if (slotListing.secondSignal.kind === 'next_open') {
        expect(slotListing.secondSignal.nextOpenAt).not.toBeNull();
      }

      const request = await requestListing(app);
      const requestListing_ = await publicOf(request.listingId);
      expect(requestListing_.bookingMode).toBe('request');
      // Below §1f's floor the response time is hidden, not shown as zero.
      expect(requestListing_.secondSignal).toEqual({
        kind: 'response_time',
        medianResponseSeconds: null,
      });
    });

    it('an empty review history is null, never a zero rating', async () => {
      const { listingId } = await bookableListing(app);
      const { rating } = await publicOf(listingId);
      expect(rating.reviewCount).toBe(0);
      expect(rating.averageRating).toBeNull();
    });

    it('a posted review appears in the listing and provider summaries', async () => {
      const { listingId, provider, customer, slotId, providerProfileId } =
        await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);
      await actOk(app, provider, booking.id, 'accept');
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');
      await actOk(app, provider, booking.id, 'complete');
      const reviewed = await app.inject({
        method: 'POST',
        url: `/v1/bookings/${booking.id}/review`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { rating: 4 },
      });
      expect(reviewed.statusCode, reviewed.body).toBe(201);
      // Conduct is recomputed by a job after a terminal transition, not on read.
      await app.conduct.recompute(providerProfileId, new Date());

      const { rating } = await publicOf(listingId);
      expect(rating).toMatchObject({ reviewCount: 1, averageRating: 4 });

      const summary = await app.inject({
        method: 'GET',
        url: `/v1/providers/${providerProfileId}/public-summary`,
        remoteAddress: freshIp(),
      });
      expect(summary.statusCode, summary.body).toBe(200);
      const body = summary.json<Envelope<PublicProviderSummaryDto>>().data;
      expect(body.rating).toEqual({ reviewCount: 1, averageRating: 4 });
      expect(body.provider.id).toBe(providerProfileId);
      expect(body.provider.conduct.jobsCompletedCount).toBe(1);
    });

    it('records a view for a customer or guest, and not for the owner', async () => {
      const { listingId, provider, customer } = await bookableListing(app);
      const prisma = app.deps.prisma;
      const views = () => prisma.listingEvent.count({ where: { listingId, kind: 'view' } });

      await publicOf(listingId);
      expect(await views()).toBe(1);
      await publicOf(listingId, customer);
      expect(await views()).toBe(2);
      await publicOf(listingId, provider);
      expect(await views()).toBe(2);
    });
  });

  describe('the Edit control appears only for the owner', () => {
    it('viewerIsOwner is true for the owner alone', async () => {
      const { listingId, provider, customer } = await bookableListing(app);
      const stranger = await registerUser(app, { role: 'provider' });

      expect((await publicOf(listingId, provider)).viewerIsOwner).toBe(true);
      expect((await publicOf(listingId, customer)).viewerIsOwner).toBe(false);
      expect((await publicOf(listingId, stranger)).viewerIsOwner).toBe(false);
      expect((await publicOf(listingId)).viewerIsOwner).toBe(false);
    });

    it('a garbage token reads as a guest rather than failing the page', async () => {
      const { listingId } = await bookableListing(app);
      const res = await app.inject({
        method: 'GET',
        url: `/v1/listings/${listingId}/public`,
        headers: { authorization: 'Bearer not-a-token' },
        remoteAddress: freshIp(),
      });
      expect(res.statusCode, res.body).toBe(200);
      expect(res.json<Envelope<PublicListingDto>>().data.viewerIsOwner).toBe(false);
    });
  });

  describe('no contact or payment data, under any circumstance', () => {
    it('neither raw response carries a phone, an email or a bank detail — for a guest, a customer or the owner', async () => {
      const { listingId, provider, customer, providerProfileId } = await bookableListing(app);
      const secrets = [
        ...(await withPrivateFacts(provider)),
        provider.phone,
        `+960${provider.phone}`,
        provider.email,
        customer.phone,
        customer.email,
      ];

      const bodies: string[] = [];
      for (const viewer of [undefined, customer, provider]) {
        bodies.push((await getPublic(listingId, viewer)).body);
        bodies.push(
          (
            await app.inject({
              method: 'GET',
              url: `/v1/providers/${providerProfileId}/public-summary`,
              remoteAddress: freshIp(),
              ...(viewer === undefined ? {} : { headers: viewer.headers }),
            })
          ).body,
        );
      }
      for (const body of bodies) {
        for (const secret of secrets) expect(body).not.toContain(secret);
        // Structurally: no key that could hold one, at any depth.
        expect(body).not.toMatch(
          /"(phone|phoneE164|phoneDialCode|email|bank\w*|paymentDetails|transferInstructions|userId)"/,
        );
      }
    });

    it('holds for a request listing and an emergency listing too', async () => {
      const request = await requestListing(app);
      const emergency = await emergencyProvider(app, {
        categoryName: 'Plumbing',
        island: { atollAbbr: 'K', name: "Male'" },
      });
      for (const { provider, listingId } of [request, emergency]) {
        const secrets = await withPrivateFacts(provider);
        const body = (await getPublic(listingId)).body;
        for (const secret of [...secrets, provider.phone, provider.email]) {
          expect(body).not.toContain(secret);
        }
      }
    });
  });

  describe('what is not public is not found', () => {
    it('a draft, a provider-hidden listing and a deleted listing all read as the same 404', async () => {
      const { listingId, provider } = await bookableListing(app);

      const hidden = await app.inject({
        method: 'PATCH',
        url: `/v1/providers/me/listings/${listingId}/visibility`,
        headers: provider.headers,
        remoteAddress: freshIp(),
        payload: { visibility: 'hidden_by_provider' },
      });
      expect(hidden.statusCode, hidden.body).toBe(200);
      const hiddenRes = await getPublic(listingId);
      expect(hiddenRes.statusCode).toBe(404);

      const draftOwner = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, draftOwner.headers);
      const draftRes = await getPublic(draft.id);
      expect(draftRes.statusCode).toBe(404);

      // The hidden thing and the thing that never existed are indistinguishable.
      const missing = await getPublic(randomUUID());
      expect(missing.statusCode).toBe(404);
      const errorOf = (res: { json: () => { error: unknown } }) => res.json().error;
      expect(errorOf(hiddenRes)).toEqual(errorOf(missing));

      const gone = await app.inject({
        method: 'DELETE',
        url: `/v1/providers/me/listings/${listingId}`,
        headers: provider.headers,
        remoteAddress: freshIp(),
      });
      expect(gone.statusCode, gone.body).toBeLessThan(300);
      expect((await getPublic(listingId)).statusCode).toBe(404);
    });

    it('a suspended provider is not found, listing and summary alike', async () => {
      const { listingId, providerProfileId } = await bookableListing(app);
      await app.deps.prisma.providerProfile.update({
        where: { id: providerProfileId },
        data: { suspendedAt: new Date(), suspendedReason: 'test' },
      });
      expect((await getPublic(listingId)).statusCode).toBe(404);
      const summary = await app.inject({
        method: 'GET',
        url: `/v1/providers/${providerProfileId}/public-summary`,
        remoteAddress: freshIp(),
      });
      expect(summary.statusCode).toBe(404);
    });

    it('a drafts-only provider has no public summary, even by direct id', async () => {
      const owner = await registerUser(app, { role: 'provider' });
      await completeDraft(app, owner.headers);
      const profile = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { userId: owner.userId },
        select: { id: true },
      });
      const res = await app.inject({
        method: 'GET',
        url: `/v1/providers/${profile.id}/public-summary`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });

    it('rejects a malformed id before touching the database', async () => {
      const res = await app.inject({
        method: 'GET',
        url: '/v1/listings/not-a-uuid/public',
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('the emergency door', () => {
    it('is offered with the dispatch fee up front, and only while the provider still meets the bar', async () => {
      const { listingId, providerProfileId } = await emergencyProvider(app, {
        categoryName: 'Plumbing',
        island: { atollAbbr: 'K', name: "Male'" },
      });
      const open = await publicOf(listingId);
      expect(open.emergency.available).toBe(true);
      expect(open.emergency.dispatchFeeLaari).toBe(20_000);
      expect(open.emergency.categoryId).toBe(open.category.id);

      // Plumbing's bar is Gold (read from the category, never hardcoded). A
      // silver provider whose stored flag has not yet been swept is not offered.
      await app.deps.prisma.providerProfile.update({
        where: { id: providerProfileId },
        data: { verificationTier: 'silver' },
      });
      const closed = await publicOf(listingId);
      expect(closed.emergency).toEqual({
        available: false,
        dispatchFeeLaari: null,
        categoryId: null,
      });
    });

    it('a listing that never turned emergency on does not advertise it', async () => {
      const { listingId } = await requestListing(app);
      expect((await publicOf(listingId)).emergency.available).toBe(false);
    });
  });

  describe('the callback guarantee is per-category', () => {
    async function listingWithCallback(categoryName: string) {
      const owner = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, owner.headers, { categoryName });
      const pub = await publish(app, owner.headers, draft.id);
      expect(pub.statusCode, pub.body).toBe(200);
      return { owner, id: draft.id };
    }

    it('renders on an eligible category when offered, and never on an ineligible one', async () => {
      const plumbing = await listingWithCallback('Plumbing');
      expect((await publicOf(plumbing.id)).callbackGuarantee).toBe(false);
      const on = await patchDraft(app, plumbing.owner.headers, plumbing.id, {
        callbackGuaranteeOffered: true,
      });
      expect(on.statusCode, on.body).toBe(200);
      expect((await publicOf(plumbing.id)).callbackGuarantee).toBe(true);

      // A stored flag on an ineligible category (however it got there) is not shown.
      const cleaning = await listingWithCallback('Cleaning');
      await app.deps.prisma.listing.update({
        where: { id: cleaning.id },
        data: { callbackGuaranteeOffered: true },
      });
      expect((await publicOf(cleaning.id)).callbackGuarantee).toBe(false);
    });
  });

  describe('self-declared cover is the provider’s own text, only when declared', () => {
    it('returns warranty and insurance text only behind their flags', async () => {
      const { listingId } = await bookableListing(app);
      await app.deps.prisma.listing.update({
        where: { id: listingId },
        data: {
          warrantyOffered: true,
          warrantyTermsText: '90-day workmanship warranty',
          insuranceDeclared: false,
          insuranceDetailText: 'stale text behind an unset flag',
        },
      });
      const { selfDeclared } = await publicOf(listingId);
      expect(selfDeclared).toEqual({
        warrantyOffered: true,
        warrantyTermsText: '90-day workmanship warranty',
        insuranceDeclared: false,
        insuranceDetailText: null,
      });
    });
  });

  it('verifiedCustomer fixture is not the owner of anything it reads', async () => {
    const stranger = await verifiedCustomer(app);
    const { listingId } = await bookableListing(app);
    expect((await publicOf(listingId, stranger)).viewerIsOwner).toBe(false);
  });
});
