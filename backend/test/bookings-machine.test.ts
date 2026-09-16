import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { ownSlots } from './helpers/availability.js';
import {
  act,
  acceptedBooking,
  actOk,
  bookableListing,
  bookSlot,
  createBooking,
  errorCode,
  listBookings,
  readBooking,
  verifiedCustomer,
} from './helpers/bookings.js';
import { registerUser } from './helpers/users.js';

/**
 * §Phase 17.1 — the core booking machine and §1c's payment attestation.
 *
 * The state machine is tested **at its boundaries** (backend/CLAUDE.md): the
 * transition that should be rejected matters more than the one that should
 * succeed, so most of what follows asserts a refusal and names the rule that
 * produced it.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — the booking machine', () => {
  /** Monday 14 September 2026, 08:00 in Malé — the same anchor §Phase 9a's suite uses. */
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
  // Put the clock back after every test, passing or failing — a failed
  // assertion mid-test would otherwise leave every later test reading a
  // different "now" (§Phase 8a's and §Phase 9a's suites carry the same note).
  afterEach(() => {
    clock.set(START);
  });

  describe('creation', () => {
    it('takes the slot inside the booking transaction and lands at requested', async () => {
      const { customer, listingId, slotId, provider } = await bookableListing(app);

      const booking = await bookSlot(app, customer, listingId, slotId, {
        jobNotes: 'Two-bedroom apartment, third floor',
      });

      expect(booking.status).toBe('requested');
      expect(booking.bookingMode).toBe('slot');
      expect(booking.timeSlotId).toBe(slotId);
      expect(booking.reference).toMatch(/^RP-[A-Z2-9]{8}$/);
      expect(booking.agreedAmountLaari).toBeNull();

      // The hold exists and the slot is gone from the provider's open grid.
      const slots = await ownSlots(app, provider, listingId);
      expect(slots.find((s) => s.id === slotId)?.status).toBe('reserved');
    });

    it('refuses an unverified customer — §1c gates booking on requireEmailVerified', async () => {
      const { listingId, slotId } = await bookableListing(app);
      const unverified = await registerUser(app, { role: 'customer' });

      const res = await createBooking(app, unverified, listingId, { timeSlotId: slotId });

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('EMAIL_NOT_VERIFIED');
    });

    it('refuses a provider booking their own listing', async () => {
      const { provider, listingId, slotId } = await bookableListing(app);
      await app.deps.prisma.user.update({
        where: { id: provider.userId },
        data: { emailVerifiedAt: new Date() },
      });

      const res = await createBooking(app, provider, listingId, { timeSlotId: slotId });

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CANNOT_BOOK_OWN_LISTING');
    });

    it('refuses a slot that belongs to a different listing', async () => {
      const a = await bookableListing(app);
      const b = await bookableListing(app);

      const res = await createBooking(app, a.customer, a.listingId, { timeSlotId: b.slotId });

      expect(res.statusCode).toBe(404);
      expect(errorCode(res)).toBe('SLOT_NOT_FOUND');
    });

    it('refuses a second booking on the same slot with a clear "no longer available"', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const second = await verifiedCustomer(app);
      await bookSlot(app, customer, listingId, slotId);

      const res = await createBooking(app, second, listingId, { timeSlotId: slotId });

      expect(res.statusCode).toBe(409);
      expect(errorCode(res)).toBe('SLOT_NO_LONGER_AVAILABLE');
    });

    it('replays an idempotency key without taking a second slot', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const key = { 'idempotency-key': `booking-${Date.now().toString()}` };

      const first = await createBooking(app, customer, listingId, { timeSlotId: slotId }, key);
      const replay = await createBooking(app, customer, listingId, { timeSlotId: slotId }, key);

      expect(first.statusCode).toBe(201);
      expect(replay.statusCode).toBe(201);
      const firstId = (JSON.parse(first.body) as { data: { id: string } }).data.id;
      const replayId = (JSON.parse(replay.body) as { data: { id: string } }).data.id;
      expect(replayId).toBe(firstId);
      const count = await app.deps.prisma.booking.count({ where: { timeSlotId: slotId } });
      expect(count).toBe(1);
    });
  });

  describe('accept — §1c step 3: the amount is set here, and nothing reaches awaiting_payment without one', () => {
    it('passes straight through accepted into awaiting_payment, recording both transitions', async () => {
      const { provider, customer, booking } = await acceptedBooking(app);

      expect(booking.status).toBe('awaiting_payment');
      expect(booking.agreedAmountLaari).toBeGreaterThan(0);
      expect(booking.amountKind).toBe('fixed_price');

      const detail = await readBooking(app, customer, booking.id);
      const transitions = (detail.statusHistory ?? []).map((e) => e.transition);
      expect(transitions).toEqual(['create', 'accept', 'amount-set']);
      expect(detail.statusHistory?.map((e) => e.toStatus)).toEqual([
        'requested',
        'accepted',
        'awaiting_payment',
      ]);
      expect(detail.statusHistory?.at(-1)?.actorRole).toBe('provider');
      expect(provider.userId).toBeDefined();
    });

    it('shows the customer the provider bank details at the payment step, and only there', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);

      const atPayment = await readBooking(app, customer, booking.id);
      expect(atPayment.paymentDetails).toBeDefined();

      // Not to the provider, who does not need their own details read back at
      // them here, and not once the step has passed.
      const providerView = await readBooking(app, provider, booking.id);
      expect(providerView.paymentDetails).toBeUndefined();

      await actOk(app, customer, booking.id, 'claim-payment');
      const afterClaim = await readBooking(app, customer, booking.id);
      expect(afterClaim.paymentDetails).toBeUndefined();
    });

    it('refuses the customer calling the provider action', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      const res = await act(app, customer, booking.id, 'accept');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_ACTOR_NOT_ALLOWED');
    });

    it('refuses a second accept — the transition carries its own status in the WHERE', async () => {
      const { provider, booking } = await acceptedBooking(app);

      const res = await act(app, provider, booking.id, 'accept');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_TRANSITION_NOT_ALLOWED');
    });

    it('is not found for a stranger, rather than forbidden', async () => {
      const { booking } = await acceptedBooking(app);
      const stranger = await verifiedCustomer(app);

      const res = await app.inject({
        method: 'GET',
        url: `/v1/bookings/${booking.id}`,
        headers: stranger.headers,
        remoteAddress: freshIp(),
      });

      expect(res.statusCode).toBe(404);
      expect(errorCode(res)).toBe('BOOKING_NOT_FOUND');
    });
  });

  describe('decline — distinct from dispute (§1c), and it frees the time', () => {
    it('frees the slot back to open', async () => {
      const { provider, customer, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      const declined = await actOk(app, provider, booking.id, 'decline', {
        reason: 'Away that week',
      });

      expect(declined.status).toBe('declined');
      const slots = await ownSlots(app, provider, listingId);
      expect(slots.find((s) => s.id === slotId)?.status).toBe('open');
    });
  });

  describe('cancel — and §1h: who cancelled is not cosmetic', () => {
    it('frees the slot and records the customer as the canceller', async () => {
      const { customer, provider, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);

      const cancelled = await actOk(app, customer, booking.id, 'cancel', {
        reason: 'Changed plans',
      });

      expect(cancelled.status).toBe('cancelled');
      expect(cancelled.cancelledByRole).toBe('customer');
      const slots = await ownSlots(app, provider, listingId);
      expect(slots.find((s) => s.id === slotId)?.status).toBe('open');
    });

    it('offers the customer §1h’s replacement prefill when the provider cancelled, and never when they did', async () => {
      const providerCancelled = await acceptedBooking(app);
      await actOk(app, providerCancelled.provider, providerCancelled.booking.id, 'cancel', {
        reason: 'Van broke down',
      });

      const view = await readBooking(app, providerCancelled.customer, providerCancelled.booking.id);
      expect(view.cancelledByRole).toBe('provider');
      expect(view.replacement).toEqual(
        expect.objectContaining({
          listingId: providerCancelled.listingId,
          bookingMode: 'slot',
        }),
      );
      expect(view.replacement?.scheduledFor).not.toBeNull();

      // The provider gets no prefill — it is not their booking to remake.
      const providerView = await readBooking(
        app,
        providerCancelled.provider,
        providerCancelled.booking.id,
      );
      expect(providerView.replacement).toBeUndefined();

      // And a customer who cancelled their own booking is not offered one.
      const self = await acceptedBooking(app);
      await actOk(app, self.customer, self.booking.id, 'cancel');
      const selfView = await readBooking(app, self.customer, self.booking.id);
      expect(selfView.replacement).toBeUndefined();
    });

    it('refuses a customer cancelling a completed booking', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');
      await actOk(app, provider, booking.id, 'complete');

      const res = await act(app, customer, booking.id, 'cancel');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_TRANSITION_NOT_ALLOWED');
    });
  });

  describe('the bookings list — §Phase 17 item 18', () => {
    it('reads the same booking from both sides and filters by status', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);

      const asCustomer = await listBookings(app, customer, '?role=customer');
      expect(asCustomer.bookings.map((b) => b.id)).toContain(booking.id);

      const asProvider = await listBookings(app, provider, '?role=provider');
      expect(asProvider.bookings.map((b) => b.id)).toContain(booking.id);

      const filtered = await listBookings(app, customer, '?role=customer&status=completed');
      expect(filtered.bookings.map((b) => b.id)).not.toContain(booking.id);

      // The provider's own list, asked for as a customer, does not contain
      // their provider-side bookings: the role is the scope, not a hint.
      const providerAsCustomer = await listBookings(app, provider, '?role=customer');
      expect(providerAsCustomer.bookings.map((b) => b.id)).not.toContain(booking.id);
    });

    it('pages with a stable cursor', async () => {
      const fixture = await bookableListing(app);
      const slots = await ownSlots(app, fixture.provider, fixture.listingId);
      const picked = slots.slice(0, 3);
      expect(picked.length).toBe(3);
      for (const slot of picked) {
        await bookSlot(app, fixture.customer, fixture.listingId, slot.id);
      }

      const first = await listBookings(app, fixture.customer, '?role=customer&limit=2');
      expect(first.bookings).toHaveLength(2);
      expect(first.nextCursor).not.toBeNull();

      const second = await listBookings(
        app,
        fixture.customer,
        `?role=customer&limit=2&cursor=${encodeURIComponent(first.nextCursor ?? '')}`,
      );
      const ids = new Set([...first.bookings, ...second.bookings].map((b) => b.id));
      expect(ids.size).toBe(first.bookings.length + second.bookings.length);
    });

    it('rejects an unknown status filter rather than ignoring it', async () => {
      const customer = await verifiedCustomer(app);

      const res = await app.inject({
        method: 'GET',
        url: '/v1/users/me/bookings?role=customer&status=nonsense',
        headers: customer.headers,
        remoteAddress: freshIp(),
      });

      expect(res.statusCode).toBe(400);
    });
  });
});
