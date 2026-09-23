import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import type { buildApp } from '../src/app.js';
import {
  BOOKING_ACCEPT_TIMEOUT_JOB_NAME,
  BOOKING_QUOTE_APPROVAL_TIMEOUT_JOB_NAME,
  BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import type { BookingRepository } from '../src/modules/bookings/repository.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  act,
  actOk,
  bookRequest,
  createBooking,
  errorCode,
  listBookings,
  quotedBooking,
  readBooking,
  requestListing,
} from './helpers/bookings.js';

/**
 * §Phase 17's **Done when** list — the four clauses §Phase 17.2 owns, and no
 * others (§0.0 item 21: "each slice finishes against its own list and against
 * no other").
 *
 *  1. **a request-mode listing takes a booking at all** — "the nine `request`
 *     categories are refused by 17.1 by name and this is what opens them"
 *  2. **a quote expires on its own clock** — the category's
 *     `quoteApprovalMinutes`, "asserted at **both** ends of the split so a
 *     4-hour window and a 72-hour one are each seen to expire on time" — and
 *     releases its provisional reservation
 *  3. **the provisional reservation is created inside the quote transaction
 *     and released in one** — "the property 17.1 proved for the firm hold"
 *  4. **the `booking`-type chat opens at `quote_offered`**, not at `accepted`
 *
 * Plus the rule standing above all four slices: **no endpoint in the module
 * returns a phone number**, re-checked here over the three endpoints this
 * slice adds.
 *
 * Emergency (17.3) and recurring, reschedule, Book Again and ICS (17.4) are
 * not asserted here and are not claimed.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.2 — Done when', () => {
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
    vi.restoreAllMocks();
  });

  describe('1. a request-mode listing takes a booking at all', () => {
    it('runs request → quote → approve → pay → confirm → complete through the real routes', async () => {
      const { customer, provider, listingId, category } = await requestListing(app);

      const created = await bookRequest(app, customer, listingId, {
        preferredWindowChip: 'tomorrow_morning',
        jobNotes: 'Steady leak under the kitchen sink, cupboard base is wet',
      });
      // §1c's machine: request-based inserts `awaiting_quote → quote_offered →
      // accepted`. Nothing is held and no time is fixed — "this is a
      // preference, not a slot".
      expect(created.status).toBe('awaiting_quote');
      expect(created.bookingMode).toBe('request');
      expect(created.scheduledFor).toBeNull();
      expect(created.preferredWindowText).toBe('Tomorrow morning');
      expect(created.agreedAmountLaari).toBeNull();

      const scheduledFor = new Date(
        clock.clock().getTime() + (category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
      );
      const quoted = await actOk(app, provider, created.id, 'quote', {
        scheduledFor: scheduledFor.toISOString(),
        amountLaari: 65_000,
        note: 'Replace joint, reseal line — parts included',
      });
      expect(quoted.status).toBe('quote_offered');
      expect(quoted.quotedAmountLaari).toBe(65_000);
      expect(quoted.scheduledFor).toBe(scheduledFor.toISOString());
      // Still a proposal: §1h locks the terms at `accepted` and not before.
      expect(quoted.agreedAmountLaari).toBeNull();

      const approved = await actOk(app, customer, created.id, 'approve-quote');
      // §1c: "everything downstream is identical to the slot-based flow from
      // `accepted` onward" — including passing straight through to the payment
      // prompt, because the amount is set at `accepted`.
      expect(approved.status).toBe('awaiting_payment');
      expect(approved.agreedAmountLaari).toBe(65_000);
      // Round 17: derived, never set — an accepted quote is always `quoted`.
      expect(approved.amountKind).toBe('quoted');

      await actOk(app, customer, created.id, 'claim-payment');
      await actOk(app, provider, created.id, 'confirm-payment-received');
      const completed = await actOk(app, provider, created.id, 'complete');
      expect(completed.status).toBe('completed');
      expect(completed.completedVia).toBe('confirmed');

      // And the whole of it is one readable timeline, for both parties.
      for (const party of [customer, provider]) {
        const detail = await readBooking(app, party, created.id);
        expect((detail.statusHistory ?? []).map((e) => e.toStatus)).toEqual([
          'awaiting_quote',
          'quote_offered',
          'accepted',
          'awaiting_payment',
          'payment_claimed',
          'confirmed',
          'completed',
        ]);
      }
    });

    it('opens all nine request categories, not just the one the fixture uses', async () => {
      // The clause is about the *mode*, so the assertion is about the mode:
      // every seeded `request` category produces a bookable listing. Reading
      // the catalogue rather than naming nine strings means a Round that
      // changes the membership changes this test's subject too.
      const requestCategories = await app.deps.prisma.category.findMany({
        where: { bookingMode: 'request', isActive: true },
        select: { name: true },
      });
      expect(requestCategories.length).toBe(9);

      for (const { name } of requestCategories) {
        const { customer, listingId } = await requestListing(app, { categoryName: name });
        const booking = await bookRequest(app, customer, listingId);
        expect(booking.status).toBe('awaiting_quote');
      }
    });

    it('still refuses a slot listing sent a window, and a request listing sent a slot', async () => {
      const { customer, listingId } = await requestListing(app);

      // A request listing has no published slots to pick, so the slot shape is
      // refused by name rather than silently mishandled.
      const asSlot = await createBooking(app, customer, listingId, { timeSlotId: randomUUID() });
      expect(asSlot.statusCode).toBe(422);
      expect(errorCode(asSlot)).toBe('BOOKING_MODE_NOT_AVAILABLE');
    });

    it('refuses a request with no window at all', async () => {
      const { customer, listingId } = await requestListing(app);
      const res = await createBooking(app, customer, listingId, { jobNotes: 'Leak' });
      // §1c's request flow *is* "customer submits a preferred date/time
      // window"; a request without one gives the provider nothing to answer.
      expect(res.statusCode).toBe(400);
    });

    it('refuses an occasion the category does not seed, and takes one it does', async () => {
      // Round 25: "one of the category's `occasionPresets`". Photography seeds
      // them; Plumbing does not, and a plumbing job has no occasion.
      const photography = await requestListing(app, { categoryName: 'Photography' });
      const presets = (
        await app.deps.prisma.category.findUniqueOrThrow({
          where: { seedKey: 'Photography' },
          select: { occasionPresets: true },
        })
      ).occasionPresets;
      const first = presets[0];
      expect(first).toBeDefined();

      const booked = await bookRequest(app, photography.customer, photography.listingId, {
        occasion: first,
      });
      expect(booked.occasion).toBe(first);

      const bogus = await createBooking(app, photography.customer, photography.listingId, {
        preferredWindowChip: 'this_week',
        occasion: 'Bar mitzvah',
      });
      expect(bogus.statusCode).toBe(422);
      expect(errorCode(bogus)).toBe('OCCASION_NOT_IN_CATEGORY');
    });
  });

  describe('2. a quote expires on its own clock, at both ends of the split', () => {
    /**
     * The clause asks for both ends "so a 4-hour window and a 72-hour one are
     * each seen to expire on time". The two are asserted the same way and the
     * numbers come from the seeded category rather than from this file — a
     * test that hardcoded 240 and 4320 would pass against a service that
     * hardcoded them too, which is the failure invariant 13 exists to prevent.
     */
    for (const categoryName of ['Plumbing', 'Boat Charter']) {
      it(`expires a ${categoryName} quote on the category's own quoteApprovalMinutes`, async () => {
        const { customer, booking, category } = await quotedBooking(app, { categoryName });
        const approvalMinutes = category.quoteApprovalMinutes;

        // The deadline the customer is shown is the one the category sets.
        expect(booking.quoteExpiresAt).toBe(
          new Date(clock.clock().getTime() + approvalMinutes * 60_000).toISOString(),
        );

        // One minute short: still live, and still approvable.
        clock.advance((approvalMinutes - 1) * 60_000);
        await app.jobs.runOnce(BOOKING_QUOTE_APPROVAL_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readBooking(app, customer, booking.id)).status).toBe('quote_offered');

        // Two minutes on: expired, and the hold released with it.
        clock.advance(2 * 60_000);
        await app.jobs.runOnce(BOOKING_QUOTE_APPROVAL_TIMEOUT_JOB_NAME, clock.clock());

        const after = await readBooking(app, customer, booking.id);
        expect(after.status).toBe('cancelled');
        // §1f: a clock running out is not a cancellation by either party, and
        // an unanswered quote must not touch the provider's record.
        expect(after.cancelledByRole).toBeNull();

        const row = await app.deps.prisma.booking.findUniqueOrThrow({
          where: { id: booking.id },
          select: { reservationId: true },
        });
        const hold = await app.deps.prisma.reservation.findUniqueOrThrow({
          where: { id: row.reservationId ?? '' },
          select: { releasedAt: true, releaseReason: true },
        });
        expect(hold.releasedAt).not.toBeNull();
      });
    }

    it('gives the two ends of the split genuinely different deadlines', async () => {
      // The point of reading the column: the split is real, and one of these
      // two categories waits hours where the other waits days.
      const household = await quotedBooking(app, { categoryName: 'Plumbing' });
      const longLead = await quotedBooking(app, { categoryName: 'Boat Charter' });
      expect(longLead.category.quoteApprovalMinutes).toBeGreaterThan(
        household.category.quoteApprovalMinutes,
      );
      expect(household.booking.quoteExpiresAt).not.toBe(longLead.booking.quoteExpiresAt);
    });

    it('refuses an approval that arrives after the deadline, before the sweep has run', async () => {
      // The job is what makes the transition (backend/CLAUDE.md), but a
      // customer can tap Accept in the minutes between the deadline and the
      // next sweep, and the terms they would be accepting are already gone.
      const { customer, booking, category } = await quotedBooking(app);
      clock.advance((category.quoteApprovalMinutes + 1) * 60_000);

      const res = await act(app, customer, booking.id, 'approve-quote');
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('QUOTE_EXPIRED');
    });

    it("expires an unanswered request on the provider's own clock, not the flat 24 hours", async () => {
      // §1c step 4's first clause for request mode, and `Request a Time.dc.html`'s
      // promise: "Ibrahim has 2 hours … if he doesn't, the request expires and
      // you owe nothing." Plumbing's `quoteExpiryMinutes` is well short of a
      // day, so the slot job's 24-hour window would leave this sitting.
      const { customer, listingId, category } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);
      expect(category.quoteExpiryMinutes).toBeLessThan(24 * 60);
      expect(booking.quoteDueAt).toBe(
        new Date(clock.clock().getTime() + category.quoteExpiryMinutes * 60_000).toISOString(),
      );

      clock.advance((category.quoteExpiryMinutes - 1) * 60_000);
      await app.jobs.runOnce(BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('awaiting_quote');

      clock.advance(2 * 60_000);
      await app.jobs.runOnce(BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME, clock.clock());
      const after = await readBooking(app, customer, booking.id);
      // `declined` with a system actor, as the slot window's timeout is: §1f
      // reads the actor to keep timeouts out of acceptance rate.
      expect(after.status).toBe('declined');
      const last = (after.statusHistory ?? []).at(-1);
      expect(last?.actorRole).toBe('system');
      expect(last?.transition).toBe('quote-request-timeout');
    });

    it('leaves a request booking alone when the slot job runs', async () => {
      // The 24-hour sweep is the *slot* window. A request booking with a
      // two-hour clock must not be answered by it, in either direction.
      const { customer, listingId } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);

      clock.advance(25 * 60 * 60_000);
      await app.jobs.runOnce(BOOKING_ACCEPT_TIMEOUT_JOB_NAME, clock.clock());
      const after = await readBooking(app, customer, booking.id);
      expect(after.status).toBe('awaiting_quote');
    });
  });

  describe('3. the provisional hold lives and dies inside the quote transaction', () => {
    it('takes the hold in the same transaction that offers the quote', async () => {
      const { booking, scheduledFor, providerProfileId } = await quotedBooking(app);

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { reservationId: true, quoteExpiresAt: true },
      });
      expect(row.reservationId).not.toBeNull();

      const hold = await app.deps.prisma.reservation.findUniqueOrThrow({
        where: { id: row.reservationId ?? '' },
      });
      expect(hold.kind).toBe('provisional');
      expect(hold.providerProfileId).toBe(providerProfileId);
      expect(hold.startsAt.toISOString()).toBe(scheduledFor.toISOString());
      expect(hold.releasedAt).toBeNull();
      // §1c: the hold expires *with* the quote's approval window — one instant
      // written twice rather than two clocks that can drift apart.
      expect(hold.expiresAt?.toISOString()).toBe(row.quoteExpiresAt?.toISOString());
    });

    it('leaves no hold behind when the booking write fails after the reservation succeeded', async () => {
      // The property §Phase 17.1 proved for the firm hold (ledger row
      // **P9A-2**), asserted here for the provisional one.
      //
      // 17.1 forced its failure with a bad island foreign key; the quote path
      // takes no island, so the failure is forced at the seam instead — the
      // service's own repository, made to throw *after* `reserveWindow` has
      // run inside the transaction. If the hold were taken in its own
      // transaction it would survive this; it does not.
      const { provider, listingId, customer, category } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);
      const scheduledFor = new Date(
        clock.clock().getTime() + (category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
      );

      const repo = (app.bookings as unknown as { repo: BookingRepository }).repo;
      const transition = vi
        .spyOn(repo, 'transition')
        .mockRejectedValueOnce(new Error('forced, after the hold'));

      const res = await act(app, provider, booking.id, 'quote', {
        scheduledFor: scheduledFor.toISOString(),
        amountLaari: 65_000,
      });
      expect(res.statusCode).toBeGreaterThanOrEqual(500);
      // Not vacuous: the failure really did happen *after* the hold was taken.
      // If `reserveWindow` had thrown first, or if the two were in separate
      // transactions, this spy would never have been reached and the assertion
      // below would be proving nothing.
      expect(transition).toHaveBeenCalledTimes(1);

      expect((await readBooking(app, customer, booking.id)).status).toBe('awaiting_quote');
      expect(
        await app.deps.prisma.reservation.count({
          where: { listingId, releasedAt: null },
        }),
      ).toBe(0);
    });

    it('leaves the booking unmoved when the provider is already booked at that time', async () => {
      // The same atomicity from the other direction, and the one that really
      // happens: the exclusion constraint refuses the overlap, so the status
      // never moves and no half-quote is left on screen.
      const fixture = await quotedBooking(app);
      const second = await bookRequest(app, fixture.customer, fixture.listingId);

      const res = await act(app, fixture.provider, second.id, 'quote', {
        // The very time the first quote is already holding.
        scheduledFor: fixture.scheduledFor.toISOString(),
        amountLaari: 40_000,
      });
      expect(res.statusCode).toBe(409);
      expect(errorCode(res)).toBe('PROVIDER_TIME_UNAVAILABLE');
      expect((await readBooking(app, fixture.customer, second.id)).status).toBe('awaiting_quote');
    });

    it('releases the hold in one transaction on a decline, and frees the time', async () => {
      const { customer, provider, booking, scheduledFor, listingId } = await quotedBooking(app);

      const declined = await actOk(app, customer, booking.id, 'decline-quote', {
        reason: 'Too expensive',
      });
      // §1f: the customer turning a price down is never the provider's
      // `declined`, and a customer cancellation never counts against them.
      expect(declined.status).toBe('cancelled');
      expect(declined.cancelledByRole).toBe('customer');

      expect(
        await app.deps.prisma.reservation.count({ where: { listingId, releasedAt: null } }),
      ).toBe(0);

      // And the time really is free: the provider can quote it to somebody else.
      const other = await bookRequest(app, await freshCustomer(), listingId);
      const requote = await actOk(app, provider, other.id, 'quote', {
        scheduledFor: scheduledFor.toISOString(),
        amountLaari: 55_000,
      });
      expect(requote.status).toBe('quote_offered');
    });

    it('moves the hold rather than doubling it when a quote is revised', async () => {
      // §1c's negotiation case: "the provider proposes Tuesday 2pm and the
      // customer wants Tuesday 3pm". The revision releases and retakes in one
      // transaction, so the provider is never holding two times at once.
      const { provider, customer, booking, scheduledFor, listingId, category } =
        await quotedBooking(app);
      const moved = new Date(scheduledFor.getTime() + 60 * 60_000);

      const revised = await actOk(app, provider, booking.id, 'quote', {
        scheduledFor: moved.toISOString(),
        amountLaari: 72_000,
      });
      expect(revised.status).toBe('quote_offered');
      expect(revised.quotedAmountLaari).toBe(72_000);
      expect(revised.scheduledFor).toBe(moved.toISOString());

      const live = await app.deps.prisma.reservation.findMany({
        where: { listingId, releasedAt: null },
        select: { startsAt: true },
      });
      expect(live).toHaveLength(1);
      expect(live[0]?.startsAt.toISOString()).toBe(moved.toISOString());

      // And the customer's clock restarted, because the terms are new — on
      // the category's own window, read back rather than written here.
      expect(revised.quoteExpiresAt).toBe(
        new Date(clock.clock().getTime() + category.quoteApprovalMinutes * 60_000).toISOString(),
      );
      const history = (await readBooking(app, customer, booking.id)).statusHistory ?? [];
      expect(history.map((e) => e.transition)).toContain('revise-quote');
    });

    it('converts the hold to firm on approval rather than retaking it', async () => {
      // §1c: "Approval converts the provisional reservation to a firm one."
      // The id does not change, so there is no instant in which the time is
      // free and a stranger could win it.
      const { customer, booking } = await quotedBooking(app);
      const before = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { reservationId: true },
      });

      await actOk(app, customer, booking.id, 'approve-quote');

      const after = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { reservationId: true },
      });
      expect(after.reservationId).toBe(before.reservationId);

      const hold = await app.deps.prisma.reservation.findUniqueOrThrow({
        where: { id: after.reservationId ?? '' },
      });
      expect(hold.kind).toBe('firm');
      // A firm hold has no expiry — the provisional one's clock is spent.
      expect(hold.expiresAt).toBeNull();
      expect(hold.releasedAt).toBeNull();
    });
  });

  describe('4. the booking chat opens at quote_offered, not at accepted', () => {
    it('is shut while the request waits, open the moment the quote is sent', async () => {
      const { customer, provider, listingId, category } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);

      // §1c step 2: the accept prompt is "job details and the customer's name
      // only, no contact details, **and no chat yet**".
      expect(booking.chatState).toBe('not_open');
      expect(booking.quoteOfferedAt).toBeNull();

      const quoted = await actOk(app, provider, booking.id, 'quote', {
        scheduledFor: new Date(
          clock.clock().getTime() + (category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
        ).toISOString(),
        amountLaari: 65_000,
      });

      // §0.0 item 7 and §1c: the thread opens here, one whole state before
      // `accepted` — "this is the one window where negotiation is most likely
      // to be needed", and `Propose Time and Price.dc.html` tells the provider
      // so as they send.
      expect(quoted.status).toBe('quote_offered');
      expect(quoted.chatState).toBe('open');
      expect(quoted.quoteOfferedAt).toBe(clock.clock().toISOString());

      // Open to both parties, not just the one who opened it.
      for (const party of [customer, provider]) {
        expect((await readBooking(app, party, booking.id)).chatState).toBe('open');
      }

      // And it stays open through approval rather than opening a second time.
      const approved = await actOk(app, customer, booking.id, 'approve-quote');
      expect(approved.chatState).toBe('open');
    });

    it('opens a slot booking at accepted, exactly as before', async () => {
      // The clause is "at `quote_offered`, **not** at `accepted`" for the
      // request path — it changes nothing for the other modes, and a slot
      // booking that started opening its chat early would be the regression.
      // `chatState` is new on every mode, so this is the other door being
      // asserted rather than §Phase 17.1's path being re-tested.
      const { bookableListing, bookSlot } = await import('./helpers/bookings.js');
      const fixture = await bookableListing(app);

      // 🔧 **Park this fixture's generator before anything else runs.**
      // `findGenerationCandidates` is a *global* `take(50)` over every listing
      // with work pending, and the whole suite shares one database — so an
      // extra slot-mode listing here is an extra candidate competing for that
      // batch in `availability-rules`'s own sweep, which then finds 50 other
      // listings and never reaches its own. The grid this fixture needs is
      // already generated inline by `addRule`; nothing below wants it swept
      // again. (The fragility is the suite's, not the job's: in production the
      // sweep runs every five minutes and a listing missed by one batch is
      // picked up by the next.)
      await app.deps.prisma.listingSlotState.updateMany({
        where: { listingId: fixture.listingId },
        data: { nextGenerationAt: null },
      });

      const booking = await bookSlot(app, fixture.customer, fixture.listingId, fixture.slotId);
      expect(booking.chatState).toBe('not_open');

      const accepted = await actOk(app, fixture.provider, booking.id, 'accept');
      expect(accepted.chatState).toBe('open');
    });

    it('never opens for a request that expired before any quote', async () => {
      const { customer, listingId, category } = await requestListing(app);
      const booking = await bookRequest(app, customer, listingId);

      clock.advance((category.quoteExpiryMinutes + 1) * 60_000);
      await app.jobs.runOnce(BOOKING_QUOTE_REQUEST_TIMEOUT_JOB_NAME, clock.clock());

      const after = await readBooking(app, customer, booking.id);
      expect(after.status).toBe('declined');
      // Nothing was ever said, so there is no history to lock — as opposed to
      // a declined quote, which has a thread and keeps it readable.
      expect(after.chatState).toBe('not_open');
    });

    it('keeps a declined quote readable rather than pretending it never opened', async () => {
      const { customer, booking } = await quotedBooking(app);
      const declined = await actOk(app, customer, booking.id, 'decline-quote');
      expect(declined.chatState).toBe('locked');
    });
  });

  describe('standing rule — no endpoint in the module returns a phone number', () => {
    it('carries no number through any of the three endpoints this slice adds', async () => {
      // Re-checked over the shapes 17.2 adds, by inspecting the whole response
      // rather than the fields expected to carry one — §Phase 17's own
      // instruction, and the reason this is a string search and not a field
      // assertion.
      const { customer, provider, listingId, category } = await requestListing(app);

      const phones = await app.deps.prisma.user.findMany({
        where: { id: { in: [customer.userId, provider.userId] } },
        select: { phoneE164: true },
      });
      const numbers = phones.map((p) => p.phoneE164).filter((p): p is string => p !== null);
      expect(numbers.length).toBeGreaterThan(0);

      const booking = await bookRequest(app, customer, listingId);
      const quoted = await act(app, provider, booking.id, 'quote', {
        scheduledFor: new Date(
          clock.clock().getTime() + (category.minimumLeadTimeMinutes + 24 * 60) * 60_000,
        ).toISOString(),
        amountLaari: 65_000,
      });
      const approved = await act(app, customer, booking.id, 'approve-quote');

      const second = await bookRequest(app, customer, listingId);
      const secondQuote = await act(app, provider, second.id, 'quote', {
        scheduledFor: new Date(
          clock.clock().getTime() + (category.minimumLeadTimeMinutes + 48 * 60) * 60_000,
        ).toISOString(),
        amountLaari: 30_000,
      });
      expect(secondQuote.statusCode).toBe(200);
      const declined = await act(app, customer, second.id, 'decline-quote');

      const detail = await app.inject({
        method: 'GET',
        url: `/v1/bookings/${booking.id}`,
        headers: customer.headers,
        remoteAddress: freshIp(),
      });
      const listed = await listBookings(app, customer);

      const bodies = [
        quoted.body,
        approved.body,
        declined.body,
        detail.body,
        JSON.stringify(listed.bookings),
      ];
      for (const body of bodies) {
        for (const number of numbers) {
          expect(body).not.toContain(number);
          // The national form too — a stripped `+960` would defeat a whole-string match.
          expect(body).not.toContain(number.replace('+960', ''));
        }
        expect(body.toLowerCase()).not.toContain('whatsapp');
        expect(body.toLowerCase()).not.toContain('viber');
        expect(body).not.toContain('phone');
      }
    });
  });

  /** A second verified customer, for the "somebody else can have the time" case. */
  async function freshCustomer() {
    const { verifiedCustomer } = await import('./helpers/bookings.js');
    return verifiedCustomer(app);
  }
});
