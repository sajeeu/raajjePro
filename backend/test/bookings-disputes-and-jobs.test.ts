import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import {
  BOOKING_ACCEPT_TIMEOUT_JOB_NAME,
  BOOKING_COMPLETION_TIMEOUT_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { CSRF, createEnrolledAdmin, loginAndVerify } from './helpers/admin.js';
import {
  act,
  acceptedBooking,
  actOk,
  bookableListing,
  bookSlot,
  errorCode,
  readBooking,
} from './helpers/bookings.js';

const DAY = 24 * 60 * 60_000;

/**
 * §Phase 17.1's disputes and its three scheduled clocks.
 *
 * Every timing assertion moves a clock rather than waiting — and asserts both
 * sides of the boundary, because a job that fires early is as wrong as one
 * that never fires.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — disputes and the scheduled clocks', () => {
  const START = new Date('2026-09-14T03:00:00Z');
  const clock = controllableClock(START);
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 60,
      sessionIdleMinutes: 60 * 24 * 60,
      sessionAbsoluteHours: 24 * 60,
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(() => {
    clock.set(START);
  });

  describe('the 24-hour accept window — §1c step 4', () => {
    it('does not fire at 23 hours and does fire past 24, releasing the slot', async () => {
      const { customer, provider, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      clock.advance(23 * 60 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect(
        (
          await app.deps.prisma.booking.findUniqueOrThrow({
            where: { id: booking.id },
            select: { status: true },
          })
        ).status,
      ).toBe('requested');

      clock.advance(2 * 60 * 60_000);
      const ran = await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect(ran).toBe('ran');

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { status: true, declinedAt: true },
      });
      expect(row.status).toBe('declined');
      expect(row.declinedAt).not.toBeNull();

      // Read from the row rather than the provider's grid: the clock has moved
      // 25 hours, so this slot is now in the past and the grid — correctly —
      // no longer lists it. What the clause is about is that the hold went.
      const slot = await app.deps.prisma.timeSlot.findUniqueOrThrow({
        where: { id: slotId },
        select: { status: true },
      });
      expect(slot.status).toBe('open');
      const live = await app.deps.prisma.reservation.count({
        where: { timeSlotId: slotId, releasedAt: null },
      });
      expect(live).toBe(0);
      expect(provider.userId).toBeDefined();
      expect(listingId).toBeDefined();
    });

    it('records the timeout as the system, distinguishable from a provider who said no', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      clock.advance(25 * 60 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());

      const detail = await readBooking(app, customer, booking.id);
      const last = detail.statusHistory?.at(-1);
      // §1f: "timeouts feed response rate, not acceptance rate" — which is
      // only computable because the actor and the transition differ.
      expect(last?.transition).toBe('accept-timeout');
      expect(last?.actorRole).toBe('system');
      expect(last?.toStatus).toBe('declined');
    });

    it('leaves an accepted booking alone', async () => {
      const { booking } = await acceptedBooking(app);

      clock.advance(3 * DAY);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());

      expect(
        (
          await app.deps.prisma.booking.findUniqueOrThrow({
            where: { id: booking.id },
            select: { status: true },
          })
        ).status,
      ).toBe('awaiting_payment');
    });
  });

  describe('the completion timeout — §1c step 10', () => {
    async function confirmedBooking() {
      const fixture = await acceptedBooking(app);
      await actOk(app, fixture.customer, fixture.booking.id, 'claim-payment');
      await actOk(app, fixture.provider, fixture.booking.id, 'confirm-payment-received');
      return fixture;
    }

    it('prompts the customer 7 days past the scheduled time without moving the booking', async () => {
      const { customer, booking } = await confirmedBooking();

      clock.set(new Date(new Date(booking.scheduledFor ?? START).getTime() + 7 * DAY + 60_000));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());

      const view = await readBooking(app, customer, booking.id);
      expect(view.status).toBe('confirmed');
      expect(view.completionPromptedAt).not.toBeNull();
    });

    it('auto-completes as unconfirmed 3 days after the prompt, and not before', async () => {
      const { customer, booking } = await confirmedBooking();
      const scheduled = new Date(booking.scheduledFor ?? START).getTime();

      clock.set(new Date(scheduled + 7 * DAY + 60_000));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());

      clock.set(new Date(scheduled + 9 * DAY));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('confirmed');

      clock.set(new Date(scheduled + 11 * DAY));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());

      const view = await readBooking(app, customer, booking.id);
      expect(view.status).toBe('completed');
      expect(view.completedVia).toBe('unconfirmed');
    });

    it('distinguishes a customer answering "yes" from the silent auto-completion', async () => {
      const { customer, booking } = await confirmedBooking();
      clock.set(new Date(new Date(booking.scheduledFor ?? START).getTime() + 7 * DAY + 60_000));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());

      const answered = await actOk(app, customer, booking.id, 'completion-answer', {
        happened: true,
      });

      expect(answered.status).toBe('completed');
      expect(answered.completedVia).toBe('confirmed');
    });

    it('routes "no" to the moderation queue as a dispute (§1c step 10)', async () => {
      const { customer, booking } = await confirmedBooking();
      clock.set(new Date(new Date(booking.scheduledFor ?? START).getTime() + 7 * DAY + 60_000));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());

      const answered = await actOk(app, customer, booking.id, 'completion-answer', {
        happened: false,
      });

      expect(answered.status).toBe('disputed');
      const report = await app.deps.prisma.report.findFirstOrThrow({
        where: { bookingId: booking.id },
      });
      expect(report.reason).toBe('work_not_done');
      expect(report.reporterId).toBe(customer.userId);
    });
  });

  describe('disputes — §1c', () => {
    it('files a Report and moves a live booking to disputed', async () => {
      const { customer, booking } = await acceptedBooking(app);

      const disputed = await actOk(app, customer, booking.id, 'dispute', {
        reason: 'price_changed_on_site',
        note: 'Asked for more on arrival',
      });

      expect(disputed.status).toBe('disputed');
      const report = await app.deps.prisma.report.findFirstOrThrow({
        where: { bookingId: booking.id },
      });
      expect(report.reason).toBe('price_changed_on_site');
      expect(report.status).toBe('open');
    });

    it('accepts a late dispute without moving a completed booking', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');
      await actOk(app, provider, booking.id, 'complete');

      const after = await actOk(app, customer, booking.id, 'dispute', { reason: 'work_not_done' });

      expect(after.status).toBe('completed');
      expect(await app.deps.prisma.report.count({ where: { bookingId: booking.id } })).toBe(1);
    });

    it('refuses a reason that belongs to another target type', async () => {
      const { customer, booking } = await acceptedBooking(app);

      const res = await act(app, customer, booking.id, 'dispute', { reason: 'fake_review' });

      expect(res.statusCode).toBe(400);
    });

    describe('an admin resolving it', () => {
      async function adminCookie(): Promise<string> {
        const admin = await createEnrolledAdmin(app);
        const { cookie } = await loginAndVerify(app, admin.email, admin.secret);
        return cookie;
      }

      it('closes a dispute with an enumerated outcome and resolves its Reports', async () => {
        const { customer, booking } = await acceptedBooking(app);
        await actOk(app, customer, booking.id, 'dispute', { reason: 'payment_dispute' });
        const cookie = await adminCookie();

        const res = await app.inject({
          method: 'PATCH',
          url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
          headers: { cookie, ...CSRF },
          remoteAddress: freshIp(),
          payload: { outcome: 'resolved_for_customer', note: 'Refund arranged off-platform' },
        });

        expect(res.statusCode).toBe(200);
        const row = await app.deps.prisma.booking.findUniqueOrThrow({
          where: { id: booking.id },
          select: { status: true, disputeOutcome: true },
        });
        expect(row.status).toBe('dispute_resolved');
        expect(row.disputeOutcome).toBe('resolved_for_customer');

        const report = await app.deps.prisma.report.findFirstOrThrow({
          where: { bookingId: booking.id },
        });
        expect(report.status).toBe('resolved');
        // §Phase 22: `resolved` is unreachable without a resolution reason.
        expect(report.resolutionReason).not.toBeNull();
      });

      it('rejects a free-text outcome', async () => {
        const { customer, booking } = await acceptedBooking(app);
        await actOk(app, customer, booking.id, 'dispute', { reason: 'payment_dispute' });
        const cookie = await adminCookie();

        const res = await app.inject({
          method: 'PATCH',
          url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
          headers: { cookie, ...CSRF },
          remoteAddress: freshIp(),
          payload: { outcome: 'sorted it out' },
        });

        expect(res.statusCode).toBe(400);
      });

      it('resolves payment_unresolved to confirmed, reaching §Phase 8a’s trial hook', async () => {
        const { customer, booking, providerProfileId } = await acceptedBooking(app);
        await actOk(app, customer, booking.id, 'claim-payment');
        clock.advance(8 * DAY);
        await app.jobs.runOnce('booking-payment-silence', clock.clock());
        const cookie = await adminCookie();

        const res = await app.inject({
          method: 'PATCH',
          url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
          headers: { cookie, ...CSRF },
          remoteAddress: freshIp(),
          payload: { outcome: 'resolved_for_customer', unresolvedTo: 'confirmed' },
        });

        expect(res.statusCode).toBe(200);
        const row = await app.deps.prisma.booking.findUniqueOrThrow({
          where: { id: booking.id },
          select: { status: true, trialHookFiredAt: true },
        });
        expect(row.status).toBe('confirmed');
        // §Phase 17 item 20: the hook fires on the transition, from either door.
        expect(row.trialHookFiredAt).not.toBeNull();
        const subscription = await app.deps.prisma.providerSubscription.findFirst({
          where: { providerProfileId },
          select: { trialStartedAt: true },
        });
        expect(subscription?.trialStartedAt).not.toBeNull();
      });

      it('refuses to resolve an unresolved claim without saying to what', async () => {
        const { customer, booking } = await acceptedBooking(app);
        await actOk(app, customer, booking.id, 'claim-payment');
        clock.advance(8 * DAY);
        await app.jobs.runOnce('booking-payment-silence', clock.clock());
        const cookie = await adminCookie();

        const res = await app.inject({
          method: 'PATCH',
          url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
          headers: { cookie, ...CSRF },
          remoteAddress: freshIp(),
          payload: { outcome: 'inconclusive' },
        });

        expect(res.statusCode).toBe(422);
        expect(errorCode(res)).toBe('UNRESOLVED_NEEDS_AN_OUTCOME');
      });

      it('is not reachable by a signed-in customer', async () => {
        const { customer, booking } = await acceptedBooking(app);
        await actOk(app, customer, booking.id, 'dispute', { reason: 'payment_dispute' });

        const res = await app.inject({
          method: 'PATCH',
          url: `/v1/admin/bookings/${booking.id}/resolve-dispute`,
          headers: { ...customer.headers, ...CSRF },
          remoteAddress: freshIp(),
          payload: { outcome: 'inconclusive' },
        });

        expect(res.statusCode).toBe(401);
      });
    });
  });
});
