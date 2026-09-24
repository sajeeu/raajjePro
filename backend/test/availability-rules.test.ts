import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { maldivesDateOf } from '../src/core/maldives-time.js';
import { SLOT_GENERATION_JOB_NAME } from '../src/jobs/slot-generation.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  addRule,
  addTimeOff,
  availabilityBase,
  firstOf,
  openSlots,
  ownSlots,
  pickOne,
  providerWithSlotListing,
  readAvailability,
} from './helpers/availability.js';
import { completeDraft, patchDraft } from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

/**
 * The availability surface itself — generation, regeneration, the rules that
 * make a grid readable, authorization, and the scheduled job's shape.
 *
 * §Phase 9a's own Done-when list is asserted in `phase9a-done-when.test.ts`;
 * this is everything the phase has to get right for those six clauses to mean
 * anything.
 */
describe.skipIf(databaseUrl === undefined)('availability rules and slot generation', () => {
  const START = new Date('2026-09-14T03:00:00Z'); // Monday, 08:00 in Malé
  const clock = controllableClock(START);
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 30,
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(() => {
    clock.set(START);
  });

  const regenerate = (listingId: string, headers: Record<string, string>) =>
    app.inject({
      method: 'POST',
      url: `/v1/providers/me/listings/${listingId}/slots/regenerate`,
      headers,
      remoteAddress: freshIp(),
    });

  describe('generation', () => {
    it('is idempotent — re-running changes nothing', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const first = await ownSlots(app, user, listingId);

      const again = await regenerate(listingId, user.headers);
      expect(again.statusCode).toBe(200);
      expect(again.json<{ data: { created: number; removed: number } }>().data).toEqual({
        created: 0,
        removed: 0,
      });

      const second = await ownSlots(app, user, listingId);
      // Same times AND the same rows — a regeneration that deleted and
      // recreated identical slots would break every id a client is holding.
      expect(second.map((s) => s.id)).toEqual(first.map((s) => s.id));
    });

    it('covers sixty rolling days and says how far ahead that reaches', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId, { weekdays: [1, 2, 3, 4, 5, 6, 7] });

      const slots = await ownSlots(app, user, listingId);
      const days = new Set(slots.map((s) => maldivesDateOf(new Date(s.startsAt))));
      expect(days.size).toBe(60);

      const availability = await readAvailability(app, user, listingId);
      // The last bookable Maldives day, not the exclusive boundary after it.
      expect(availability.horizonDate).toBe('2026-11-12');
    });

    it('publishes nothing until there is a rule, and withdraws everything when the last one goes', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      expect(await ownSlots(app, user, listingId)).toEqual([]);

      const rule = await addRule(app, user, listingId);
      expect((await ownSlots(app, user, listingId)).length).toBeGreaterThan(0);

      const removed = await app.inject({
        method: 'DELETE',
        url: `${availabilityBase(listingId)}/rules/${rule.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(removed.statusCode).toBe(204);
      expect(await ownSlots(app, user, listingId)).toEqual([]);

      // Dormant, so the job stops reading it entirely.
      const state = await app.deps.prisma.listingSlotState.findUniqueOrThrow({
        where: { listingId },
      });
      expect(state.nextGenerationAt).toBeNull();

      // Invariant 8: the rule itself is stamped, not removed.
      const row = await app.deps.prisma.availabilityRule.findUniqueOrThrow({
        where: { id: rule.id },
      });
      expect(row.deletedAt).not.toBeNull();
    });
  });

  describe('a rule change regenerates future unreserved slots only', () => {
    it('leaves a reserved slot exactly where it is', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      const rule = await addRule(app, user, listingId, {
        startTime: '09:00',
        endTime: '17:00',
        slotDurationMinutes: 120,
      });
      // 15:00 Malé tomorrow — inside the current window, outside the shorter one.
      const target = pickOne(
        await ownSlots(app, user, listingId),
        (s) => s.startsAt === '2026-09-15T10:00:00.000Z',
        'a slot at 15:00 Malé tomorrow',
      );
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: target.id, kind: 'firm' }),
      );

      // Shorten the working day so that time is no longer produced at all.
      const edited = await app.inject({
        method: 'PUT',
        url: `${availabilityBase(listingId)}/rules/${rule.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: {
          weekdays: [1, 2, 3, 4],
          startTime: '09:00',
          endTime: '13:00',
          slotDurationMinutes: 120,
        },
      });
      expect(edited.statusCode).toBe(200);

      // §Phase 9a: "reserved slots are never touched by a rule change", and
      // `Availability.dc.html`'s save sheet promises it in so many words —
      // "Times someone has already booked stay exactly as they are."
      const survivor = await app.deps.prisma.timeSlot.findUnique({ where: { id: target.id } });
      expect(survivor?.status).toBe('reserved');
      // Its unbooked neighbour at 15:00 on another day is gone.
      const after = await ownSlots(app, user, listingId);
      expect(after.map((s) => s.startsAt)).not.toContain('2026-09-16T10:00:00.000Z');
    });

    it('keeps an individual block the new rule still produces, and drops one it does not', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      const rule = await addRule(app, user, listingId, {
        startTime: '09:00',
        endTime: '17:00',
        slotDurationMinutes: 120,
      });
      const slots = await ownSlots(app, user, listingId);
      const kept = pickOne(slots, (s) => s.startsAt === '2026-09-15T04:00:00.000Z', '09:00 Malé');
      const dropped = pickOne(
        slots,
        (s) => s.startsAt === '2026-09-15T10:00:00.000Z',
        '15:00 Malé',
      );

      for (const slot of [kept, dropped]) {
        const res = await app.inject({
          method: 'POST',
          url: `/v1/providers/me/slots/${slot.id}/block`,
          headers: user.headers,
          remoteAddress: freshIp(),
        });
        expect(res.statusCode).toBe(200);
      }

      await app.inject({
        method: 'PUT',
        url: `${availabilityBase(listingId)}/rules/${rule.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: {
          weekdays: [1, 2, 3, 4],
          startTime: '09:00',
          endTime: '13:00',
          slotDurationMinutes: 120,
        },
      });

      // Still produced by the shortened rule, so the override outlives the edit.
      expect((await app.deps.prisma.timeSlot.findUnique({ where: { id: kept.id } }))?.status).toBe(
        'blocked',
      );
      // No longer produced, so it goes with every other unreserved future slot.
      expect(await app.deps.prisma.timeSlot.findUnique({ where: { id: dropped.id } })).toBeNull();
    });

    it('never touches a slot in the past', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      const rule = await addRule(app, user, listingId);
      const firstToday = firstOf(await ownSlots(app, user, listingId), 'generated slot');
      expect(firstToday.startsAt).toBe('2026-09-14T04:00:00.000Z');

      // Walk past it, then change the rule so that time is no longer produced.
      clock.set(new Date('2026-09-14T12:00:00Z'));
      await app.inject({
        method: 'PUT',
        url: `${availabilityBase(listingId)}/rules/${rule.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: {
          weekdays: [1, 2, 3, 4],
          startTime: '14:00',
          endTime: '18:00',
          slotDurationMinutes: 120,
        },
      });

      // History is not the generator's business: the slot stays, and it is
      // simply never offered again because the picker filters on `now`.
      const past = await app.deps.prisma.timeSlot.findUnique({ where: { id: firstToday.id } });
      expect(past).not.toBeNull();
      expect((await openSlots(app, listingId)).slots.map((s) => s.id)).not.toContain(firstToday.id);
    });
  });

  describe('rules a provider cannot write', () => {
    const cases: { name: string; payload: Record<string, unknown>; code: string }[] = [
      {
        name: 'a window that ends before it starts',
        payload: { weekdays: [1], startTime: '17:00', endTime: '09:00', slotDurationMinutes: 60 },
        code: 'WINDOW_ENDS_BEFORE_IT_STARTS',
      },
      {
        name: 'a visit longer than the window, which would publish nothing',
        payload: { weekdays: [1], startTime: '09:00', endTime: '11:00', slotDurationMinutes: 240 },
        code: 'VISIT_LONGER_THAN_WINDOW',
      },
    ];

    for (const testCase of cases) {
      it(`refuses ${testCase.name}, naming the rule`, async () => {
        const { user, listingId } = await providerWithSlotListing(app);
        const res = await app.inject({
          method: 'POST',
          url: `${availabilityBase(listingId)}/rules`,
          headers: user.headers,
          remoteAddress: freshIp(),
          payload: testCase.payload,
        });
        expect(res.statusCode).toBe(422);
        expect(res.json<{ error: { code: string } }>().error.code).toBe(testCase.code);
      });
    }

    it('refuses a second rule overlapping the first on the same weekday', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId, {
        weekdays: [1, 2],
        startTime: '09:00',
        endTime: '13:00',
      });

      const clash = await app.inject({
        method: 'POST',
        url: `${availabilityBase(listingId)}/rules`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: {
          weekdays: [2, 3],
          startTime: '12:00',
          endTime: '16:00',
          slotDurationMinutes: 120,
        },
      });
      expect(clash.statusCode).toBe(422);
      expect(clash.json<{ error: { code: string } }>().error.code).toBe('RULE_HOURS_OVERLAP');

      // A different weekday, same hours, is fine — nothing overlaps.
      const fine = await app.inject({
        method: 'POST',
        url: `${availabilityBase(listingId)}/rules`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: { weekdays: [4], startTime: '12:00', endTime: '16:00', slotDurationMinutes: 120 },
      });
      expect(fine.statusCode).toBe(201);
    });

    it('refuses a second exception covering the same dates', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const body = {
        name: 'Ramadan hours',
        startDate: '2026-09-20',
        endDate: '2026-10-20',
        startTime: '09:00',
        endTime: '13:00',
      };
      const first = await app.inject({
        method: 'POST',
        url: `${availabilityBase(listingId)}/exceptions`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: body,
      });
      expect(first.statusCode).toBe(201);

      const second = await app.inject({
        method: 'POST',
        url: `${availabilityBase(listingId)}/exceptions`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: { ...body, name: 'Also Ramadan', startDate: '2026-10-01', endDate: '2026-11-01' },
      });
      expect(second.statusCode).toBe(422);
      expect(second.json<{ error: { code: string } }>().error.code).toBe('EXCEPTION_DATES_OVERLAP');
    });

    it('refuses availability on a request-based listing, because it has no published times', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const plumbing = await completeDraft(app, user.headers, { categoryName: 'Plumbing' });

      const res = await app.inject({
        method: 'POST',
        url: `${availabilityBase(plumbing.id)}/rules`,
        headers: user.headers,
        remoteAddress: freshIp(),
        payload: { weekdays: [1], startTime: '09:00', endTime: '17:00', slotDurationMinutes: 120 },
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('LISTING_NOT_SLOT_BASED');
    });
  });

  describe('authorization', () => {
    it('answers not-found for another provider’s listing, on reads as well as writes', async () => {
      const owner = await providerWithSlotListing(app);
      await addRule(app, owner.user, owner.listingId);
      const stranger = await registerUser(app, { role: 'provider' });
      await completeDraft(app, stranger.headers, {}); // so they have a profile

      for (const request of [
        { method: 'GET' as const, url: availabilityBase(owner.listingId) },
        { method: 'GET' as const, url: `/v1/providers/me/listings/${owner.listingId}/slots` },
      ]) {
        const res = await app.inject({
          ...request,
          headers: stranger.headers,
          remoteAddress: freshIp(),
        });
        // Not-found rather than forbidden: an id must not be usable to
        // discover which listings are real.
        expect(res.statusCode).toBe(404);
      }

      const write = await app.inject({
        method: 'POST',
        url: `${availabilityBase(owner.listingId)}/rules`,
        headers: stranger.headers,
        remoteAddress: freshIp(),
        payload: { weekdays: [1], startTime: '09:00', endTime: '17:00', slotDurationMinutes: 120 },
      });
      expect(write.statusCode).toBe(404);
    });

    it('refuses to block another provider’s slot', async () => {
      const owner = await providerWithSlotListing(app);
      await addRule(app, owner.user, owner.listingId);
      const slot = firstOf(await ownSlots(app, owner.user, owner.listingId), 'generated slot');
      const stranger = await registerUser(app, { role: 'provider' });

      const res = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/slots/${slot.id}/block`,
        headers: stranger.headers,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });

    it('requires authentication for every provider route', async () => {
      const { listingId } = await providerWithSlotListing(app);
      const res = await app.inject({
        method: 'GET',
        url: availabilityBase(listingId),
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(401);
    });
  });

  describe('the customer picker', () => {
    it('is open to a guest, with no headers at all', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const res = await app.inject({
        method: 'GET',
        url: `/v1/listings/${listingId}/slots`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(200);
    });

    it('answers not-found for a listing that is not published', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, user.headers, {});
      const res = await app.inject({
        method: 'GET',
        url: `/v1/listings/${draft.id}/slots`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });

    it('answers not-found once the provider is suspended — through §1a’s one shared helper', async () => {
      const { user, listingId, providerProfileId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      expect((await openSlots(app, listingId)).slots.length).toBeGreaterThan(0);

      await app.deps.prisma.providerProfile.update({
        where: { id: providerProfileId },
        data: { suspendedAt: clock.clock(), suspendedReason: 'test' },
      });

      const res = await app.inject({
        method: 'GET',
        url: `/v1/listings/${listingId}/slots`,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });

    it('reports the category’s own lead time rather than a hardcoded one', async () => {
      const cleaning = await providerWithSlotListing(app, { categoryName: 'Cleaning' });
      await addRule(app, cleaning.user, cleaning.listingId);
      expect((await openSlots(app, cleaning.listingId)).minimumLeadTimeMinutes).toBe(180);

      const beauty = await providerWithSlotListing(app, { categoryName: 'Beauty' });
      await addRule(app, beauty.user, beauty.listingId);
      // Seeded at 120 for Beauty, 180 for Cleaning (§Phase 4, Round 14) — and
      // admin-editable from §Phase 10b, which is why it is read, not assumed.
      expect((await openSlots(app, beauty.listingId)).minimumLeadTimeMinutes).toBe(120);
    });
  });

  describe('the scheduled generator', () => {
    /// 🔧 Puts this test's listing at the front of the work list (2026-09-24).
    ///
    /// `findGenerationCandidates` is `nextGenerationAt <= now`, ordered ascending,
    /// with a `take` — a batch bound for the job, not part of the rule being
    /// tested. The suite shares one database and never truncates, so once more
    /// than fifty listings are due at the same instant, a test's own listing
    /// falls off the first page and the job never reaches it. That is what turned
    /// this file red when §Phase 17.2 added one more slot-mode fixture, and it
    /// would have happened again to whoever added the next one.
    ///
    /// Back-dating by an hour keeps the row *due* — which is the property under
    /// test — while making it strictly earlier than every sibling parked at the
    /// same midnight, so the ordering guarantees it is on the first page no
    /// matter how many others accumulate.
    const beFirstInLine = (listingId: string) =>
      app.deps.prisma.listingSlotState.update({
        where: { listingId },
        data: { nextGenerationAt: new Date('2026-09-14T18:00:00.000Z') },
      });

    it('reads only listings that have something to do', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);

      // Inline generation already ran inside the rule's own transaction, so
      // the listing is parked at the next Maldives midnight and is not a
      // candidate now.
      const parked = await app.deps.prisma.listingSlotState.findUniqueOrThrow({
        where: { listingId },
      });
      expect(parked.nextGenerationAt?.toISOString()).toBe('2026-09-14T19:00:00.000Z');
      // Asserted against the row, not against absence from a page: a listing
      // pushed off the first page by unrelated fixtures is also "not in the
      // list", so the page form of this passes whether the rule works or not.
      // `?? 0` rather than a non-null assertion: a null would land at zero and
      // fail this, which is the right answer for a row that is not parked.
      expect(parked.nextGenerationAt?.getTime() ?? 0).toBeGreaterThan(clock.clock().getTime());

      // Once the horizon has moved on, it is a candidate.
      await beFirstInLine(listingId);
      clock.set(new Date('2026-09-15T00:00:00Z'));
      const due = await app.availability.repo.findGenerationCandidates(clock.clock(), 50);
      expect(due.map((c) => c.listingId)).toContain(listingId);
    });

    it('extends the horizon by a day when it runs, and parks itself again', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId, { weekdays: [1, 2, 3, 4, 5, 6, 7] });
      expect((await readAvailability(app, user, listingId)).horizonDate).toBe('2026-11-12');

      await beFirstInLine(listingId);
      clock.set(new Date('2026-09-15T00:00:00Z')); // 05:00 Malé, the next day
      expect(await app.jobs.runOnce(SLOT_GENERATION_JOB_NAME, clock.clock())).toBe('ran');

      const moved = await readAvailability(app, user, listingId);
      expect(moved.horizonDate).toBe('2026-11-13');
      const state = await app.deps.prisma.listingSlotState.findUniqueOrThrow({
        where: { listingId },
      });
      expect(state.nextGenerationAt?.toISOString()).toBe('2026-09-15T19:00:00.000Z');
      expect(state.lastRunMs).not.toBeNull();
    });

    it('picks up a time-off change across every listing the provider publishes', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      await addTimeOff(app, user, { startDate: '2026-09-17', endDate: '2026-09-17' });

      // Provider-wide, and applied at once rather than waiting for a sweep —
      // §Phase 9a's "incremental and per-provider".
      const after = await ownSlots(app, user, listingId);
      expect(after.some((s) => maldivesDateOf(new Date(s.startsAt)) === '2026-09-17')).toBe(false);
    });
  });

  describe('a soft-deleted listing (ledger P8-2)', () => {
    it('stops offering future unreserved times, keeps reserved ones, and is never refused', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);
      const booked = firstOf((await openSlots(app, listingId)).slots, 'offered slot');
      await app.deps.prisma.$transaction((tx) =>
        app.reservations.reserveSlot(tx, { slotId: booked.id, kind: 'firm' }),
      );

      // §Phase 8's cascade table: deletion is the provider's to make, and it
      // must not be blocked because somebody has a booking.
      const deleted = await app.inject({
        method: 'DELETE',
        url: `/v1/providers/me/listings/${listingId}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(deleted.statusCode).toBe(200);

      // The picker cannot reach it at all any more.
      const picker = await app.inject({
        method: 'GET',
        url: `/v1/listings/${listingId}/slots`,
        remoteAddress: freshIp(),
      });
      expect(picker.statusCode).toBe(404);

      // And the next generation withdraws the unreserved future times while
      // leaving the appointment alone — "the reservation is somebody's
      // appointment".
      await app.availability.repo.markForGeneration(
        listingId,
        (await app.deps.prisma.listing.findUniqueOrThrow({ where: { id: listingId } }))
          .providerProfileId,
        clock.clock(),
      );
      expect(await app.jobs.runOnce(SLOT_GENERATION_JOB_NAME, clock.clock())).toBe('ran');

      const survivors = await app.deps.prisma.timeSlot.findMany({
        where: { listingId, startsAt: { gt: clock.clock() } },
      });
      expect(survivors).toHaveLength(1);
      expect(survivors[0]?.id).toBe(booked.id);
      expect(survivors[0]?.status).toBe('reserved');
    });
  });

  describe('the rule editor’s defaults', () => {
    it('opens with the wizard’s own step-5 window rather than empty', async () => {
      const { user, listingId } = await providerWithSlotListing(app);
      // §Phase 9's step 5 collects this simple window. It is not the pattern —
      // its own helper says so — but it is what the provider already told us,
      // and the editor should not ask twice.
      const patched = await patchDraft(app, user.headers, listingId, {
        workingDays: [6, 7],
        workingHoursFrom: '08:00',
        workingHoursTo: '12:00',
      });
      expect(patched.statusCode).toBe(200);

      const res = await app.inject({
        method: 'GET',
        url: `${availabilityBase(listingId)}/rule-defaults`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(res.json<{ data: Record<string, unknown> }>().data).toEqual({
        weekdays: [6, 7],
        startTime: '08:00',
        endTime: '12:00',
        slotDurationMinutes: 120,
      });
    });
  });

  /**
   * §Phase 9a takes an explicit exception to invariant 8 — a future,
   * unreserved `TimeSlot` is removed rather than stamped, because a slot is
   * the expansion of a rule and not a record of anything. The exception is
   * only defensible while it stays inside those two bounds, so the bounds are
   * asserted against the repository directly, with ids the callers would
   * never pass. A guard that lives only in the caller is a guard the next
   * caller has to remember.
   */
  describe('the one deletion in this codebase, and what it refuses', () => {
    it('refuses a past slot and a reserved one, and takes the future unreserved one beside them', async () => {
      const { user, listingId, providerProfileId } = await providerWithSlotListing(app);
      await addRule(app, user, listingId);

      const prisma = app.deps.prisma;
      const future = firstOf(await ownSlots(app, user, listingId), 'a generated slot');

      // A slot in the past, and a reserved one — neither reachable through
      // the rules, both reachable by id.
      const past = await prisma.timeSlot.create({
        data: {
          providerProfileId,
          listingId,
          startsAt: new Date(START.getTime() - 48 * 60 * 60 * 1000),
          endsAt: new Date(START.getTime() - 46 * 60 * 60 * 1000),
          status: 'open',
        },
      });
      const held = await prisma.timeSlot.create({
        data: {
          providerProfileId,
          listingId,
          startsAt: new Date(START.getTime() + 96 * 60 * 60 * 1000),
          endsAt: new Date(START.getTime() + 98 * 60 * 60 * 1000),
          status: 'reserved',
        },
      });

      const { count } = await app.availability.repo.deleteSlots(
        [past.id, held.id, future.id],
        START,
      );

      expect(count).toBe(1);
      expect(await prisma.timeSlot.findUnique({ where: { id: past.id } })).not.toBeNull();
      expect(await prisma.timeSlot.findUnique({ where: { id: held.id } })).not.toBeNull();
      expect(await prisma.timeSlot.findUnique({ where: { id: future.id } })).toBeNull();
    });
  });
});
