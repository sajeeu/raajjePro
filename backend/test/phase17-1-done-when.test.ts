import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { BOOKING_ACCEPT_TIMEOUT_JOB_NAME } from '../src/jobs/booking-lifecycle.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { addRule, ownSlots } from './helpers/availability.js';
import { completeDraft, publish } from './helpers/listings.js';
import {
  act,
  acceptedBooking,
  actOk,
  bookableListing,
  bookSlot,
  errorCode,
  listBookings,
  readBooking,
  verifiedCustomer,
} from './helpers/bookings.js';
import { registerUser } from './helpers/users.js';

/**
 * §Phase 17's **Done when** list — the clauses §Phase 17.1 owns.
 *
 * The list covers all four slices, so this file asserts the ones this slice
 * can answer and says, per clause, which slice owns the rest:
 *
 *  1. the full lifecycle works — for **slot** here; request is 17.2 and
 *     emergency 17.3
 *  2. concurrent bookings on one reservation window resolve to one winner,
 *     **even across different listings of the same provider**
 *  3. an unresponsive provider auto-declines at the correct window per mode —
 *     the 24-hour slot/request window here; the emergency one is 17.3's
 *  4. an unresolved payment claim escalates to admin review at day 7 **without
 *     unlocking anything**
 *  5. a payment claim can be withdrawn while unanswered; the withdrawal is
 *     rejected once answered and on a second attempt; both transitions stay
 *     in `statusHistory`; it files no Report and moves no conduct metric
 *  6. **no endpoint in the module returns a phone number, WhatsApp handle or
 *     Viber handle** — verified by inspecting *every* response shape, not only
 *     the ones expected to carry one
 *
 * Clauses about quotes (17.2), emergency, offers, the dispatch fee, the reveal
 * endpoint and the verification cascade (17.3), and recurring, reschedule,
 * Book Again and ICS (17.4) are not asserted here and are not claimed.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — Done when', () => {
  const START = new Date('2026-09-14T03:00:00Z');
  const clock = controllableClock(START);
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 60,
      sessionIdleMinutes: 60 * 24 * 60,
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(() => {
    clock.set(START);
  });

  describe('1. the full slot lifecycle, end to end', () => {
    it('runs create → accept → pay → confirm → complete through the real routes', async () => {
      const { customer, provider, listingId, slotId } = await bookableListing(app);

      const created = await bookSlot(app, customer, listingId, slotId, {
        jobNotes: 'Deep clean, two bedrooms',
      });
      expect(created.status).toBe('requested');

      const accepted = await actOk(app, provider, created.id, 'accept');
      expect(accepted.status).toBe('awaiting_payment');
      expect(accepted.agreedAmountLaari).toBeGreaterThan(0);

      const claimed = await actOk(app, customer, created.id, 'claim-payment');
      expect(claimed.status).toBe('payment_claimed');

      const confirmed = await actOk(app, provider, created.id, 'confirm-payment-received');
      expect(confirmed.status).toBe('confirmed');

      const completed = await actOk(app, provider, created.id, 'complete');
      expect(completed.status).toBe('completed');
      expect(completed.completedVia).toBe('confirmed');

      // And the whole of it is readable as a timeline, by both parties.
      for (const party of [customer, provider]) {
        const detail = await readBooking(app, party, created.id);
        expect((detail.statusHistory ?? []).map((e) => e.toStatus)).toEqual([
          'requested',
          'accepted',
          'awaiting_payment',
          'payment_claimed',
          'confirmed',
          'completed',
        ]);
      }
    });
  });

  describe('2. concurrent bookings resolve to one winner, across listings of one provider', () => {
    it('gives one customer the slot and the other a clear refusal, under real concurrency', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const rival = await verifiedCustomer(app);

      const [a, b] = await Promise.all([
        app.inject({
          method: 'POST',
          url: `/v1/listings/${listingId}/bookings`,
          headers: { ...customer.headers, 'idempotency-key': randomUUID() },
          remoteAddress: freshIp(),
          payload: { timeSlotId: slotId },
        }),
        app.inject({
          method: 'POST',
          url: `/v1/listings/${listingId}/bookings`,
          headers: { ...rival.headers, 'idempotency-key': randomUUID() },
          remoteAddress: freshIp(),
          payload: { timeSlotId: slotId },
        }),
      ]);

      const codes = [a.statusCode, b.statusCode].sort((x, y) => x - y);
      expect(codes).toEqual([201, 409]);
      const loser = a.statusCode === 409 ? a : b;
      expect(errorCode(loser)).toBe('SLOT_NO_LONGER_AVAILABLE');
      expect(await app.deps.prisma.booking.count({ where: { timeSlotId: slotId } })).toBe(1);
    });

    it('refuses an overlapping booking on a second listing of the same provider', async () => {
      // §Phase 9a's guarantee, now asserted through the **booking** endpoint
      // rather than the reservation seam — which is the half ledger row
      // **P9A-2** left open. The exclusion constraint is provider-scoped, so a
      // second listing does not buy the provider a second body.
      const first = await bookableListing(app);
      // §1b's free tier is one active listing, so a second one publishes only
      // on a trial. Starting it here is the rule working, not a workaround.
      await app.subscriptions.startTrialForOwner(first.provider.userId);
      const secondDraft = await completeDraft(app, first.provider.headers, {
        categoryName: 'Cleaning',
      });
      const published = await publish(app, first.provider.headers, secondDraft.id);
      expect(published.statusCode).toBe(200);
      await addRule(app, first.provider, secondDraft.id);

      await bookSlot(app, first.customer, first.listingId, first.slotId);

      const rivalSlots = await ownSlots(app, first.provider, secondDraft.id);
      const overlapping = rivalSlots.find((s) => s.startsAt === first.slotStartsAt);
      expect(overlapping).toBeDefined();

      const other = await verifiedCustomer(app);
      const res = await app.inject({
        method: 'POST',
        url: `/v1/listings/${secondDraft.id}/bookings`,
        headers: { ...other.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { timeSlotId: overlapping?.id },
      });

      expect(res.statusCode).toBe(409);
      expect(errorCode(res)).toBe('PROVIDER_TIME_UNAVAILABLE');
    });

    it('leaves no hold behind when the booking write fails after the reservation succeeded', async () => {
      // The other half of ledger row **P9A-2**: one transaction, not two. The
      // booking is made to fail *after* `reserveSlot` has already run by
      // pointing it at an island id that does not exist — the foreign key
      // refuses the insert, and if the hold were taken in its own transaction
      // it would survive.
      const { customer, listingId, slotId } = await bookableListing(app);

      const res = await app.inject({
        method: 'POST',
        url: `/v1/listings/${listingId}/bookings`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { timeSlotId: slotId, islandId: randomUUID() },
      });

      expect(res.statusCode).toBeGreaterThanOrEqual(400);
      expect(await app.deps.prisma.booking.count({ where: { timeSlotId: slotId } })).toBe(0);
      expect(
        await app.deps.prisma.reservation.count({
          where: { timeSlotId: slotId, releasedAt: null },
        }),
      ).toBe(0);
      const slot = await app.deps.prisma.timeSlot.findUniqueOrThrow({
        where: { id: slotId },
        select: { status: true },
      });
      expect(slot.status).toBe('open');
    });
  });

  describe('3. an unresponsive provider auto-declines at the correct window for the mode', () => {
    it('declines a slot booking at 24 hours and no sooner', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      clock.advance(23 * 60 * 60_000 + 59 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('requested');

      clock.advance(2 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('declined');
    });
  });

  describe('4. an unresolved claim escalates at day 7 without unlocking anything', () => {
    it('reaches payment_unresolved, files a Report, and grants nothing', async () => {
      const { customer, booking, providerProfileId } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      clock.advance(7 * 24 * 60 * 60_000 + 60_000);
      await app.jobs.runOnce('booking-payment-silence', clock.clock());

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { status: true, paymentAttestedAt: true, trialHookFiredAt: true },
      });
      expect(row.status).toBe('payment_unresolved');
      expect(row.paymentAttestedAt).toBeNull();
      expect(row.trialHookFiredAt).toBeNull();
      expect(
        await app.deps.prisma.report.count({ where: { bookingId: booking.id, status: 'open' } }),
      ).toBe(1);
      const subscription = await app.deps.prisma.providerSubscription.findFirst({
        where: { providerProfileId },
        select: { trialStartedAt: true },
      });
      expect(subscription?.trialStartedAt ?? null).toBeNull();
    });
  });

  describe('5. the withdrawal rules, Round 24', () => {
    it('withdraws while unanswered, refuses after an answer and refuses a second attempt', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);

      await actOk(app, customer, booking.id, 'claim-payment');
      const withdrawn = await actOk(app, customer, booking.id, 'withdraw-payment-claim');
      expect(withdrawn.status).toBe('awaiting_payment');

      await actOk(app, customer, booking.id, 'claim-payment');
      const second = await act(app, customer, booking.id, 'withdraw-payment-claim');
      expect(second.statusCode).toBe(422);
      expect(errorCode(second)).toBe('PAYMENT_CLAIM_ALREADY_WITHDRAWN');

      await actOk(app, provider, booking.id, 'confirm-payment-received');
      const afterAnswer = await act(app, customer, booking.id, 'withdraw-payment-claim');
      expect(afterAnswer.statusCode).toBe(422);

      const detail = await readBooking(app, customer, booking.id);
      const transitions = (detail.statusHistory ?? []).map((e) => e.transition);
      expect(transitions.filter((t) => t === 'claim-payment')).toHaveLength(2);
      expect(transitions).toContain('withdraw-payment-claim');
      expect(await app.deps.prisma.report.count({ where: { bookingId: booking.id } })).toBe(0);
    });
  });

  describe('ledger P9A-1: a booked slot appears on the provider\u2019s calendar', () => {
    it('carries the customer, the reference and the mode — the three fields a Reservation has not', async () => {
      const { customer, provider, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/calendar',
        headers: provider.headers,
        remoteAddress: freshIp(),
      });

      expect(res.statusCode).toBe(200);
      const body = res.json<{
        data: {
          commitments: {
            bookingId: string | null;
            bookingReference: string | null;
            bookingMode: string | null;
            customerName: string | null;
          }[];
        };
      }>().data;
      const row = body.commitments.find((c) => c.bookingId === booking.id);
      expect(row).toBeDefined();
      expect(row?.bookingReference).toBe(booking.reference);
      expect(row?.bookingMode).toBe('slot');
      expect(row?.customerName).toBe('Aishath Test');

      // And still no phone number, on the one endpoint that now joins a
      // `User` row to answer this.
      expect(res.body).not.toContain('+960');
      expect(/"phone/i.test(res.body)).toBe(false);
    });
  });

  describe('6. no response shape in the module carries a phone number', () => {
    /**
     * Two properties, checked together over **every** response this module
     * can produce — the Done-when asks for "every response shape in the
     * module, not just the ones expected to carry it":
     *
     *  - no key anywhere in the tree is phone-, WhatsApp- or Viber-shaped;
     *  - no *value* anywhere in the tree is the phone number of either party,
     *    which catches a number that arrived under an innocent key.
     */
    function findPhoneLeak(value: unknown, forbidden: string[], path = '$'): string | null {
      if (value === null || value === undefined) return null;
      if (typeof value === 'string') {
        const digits = value.replace(/\D/g, '');
        for (const number of forbidden) {
          if (digits.length >= 7 && digits.includes(number)) {
            return `${path} carries the number ${number}`;
          }
        }
        return null;
      }
      if (Array.isArray(value)) {
        for (const [i, item] of value.entries()) {
          const leak = findPhoneLeak(item, forbidden, `${path}[${String(i)}]`);
          if (leak !== null) return leak;
        }
        return null;
      }
      if (typeof value === 'object') {
        for (const [key, item] of Object.entries(value)) {
          if (/phone|mobile|whatsapp|viber|msisdn|tel\b/i.test(key)) {
            return `${path}.${key} is a contact-shaped key`;
          }
          const leak = findPhoneLeak(item, forbidden, `${path}.${key}`);
          if (leak !== null) return leak;
        }
      }
      return null;
    }

    it('holds across every endpoint the slice exposes, at every status it can reach', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      const customerRow = await app.deps.prisma.user.findUniqueOrThrow({
        where: { id: customer.userId },
        select: { phoneE164: true },
      });
      const providerRow = await app.deps.prisma.user.findUniqueOrThrow({
        where: { id: provider.userId },
        select: { phoneE164: true },
      });
      const forbidden = [customerRow.phoneE164, providerRow.phoneE164]
        .filter((p): p is string => p !== null)
        .map((p) => p.replace(/\D/g, ''));
      expect(forbidden).toHaveLength(2);

      const bodies: { label: string; body: unknown }[] = [];
      const capture = (label: string, res: { body: string }) => {
        bodies.push({ label, body: JSON.parse(res.body) });
      };

      // Every read, on both sides, at the status where the payment details
      // (the one thing this module deliberately does reveal) are attached.
      capture('read as customer', {
        body: JSON.stringify({ data: await readBooking(app, customer, booking.id) }),
      });
      capture('read as provider', {
        body: JSON.stringify({ data: await readBooking(app, provider, booking.id) }),
      });
      capture('list as customer', {
        body: JSON.stringify(await listBookings(app, customer, '?role=customer')),
      });
      capture('list as provider', {
        body: JSON.stringify(await listBookings(app, provider, '?role=provider')),
      });

      // Every mutation, in the order that walks the machine.
      capture('claim-payment', await act(app, customer, booking.id, 'claim-payment'));
      capture(
        'withdraw-payment-claim',
        await act(app, customer, booking.id, 'withdraw-payment-claim'),
      );
      capture('claim-payment again', await act(app, customer, booking.id, 'claim-payment'));
      capture(
        'confirm-payment-received',
        await act(app, provider, booking.id, 'confirm-payment-received'),
      );
      capture(
        'amendment',
        await app.inject({
          method: 'POST',
          url: `/v1/bookings/${booking.id}/amendments`,
          headers: { ...provider.headers, 'idempotency-key': randomUUID() },
          remoteAddress: freshIp(),
          payload: { amountLaari: 9999, reason: 'Extra room' },
        }),
      );
      capture('complete', await act(app, provider, booking.id, 'complete'));
      capture(
        'dispute',
        await act(app, customer, booking.id, 'dispute', { reason: 'work_not_done' }),
      );

      // A second booking, walked down the refusal paths, so the error shapes
      // are inspected too.
      const other = await bookableListing(app);
      const fresh = await bookSlot(app, other.customer, other.listingId, other.slotId);
      capture('decline', await act(app, other.provider, fresh.id, 'decline'));
      capture('accept after decline', await act(app, other.provider, fresh.id, 'accept'));
      const stranger = await registerUser(app, { role: 'customer' });
      capture(
        'read as stranger',
        await app.inject({
          method: 'GET',
          url: `/v1/bookings/${fresh.id}`,
          headers: stranger.headers,
          remoteAddress: freshIp(),
        }),
      );

      const leaks = bodies
        .map(({ label, body }) => ({ label, leak: findPhoneLeak(body, forbidden) }))
        .filter((r) => r.leak !== null);
      expect(leaks).toEqual([]);
      // And the audit actually looked at something — a silent pass because
      // every body was empty would be worse than a failure.
      expect(bodies.length).toBeGreaterThanOrEqual(14);
    });

    it('has no contact-info route, the one §1c says must never be recreated', async () => {
      const { customer, booking } = await acceptedBooking(app);

      const res = await app.inject({
        method: 'GET',
        url: `/v1/bookings/${booking.id}/contact-info`,
        headers: customer.headers,
        remoteAddress: freshIp(),
      });

      expect(res.statusCode).toBe(404);
      // §Phase 17.3 builds `reveal-contact`, the single exception. It is not
      // this slice's and is deliberately absent too.
      const reveal = await app.inject({
        method: 'POST',
        url: `/v1/bookings/${booking.id}/reveal-contact`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: {},
      });
      expect(reveal.statusCode).toBe(404);
    });
  });
});
