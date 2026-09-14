import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { maldivesDateOf } from '../src/core/maldives-time.js';
import {
  SlotNoLongerAvailableError,
  TimeNoLongerAvailableError,
} from '../src/modules/availability/reservations.js';
import { RESERVATION_EXPIRY_JOB_NAME } from '../src/jobs/slot-generation.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  addRule,
  addTimeOff,
  firstOf,
  lastOf,
  openSlots,
  ownSlots,
  pickOne,
  providerWithSlotListing,
} from './helpers/availability.js';
import { categoryByName, completeDraft } from './helpers/listings.js';

/**
 * §Phase 9a's own Done-when list, one describe per clause:
 *
 *   1. two concurrent booking attempts on the same slot resolve to exactly
 *      one success and one clear "no longer available" error **under real
 *      concurrency**
 *   2. a slot-based and a request-based booking that overlap in time on the
 *      same provider cannot both succeed, **even on different listings**
 *   3. a cancelled booking's slot reappears
 *   4. a blocked range removes those slots
 *   5. an expired quote's provisional reservation is released
 *   6. a slot whose `startsAt` has just passed disappears from the picker
 *      immediately, without waiting on the regeneration job
 *
 * **Where the seam is.** Clauses 1, 2, 3 and 5 say "booking", and there is no
 * `Booking` until §Phase 17.1. What §Phase 9a builds is the thing a booking
 * is made of — the reservation — and §Phase 9a itself says reservations are
 * "created inside the booking transaction". So these drive
 * `app.reservations` in real, separate, concurrent transactions, which is the
 * whole of the guarantee: the constraint, the claim and the release are
 * exercised exactly as §Phase 17.1 will exercise them. Ledger row **P9A-2**
 * carries the half that needs a real booking row — that Phase 17.1 actually
 * calls this from inside its transition rather than beside it.
 *
 * Clauses 4 and 6 need no seam and are asserted end to end through the real
 * HTTP routes, as a provider and as a guest.
 */
describe.skipIf(databaseUrl === undefined)('Phase 9a — Done when', () => {
  /** Monday 14 September 2026, 08:00 in Malé. A weekday the fixtures' rule works. */
  const START = new Date('2026-09-14T03:00:00Z');
  const clock = controllableClock(START);
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    // A generous access-token life because several clauses below walk the
    // clock forward past a category's approval window, and the provider's
    // token is measured against the same clock — the reason §Phase 8a's
    // suite does the same.
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 30,
      sessionIdleMinutes: 60 * 24 * 30,
    }));
  });
  afterAll(async () => {
    await app.close();
  });

  // Put the clock back after **every** test, passing or failing.
  //
  // Restoring it at the end of a test body only works when the body reaches
  // the end: one failed assertion leaves the clock moved and every later test
  // in the file silently reads a different "now" — which is precisely how the
  // lead-time assertions below first appeared to fail for the wrong reason.
  // §Phase 8a's suite carries the same warning.
  afterEach(() => {
    clock.set(START);
  });

  /** The instant a Maldives wall-clock time falls on, on the fixture's own Monday. */
  const at = (utcTime: string) => new Date(`2026-09-14T${utcTime}:00Z`);

  describe('1. two customers racing the same slot', () => {
    it('resolves to exactly one success and one "no longer available", under real concurrency', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const contested = firstOf(await ownSlots(app, user, listingId), 'generated slot');

      // Two genuinely separate transactions, started together. Not two
      // sequential calls — the point of the clause is the interleaving.
      const attempt = () =>
        app.deps.prisma.$transaction((tx) =>
          app.reservations.reserveSlot(tx, { slotId: contested.id, kind: 'firm' }),
        );
      const [first, second] = await Promise.allSettled([attempt(), attempt()]);

      const outcomes = [first, second];
      expect(outcomes.filter((o) => o.status === 'fulfilled')).toHaveLength(1);

      const loser = outcomes.find((o): o is PromiseRejectedResult => o.status === 'rejected');
      if (loser === undefined) throw new Error('expected one attempt to be refused');
      const reason: unknown = loser.reason;
      // A clear, stable, machine-readable answer — not a raw constraint error.
      // `Pick a Time.dc.html` renders it as "…is no longer available".
      expect(reason).toBeInstanceOf(SlotNoLongerAvailableError);
      expect((reason as SlotNoLongerAvailableError).code).toBe('SLOT_NO_LONGER_AVAILABLE');
      expect((reason as SlotNoLongerAvailableError).status).toBe(409);

      // Exactly one hold exists on that time, and the slot says so.
      const held = await app.deps.prisma.reservation.count({
        where: { timeSlotId: contested.id, releasedAt: null },
      });
      expect(held).toBe(1);
      const row = await app.deps.prisma.timeSlot.findUniqueOrThrow({
        where: { id: contested.id },
      });
      expect(row.status).toBe('reserved');
    });

    it('holds across a thousand attempts, and every loser is told the real reason', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const contested = firstOf(await ownSlots(app, user, listingId), 'generated slot');

      // backend/CLAUDE.md asks for "1,000 concurrent attempts asserting zero
      // double-books". A thousand simultaneous interactive transactions would
      // exhaust the connection pool, and most attempts would then fail on a
      // pool timeout rather than on the rule — a test that passes because
      // nothing reached the database is not a test. So they run in waves that
      // genuinely contend, and **every** loss is asserted to be the slot
      // being gone rather than infrastructure giving up.
      const WAVE = 20;
      const losses: unknown[] = [];
      let won = 0;
      for (let sent = 0; sent < 1000; sent += WAVE) {
        const wave = await Promise.allSettled(
          Array.from({ length: WAVE }, () =>
            app.deps.prisma.$transaction((tx) =>
              app.reservations.reserveSlot(tx, { slotId: contested.id, kind: 'firm' }),
            ),
          ),
        );
        for (const outcome of wave) {
          if (outcome.status === 'fulfilled') won += 1;
          else losses.push(outcome.reason);
        }
      }

      expect(won).toBe(1);
      expect(losses).toHaveLength(999);
      expect(losses.every((e) => e instanceof SlotNoLongerAvailableError)).toBe(true);
      expect(
        await app.deps.prisma.reservation.count({
          where: { timeSlotId: contested.id, releasedAt: null },
        }),
      ).toBe(1);
    }, 180_000);
  });

  describe('2. one provider, two listings, overlapping times', () => {
    it('refuses the second even though the listings and booking modes differ', async () => {
      const { user, listingId, providerProfileId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);

      // A second listing on the same provider, request-based — the mode that
      // never has a published slot and proposes a concrete time instead.
      const plumbing = await completeDraft(app, user.headers, { categoryName: 'Plumbing' });
      expect(plumbing.bookingMode).toBe('request');

      // Take a slot on the cleaning listing: 13:00–15:00 Malé is 08:00–10:00Z.
      const slot = pickOne(
        await ownSlots(app, user, listingId),
        (s) => s.startsAt === at('08:00').toISOString(),
        'a slot at 13:00 Malé',
      );
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }),
      );

      // Now a request-based quote for 14:00–16:00 Malé on the *other* listing.
      // It overlaps by an hour. The v2/v3 `UNIQUE (providerId, listingId,
      // startsAt)` this replaced would have allowed it twice over — different
      // listing, different start.
      await expect(
        app.deps.prisma.$transaction((tx) =>
          app.reservations.reserveWindow(tx, {
            providerProfileId,
            listingId: plumbing.id,
            startsAt: at('09:00'),
            endsAt: at('11:00'),
            kind: 'firm',
          }),
        ),
      ).rejects.toBeInstanceOf(TimeNoLongerAvailableError);

      // Adjacent, not overlapping, is fine — 15:00–17:00 Malé starts exactly
      // where the slot ends. A `[)` range is what makes a back-to-back grid
      // bookable at all.
      const adjacent = await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveWindow(tx, {
          providerProfileId,
          listingId: plumbing.id,
          startsAt: at('10:00'),
          endsAt: at('12:00'),
          kind: 'firm',
        }),
      );
      expect(adjacent.releasedAt).toBeNull();
    });

    it('hides the overlapped slot from the picker, on the listing that knows nothing about it', async () => {
      const { user, listingId, providerProfileId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const plumbing = await completeDraft(app, user.headers, { categoryName: 'Plumbing' });

      const target = pickOne(
        (await openSlots(app, listingId)).slots,
        (s) => s.startsAt === at('08:00').toISOString(),
        'an offered slot at 13:00 Malé',
      );

      // A quote held on the *plumbing* listing, overlapping the cleaning slot.
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveWindow(tx, {
          providerProfileId,
          listingId: plumbing.id,
          startsAt: at('08:30'),
          endsAt: at('09:30'),
          kind: 'firm',
        }),
      );

      // §1c: "no picker ever shows an unavailable time." The cleaning slot's
      // own row still says `open` — nothing wrote to it — so this can only
      // come from resolving the collision on read.
      const after = await openSlots(app, listingId);
      expect(after.slots.map((s) => s.startsAt)).not.toContain(at('08:00').toISOString());
      const row = await app.deps.prisma.timeSlot.findUniqueOrThrow({ where: { id: target.id } });
      expect(row.status).toBe('open');

      // And the provider is told the truth about their own grid, in the words
      // `Availability.dc.html`'s reserved sheet already uses.
      const mine = await ownSlots(app, user, listingId);
      const shown = mine.find((s) => s.id === target.id);
      expect(shown?.status).toBe('reserved');
      expect(shown?.heldByAnotherListing).toBe(true);
    });
  });

  describe('3. a cancelled booking', () => {
    it('returns its slot to the picker', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      // Taken from the picker rather than from the grid: the grid includes
      // times inside Cleaning's 180-minute lead window, which the picker
      // correctly never offers — reserving one of those would make this
      // clause pass for a reason that has nothing to do with cancellation.
      const slot = firstOf((await openSlots(app, listingId)).slots, 'offered slot');

      const reservation = await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }),
      );
      expect((await openSlots(app, listingId)).slots.map((s) => s.id)).not.toContain(slot.id);

      const released = await app.deps.prisma.$transaction((tx) =>
        app.reservations.release(tx, reservation.id, 'cancelled'),
      );
      expect(released).toBe(true);

      const back = await openSlots(app, listingId);
      expect(back.slots.map((s) => s.id)).toContain(slot.id);
      expect(
        (await app.deps.prisma.timeSlot.findUniqueOrThrow({ where: { id: slot.id } })).status,
      ).toBe('open');

      // Invariant 8: the reservation is not deleted, it is stamped — and the
      // stamp is what the exclusion constraint's predicate reads, which is why
      // the time is bookable again at all.
      const row = await app.deps.prisma.reservation.findUniqueOrThrow({
        where: { id: reservation.id },
      });
      expect(row.releasedAt).not.toBeNull();
      expect(row.releaseReason).toBe('cancelled');
    });

    it('releases once, however many times the cancel is replayed', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const slot = firstOf(await ownSlots(app, user, listingId), 'generated slot');
      const reservation = await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }),
      );

      const first = await app.deps.prisma.$transaction((tx) =>
        app.reservations.release(tx, reservation.id, 'cancelled'),
      );
      const second = await app.deps.prisma.$transaction((tx) =>
        app.reservations.release(tx, reservation.id, 'declined'),
      );
      expect(first).toBe(true);
      expect(second).toBe(false);
      // The first reason stands; a replay does not rewrite history.
      expect(
        (await app.deps.prisma.reservation.findUniqueOrThrow({ where: { id: reservation.id } }))
          .releaseReason,
      ).toBe('cancelled');
    });
  });

  describe('4. a blocked range', () => {
    it('removes those days from the grid and leaves the rest alone', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const before = await ownSlots(app, user, listingId);
      const blockedDay = '2026-09-16';
      expect(before.some((s) => maldivesDateOf(new Date(s.startsAt)) === blockedDay)).toBe(true);

      await addTimeOff(app, user, { startDate: blockedDay, endDate: blockedDay });

      const after = await ownSlots(app, user, listingId);
      expect(after.some((s) => maldivesDateOf(new Date(s.startsAt)) === blockedDay)).toBe(false);
      // The day before and the day after are untouched — a trip is not a
      // reason to withdraw the whole calendar.
      expect(after.some((s) => maldivesDateOf(new Date(s.startsAt)) === '2026-09-15')).toBe(true);
      expect(after.some((s) => maldivesDateOf(new Date(s.startsAt)) === '2026-09-17')).toBe(true);
    });

    it('never touches a time somebody has already booked', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const blockedDay = '2026-09-16';
      const onThatDay = (await ownSlots(app, user, listingId)).filter(
        (s) => maldivesDateOf(new Date(s.startsAt)) === blockedDay,
      );
      expect(onThatDay.length).toBeGreaterThan(1);
      const booked = firstOf(onThatDay, 'slot on the blocked day');
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: booked.id, kind: 'firm' }),
      );

      await addTimeOff(app, user, { startDate: blockedDay, endDate: blockedDay });

      // `My Calendar.dc.html`: "booked times are never touched."
      const survivor = await app.deps.prisma.timeSlot.findUnique({ where: { id: booked.id } });
      expect(survivor).not.toBeNull();
      expect(survivor?.status).toBe('reserved');
      // Its unbooked neighbours on the same day are gone.
      const others = await app.deps.prisma.timeSlot.findMany({
        where: { listingId, id: { in: onThatDay.slice(1).map((s) => s.id) } },
      });
      expect(others).toHaveLength(0);
    });

    it('blocks a single time as the plan’s individual override, and unblocks it', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const slot = lastOf(await ownSlots(app, user, listingId), 'generated slot');

      const blocked = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/slots/${slot.id}/block`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(blocked.statusCode).toBe(200);
      expect((await openSlots(app, listingId)).slots.map((s) => s.id)).not.toContain(slot.id);

      const unblocked = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/slots/${slot.id}/unblock`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(unblocked.statusCode).toBe(200);
      expect((await openSlots(app, listingId)).slots.map((s) => s.id)).toContain(slot.id);
    });

    it('refuses to block a time a booking holds, naming the rule', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const slot = firstOf(await ownSlots(app, user, listingId), 'generated slot');
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }),
      );

      const res = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/slots/${slot.id}/block`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('SLOT_RESERVED');
    });
  });

  describe('5. an expired quote', () => {
    it('releases its provisional reservation and frees the time', async () => {
      const { user, listingId, providerProfileId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const plumbing = await completeDraft(app, user.headers, { categoryName: 'Plumbing' });

      // The window is per-category and read from the category (invariant 13),
      // never a flat 72 hours — §Phase 9a's own "72-hour" line is a
      // pre-Round-15 residue. Plumbing approves in 240 minutes.
      const category = await categoryByName(app.deps.prisma, 'Plumbing');
      const approvalMinutes = category.quoteApprovalMinutes;
      if (approvalMinutes === null) throw new Error('Plumbing should seed an approval window');
      expect(approvalMinutes).toBe(240);
      const expiresAt = new Date(clock.clock().getTime() + approvalMinutes * 60_000);

      // Tomorrow morning, deliberately: the clock moves four hours during
      // this test, and a time later today would drift in and out of
      // Cleaning's 180-minute lead window as it does — which would prove
      // nothing about expiry.
      const tomorrowNine = new Date('2026-09-15T04:00:00Z');
      const hold = await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveWindow(tx, {
          providerProfileId,
          listingId: plumbing.id,
          startsAt: tomorrowNine,
          endsAt: new Date('2026-09-15T06:00:00Z'),
          kind: 'provisional',
          expiresAt,
        }),
      );
      // While it stands, the overlapping cleaning slot is not offered.
      expect((await openSlots(app, listingId)).slots.map((s) => s.startsAt)).not.toContain(
        tomorrowNine.toISOString(),
      );

      // Advance past the window and run the sweep — by moving the clock, never
      // by waiting.
      clock.advance((approvalMinutes + 1) * 60_000);
      const ran = await app.jobs.runOnce(RESERVATION_EXPIRY_JOB_NAME, clock.clock());
      expect(ran).toBe('ran');

      const released = await app.deps.prisma.reservation.findUniqueOrThrow({
        where: { id: hold.id },
      });
      expect(released.releasedAt).not.toBeNull();
      expect(released.releaseReason).toBe('expired');

      // The cleaning slot is bookable again.
      expect((await openSlots(app, listingId)).slots.map((s) => s.startsAt)).toContain(
        tomorrowNine.toISOString(),
      );
    });

    it('leaves a firm reservation alone however long it stands', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const slot = firstOf(await ownSlots(app, user, listingId), 'generated slot');
      const firm = await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }),
      );

      await app.reservations.sweepExpiredHolds(new Date('2027-01-01T00:00:00Z'));

      expect(
        (await app.deps.prisma.reservation.findUniqueOrThrow({ where: { id: firm.id } }))
          .releasedAt,
      ).toBeNull();
    });
  });

  describe('6. a slot whose time has just passed', () => {
    it('leaves the picker the moment it passes, with no job having run', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);

      // Cleaning's seeded lead time is 180 minutes and is read per category,
      // never hardcoded (§Phase 4, admin-editable from §Phase 10b). At 08:00
      // Malé that puts the first bookable time at 11:00, so today's 09:00 is
      // already excluded for lead time rather than for having passed.
      const picker = await openSlots(app, listingId);
      expect(picker.minimumLeadTimeMinutes).toBe(180);
      expect(picker.slots.map((s) => s.startsAt)).not.toContain(at('04:00').toISOString());
      expect(picker.slots.map((s) => s.startsAt)).toContain(at('08:00').toISOString());

      // Move to 13:01 Malé — one minute past the 13:00 slot's start.
      clock.set(new Date('2026-09-14T08:01:00Z'));
      const after = await openSlots(app, listingId);
      expect(after.slots.map((s) => s.startsAt)).not.toContain(at('08:00').toISOString());

      // And prove it is a query-time guarantee rather than job timing: the row
      // is untouched, still `open`, still there. Nothing swept it.
      const row = await app.deps.prisma.timeSlot.findFirstOrThrow({
        where: { listingId, startsAt: at('08:00') },
      });
      expect(row.status).toBe('open');
    });

    it('refuses to reserve a slot whose time has passed, even by id', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const slot = firstOf(await ownSlots(app, user, listingId), 'generated slot');

      clock.set(new Date(new Date(slot.startsAt).getTime() + 60_000));
      await expect(
        app.deps.prisma.$transaction((tx) =>
          app.reservations.reserveSlot(tx, { slotId: slot.id, kind: 'firm' }, clock.clock()),
        ),
      ).rejects.toBeInstanceOf(SlotNoLongerAvailableError);
    });
  });

  describe('what no response may carry', () => {
    it('returns no phone number from any availability endpoint', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      await addTimeOff(app, user, { startDate: '2026-10-01', endDate: '2026-10-02' });

      const bodies = await Promise.all(
        [
          `/v1/providers/me/listings/${listingId}/availability`,
          `/v1/providers/me/listings/${listingId}/slots`,
          '/v1/providers/me/calendar',
          '/v1/providers/me/time-off',
        ].map((url) =>
          app
            .inject({ method: 'GET', url, headers: user.headers, remoteAddress: freshIp() })
            .then((r) => r.body),
        ),
      );
      bodies.push(
        (await app.inject({ method: 'GET', url: `/v1/listings/${listingId}/slots` })).body,
      );

      for (const body of bodies) {
        expect(body).not.toContain(user.phone);
        expect(body).not.toMatch(/\+960/);
        expect(body).not.toMatch(/phone/i);
      }
    });
  });
});
