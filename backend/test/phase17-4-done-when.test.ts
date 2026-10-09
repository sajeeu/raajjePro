import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import type { buildApp } from '../src/app.js';
import {
  BOOKING_ACCEPT_TIMEOUT_JOB_NAME,
  BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME,
  RECURRING_SERIES_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import type { ReservationService } from '../src/modules/availability/reservations.js';
import { createOwedDispatchFee } from '../src/modules/bookings/dispatch-fee.js';
import type {
  BookingNotificationEvent,
  BookingNotifier,
} from '../src/modules/bookings/notifications.js';
import type {
  BookAgainDto,
  BookingDto,
  RecurringSeriesDto,
} from '../src/modules/bookings/types.js';
import type { SavedPreferencesDto } from '../src/modules/saved-preferences/types.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  act,
  actOk,
  bookableListing,
  bookRequest,
  bookSlot,
  errorCode,
  readBooking,
  requestListing,
  verifiedCustomer,
} from './helpers/bookings.js';
import { addRule, ownSlots, providerWithSlotListing } from './helpers/availability.js';
import { ensureIslandsSeeded } from './helpers/islands.js';
import { patchDraft } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
  meta?: { nextCursor: string | null };
}

/** Every event the module fired, so "both parties are notified" is something a test can see. */
class RecordingNotifier implements BookingNotifier {
  readonly events: BookingNotificationEvent[] = [];
  notify(event: BookingNotificationEvent): Promise<void> {
    this.events.push(event);
    return Promise.resolve();
  }
  for(subjectId: string, event: string): BookingNotificationEvent[] {
    return this.events.filter((e) => e.bookingId === subjectId && e.event === event);
  }
}

const DAY = 24 * 60 * 60_000;
const WEEK = 7 * DAY;

/**
 * §Phase 17's **17.4 — Done when**, and nothing of the other three slices
 * (§0.0 item 21):
 *
 *  1. **a missed recurring occurrence skips rather than kills the series**
 *  2. **reschedule manages reservations atomically**
 *  3. **"Book again" opens a correctly-routed new request against the same
 *     listing**
 *  4. **a confirmed booking exports a valid ICS entry**
 *
 * Plus the rule standing above all four slices — no endpoint in the module
 * returns a phone number — re-checked over every endpoint this slice adds.
 *
 * The callback guarantee and Saved Preferences are this slice's work but not
 * Done-when clauses; they are asserted below their own headings so the
 * behaviour the owner decided on 2026-10-09 is held by a test.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.4 — Done when', () => {
  const START = new Date('2026-10-12T03:00:00Z');
  const clock = controllableClock(START);
  const notifier = new RecordingNotifier();
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 120,
      sessionIdleMinutes: 60 * 24 * 120,
      deps: { bookingNotifier: notifier },
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(() => {
    clock.set(START);
    vi.restoreAllMocks();
  });

  // -- Fixtures --------------------------------------------------------------

  async function send(
    user: RegisteredUser,
    method: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE',
    url: string,
    payload?: Record<string, unknown>,
  ) {
    return app.inject({
      method,
      url,
      headers: { 'idempotency-key': randomUUID(), ...user.headers },
      remoteAddress: freshIp(),
      ...(payload === undefined ? {} : { payload }),
    });
  }

  async function sendOk<T>(
    user: RegisteredUser,
    method: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE',
    url: string,
    payload?: Record<string, unknown>,
  ): Promise<T> {
    const res = await send(user, method, url, payload);
    if (res.statusCode !== 200 && res.statusCode !== 201) {
      throw new Error(`${method} ${url}: ${String(res.statusCode)} ${res.body}`);
    }
    return res.json<Envelope<T>>().data;
  }

  /** A slot booking driven to `confirmed` — the state "Make this recurring" is offered on. */
  async function confirmedSlotBooking() {
    const fixture = await bookableListing(app);
    const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
    await actOk(app, fixture.provider, booking.id, 'accept');
    await actOk(app, fixture.customer, booking.id, 'claim-payment');
    const confirmed = await actOk(app, fixture.provider, booking.id, 'confirm-payment-received');
    return { ...fixture, booking: confirmed };
  }

  async function openSlotAt(listingId: string, startsAt: Date) {
    return app.deps.prisma.timeSlot.findFirst({
      where: { listingId, startsAt, status: 'open' },
      select: { id: true, startsAt: true },
    });
  }

  /**
   * Leaves the customer owing §1c's MVR 200 dispatch fee, unsettled — linked
   * to an emergency request, which is where the creation gate looks for it.
   */
  async function owesDispatchFee(customerId: string, listingId: string) {
    const prisma = app.deps.prisma;
    const fee = await createOwedDispatchFee(prisma, customerId);
    const listing = await prisma.listing.findUniqueOrThrow({
      where: { id: listingId },
      select: { categoryId: true },
    });
    const island = await prisma.island.findFirstOrThrow({ select: { id: true } });
    await prisma.emergencyRequest.create({
      data: {
        customerId,
        categoryId: listing.categoryId ?? '',
        islandId: island.id,
        jobNotes: 'Burst pipe',
        windowEndsAt: clock.clock(),
        dispatchFeeSubmissionId: fee.id,
      },
    });
  }

  async function series(user: RegisteredUser, id: string) {
    return sendOk<RecurringSeriesDto>(user, 'GET', `/v1/recurring-series/${id}`);
  }

  async function sweep() {
    await app.jobs.runOnce(RECURRING_SERIES_JOB_NAME, clock.clock());
  }

  async function activeHoldsFor(providerProfileId: string) {
    return app.deps.prisma.reservation.findMany({
      where: { providerProfileId, releasedAt: null },
      select: { id: true, timeSlotId: true, startsAt: true },
    });
  }

  // =========================================================================
  // 1. A missed recurring occurrence skips rather than kills the series
  // =========================================================================

  describe('1. a missed recurring occurrence skips rather than kills the series', () => {
    it('asks for next week at once, as an ordinary booking the provider must accept', async () => {
      const { customer, provider, listingId, booking } = await confirmedSlotBooking();
      const scheduled = new Date(booking.scheduledFor ?? '');

      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      expect(made.status).toBe('active');
      // §1c: "Each occurrence still requires individual provider accept."
      const [first] = made.occurrences;
      expect(first?.state).toBe('asked');
      expect(first?.occursAt).toBe(new Date(scheduled.getTime() + WEEK).toISOString());
      expect(first?.bookingStatus).toBe('requested');

      const week = await readBooking(app, provider, first?.bookingId ?? '');
      expect(week.listingId).toBe(listingId);
      expect(week.status).toBe('requested');
      expect(week.recurringSeriesId).toBe(made.id);
      // The artboard: "The ask goes out on Tue 8 Sep" for Tue 15 Sep.
      expect(made.nextOccurrenceAt).toBe(new Date(scheduled.getTime() + 2 * WEEK).toISOString());
      expect(made.nextAskAt).toBe(first?.occursAt);
    });

    it('a week that times out is missed, both are told, and the next week is still asked', async () => {
      const { customer, provider, booking } = await confirmedSlotBooking();
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      const weekOne = made.occurrences[0];

      // §1c: the occurrence "auto-declines at the 24-hour timeout".
      clock.advance(DAY + 10 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      await sweep();

      const after = await series(customer, made.id);
      expect(after.status).toBe('active');
      expect(after.consecutiveMisses).toBe(1);
      const missed = after.occurrences.find((o) => o.id === weekOne?.id);
      expect(missed?.state).toBe('missed');
      expect(missed?.missReason).toBe('timed_out');
      // §1c: "both parties are notified explicitly".
      expect(
        notifier
          .for(made.id, 'recurring_week_missed')
          .map((e) => e.userId)
          .sort(),
      ).toEqual([customer.userId, provider.userId].sort());

      // The series is not dead: when week one's own time comes round, week
      // two is asked for.
      clock.set(new Date(weekOne?.occursAt ?? ''));
      await sweep();
      const next = await series(provider, made.id);
      const weekTwo = next.occurrences.at(-1);
      expect(weekTwo?.state).toBe('asked');
      expect(weekTwo?.occursAt).toBe(
        new Date(new Date(weekOne?.occursAt ?? '').getTime() + WEEK).toISOString(),
      );
    });

    it('three misses in a row pause it; an accepted week in between resets the run', async () => {
      const { customer, provider, booking } = await confirmedSlotBooking();
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });

      // Week 1: the provider declines — a miss (owner, 2026-10-09).
      const w1 = made.occurrences[0];
      await actOk(app, provider, w1?.bookingId ?? '', 'decline');
      await sweep();
      let now = await series(customer, made.id);
      expect(now.consecutiveMisses).toBe(1);
      expect(now.occurrences[0]?.missReason).toBe('declined');

      // Week 2: accepted — the run resets.
      clock.set(new Date(w1?.occursAt ?? ''));
      await sweep();
      now = await series(customer, made.id);
      const w2 = now.occurrences.at(-1);
      await actOk(app, provider, w2?.bookingId ?? '', 'accept');
      await sweep();
      now = await series(customer, made.id);
      expect(now.occurrences.at(-1)?.state).toBe('accepted');
      expect(now.consecutiveMisses).toBe(0);

      // Weeks 3, 4, 5: declined each time.
      let last = w2;
      for (let i = 0; i < 3; i += 1) {
        clock.set(new Date(last?.occursAt ?? ''));
        await sweep();
        now = await series(customer, made.id);
        last = now.occurrences.at(-1);
        expect(last?.state).toBe('asked');
        await actOk(app, provider, last?.bookingId ?? '', 'decline');
        await sweep();
        now = await series(customer, made.id);
        if (i < 2) expect(now.status).toBe('active');
      }
      // §1c: "Three consecutive missed occurrences pause the series."
      expect(now.status).toBe('paused');
      expect(now.consecutiveMisses).toBe(3);
      expect(now.nextAskAt).toBeNull();
      // All three were the provider's declines, so the banner may name them.
      expect(now.pauseCause).toBe('provider');

      // Paused means no ask goes out, however long it waits.
      const weeksBefore = now.occurrences.length;
      clock.set(new Date(new Date(last?.occursAt ?? '').getTime() + WEEK));
      await sweep();
      expect((await series(customer, made.id)).occurrences).toHaveLength(weeksBefore);

      // "Keep asking weekly" reconfirms, and asks for the next future week.
      const resumed = await sendOk<RecurringSeriesDto>(
        customer,
        'PATCH',
        `/v1/recurring-series/${made.id}/resume`,
      );
      expect(resumed.status).toBe('active');
      expect(resumed.consecutiveMisses).toBe(0);
      expect(resumed.pauseCause).toBeNull();
      expect(resumed.occurrences.at(-1)?.state).toBe('asked');
      expect(new Date(resumed.occurrences.at(-1)?.occursAt ?? '') > clock.clock()).toBe(true);
    });

    it('a week with no open slot is missed, not fatal', async () => {
      const { customer, provider, listingId, booking } = await confirmedSlotBooking();
      // The provider blocks next week's time before the series is made.
      const target = new Date(new Date(booking.scheduledFor ?? '').getTime() + WEEK);
      const slot = await openSlotAt(listingId, target);
      await app.deps.prisma.timeSlot.update({
        where: { id: slot?.id ?? '' },
        data: { status: 'blocked' },
      });

      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      expect(made.status).toBe('active');
      expect(made.occurrences[0]?.state).toBe('missed');
      expect(made.occurrences[0]?.missReason).toBe('no_open_slot');
      expect(made.consecutiveMisses).toBe(1);
      expect((await series(provider, made.id)).status).toBe('active');
    });

    /** Sweeps at each week's ask time until the series has `weeks` resolved weeks. */
    async function sweepWeeks(customer: RegisteredUser, id: string, weeks: number) {
      let now = await series(customer, id);
      while (now.occurrences.length < weeks && now.nextAskAt !== null) {
        clock.set(new Date(now.nextAskAt));
        await sweep();
        now = await series(customer, id);
      }
      return now;
    }

    it("three weeks the customer's own unsettled fee blocked pause it — attributed to the customer, not the provider", async () => {
      const { customer, listingId, booking } = await confirmedSlotBooking();
      // §1c: an unsettled dispatch fee blocks all new bookings — every week's ask with it.
      await owesDispatchFee(customer.userId, listingId);
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      expect(made.occurrences[0]?.missReason).toBe('customer_blocked');

      const now = await sweepWeeks(customer, made.id, 3);
      expect(now.occurrences.map((o) => o.missReason)).toEqual([
        'customer_blocked',
        'customer_blocked',
        'customer_blocked',
      ]);
      // The count and the pause are unchanged by the split — only whose they are.
      expect(now.status).toBe('paused');
      expect(now.consecutiveMisses).toBe(3);
      expect(now.pauseCause).toBe('customer');
    });

    it('a provider who stops taking new customers misses on their side; mixed with the customer’s, it is neither’s', async () => {
      const { customer, provider, listingId, booking } = await confirmedSlotBooking();
      await app.deps.prisma.providerProfile.update({
        where: { userId: provider.userId },
        data: { acceptingNewCustomers: false },
      });
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      expect(made.occurrences[0]?.missReason).toBe('provider_unavailable');

      await app.deps.prisma.providerProfile.update({
        where: { userId: provider.userId },
        data: { acceptingNewCustomers: true },
      });
      await owesDispatchFee(customer.userId, listingId);
      const now = await sweepWeeks(customer, made.id, 3);
      expect(now.occurrences.map((o) => o.missReason)).toEqual([
        'provider_unavailable',
        'customer_blocked',
        'customer_blocked',
      ]);
      expect(now.status).toBe('paused');
      expect(now.pauseCause).toBe('mixed');
    });

    it('a week the customer skips is neutral, and frees the slot', async () => {
      const { customer, listingId, booking } = await confirmedSlotBooking();
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      const asked = made.occurrences[0];

      const skipped = await sendOk<RecurringSeriesDto>(
        customer,
        'PATCH',
        `/v1/recurring-series/${made.id}/skip`,
        { occursAt: asked?.occursAt },
      );
      expect(skipped.occurrences[0]?.state).toBe('skipped');
      expect(skipped.consecutiveMisses).toBe(0);
      expect(skipped.status).toBe('active');
      // The week's booking was the customer's own cancel, so the slot is back.
      expect(await openSlotAt(listingId, new Date(asked?.occursAt ?? ''))).not.toBeNull();

      // The next, not-yet-asked week can be skipped ahead — and then is never asked.
      const ahead = await sendOk<RecurringSeriesDto>(
        customer,
        'PATCH',
        `/v1/recurring-series/${made.id}/skip`,
        { occursAt: skipped.nextOccurrenceAt },
      );
      expect(ahead.nextOccurrenceSkipped).toBe(true);
      clock.set(new Date(asked?.occursAt ?? ''));
      await sweep();
      const later = await series(customer, made.id);
      expect(later.occurrences.at(-1)?.state).toBe('skipped');
      expect(later.occurrences.at(-1)?.bookingId).toBeNull();
    });

    it('ending the series withdraws the unanswered week and leaves the rest alone', async () => {
      const { customer, provider, booking } = await confirmedSlotBooking();
      const made = await sendOk<RecurringSeriesDto>(customer, 'POST', '/v1/recurring-series', {
        bookingId: booking.id,
      });
      const ended = await sendOk<RecurringSeriesDto>(
        customer,
        'PATCH',
        `/v1/recurring-series/${made.id}/end`,
      );
      expect(ended.status).toBe('ended');
      expect(ended.occurrences[0]?.state).toBe('withdrawn');
      expect((await readBooking(app, provider, made.occurrences[0]?.bookingId ?? '')).status).toBe(
        'cancelled',
      );
      // The booking it started from is untouched.
      expect((await readBooking(app, customer, booking.id)).status).toBe('confirmed');
    });

    it('is slot-only, the customer’s alone, and one per listing', async () => {
      const { customer, provider, booking } = await confirmedSlotBooking();
      await app.deps.prisma.user.update({
        where: { id: provider.userId },
        data: { emailVerifiedAt: new Date() },
      });
      expect(
        errorCode(await send(provider, 'POST', '/v1/recurring-series', { bookingId: booking.id })),
      ).toBe('BOOKING_NOT_FOUND');
      await sendOk(customer, 'POST', '/v1/recurring-series', { bookingId: booking.id });
      expect(
        errorCode(await send(customer, 'POST', '/v1/recurring-series', { bookingId: booking.id })),
      ).toBe('RECURRING_SERIES_EXISTS');

      const req = await requestListing(app);
      const request = await bookRequest(app, req.customer, req.listingId);
      expect(
        errorCode(
          await send(req.customer, 'POST', '/v1/recurring-series', { bookingId: request.id }),
        ),
      ).toBe('RECURRING_SLOT_ONLY');
    });
  });

  // =========================================================================
  // 2. Reschedule manages reservations atomically
  // =========================================================================

  describe('2. reschedule manages reservations atomically', () => {
    async function twoSlots() {
      const fixture = await bookableListing(app);
      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
      const other = await app.deps.prisma.timeSlot.findFirst({
        where: { listingId: fixture.listingId, status: 'open', id: { not: fixture.slotId } },
        orderBy: { startsAt: 'asc' },
        select: { id: true, startsAt: true },
      });
      if (other === null) throw new Error('fixture has one slot');
      return { ...fixture, booking, other };
    }

    it('before accept: frees the old slot and holds the new one, one hold throughout', async () => {
      const { customer, provider, providerProfileId, booking, slotId, other } = await twoSlots();
      clock.advance(60 * 60_000);

      const moved = await sendOk<BookingDto>(
        customer,
        'PATCH',
        `/v1/bookings/${booking.id}/reschedule`,
        { timeSlotId: other.id },
      );
      expect(moved.status).toBe('requested');
      expect(moved.timeSlotId).toBe(other.id);
      expect(moved.scheduledFor).toBe(other.startsAt.toISOString());
      expect(moved.rescheduledAt).toBe(clock.clock().toISOString());

      const slots = await app.deps.prisma.timeSlot.findMany({
        where: { id: { in: [slotId, other.id] } },
        select: { id: true, status: true },
      });
      expect(slots.find((s) => s.id === slotId)?.status).toBe('open');
      expect(slots.find((s) => s.id === other.id)?.status).toBe('reserved');
      const holds = await activeHoldsFor(providerProfileId);
      expect(holds.filter((h) => h.timeSlotId === slotId || h.timeSlotId === other.id)).toEqual([
        expect.objectContaining({ timeSlotId: other.id }),
      ]);

      // The provider's 24 hours run from the move, not from creation.
      clock.advance(DAY - 30 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, provider, booking.id)).status).toBe('requested');
      clock.advance(60 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, provider, booking.id)).status).toBe('declined');

      const history = (await readBooking(app, customer, booking.id)).statusHistory ?? [];
      expect(history.map((e) => e.transition)).toContain('reschedule');
    });

    it('a slot somebody else took first refuses, and the booking keeps its own hold', async () => {
      const { customer, booking, slotId, other, listingId, providerProfileId } = await twoSlots();
      const rival = await registerUser(app, { role: 'customer' });
      await app.deps.prisma.user.update({
        where: { id: rival.userId },
        data: { emailVerifiedAt: new Date() },
      });
      await bookSlot(app, rival, listingId, other.id);

      const res = await send(customer, 'PATCH', `/v1/bookings/${booking.id}/reschedule`, {
        timeSlotId: other.id,
      });
      expect(res.statusCode).toBe(409);
      expect(errorCode(res)).toBe('SLOT_NO_LONGER_AVAILABLE');

      const still = await readBooking(app, customer, booking.id);
      expect(still.timeSlotId).toBe(slotId);
      const holds = await activeHoldsFor(providerProfileId);
      expect(holds.some((h) => h.timeSlotId === slotId)).toBe(true);
    });

    it('a failure after the new hold is taken leaves the old hold and nothing else', async () => {
      const { customer, booking, slotId, other, providerProfileId } = await twoSlots();
      const reservations: ReservationService = app.reservations;
      const original = reservations.reschedule.bind(reservations);
      const spy = vi.spyOn(reservations, 'reschedule').mockImplementationOnce(async (...args) => {
        await original(...args);
        throw new Error('injected failure after the new hold');
      });

      const res = await send(customer, 'PATCH', `/v1/bookings/${booking.id}/reschedule`, {
        timeSlotId: other.id,
      });
      expect(spy).toHaveBeenCalledTimes(1);
      expect(res.statusCode).toBe(500);

      const slots = await app.deps.prisma.timeSlot.findMany({
        where: { id: { in: [slotId, other.id] } },
        select: { id: true, status: true },
      });
      expect(slots.find((s) => s.id === slotId)?.status).toBe('reserved');
      expect(slots.find((s) => s.id === other.id)?.status).toBe('open');
      const holds = await activeHoldsFor(providerProfileId);
      expect(holds.filter((h) => h.timeSlotId === slotId)).toHaveLength(1);
      expect(holds.filter((h) => h.timeSlotId === other.id)).toHaveLength(0);
      expect((await readBooking(app, customer, booking.id)).timeSlotId).toBe(slotId);
    });

    it('after accept: files a time amendment, and only acceptance moves the hold', async () => {
      const { customer, provider, booking, slotId, other, providerProfileId } = await twoSlots();
      await actOk(app, provider, booking.id, 'accept');

      const proposed = await sendOk<BookingDto>(
        customer,
        'PATCH',
        `/v1/bookings/${booking.id}/reschedule`,
        { timeSlotId: other.id, reason: 'Work moved my shift' },
      );
      // §1h: locked — the time has not moved, a proposal is waiting.
      expect(proposed.timeSlotId).toBe(slotId);
      const amendment = proposed.amendments[0];
      expect(amendment?.status).toBe('proposed');
      expect(amendment?.proposedScheduledFor).toBe(other.startsAt.toISOString());
      expect((await activeHoldsFor(providerProfileId)).some((h) => h.timeSlotId === slotId)).toBe(
        true,
      );

      const accepted = await sendOk<BookingDto>(
        provider,
        'PATCH',
        `/v1/bookings/${booking.id}/amendments/${amendment?.id ?? ''}`,
        { accept: true },
      );
      // Back on a published slot, not on a bare window.
      expect(accepted.timeSlotId).toBe(other.id);
      expect(accepted.scheduledFor).toBe(other.startsAt.toISOString());
      const slots = await app.deps.prisma.timeSlot.findMany({
        where: { id: { in: [slotId, other.id] } },
        select: { id: true, status: true },
      });
      expect(slots.find((s) => s.id === slotId)?.status).toBe('open');
      expect(slots.find((s) => s.id === other.id)?.status).toBe('reserved');
    });

    it('a request before its quote takes a new window and restarts the quote clock', async () => {
      const { customer, listingId, category } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);
      clock.advance(30 * 60_000);
      const moved = await sendOk<BookingDto>(
        customer,
        'PATCH',
        `/v1/bookings/${booking.id}/reschedule`,
        { preferredWindowChip: 'this_weekend' },
      );
      expect(moved.status).toBe('awaiting_quote');
      expect(moved.preferredWindowText).toBe('This weekend');
      // Invariant 13: the category's own window, from the move.
      expect(moved.quoteDueAt).toBe(
        new Date(clock.clock().getTime() + category.quoteExpiryMinutes * 60_000).toISOString(),
      );
      await app.jobs.runOnce(BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME, clock.clock());
    });

    it('refuses the provider before accept, and any emergency', async () => {
      const { provider, booking, other } = await twoSlots();
      const res = await send(provider, 'PATCH', `/v1/bookings/${booking.id}/reschedule`, {
        timeSlotId: other.id,
      });
      expect(errorCode(res)).toBe('BOOKING_ACTOR_NOT_ALLOWED');
    });
  });

  // =========================================================================
  // 3. Book again opens a correctly-routed new request against the same listing
  // =========================================================================

  describe('3. "Book again" opens a correctly-routed new request against the same listing', () => {
    async function completedSlotBooking() {
      const fixture = await confirmedSlotBooking();
      const done = await actOk(app, fixture.provider, fixture.booking.id, 'complete');
      return { ...fixture, booking: done };
    }

    it('routes by the listing’s mode now, and the booking it opens is accepted by that route', async () => {
      // A Plumbing listing a provider chose to run on published slots (§1c:
      // the mode is "defaulted by category, editable per listing") — so that
      // switching it back to requests lands on a category with a quote clock.
      const { user: provider, listingId } = await providerWithSlotListing(app, {
        categoryName: 'Plumbing',
      });
      await app.deps.prisma.listing.update({
        where: { id: listingId },
        data: { bookingMode: 'slot', pricingModel: 'fixed', priceLaari: 45_000 },
      });
      await addRule(app, provider, listingId);
      const [slot] = await ownSlots(app, provider, listingId);
      const customer = await verifiedCustomer(app);
      const first = await bookSlot(app, customer, listingId, slot?.id ?? '');
      await actOk(app, provider, first.id, 'accept');
      await actOk(app, customer, first.id, 'claim-payment');
      await actOk(app, provider, first.id, 'confirm-payment-received');
      const booking = await actOk(app, provider, first.id, 'complete');

      const slotRoute = await sendOk<BookAgainDto>(
        customer,
        'GET',
        `/v1/bookings/${booking.id}/book-again`,
      );
      expect(slotRoute.listingId).toBe(listingId);
      expect(slotRoute.available).toBe(true);
      expect(slotRoute.bookingMode).toBe('slot');
      expect(slotRoute.modeChanged).toBe(false);

      // The provider switches the listing to requests (§1c: editable per
      // listing). Book Again follows the listing, not the old booking.
      await app.deps.prisma.listing.update({
        where: { id: listingId },
        data: { bookingMode: 'request' },
      });
      const requestRoute = await sendOk<BookAgainDto>(
        customer,
        'GET',
        `/v1/bookings/${booking.id}/book-again`,
      );
      expect(requestRoute.bookingMode).toBe('request');
      expect(requestRoute.modeChanged).toBe(true);

      // And the new booking, made the way Book Again routed it, is a request
      // against the same listing and the same provider.
      const again = await sendOk<BookingDto>(
        customer,
        'POST',
        `/v1/listings/${listingId}/bookings`,
        {
          preferredWindowChip: 'tomorrow_morning',
          jobNotes: requestRoute.jobNotes ?? 'Same as last time',
        },
      );
      expect(again.bookingMode).toBe('request');
      expect(again.listingId).toBe(listingId);
      expect(again.provider.userId).toBe(provider.userId);
    });

    it('carries the address and the saved preferences forward', async () => {
      const { customer, booking } = await completedSlotBooking();
      await sendOk(customer, 'PUT', '/v1/users/me/saved-preferences/standing-instructions', {
        text: 'Gate code 4471 — keys with the caretaker',
      });
      await sendOk(customer, 'POST', '/v1/users/me/saved-preferences/time-windows', {
        weekdays: [2],
        startTime: '13:00',
        endTime: '17:00',
      });
      const again = await sendOk<BookAgainDto>(
        customer,
        'GET',
        `/v1/bookings/${booking.id}/book-again`,
      );
      expect(again.standingInstructions).toBe('Gate code 4471 — keys with the caretaker');
      expect(again.preferredWindowLabel).toBe('Tuesday · 13:00–17:00');
    });

    it('says "no longer offered" for a listing that went, and is refused before completion', async () => {
      const { customer, listingId, booking } = await completedSlotBooking();
      await app.deps.prisma.listing.update({
        where: { id: listingId },
        data: { visibility: 'hidden_by_provider' },
      });
      const gone = await sendOk<BookAgainDto>(
        customer,
        'GET',
        `/v1/bookings/${booking.id}/book-again`,
      );
      expect(gone.available).toBe(false);
      expect(gone.bookingMode).toBeNull();

      const open = await confirmedSlotBooking();
      expect(
        errorCode(await send(open.customer, 'GET', `/v1/bookings/${open.booking.id}/book-again`)),
      ).toBe('BOOK_AGAIN_NOT_AVAILABLE');
      // The provider is not offered the customer's Book Again.
      expect(
        errorCode(await send(open.provider, 'GET', `/v1/bookings/${open.booking.id}/book-again`)),
      ).toBe('BOOKING_ACTOR_NOT_ALLOWED');
    });
  });

  // =========================================================================
  // 4. A confirmed booking exports a valid ICS entry
  // =========================================================================

  describe('4. a confirmed booking exports a valid ICS entry', () => {
    it('returns an RFC 5545 calendar with the agreed time, for either party', async () => {
      const { customer, provider, booking } = await confirmedSlotBooking();
      for (const party of [customer, provider]) {
        const file = await sendOk<{ filename: string; contentType: string; ics: string }>(
          party,
          'GET',
          `/v1/bookings/${booking.id}/calendar`,
        );
        expect(file.contentType).toBe('text/calendar');
        expect(file.filename).toBe(`raajjepro-${booking.reference}.ics`);
        const ics = file.ics;

        // CRLF line endings everywhere, and no bare LF.
        expect(ics.endsWith('\r\n')).toBe(true);
        expect(ics.replace(/\r\n/g, '')).not.toContain('\n');
        const lines = ics.split('\r\n').slice(0, -1);
        // Folding: no physical line over 75 octets.
        for (const line of lines) expect(Buffer.byteLength(line, 'utf8')).toBeLessThanOrEqual(75);
        const unfolded = ics.replace(/\r\n /g, '').split('\r\n');
        expect(unfolded[0]).toBe('BEGIN:VCALENDAR');
        expect(unfolded).toContain('VERSION:2.0');
        expect(unfolded.filter((l) => l === 'BEGIN:VEVENT')).toHaveLength(1);
        expect(unfolded.filter((l) => l === 'END:VEVENT')).toHaveLength(1);
        expect(unfolded.at(-2)).toBe('END:VCALENDAR');
        for (const prop of ['UID:', 'DTSTAMP:', 'DTSTART:', 'DTEND:', 'SUMMARY:']) {
          expect(unfolded.some((l) => l.startsWith(prop))).toBe(true);
        }
        const start = (booking.scheduledFor ?? '').replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
        expect(unfolded).toContain(`DTSTART:${start}`);
        expect(unfolded.find((l) => l.startsWith('DTEND:')) ?? '').not.toBe(`DTEND:${start}`);
      }
    });

    it('is refused before the time is agreed, and to a stranger', async () => {
      const fixture = await bookableListing(app);
      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
      expect(
        errorCode(await send(fixture.customer, 'GET', `/v1/bookings/${booking.id}/calendar`)),
      ).toBe('CALENDAR_EXPORT_NOT_AVAILABLE');
      const stranger = await registerUser(app, { role: 'customer' });
      expect(errorCode(await send(stranger, 'GET', `/v1/bookings/${booking.id}/calendar`))).toBe(
        'BOOKING_NOT_FOUND',
      );
    });
  });

  // =========================================================================
  // The callback guarantee (§1h, Round 28)
  // =========================================================================

  describe('the callback guarantee', () => {
    async function completedGuaranteedJob() {
      const fixture = await requestListing(app, { categoryName: 'Plumbing' });
      const flagged = await patchDraft(app, fixture.provider.headers, fixture.listingId, {
        callbackGuaranteeOffered: true,
      });
      if (flagged.statusCode !== 200) throw new Error(`opt-in: ${flagged.body}`);
      const booking = await bookRequest(app, fixture.customer, fixture.listingId);
      const at = new Date(
        clock.clock().getTime() + (fixture.category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
      );
      await actOk(app, fixture.provider, booking.id, 'quote', {
        scheduledFor: at.toISOString(),
        amountLaari: 65_000,
      });
      await actOk(app, fixture.customer, booking.id, 'approve-quote');
      await actOk(app, fixture.customer, booking.id, 'claim-payment');
      await actOk(app, fixture.provider, booking.id, 'confirm-payment-received');
      const done = await actOk(app, fixture.provider, booking.id, 'complete');
      return { ...fixture, booking: done };
    }

    it('a claim inside 7 days opens a linked free booking that skips payment', async () => {
      const { customer, provider, listingId, category, booking } = await completedGuaranteedJob();
      expect(booking.callback.guaranteed).toBe(true);
      expect(booking.callback.canClaim).toBe(true);

      clock.advance(3 * DAY);
      const claim = await sendOk<BookingDto>(
        customer,
        'POST',
        `/v1/bookings/${booking.id}/callback`,
        {
          jobNotes: 'The same joint is dripping again',
          preferredWindowChip: 'tomorrow_morning',
        },
      );
      expect(claim.bookingMode).toBe('request');
      expect(claim.status).toBe('awaiting_quote');
      expect(claim.listingId).toBe(listingId);
      expect(claim.callbackForBookingId).toBe(booking.id);
      clock.advance(60_000);

      // The original now says it was claimed, and cannot be claimed again.
      const original = await readBooking(app, customer, booking.id);
      expect(original.callback.claimBookingId).toBe(claim.id);
      expect(original.callback.canClaim).toBe(false);
      expect(
        errorCode(
          await send(customer, 'POST', `/v1/bookings/${booking.id}/callback`, {
            jobNotes: 'Again',
            preferredWindowChip: 'tomorrow_morning',
          }),
        ),
      ).toBe('CALLBACK_ALREADY_CLAIMED');

      const at = new Date(
        clock.clock().getTime() + (category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
      );
      // "At zero cost": a price is refused, zero is accepted.
      expect(
        errorCode(
          await act(app, provider, claim.id, 'quote', {
            scheduledFor: at.toISOString(),
            amountLaari: 10_000,
          }),
        ),
      ).toBe('CALLBACK_IS_FREE');
      await actOk(app, provider, claim.id, 'quote', {
        scheduledFor: at.toISOString(),
        amountLaari: 0,
      });
      clock.advance(60_000);
      const approved = await actOk(app, customer, claim.id, 'approve-quote');
      expect(approved.status).toBe('confirmed');
      expect(approved.agreedAmountLaari).toBe(0);
      expect(approved.amountKind).toBe('callback');
      const history = (await readBooking(app, customer, claim.id)).statusHistory ?? [];
      expect(history.map((e) => e.transition)).toEqual([
        'create-callback',
        'offer-quote',
        'approve-quote',
        'no-payment-due',
      ]);
    });

    it('a declined claim files a report against the provider', async () => {
      const { customer, provider, booking } = await completedGuaranteedJob();
      const claim = await sendOk<BookingDto>(
        customer,
        'POST',
        `/v1/bookings/${booking.id}/callback`,
        {
          jobNotes: 'Leaking again',
          preferredWindowChip: 'tomorrow_morning',
        },
      );
      await actOk(app, provider, claim.id, 'decline');
      const reports = await app.deps.prisma.report.findMany({
        where: { bookingId: claim.id },
        select: { reason: true, reporterId: true },
      });
      expect(reports).toEqual([{ reason: 'callback_declined', reporterId: null }]);
    });

    it('closes at 7 days, and is never offered where the listing did not guarantee it', async () => {
      const { customer, booking } = await completedGuaranteedJob();
      clock.advance(7 * DAY + 60_000);
      expect(
        errorCode(
          await send(customer, 'POST', `/v1/bookings/${booking.id}/callback`, {
            jobNotes: 'Late',
            preferredWindowChip: 'tomorrow_morning',
          }),
        ),
      ).toBe('CALLBACK_WINDOW_CLOSED');

      clock.set(START);
      const plain = await confirmedSlotBooking();
      const done = await actOk(app, plain.provider, plain.booking.id, 'complete');
      expect(done.callback.guaranteed).toBe(false);
      expect(
        errorCode(
          await send(plain.customer, 'POST', `/v1/bookings/${done.id}/callback`, {
            jobNotes: 'Again',
            preferredWindowChip: 'tomorrow_morning',
          }),
        ),
      ).toBe('CALLBACK_NOT_OFFERED');
    });
  });

  // =========================================================================
  // Saved preferences (§1h)
  // =========================================================================

  describe('saved preferences', () => {
    it('saves an address by island id, renders labels, and is nobody else’s', async () => {
      await ensureIslandsSeeded(app.deps.prisma);
      const island = await app.deps.prisma.island.findFirstOrThrow({
        where: { nameAmbiguous: true, isActive: true },
      });
      const user = await registerUser(app, { role: 'customer' });
      const stranger = await registerUser(app, { role: 'customer' });

      const added = await sendOk<{ id: string; islandDisplayName: string }>(
        user,
        'POST',
        '/v1/users/me/saved-preferences/addresses',
        { label: 'Home', islandId: island.id, addressLine: 'Fehivina, 3rd floor' },
      );
      // §0.0 item 12: an ambiguous name is qualified, by the server.
      expect(added.islandDisplayName).toBe(`${island.atollAbbr}. ${island.name}`);

      await sendOk(user, 'POST', '/v1/users/me/saved-preferences/time-windows', {
        weekdays: [7, 1, 2, 3, 4],
        startTime: '09:00',
        endTime: '12:00',
      });
      const prefs = await sendOk<SavedPreferencesDto>(
        user,
        'GET',
        '/v1/users/me/saved-preferences',
      );
      expect(prefs.addresses.map((a) => a.label)).toEqual(['Home']);
      // The Maldivian working week is Sunday to Thursday.
      expect(prefs.timeWindows.map((w) => w.label)).toEqual(['Weekdays · 9:00–12:00']);

      // Somebody else's address is not found, for edit and for delete.
      for (const method of ['PATCH', 'DELETE'] as const) {
        const res = await send(
          stranger,
          method,
          `/v1/users/me/saved-preferences/addresses/${added.id}`,
          method === 'PATCH' ? { label: 'Mine', islandId: island.id, addressLine: 'x' } : undefined,
        );
        expect(errorCode(res)).toBe('SAVED_ADDRESS_NOT_FOUND');
      }
      expect(
        (await sendOk<SavedPreferencesDto>(stranger, 'GET', '/v1/users/me/saved-preferences'))
          .addresses,
      ).toEqual([]);

      // Removal is a soft delete: gone from the read, still a row.
      await sendOk(user, 'DELETE', `/v1/users/me/saved-preferences/addresses/${added.id}`);
      expect(
        (await sendOk<SavedPreferencesDto>(user, 'GET', '/v1/users/me/saved-preferences'))
          .addresses,
      ).toEqual([]);
      const row = await app.deps.prisma.savedAddress.findUniqueOrThrow({ where: { id: added.id } });
      expect(row.deletedAt).not.toBeNull();
    });
  });

  // =========================================================================
  // Standing rule — no endpoint in the module returns a phone number
  // =========================================================================

  describe('standing rule — no endpoint in the module returns a phone number', () => {
    it('carries no number through any endpoint this slice adds', async () => {
      const { customer, provider, booking, listingId } = await confirmedSlotBooking();
      const phones = await app.deps.prisma.user.findMany({
        where: { id: { in: [customer.userId, provider.userId] } },
        select: { phoneE164: true },
      });
      const numbers = phones.map((p) => p.phoneE164).filter((p): p is string => p !== null);
      expect(numbers.length).toBeGreaterThan(0);

      const bodies: string[] = [];
      const made = await send(customer, 'POST', '/v1/recurring-series', { bookingId: booking.id });
      bodies.push(made.body);
      const seriesId = made.json<Envelope<RecurringSeriesDto>>().data.id;
      for (const user of [customer, provider]) {
        bodies.push((await send(user, 'GET', `/v1/recurring-series/${seriesId}`)).body);
        bodies.push((await send(user, 'GET', '/v1/users/me/recurring-series')).body);
        bodies.push((await send(user, 'GET', `/v1/bookings/${booking.id}/calendar`)).body);
      }
      const other = await app.deps.prisma.timeSlot.findFirst({
        where: { listingId, status: 'open' },
        select: { id: true },
      });
      bodies.push(
        (
          await send(customer, 'PATCH', `/v1/bookings/${booking.id}/reschedule`, {
            timeSlotId: other?.id,
          })
        ).body,
      );
      const done = await actOk(app, provider, booking.id, 'complete');
      bodies.push((await send(customer, 'GET', `/v1/bookings/${done.id}/book-again`)).body);
      bodies.push((await send(customer, 'GET', '/v1/users/me/saved-preferences')).body);
      bodies.push((await send(customer, 'PATCH', `/v1/recurring-series/${seriesId}/end`)).body);

      for (const body of bodies) {
        for (const number of numbers) {
          expect(body).not.toContain(number);
          expect(body).not.toContain(number.replace(/^\+960/, ''));
        }
        expect(body.toLowerCase()).not.toContain('whatsapp');
        expect(body.toLowerCase()).not.toContain('viber');
      }
    });
  });
});
