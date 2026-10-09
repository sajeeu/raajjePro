import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { BookingDto } from '../src/modules/bookings/types.js';
import type {
  BookingReviewDto,
  RatingSummaryDto,
  ReviewDto,
  ReviewTagDto,
} from '../src/modules/reviews/types.js';
import { CSRF, createEnrolledAdmin } from './helpers/admin.js';
import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { addRule, ownSlots, providerWithSlotListing } from './helpers/availability.js';
import { actOk, bookSlot, errorCode, verifiedCustomer } from './helpers/bookings.js';
import type { RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

/**
 * §Phase 11 — **Done when:** "posting a review updates the aggregate; a second
 * review on the same booking is rejected; hiding a review recomputes the
 * aggregate."
 *
 * Every booking here is driven to `completed` through the real route table —
 * accept, "I've Paid", "Payment Received", complete — so the gate under test
 * is the product's own and not a fixture's stamp. The surrounding rules the
 * phase states are asserted alongside: completed-only, tags from the
 * category's fixed set, two taps, the three-customer tag threshold, and
 * authorship retained through anonymisation but never returned (ledger P1).
 */
describe.skipIf(databaseUrl === undefined)('Phase 11 — Done when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let adminCookie: string;

  beforeAll(async () => {
    ({ app } = await buildTestApp());
    adminCookie = (await createEnrolledAdmin(app)).cookie;
  });
  afterAll(async () => {
    await app.close();
  });

  /** A provider with one slot listing and a generated grid. */
  async function provider() {
    const p = await providerWithSlotListing(app, { categoryName: 'Cleaning' });
    await addRule(app, p.user, p.listingId);
    const slots = await ownSlots(app, p.user, p.listingId);
    let next = 0;
    return {
      ...p,
      /** Books the next free slot as `customer` and drives it to `completed`. */
      async completedBooking(customer: RegisteredUser): Promise<BookingDto> {
        const slot = slots[next++];
        if (slot === undefined) throw new Error('fixture ran out of slots');
        const booking = await bookSlot(app, customer, p.listingId, slot.id);
        await actOk(app, p.user, booking.id, 'accept');
        await actOk(app, customer, booking.id, 'claim-payment');
        await actOk(app, p.user, booking.id, 'confirm-payment-received');
        return actOk(app, p.user, booking.id, 'complete');
      },
      /** Booked, accepted and paid — the confirmed future booking §Phase 8's cascade protects. */
      async confirmedBooking(customer: RegisteredUser): Promise<BookingDto> {
        const slot = slots[next++];
        if (slot === undefined) throw new Error('fixture ran out of slots');
        const booking = await bookSlot(app, customer, p.listingId, slot.id);
        await actOk(app, p.user, booking.id, 'accept');
        await actOk(app, customer, booking.id, 'claim-payment');
        return actOk(app, p.user, booking.id, 'confirm-payment-received');
      },
      async acceptedBooking(customer: RegisteredUser): Promise<BookingDto> {
        const slot = slots[next++];
        if (slot === undefined) throw new Error('fixture ran out of slots');
        const booking = await bookSlot(app, customer, p.listingId, slot.id);
        return actOk(app, p.user, booking.id, 'accept');
      },
    };
  }

  function postReview(
    user: RegisteredUser,
    bookingId: string,
    payload: Record<string, unknown>,
    key = randomUUID(),
  ) {
    return app.inject({
      method: 'POST',
      url: `/v1/bookings/${bookingId}/review`,
      headers: { ...user.headers, 'idempotency-key': key },
      remoteAddress: freshIp(),
      payload,
    });
  }

  async function postOk(
    user: RegisteredUser,
    bookingId: string,
    payload: Record<string, unknown>,
  ): Promise<BookingReviewDto> {
    const res = await postReview(user, bookingId, payload);
    if (res.statusCode !== 201) throw new Error(`review: ${String(res.statusCode)} ${res.body}`);
    return res.json<Envelope<BookingReviewDto>>().data;
  }

  async function get<T>(url: string, headers: Record<string, string> = {}): Promise<T> {
    const res = await app.inject({ method: 'GET', url, headers, remoteAddress: freshIp() });
    if (res.statusCode !== 200) throw new Error(`${url}: ${String(res.statusCode)} ${res.body}`);
    return res.json<Envelope<T>>().data;
  }

  const providerSummary = (id: string) =>
    get<RatingSummaryDto>(`/v1/providers/${id}/review-summary`);
  const listingSummary = (id: string) => get<RatingSummaryDto>(`/v1/listings/${id}/review-summary`);

  async function tags(listingId: string): Promise<ReviewTagDto[]> {
    const listing = await app.deps.prisma.listing.findUniqueOrThrow({
      where: { id: listingId },
      select: { categoryId: true },
    });
    return get<ReviewTagDto[]>(`/v1/categories/${listing.categoryId ?? ''}/review-tags`);
  }

  function tagId(set: ReviewTagDto[], key: string): string {
    const tag = set.find((t) => t.key === key);
    if (tag === undefined) throw new Error(`no tag ${key}`);
    return tag.id;
  }

  function moderate(reviewId: string, action: 'hide' | 'unhide') {
    return app.inject({
      method: 'POST',
      url: `/v1/admin/reviews/${reviewId}/${action}`,
      headers: { cookie: adminCookie, ...CSRF, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      payload: { reason: 'Fake review confirmed on report' },
    });
  }

  // =========================================================================
  // Done when, clause 1 — posting a review updates the aggregate
  // =========================================================================

  describe('posting a review updates the aggregate', () => {
    it('updates the provider and listing aggregates, star breakdown included', async () => {
      const p = await provider();
      expect((await providerSummary(p.providerProfileId)).reviewCount).toBe(0);
      expect((await providerSummary(p.providerProfileId)).averageRating).toBeNull();

      const ca = await verifiedCustomer(app);
      const cb = await verifiedCustomer(app);
      const a = await p.completedBooking(ca);
      const b = await p.completedBooking(cb);
      await postOk(ca, a.id, { rating: 5 });
      await postOk(cb, b.id, { rating: 2 });

      for (const summary of [
        await providerSummary(p.providerProfileId),
        await listingSummary(p.listingId),
      ]) {
        expect(summary.reviewCount).toBe(2);
        expect(summary.averageRating).toBe(3.5);
        expect(summary.starBreakdown).toEqual({ 1: 0, 2: 1, 3: 0, 4: 0, 5: 1 });
      }
    });

    it('finishes in two taps — stars alone are a complete review', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const review = await postOk(customer, booking.id, { rating: 4 });
      expect(review.rating).toBe(4);
      expect(review.tags).toEqual([]);
      expect(review.body).toBeNull();
    });

    it('stays consistent when reviews for one provider land at the same moment', async () => {
      const p = await provider();
      const pairs = await Promise.all(
        [5, 4, 3, 2].map(async (rating) => {
          const customer = await verifiedCustomer(app);
          return { customer, rating };
        }),
      );
      const bookings: { customer: RegisteredUser; rating: number; id: string }[] = [];
      for (const pair of pairs) {
        bookings.push({ ...pair, id: (await p.completedBooking(pair.customer)).id });
      }
      const results = await Promise.all(
        bookings.map((b) => postReview(b.customer, b.id, { rating: b.rating })),
      );
      expect(results.map((r) => r.statusCode)).toEqual([201, 201, 201, 201]);

      const summary = await providerSummary(p.providerProfileId);
      expect(summary.reviewCount).toBe(4);
      expect(summary.averageRating).toBe(3.5);
    });
  });

  // =========================================================================
  // Done when, clause 2 — a second review on the same booking is rejected
  // =========================================================================

  describe('a second review on the same booking is rejected', () => {
    it('refuses the second post and leaves the aggregate counting one', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      await postOk(customer, booking.id, { rating: 5 });

      const second = await postReview(customer, booking.id, { rating: 1 });
      expect(second.statusCode).toBe(409);
      expect(errorCode(second)).toBe('REVIEW_ALREADY_POSTED');
      expect((await providerSummary(p.providerProfileId)).reviewCount).toBe(1);
      expect((await providerSummary(p.providerProfileId)).averageRating).toBe(5);
    });

    it('lets exactly one of two concurrent posts land', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);

      const [one, two] = await Promise.all([
        postReview(customer, booking.id, { rating: 5 }),
        postReview(customer, booking.id, { rating: 1 }),
      ]);
      expect([one.statusCode, two.statusCode].sort()).toEqual([201, 409]);
      expect(await app.deps.prisma.review.count({ where: { bookingId: booking.id } })).toBe(1);
      expect((await providerSummary(p.providerProfileId)).reviewCount).toBe(1);
    });

    it('returns the original review on an idempotent replay rather than a conflict', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const key = randomUUID();
      const first = await postReview(customer, booking.id, { rating: 5 }, key);
      const replay = await postReview(customer, booking.id, { rating: 5 }, key);
      expect(first.statusCode).toBe(201);
      expect(replay.statusCode).toBe(201);
      expect(replay.json<Envelope<ReviewDto>>().data.id).toBe(
        first.json<Envelope<ReviewDto>>().data.id,
      );
    });
  });

  // =========================================================================
  // Done when, clause 3 — hiding a review recomputes the aggregate
  // =========================================================================

  describe('hiding a review recomputes the aggregate', () => {
    it('drops a hidden review from every aggregate and public read, and unhiding restores it', async () => {
      const p = await provider();
      const set = await tags(p.listingId);
      const reviews: BookingReviewDto[] = [];
      for (const rating of [5, 1]) {
        const customer = await verifiedCustomer(app);
        const booking = await p.completedBooking(customer);
        reviews.push(
          await postOk(customer, booking.id, { rating, tagIds: [tagId(set, 'arrived_late')] }),
        );
      }
      const oneStar = reviews[1];
      if (oneStar === undefined) throw new Error('fixture');
      expect((await providerSummary(p.providerProfileId)).averageRating).toBe(3);

      const hidden = await moderate(oneStar.id, 'hide');
      expect(hidden.statusCode).toBe(200);
      expect(hidden.json<Envelope<BookingReviewDto>>().data.hidden).toBe(true);

      for (const summary of [
        await providerSummary(p.providerProfileId),
        await listingSummary(p.listingId),
      ]) {
        expect(summary.reviewCount).toBe(1);
        expect(summary.averageRating).toBe(5);
        expect(summary.starBreakdown[1]).toBe(0);
      }
      const tagRow = await app.deps.prisma.providerReviewTagCount.findFirstOrThrow({
        where: { providerProfileId: p.providerProfileId, tag: { key: 'arrived_late' } },
      });
      expect(tagRow.applicationCount).toBe(1);
      const listed = await get<ReviewDto[]>(`/v1/listings/${p.listingId}/reviews`);
      expect(listed.map((r) => r.id)).not.toContain(oneStar.id);

      // A flag, never a delete (invariant 1d) — and both actions are audited.
      expect(await app.deps.prisma.review.count({ where: { id: oneStar.id } })).toBe(1);
      const again = await moderate(oneStar.id, 'hide');
      expect(again.statusCode).toBe(409);
      expect(errorCode(again)).toBe('REVIEW_ALREADY_HIDDEN');

      expect((await moderate(oneStar.id, 'unhide')).statusCode).toBe(200);
      const restored = await providerSummary(p.providerProfileId);
      expect(restored.reviewCount).toBe(2);
      expect(restored.averageRating).toBe(3);

      const audit = await app.deps.prisma.auditLogEntry.findMany({
        where: { targetType: 'review', targetId: oneStar.id },
        orderBy: { createdAt: 'asc' },
      });
      expect(audit.map((a) => a.action)).toEqual(['review.hidden', 'review.unhidden']);
      expect(audit.every((a) => a.reason.length > 0)).toBe(true);
    });

    it('is not reachable by a signed-in customer', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const review = await postOk(customer, booking.id, { rating: 1 });
      const res = await app.inject({
        method: 'POST',
        url: `/v1/admin/reviews/${review.id}/hide`,
        headers: { ...p.user.headers, ...CSRF, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { reason: 'I do not like it' },
      });
      expect(res.statusCode).toBe(401);
      expect((await providerSummary(p.providerProfileId)).reviewCount).toBe(1);
    });
  });

  // =========================================================================
  // The rules around the three clauses
  // =========================================================================

  describe('who may review what', () => {
    it('refuses a booking that has not completed', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.acceptedBooking(customer);
      const res = await postReview(customer, booking.id, { rating: 5 });
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('REVIEW_BOOKING_NOT_COMPLETED');
    });

    it('answers not-found to the provider and to a stranger', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      expect((await postReview(p.user, booking.id, { rating: 5 })).statusCode).toBe(404);
      const stranger = await verifiedCustomer(app);
      expect((await postReview(stranger, booking.id, { rating: 5 })).statusCode).toBe(404);
    });

    it('refuses free text as a tag, a tag from another category, and a rating outside 1–5', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);

      const plumbing = await app.deps.prisma.reviewTag.findFirstOrThrow({
        where: { category: { seedKey: 'Plumbing' }, key: 'on_time' },
      });
      const foreign = await postReview(customer, booking.id, { rating: 5, tagIds: [plumbing.id] });
      expect(foreign.statusCode).toBe(422);
      expect(errorCode(foreign)).toBe('REVIEW_TAG_NOT_IN_CATEGORY');

      const text = await postReview(customer, booking.id, { rating: 5, tagIds: ['Thorough'] });
      expect(text.statusCode).toBe(400);
      for (const rating of [0, 6, 4.5]) {
        expect((await postReview(customer, booking.id, { rating })).statusCode).toBe(400);
      }
      expect(await app.deps.prisma.review.count({ where: { bookingId: booking.id } })).toBe(0);
    });

    it('lets either party read the booking’s review, and nobody else', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const url = `/v1/bookings/${booking.id}/review`;
      const none = await app.inject({
        method: 'GET',
        url,
        headers: customer.headers,
        remoteAddress: freshIp(),
      });
      expect(errorCode(none)).toBe('REVIEW_NOT_FOUND');

      await postOk(customer, booking.id, { rating: 4, body: 'Thorough and on time' });
      expect((await get<BookingReviewDto>(url, p.user.headers)).rating).toBe(4);
      expect((await get<BookingReviewDto>(url, customer.headers)).body).toBe(
        'Thorough and on time',
      );
      const stranger = await verifiedCustomer(app);
      const res = await app.inject({
        method: 'GET',
        url,
        headers: stranger.headers,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });
  });

  describe('§1f tags — fixed per category, shown at three different customers', () => {
    it('seeds the plan’s eight tags, positive and negative, on every category', async () => {
      const categories = await app.deps.prisma.category.findMany({
        where: { seedKey: { not: null } },
        select: { id: true },
      });
      expect(categories).toHaveLength(12);
      for (const category of categories) {
        const set = await get<ReviewTagDto[]>(`/v1/categories/${category.id}/review-tags`);
        expect(set.map((t) => t.label)).toEqual([
          'On time',
          'Fair price',
          'Quality materials',
          'Good communication',
          'Left a mess',
          'Arrived late',
          'Poor communication',
          'Price changed on site',
        ]);
        expect(set.filter((t) => t.sentiment === 'negative')).toHaveLength(4);
      }
    });

    it('does not show a tag one customer applied three times, and does at three customers', async () => {
      const p = await provider();
      const set = await tags(p.listingId);
      const late = tagId(set, 'arrived_late');

      const repeat = await verifiedCustomer(app);
      for (let i = 0; i < 3; i++) {
        const booking = await p.completedBooking(repeat);
        await postOk(repeat, booking.id, { rating: 2, tagIds: [late] });
      }
      expect((await providerSummary(p.providerProfileId)).tags).toEqual([]);
      expect((await listingSummary(p.listingId)).tags).toEqual([]);

      for (let i = 0; i < 2; i++) {
        const customer = await verifiedCustomer(app);
        const booking = await p.completedBooking(customer);
        await postOk(customer, booking.id, { rating: 3, tagIds: [late] });
      }
      // Three different customers now; the printed count is every application.
      expect((await providerSummary(p.providerProfileId)).tags).toEqual([
        { key: 'arrived_late', label: 'Arrived late', sentiment: 'negative', count: 5 },
      ]);
    });
  });

  describe('authorship — retained, never returned (ledger P1)', () => {
    it('keeps the review and its weight after the author is anonymised, without a name', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const review = await postOk(customer, booking.id, { rating: 1, body: 'Never again' });
      expect(review.authorDisplayName).not.toBeNull();

      await app.deps.prisma.$transaction(async (tx) => {
        for (const [, hook] of app.anonymisation.list()) {
          await hook(tx, customer.userId, new Date());
        }
      });

      const [listed] = await get<ReviewDto[]>(`/v1/providers/${p.providerProfileId}/reviews`);
      expect(listed?.id).toBe(review.id);
      expect(listed?.authorDisplayName).toBeNull();
      expect(listed?.body).toBe('Never again');
      expect((await providerSummary(p.providerProfileId)).averageRating).toBe(1);

      const row = await app.deps.prisma.review.findUniqueOrThrow({ where: { id: review.id } });
      expect(row.authorId).toBe(customer.userId);
      expect(row.authorAnonymisedAt).not.toBeNull();
    });

    it('carries no author id, email or phone number in any review response', async () => {
      const p = await provider();
      const customer = await verifiedCustomer(app);
      const booking = await p.completedBooking(customer);
      const posted = await postReview(customer, booking.id, { rating: 5 });
      const user = await app.deps.prisma.user.findUniqueOrThrow({
        where: { id: customer.userId },
        select: { email: true, phoneE164: true },
      });
      const bodies = [
        posted.body,
        JSON.stringify(await get(`/v1/bookings/${booking.id}/review`, customer.headers)),
        JSON.stringify(await get(`/v1/listings/${p.listingId}/reviews`)),
        JSON.stringify(await get(`/v1/providers/${p.providerProfileId}/reviews`)),
        JSON.stringify(await providerSummary(p.providerProfileId)),
      ];
      for (const body of bodies) {
        expect(body).not.toContain(customer.userId);
        expect(body).not.toContain(user.email);
        if (user.phoneE164 !== null) expect(body).not.toContain(user.phoneE164);
        expect(body).not.toMatch(/authorId/);
      }
    });
  });

  describe('§Phase 8’s cascade, against real bookings and reviews (ledger P8-2)', () => {
    it('deletes a listing with a confirmed booking and a reviewed one, and both keep counting', async () => {
      const p = await provider();
      const reviewer = await verifiedCustomer(app);
      const reviewed = await p.completedBooking(reviewer);
      await postOk(reviewer, reviewed.id, { rating: 4 });
      const waiting = await verifiedCustomer(app);
      const confirmed = await p.confirmedBooking(waiting);
      expect(confirmed.status).toBe('confirmed');

      // §Phase 8: deletion is never refused while bookings are open.
      const del = await app.inject({
        method: 'DELETE',
        url: `/v1/providers/me/listings/${p.listingId}`,
        headers: p.user.headers,
        remoteAddress: freshIp(),
      });
      expect(del.statusCode).toBe(200);

      // The confirmed booking still completes, with its attestation intact,
      // and is still reviewable.
      const done = await actOk(app, p.user, confirmed.id, 'complete');
      expect(done.status).toBe('completed');
      expect(done.paymentAttestedAt).not.toBeNull();
      await postOk(waiting, confirmed.id, { rating: 2 });

      // The provider's aggregate keeps both reviews. With their only listing
      // deleted §1a hides the provider, so this reads the row, not the route.
      const aggregate = await app.deps.prisma.providerRatingAggregate.findUniqueOrThrow({
        where: { providerProfileId: p.providerProfileId },
      });
      expect(aggregate.reviewCount).toBe(2);
      expect(aggregate.ratingSum).toBe(6);

      // And both jobs still count toward the provider's conduct.
      await app.conduct.recompute(p.providerProfileId, new Date());
      const record = (await app.conduct.metricsFor([p.providerProfileId])).get(p.providerProfileId);
      expect(record?.jobsCompletedCount).toBe(2);
      expect(record?.completionRate).toBe(1);

      const listingRead = await app.inject({
        method: 'GET',
        url: `/v1/listings/${p.listingId}/reviews`,
        remoteAddress: freshIp(),
      });
      expect(listingRead.statusCode).toBe(404);
    });
  });
});
