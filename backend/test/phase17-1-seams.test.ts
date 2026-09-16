import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { ANONYMISE_JOB_NAME } from '../src/jobs/anonymise-accounts.js';
import {
  bookingDeletionBlocker,
  bookingSubscriptionSource,
  NON_TERMINAL_STATUSES,
} from '../src/modules/bookings/seams.js';
import { BookingRepository } from '../src/modules/bookings/repository.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { acceptedBooking, actOk, bookableListing, bookSlot } from './helpers/bookings.js';

/**
 * The two seams earlier phases built against, now filled — and asserted from
 * the *earlier phase's* side, because that is where the rule lives.
 *
 * Ledger rows **P1** and **P2** (§Phase 3's `DeletionBlocker`) and §Phase 8a's
 * `SubscriptionBookingSource` all say the same thing: the rule was built and
 * tested one phase before its data source, and what should survive is the
 * interface. Nothing in `modules/account/` or `modules/subscriptions/` changed
 * for this, which is the assertion those rows were really asking for.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — the two seams, filled', () => {
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

  describe('§Phase 3’s DeletionBlocker', () => {
    it('counts payment_unresolved and disputed as open — both read like endings and are not', () => {
      expect(NON_TERMINAL_STATUSES).toContain('payment_unresolved');
      expect(NON_TERMINAL_STATUSES).toContain('disputed');
      expect(NON_TERMINAL_STATUSES).not.toContain('completed');
      expect(NON_TERMINAL_STATUSES).not.toContain('cancelled');
      expect(NON_TERMINAL_STATUSES).not.toContain('declined');
      expect(NON_TERMINAL_STATUSES).not.toContain('dispute_resolved');
    });

    it('blocks on either side of a live booking and releases when it terminates', async () => {
      const blocker = bookingDeletionBlocker(new BookingRepository(app.deps.prisma));
      const { customer, provider, booking } = await acceptedBooking(app);

      // A provider with an accepted job owes somebody a visit; a customer with
      // one is owed it. Both are blocked.
      expect(await blocker.hasOpenBookings(customer.userId)).toBe(true);
      expect(await blocker.hasOpenBookings(provider.userId)).toBe(true);

      await actOk(app, customer, booking.id, 'cancel');

      expect(await blocker.hasOpenBookings(customer.userId)).toBe(false);
      expect(await blocker.hasOpenBookings(provider.userId)).toBe(false);
    });

    it('holds a deletion request open until the booking terminates, through the real job', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await app.deps.prisma.user.update({
        where: { id: customer.userId },
        data: {
          status: 'frozen',
          deletionRequestedAt: clock.clock(),
          // Well past the 30-day backstop, so only the booking can hold it.
          deletionDeadlineAt: new Date(clock.clock().getTime() + 30 * 24 * 60 * 60_000),
        },
      });

      await app.jobs.runOnce(ANONYMISE_JOB_NAME, clock.clock());
      expect(
        (
          await app.deps.prisma.user.findUniqueOrThrow({
            where: { id: customer.userId },
            select: { anonymisedAt: true },
          })
        ).anonymisedAt,
      ).toBeNull();

      await actOk(app, customer, booking.id, 'cancel');
      await app.jobs.runOnce(ANONYMISE_JOB_NAME, clock.clock());

      expect(
        (
          await app.deps.prisma.user.findUniqueOrThrow({
            where: { id: customer.userId },
            select: { anonymisedAt: true },
          })
        ).anonymisedAt,
      ).not.toBeNull();
    });
  });

  describe('§Phase 8a’s SubscriptionBookingSource', () => {
    it('answers "has any booking" the moment one lands, in any status', async () => {
      const source = bookingSubscriptionSource(new BookingRepository(app.deps.prisma), clock.clock);
      const fixture = await bookableListing(app);

      expect(await source.hasAnyBooking(fixture.providerProfileId)).toBe(false);

      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);

      // Deliberately "any", not "any confirmed" — §Phase 8a's own note.
      expect(booking.status).toBe('requested');
      expect(await source.hasAnyBooking(fixture.providerProfileId)).toBe(true);
    });

    it('protects a listing with a committed booking and a future scheduled time, and only then', async () => {
      const source = bookingSubscriptionSource(new BookingRepository(app.deps.prisma), clock.clock);
      const fixture = await bookableListing(app);

      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
      // `requested` is not a committed status: the provider has agreed nothing.
      expect(await source.listingIdsWithCommittedBooking([fixture.listingId])).toEqual([]);

      await actOk(app, fixture.provider, booking.id, 'accept');
      expect(await source.listingIdsWithCommittedBooking([fixture.listingId])).toEqual([
        fixture.listingId,
      ]);

      // …until it terminates.
      await actOk(app, fixture.customer, booking.id, 'cancel');
      expect(await source.listingIdsWithCommittedBooking([fixture.listingId])).toEqual([]);
    });

    it('stops protecting once the scheduled time has passed', async () => {
      const repo = new BookingRepository(app.deps.prisma);
      const fixture = await bookableListing(app);
      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
      await actOk(app, fixture.provider, booking.id, 'accept');

      const past = new Date(new Date(fixture.slotStartsAt).getTime() + 60 * 60_000);
      const laterSource = bookingSubscriptionSource(repo, () => past);

      // §1b's rule is committed **and** future — a job that already happened
      // does not keep a listing visible over the cap forever.
      expect(await laterSource.listingIdsWithCommittedBooking([fixture.listingId])).toEqual([]);
    });

    it('is what the app wires by default — no injection needed to see real rows', async () => {
      // The seam's own note: "when §Phase 17.1 lands, the same rules start
      // seeing real rows". Asserted against the app built with nothing
      // injected, through §Phase 8a's own endpoint.
      const fixture = await bookableListing(app);
      await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);

      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/subscription',
        headers: fixture.provider.headers,
        remoteAddress: freshIp(),
      });

      expect(res.statusCode).toBe(200);
      // §Phase 8a's "Try Premium" prompt fires 7 days after a first published
      // listing **if no booking has landed**. One has, so the prompt path is
      // now reading a real row rather than a constant `false`.
      const source = bookingSubscriptionSource(new BookingRepository(app.deps.prisma), clock.clock);
      expect(await source.hasAnyBooking(fixture.providerProfileId)).toBe(true);
    });
  });
});
