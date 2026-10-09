import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import {
  BOOKING_ACCEPT_TIMEOUT_JOB_NAME,
  BOOKING_COMPLETION_TIMEOUT_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import { CONDUCT_RECOMPUTE_JOB_NAME } from '../src/jobs/conduct-recompute.js';
import type { BookingDto, EmergencyRequestDto } from '../src/modules/bookings/types.js';
import type { ConductEvidenceDto } from '../src/modules/conduct/types.js';
import type { ProviderConductRecord } from '../src/modules/providers/conduct.js';
import type { OwnProviderDto } from '../src/modules/providers/types.js';
import { CSRF, createEnrolledAdmin } from './helpers/admin.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { addRule, ownSlots, providerWithSlotListing } from './helpers/availability.js';
import {
  act,
  actOk,
  actOnRequest,
  bookRequest,
  bookSlot,
  emergencyProvider,
  offerOn,
  raiseEmergency,
  randomIsland,
  readBooking,
  readRequest,
  requestListing,
  verifiedCustomer,
} from './helpers/bookings.js';
import { categoryByName, patchDraft } from './helpers/listings.js';
import type { RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * §1f's seven conduct metrics, computed from real bookings (§Phase 11, ledger
 * row **P5-2**).
 *
 * Every booking is driven through the real route table to the outcome under
 * test, then the `conduct-recompute` job runs and the numbers are read back
 * through §Phase 5's seam. Each `describe` is one definition from §1f, and
 * each asserts the edge the plan names: a customer's cancellation does not
 * move the cancellation rate, a timeout feeds response and not acceptance,
 * and a payment-claim outcome feeds nothing.
 *
 * 🔧 On-time is asserted **null**, not computed: §1f measures "completed with
 * an arrival mark", nothing records an arrival, and ledger row P11-1 says
 * what would close it. The emergency half of P5-2's ask (on-time against the
 * offer's `etaMinutes`) waits on the same row.
 */
describe.skipIf(databaseUrl === undefined)('Phase 11 — §1f conduct metrics', () => {
  const START = new Date('2026-10-12T03:00:00Z');
  const clock = controllableClock(START);
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 200,
      sessionIdleMinutes: 60 * 24 * 200,
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(() => {
    clock.set(START);
  });

  /** A slot provider with a grid; each call to `book` takes the next slot. */
  async function slotProvider() {
    const p = await providerWithSlotListing(app, { categoryName: 'Cleaning' });
    await addRule(app, p.user, p.listingId);
    const slots = await ownSlots(app, p.user, p.listingId);
    let next = 0;
    return {
      ...p,
      async book(customer: RegisteredUser): Promise<BookingDto> {
        const slot = slots[next++];
        if (slot === undefined) throw new Error('fixture ran out of slots');
        return bookSlot(app, customer, p.listingId, slot.id);
      },
    };
  }

  type SlotProvider = Awaited<ReturnType<typeof slotProvider>>;

  async function completed(
    p: SlotProvider,
    finalAmountLaari?: number,
  ): Promise<{ booking: BookingDto; customer: RegisteredUser }> {
    const customer = await verifiedCustomer(app);
    const booking = await p.book(customer);
    await actOk(app, p.user, booking.id, 'accept');
    await actOk(app, customer, booking.id, 'claim-payment');
    await actOk(app, p.user, booking.id, 'confirm-payment-received');
    const done = await actOk(
      app,
      p.user,
      booking.id,
      'complete',
      finalAmountLaari === undefined ? undefined : { finalAmountLaari },
    );
    return { booking: done, customer };
  }

  /**
   * An admin session at the current test time. Created per use because the
   * clock moves: a session made at START is idle-expired by the time a test
   * that advanced seven days needs it.
   */
  async function adminCookie(): Promise<string> {
    return (await createEnrolledAdmin(app)).cookie;
  }

  async function recompute(): Promise<void> {
    await app.jobs.runOnce(CONDUCT_RECOMPUTE_JOB_NAME, clock.clock());
  }

  async function metrics(providerProfileId: string): Promise<ProviderConductRecord> {
    await recompute();
    const record = (await app.conduct.metricsFor([providerProfileId])).get(providerProfileId);
    if (record === undefined) throw new Error('no snapshot was computed');
    return record;
  }

  // =========================================================================

  describe('completion and cancellation — customer cancellations never count', () => {
    it('counts the provider’s cancellation and ignores the customer’s', async () => {
      const p = await slotProvider();
      await completed(p);

      const c1 = await verifiedCustomer(app);
      const providerCancelled = await p.book(c1);
      await actOk(app, p.user, providerCancelled.id, 'accept');
      await actOk(app, p.user, providerCancelled.id, 'cancel', { reason: 'Boat broke down' });

      const before = await metrics(p.providerProfileId);
      expect(before.cancellationRate).toBeCloseTo(1 / 2, 4);
      expect(before.completionRate).toBeCloseTo(1 / 2, 4);

      const c2 = await verifiedCustomer(app);
      const customerCancelled = await p.book(c2);
      await actOk(app, p.user, customerCancelled.id, 'accept');
      await actOk(app, c2, customerCancelled.id, 'cancel', { reason: 'Plans changed' });

      const after = await metrics(p.providerProfileId);
      // The accepted cohort grew by one and the numerator did not: the
      // customer's cancellation is in the denominator only because the
      // provider did accept it — and it is in neither completion term.
      expect(after.cancellationRate).toBeCloseTo(1 / 3, 4);
      expect(after.completionRate).toBeCloseTo(1 / 2, 4);
      expect(after.completedInWindow).toBe(1);
      expect(after.jobsCompletedCount).toBe(1);
      expect(after.noShowRate).toBe(0);
    });

    it('does not count a system cancellation on a verification revocation against the provider', async () => {
      // Its own edge, `verification-revoked`, actor `system` — nobody chose it.
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      const booking = await p.book(customer);
      await actOk(app, p.user, booking.id, 'accept');
      await app.deps.prisma.booking.update({
        where: { id: booking.id },
        data: { status: 'cancelled', cancelledAt: clock.clock(), cancelledByRole: 'system' },
      });
      await app.conduct.markStale(app.deps.prisma, booking.id, clock.clock());
      expect((await metrics(p.providerProfileId)).cancellationRate).toBe(0);
    });
  });

  describe('acceptance and median response time — explicit answers only', () => {
    it('counts accept and decline, leaves the timeout out, and takes the median of the three answers', async () => {
      const p = await slotProvider();
      const bookings: BookingDto[] = [];
      for (let i = 0; i < 4; i++) bookings.push(await p.book(await verifiedCustomer(app)));
      const [b1, b2, b3] = bookings;
      if (b1 === undefined || b2 === undefined || b3 === undefined) throw new Error('fixture');

      clock.advance(60 * SECOND);
      await actOk(app, p.user, b1.id, 'accept');
      clock.advance(120 * SECOND);
      await actOk(app, p.user, b2.id, 'accept');
      clock.advance(120 * SECOND);
      await actOk(app, p.user, b3.id, 'decline', { reason: 'Fully booked that day' });

      // The fourth is left to §1c's 24-hour accept timeout.
      clock.advance(25 * HOUR);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      const timedOut = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: bookings[3]?.id ?? '' },
        select: { status: true },
      });
      expect(timedOut.status).toBe('declined');

      const m = await metrics(p.providerProfileId);
      expect(m.acceptanceRate).toBeCloseTo(2 / 3, 4);
      expect(m.medianResponseSeconds).toBe(180);
    });

    it('counts a declined callback against the provider (§1h, ledger P17-11)', async () => {
      const fixture = await requestListing(app, { categoryName: 'Plumbing' });
      const flagged = await patchDraft(app, fixture.provider.headers, fixture.listingId, {
        callbackGuaranteeOffered: true,
      });
      expect(flagged.statusCode).toBe(200);
      const original = await bookRequest(app, fixture.customer, fixture.listingId);
      const at = new Date(
        clock.clock().getTime() + (fixture.category.minimumLeadTimeMinutes + 24 * 60) * MINUTE,
      );
      clock.advance(10 * MINUTE);
      await actOk(app, fixture.provider, original.id, 'quote', {
        scheduledFor: at.toISOString(),
        amountLaari: 65_000,
      });
      await actOk(app, fixture.customer, original.id, 'approve-quote');
      await actOk(app, fixture.customer, original.id, 'claim-payment');
      await actOk(app, fixture.provider, original.id, 'confirm-payment-received');
      await actOk(app, fixture.provider, original.id, 'complete');
      expect((await metrics(fixture.providerProfileId)).acceptanceRate).toBe(1);

      clock.advance(DAY);
      const claim = await app.inject({
        method: 'POST',
        url: `/v1/bookings/${original.id}/callback`,
        headers: { ...fixture.customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { jobNotes: 'Dripping again', preferredWindowChip: 'tomorrow_morning' },
      });
      expect(claim.statusCode).toBe(201);
      const callback = claim.json<Envelope<BookingDto>>().data;
      clock.advance(5 * MINUTE);
      await actOk(app, fixture.provider, callback.id, 'decline', { reason: 'Not my problem' });

      expect((await metrics(fixture.providerProfileId)).acceptanceRate).toBeCloseTo(1 / 2, 4);
    });
  });

  describe('price adherence — the anti-hiking signal', () => {
    it('fails a final amount over the agreed one, and an upward proposal even when rejected', async () => {
      const p = await slotProvider();
      const clean = await completed(p);
      const agreed = clean.booking.agreedAmountLaari ?? 0;
      expect(agreed).toBeGreaterThan(0);

      // Finished at more than was agreed, with no amendment.
      await completed(p, agreed + 20_000);

      // Asked for more on site; the customer said no; the job finished at the
      // agreed price. §1h: every attempt "feeds price adherence".
      const customer = await verifiedCustomer(app);
      const booking = await p.book(customer);
      await actOk(app, p.user, booking.id, 'accept');
      const proposed = await app.inject({
        method: 'POST',
        url: `/v1/bookings/${booking.id}/amendments`,
        headers: { ...p.user.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { amountLaari: agreed + 30_000, reason: 'More work than described' },
      });
      expect(proposed.statusCode).toBe(201);
      const amendmentId = proposed.json<Envelope<BookingDto>>().data.amendments.at(-1)?.id ?? '';
      const rejected = await app.inject({
        method: 'PATCH',
        url: `/v1/bookings/${booking.id}/amendments/${amendmentId}`,
        headers: customer.headers,
        remoteAddress: freshIp(),
        payload: { accept: false },
      });
      expect(rejected.statusCode).toBe(200);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, p.user, booking.id, 'confirm-payment-received');
      await actOk(app, p.user, booking.id, 'complete');

      expect((await metrics(p.providerProfileId)).priceAdherenceRate).toBeCloseTo(1 / 3, 4);
    });

    it('is not moved by a withdrawn payment claim (§1f, Round 24)', async () => {
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      const booking = await p.book(customer);
      await actOk(app, p.user, booking.id, 'accept');
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, customer, booking.id, 'withdraw-payment-claim');
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, p.user, booking.id, 'confirm-payment-received');
      await actOk(app, p.user, booking.id, 'complete');

      const m = await metrics(p.providerProfileId);
      expect(m.priceAdherenceRate).toBe(1);
      expect(m.completionRate).toBe(1);
      expect(m.cancellationRate).toBe(0);
    });
  });

  describe('no-shows — confirmed ones only', () => {
    it('records an emergency “provider has not arrived” as a no-show, and leaves on-time null', async () => {
      const island = await randomIsland(app.deps.prisma);
      const category = await categoryByName(app.deps.prisma, 'Plumbing');
      const origin = await emergencyProvider(app, { categoryName: 'Plumbing', island });
      const customer = await verifiedCustomer(app);
      const request = await raiseEmergency(app, customer, category.id, island.id);
      expect((await offerOn(app, origin.provider, request.id, 40_000, 30)).statusCode).toBe(200);
      clock.advance(90 * SECOND);
      const offerId = (await readRequest(app, customer, request.id)).offers[0]?.id ?? '';
      const selected = await actOnRequest(app, customer, request.id, 'emergency-offer-response', {
        offerId,
      });
      expect(selected.statusCode).toBe(200);
      const bookingId = selected.json<Envelope<EmergencyRequestDto>>().data.bookingId ?? '';

      clock.advance((category.emergencyAcceptWindowMinutes ?? 30) * MINUTE + SECOND);
      expect((await act(app, customer, bookingId, 'provider-not-arrived')).statusCode).toBe(200);

      const m = await metrics(origin.providerProfileId);
      expect(m.noShowRate).toBe(1);
      expect(m.completionRate).toBe(0);
      // The customer's tap is not the provider's cancellation.
      expect(m.cancellationRate).toBe(0);
      // A broadcast is not a targeted booking: neither acceptance nor response.
      expect(m.acceptanceRate).toBeNull();
      expect(m.medianResponseSeconds).toBeNull();
      // §1f's denominator needs an arrival mark, and nothing records one (P11-1).
      expect(m.onTimeRate).toBeNull();
    });

    it('counts a completion-prompt “No” only once an admin resolves it for the customer', async () => {
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      const booking = await p.book(customer);
      await actOk(app, p.user, booking.id, 'accept');
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, p.user, booking.id, 'confirm-payment-received');
      const scheduled = await readBooking(app, customer, booking.id);

      clock.set(new Date(new Date(scheduled.scheduledFor ?? START).getTime() + 7 * DAY + MINUTE));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());
      await actOk(app, customer, booking.id, 'completion-answer', { happened: false });
      // Disputed is not terminal: no recompute is due, and a possible
      // no-show is not a confirmed one.
      const pending = await metrics(p.providerProfileId).catch(() => null);
      expect(pending?.noShowRate ?? null).toBeNull();

      const resolved = await app.inject({
        method: 'PATCH',
        url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
        headers: { cookie: await adminCookie(), ...CSRF },
        remoteAddress: freshIp(),
        payload: { outcome: 'resolved_for_customer', note: 'Provider did not attend' },
      });
      expect(resolved.statusCode).toBe(200);
      const m = await metrics(p.providerProfileId);
      expect(m.noShowRate).toBe(1);
      expect(m.completionRate).toBe(0);
    });
  });

  describe('how the numbers are kept — stale on transition, recomputed by the job', () => {
    it('marks the snapshot stale in the transition’s own transaction, and only on a terminal one', async () => {
      const p = await slotProvider();
      const customer = await verifiedCustomer(app);
      const booking = await p.book(customer);
      await actOk(app, p.user, booking.id, 'accept');
      expect(
        await app.deps.prisma.providerConductSnapshot.findUnique({
          where: { providerProfileId: p.providerProfileId },
        }),
      ).toBeNull();

      await actOk(app, p.user, booking.id, 'cancel', { reason: 'Unwell' });
      const stale = await app.deps.prisma.providerConductSnapshot.findUniqueOrThrow({
        where: { providerProfileId: p.providerProfileId },
      });
      expect(stale.staleSince).not.toBeNull();
      // Not computed on read: the public seam has nothing until the job runs.
      expect((await app.conduct.metricsFor([p.providerProfileId])).size).toBe(0);

      await recompute();
      const fresh = await app.deps.prisma.providerConductSnapshot.findUniqueOrThrow({
        where: { providerProfileId: p.providerProfileId },
      });
      expect(fresh.staleSince).toBeNull();
      expect(fresh.cancellationRateBp).toBe(10_000);
    });

    it('rolls the 90-day window when nothing happens, keeping the lifetime job count', async () => {
      const p = await slotProvider();
      await completed(p);
      expect((await metrics(p.providerProfileId)).completedInWindow).toBe(1);

      clock.advance(91 * DAY);
      const m = await metrics(p.providerProfileId);
      expect(m.completedInWindow).toBe(0);
      expect(m.completionRate).toBeNull();
      expect(m.jobsCompletedCount).toBe(1);
    });
  });

  describe('the provider sees it first, with the bookings behind it', () => {
    it('shows their own numbers and evidence, and nobody else’s', async () => {
      const p = await slotProvider();
      const { booking } = await completed(p);
      await recompute();

      const own = await app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: p.user.headers,
        remoteAddress: freshIp(),
      });
      const conduct = own.json<Envelope<OwnProviderDto>>().data.conduct;
      expect(conduct.jobsCompletedCount).toBe(1);
      expect(conduct.metrics.completionRate).toBe(1);
      // Below the ten-booking floor the public does not see it yet (§1f).
      expect(conduct.publiclyVisible).toBe(false);

      const evidence = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/conduct/bookings',
        headers: p.user.headers,
        remoteAddress: freshIp(),
      });
      expect(evidence.statusCode).toBe(200);
      const body =
        evidence.json<Envelope<{ computedAt: string | null; bookings: ConductEvidenceDto[] }>>()
          .data;
      expect(body.bookings.map((b) => b.bookingId)).toEqual([booking.id]);
      expect(body.bookings[0]).toMatchObject({
        completed: true,
        acceptedInWindow: true,
        priceAdherent: true,
        response: 'accepted',
      });

      const other = await slotProvider();
      const theirs = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/conduct/bookings',
        headers: other.user.headers,
        remoteAddress: freshIp(),
      });
      expect(theirs.json<Envelope<{ bookings: unknown[] }>>().data.bookings).toEqual([]);
    });
  });

  describe('appeal outcome — an excluded booking leaves the aggregate, audit-logged', () => {
    it('drops the booking from every metric, and restoring it puts it back', async () => {
      const p = await slotProvider();
      await completed(p);
      const customer = await verifiedCustomer(app);
      const cancelled = await p.book(customer);
      await actOk(app, p.user, cancelled.id, 'accept');
      await actOk(app, p.user, cancelled.id, 'cancel', { reason: 'Double-booked' });
      expect((await metrics(p.providerProfileId)).cancellationRate).toBeCloseTo(1 / 2, 4);

      const exclude = await app.inject({
        method: 'POST',
        url: `/v1/admin/bookings/${cancelled.id}/exclude-from-conduct`,
        headers: { cookie: await adminCookie(), ...CSRF, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { reason: 'Appeal upheld — customer asked the provider to cancel' },
      });
      expect(exclude.statusCode).toBe(200);
      // Recomputed in the same transaction — no job needed.
      const after = (await app.conduct.metricsFor([p.providerProfileId])).get(p.providerProfileId);
      expect(after?.cancellationRate).toBe(0);
      expect(after?.completionRate).toBe(1);

      const include = await app.inject({
        method: 'POST',
        url: `/v1/admin/bookings/${cancelled.id}/include-in-conduct`,
        headers: { cookie: await adminCookie(), ...CSRF, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { reason: 'Appeal reversed on new evidence' },
      });
      expect(include.statusCode).toBe(200);
      expect(
        (await app.conduct.metricsFor([p.providerProfileId])).get(p.providerProfileId)
          ?.cancellationRate,
      ).toBeCloseTo(1 / 2, 4);

      const audit = await app.deps.prisma.auditLogEntry.findMany({
        where: { targetType: 'booking', targetId: cancelled.id },
        orderBy: { createdAt: 'asc' },
      });
      expect(audit.map((a) => a.action)).toEqual([
        'booking.conduct_excluded',
        'booking.conduct_included',
      ]);
    });

    it('is not reachable by the provider', async () => {
      const p = await slotProvider();
      const { booking } = await completed(p);
      const res = await app.inject({
        method: 'POST',
        url: `/v1/admin/bookings/${booking.id}/exclude-from-conduct`,
        headers: { ...p.user.headers, ...CSRF, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { reason: 'Please' },
      });
      expect(res.statusCode).toBe(401);
    });
  });
});
