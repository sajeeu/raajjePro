import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import type { buildApp } from '../src/app.js';
import {
  BOOKING_COMPLETION_TIMEOUT_JOB_NAME,
  EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME,
  EMERGENCY_WINDOW_TIMEOUT_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import type { Island } from '../src/generated/prisma/client.js';
import type {
  BookingNotificationEvent,
  BookingNotifier,
} from '../src/modules/bookings/notifications.js';
import type { BookingRepository } from '../src/modules/bookings/repository.js';
import type {
  BookingDto,
  ContactRevealDto,
  EmergencyBroadcastDto,
} from '../src/modules/bookings/types.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  act,
  actOk,
  bookSlot,
  bookableListing,
  createBooking,
  emergencyProvider,
  errorCode,
  listBookings,
  offerOn,
  raiseEmergency,
  randomIsland,
  readBooking,
  requestListing,
  revealContact,
  verifiedCustomer,
} from './helpers/bookings.js';
import { categoryByName, completeDraft, jpeg, publish, uploadPathOf } from './helpers/listings.js';
import { registerUser, type RegisteredUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/** Every event the booking module fired, so "the counterparty is notified" is something a test can see. */
class RecordingNotifier implements BookingNotifier {
  readonly events: BookingNotificationEvent[] = [];
  notify(event: BookingNotificationEvent): Promise<void> {
    this.events.push(event);
    return Promise.resolve();
  }
  for(bookingId: string, event: string): BookingNotificationEvent[] {
    return this.events.filter((e) => e.bookingId === bookingId && e.event === event);
  }
}

/**
 * §Phase 17's **17.3 — Done when** — every clause, and no clause of another
 * slice (§0.0 item 21). Numbered in the order the plan lists them:
 *
 *  1. the reveal rejects a non-emergency booking, a `requested`-state booking
 *     and a provider-initiated call, reveals both numbers or neither, and
 *     returns nothing 24 hours after the booking goes terminal
 *  2. revoking a provider's verification auto-cancels their `accepted`
 *     emergency bookings but routes their `payment_claimed` ones to admin
 *  3. an emergency on an ineligible category or by an unverified provider is
 *     rejected
 *  4. the emergency rate limit triggers
 *  5. a broadcast reaches every eligible provider and nobody outside the rule
 *  6. two simultaneous accepts both produce offers, and the customer is shown both
 *  7. a collection window closes at 90 seconds and presents at most three offers
 *  8. selecting one releases the others immediately
 *  9. reject-all re-broadcasts and never returns to any provider who offered
 * 10. an unanswered set of offers expires 5 minutes after the window closes and
 *     re-broadcasts without resetting the overall window
 * 11. selecting incurs the MVR 200 dispatch fee, the job proceeds without
 *     waiting for payment, an unsettled fee blocks a new booking, and
 *     submitting proof lifts that block before any admin confirms it
 * 12. a provider marked as not arrived is released, takes a no-show, and the
 *     booking re-broadcasts without a second fee
 * 13. Electrical is refused to a silver provider and accepted from a gold one,
 *     while AC Repair accepts silver
 * 14. the request window expires at 30 minutes for Moving exactly as for
 *     Plumbing, and each offer carries the provider's arrival estimate
 * 15. an emergency job cannot be completed without a final amount
 * 16. the "did this happen" flow fires for emergency bookings too
 * 17. the emergency `requested` window auto-declines at 30 minutes, read from
 *     `emergencyAcceptWindowMinutes`
 *
 * Plus the phone rule inverted for this slice alone: absence asserted over
 * every endpoint 17.3 adds, and the one endpoint that returns a number held to
 * each of its seven conditions and its kill switch, one at a time.
 *
 * **No window in this file is a literal.** Every number the plan puts on a
 * category is read back from the seeded row; the flat ones (90 seconds, five
 * minutes, MVR 200, 3/24h and 10/7d) are §1c's own and are imported from
 * `windows.ts` where the service reads them.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.3 — Done when', () => {
  const START = new Date('2026-09-15T03:00:00Z');
  const clock = controllableClock(START);
  const notifier = new RecordingNotifier();
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: clock.clock,
      accessTokenMinutes: 60 * 24 * 60,
      sessionIdleMinutes: 60 * 24 * 60,
      deps: { bookingNotifier: notifier },
    }));
  });
  afterAll(async () => {
    await app.close();
  });
  afterEach(async () => {
    clock.set(START);
    vi.restoreAllMocks();
    await app.deps.prisma.killSwitch.updateMany({ data: { engaged: false } });
  });

  const seconds = (n: number) => n * 1000;
  const minutes = (n: number) => n * 60_000;

  /** The category's own numbers, from the seed — never restated here. */
  async function category(name: string) {
    const row = await categoryByName(app.deps.prisma, name);
    if (row.emergencyAcceptWindowMinutes === null || row.emergencyMinimumTier === null) {
      throw new Error(`${name} is not seeded as emergency-capable`);
    }
    return { ...row, windowMinutes: row.emergencyAcceptWindowMinutes };
  }

  /** A customer, an island, and an origin provider whose listing the request is raised from. */
  async function scene(categoryName = 'Plumbing', tier: 'gold' | 'silver' = 'gold') {
    const island = await randomIsland(app.deps.prisma);
    const origin = await emergencyProvider(app, { categoryName, island, tier });
    const customer = await verifiedCustomer(app);
    return { island, origin, customer };
  }

  /** One more eligible provider on the same island and category. */
  function another(island: Island, categoryName = 'Plumbing', tier: 'gold' | 'silver' = 'gold') {
    return emergencyProvider(app, { categoryName, island, tier });
  }

  /**
   * Who the broadcast for `bookingId` was sent to — §Phase 3c's own record of
   * it — in dispatch order. `since` is a count from an earlier call, so a test
   * can ask who a *later* round reached.
   */
  async function broadcastRecipients(bookingId: string, since = 0): Promise<string[]> {
    const rows = await app.deps.prisma.pushDispatch.findMany({
      where: { subjectId: bookingId, kind: 'emergency_dispatch' },
      select: { userId: true },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.slice(since).map((r) => r.userId);
  }

  async function providerView(provider: RegisteredUser, bookingId: string) {
    return app.inject({
      method: 'GET',
      url: `/v1/providers/me/emergency-requests/${bookingId}`,
      headers: provider.headers,
      remoteAddress: freshIp(),
    });
  }

  function respond(customer: RegisteredUser, bookingId: string, body: Record<string, unknown>) {
    return act(app, customer, bookingId, 'emergency-offer-response', body);
  }

  /** A request with one offer, taken past the collection window and selected — the job is on. */
  async function matched(categoryName = 'Plumbing') {
    const s = await scene(categoryName);
    const booking = await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
    expect((await offerOn(app, s.origin.provider, booking.id, 40_000, 30)).statusCode).toBe(200);
    clock.advance(seconds(90));
    const read = await readBooking(app, s.customer, booking.id);
    const offerId = read.emergency?.offers[0]?.id ?? '';
    const selected = await respond(s.customer, booking.id, { offerId });
    expect(selected.statusCode).toBe(200);
    return { ...s, booking: selected.json<Envelope<BookingDto>>().data };
  }

  // =========================================================================
  // 1. The reveal — the single endpoint in the system that returns a number
  // =========================================================================

  describe('1. reveal-contact holds every one of its seven conditions', () => {
    it('rejects a non-emergency booking', async () => {
      const { customer, listingId, slotId } = await bookableListing(app);
      const booking = await bookSlot(app, customer, listingId, slotId);
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CONTACT_REVEAL_EMERGENCY_ONLY');
      expect(res.body).not.toMatch(/\+960/);
    });

    it('rejects a requested-state emergency — a provider who has not committed gets nothing', async () => {
      const { customer, origin, island } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      expect(booking.status).toBe('requested');
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CONTACT_REVEAL_NOT_ACCEPTED');
      expect(res.body).not.toMatch(/\+960/);
    });

    it('rejects a provider-initiated call, and answers the provider once the customer has started it', async () => {
      const { customer, origin, booking } = await matched();

      const first = await revealContact(app, origin.provider, booking.id);
      expect(first.statusCode).toBe(422);
      expect(errorCode(first)).toBe('CONTACT_REVEAL_CUSTOMER_INITIATES');
      expect(first.body).not.toMatch(/\+960/);

      expect((await revealContact(app, customer, booking.id)).statusCode).toBe(200);
      const after = await revealContact(app, origin.provider, booking.id);
      expect(after.statusCode).toBe(200);
    });

    it('reveals both numbers at once — to either party, the same pair', async () => {
      const { customer, origin, booking } = await matched();
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(200);
      const body = res.json<Envelope<ContactRevealDto>>().data;

      const [c, p] = await Promise.all([
        app.deps.prisma.user.findUniqueOrThrow({ where: { id: customer.userId } }),
        app.deps.prisma.user.findUniqueOrThrow({ where: { id: origin.provider.userId } }),
      ]);
      expect(body.customer.phone).toBe(c.phoneE164);
      expect(body.provider.phone).toBe(p.phoneE164);
      // Round 11: the screen may say the number was confirmed at verification,
      // which is what the tier lets it say.
      expect(body.provider.verificationTier).toBe('gold');
      // No WhatsApp, no Viber — not even here.
      expect(res.body).not.toMatch(/whatsapp|viber/i);

      const mirror = (await revealContact(app, origin.provider, booking.id)).json<
        Envelope<ContactRevealDto>
      >().data;
      expect(mirror.customer.phone).toBe(body.customer.phone);
      expect(mirror.provider.phone).toBe(body.provider.phone);
    });

    it('reveals neither when one party has no number on file', async () => {
      const { customer, booking } = await matched();
      await app.deps.prisma.user.update({
        where: { id: customer.userId },
        data: { phoneE164: null },
      });
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CONTACT_REVEAL_UNAVAILABLE');
      // The provider's number must not come back on its own.
      expect(res.body).not.toMatch(/\+960/);
    });

    it('notifies the counterparty once, at the moment of reveal', async () => {
      const { customer, origin, booking } = await matched();
      await revealContact(app, customer, booking.id);
      await revealContact(app, customer, booking.id);
      await revealContact(app, origin.provider, booking.id);
      const told = notifier.for(booking.id, 'contact_revealed');
      expect(told).toHaveLength(1);
      expect(told[0]?.userId).toBe(origin.provider.userId);
    });

    it('logs every call that returned numbers — ids and a timestamp, never the numbers', async () => {
      const { customer, origin, booking } = await matched();
      await revealContact(app, customer, booking.id);
      await revealContact(app, origin.provider, booking.id);
      const log = await app.deps.prisma.contactRevealEvent.findMany({
        where: { bookingId: booking.id },
        orderBy: { createdAt: 'asc' },
      });
      expect(log.map((l) => l.actorRole)).toEqual(['customer', 'provider']);
      expect(log.map((l) => l.userId)).toEqual([customer.userId, origin.provider.userId]);
      expect(JSON.stringify(log)).not.toMatch(/\+960/);
    });

    it('returns nothing 24 hours after the booking goes terminal, and still answers an hour before', async () => {
      const { customer, origin, booking } = await matched();
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, origin.provider, booking.id, 'confirm-payment-received');
      await actOk(app, origin.provider, booking.id, 'complete', { finalAmountLaari: 90_000 });

      clock.advance(minutes(23 * 60));
      expect((await revealContact(app, customer, booking.id)).statusCode).toBe(200);

      clock.advance(minutes(61));
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CONTACT_REVEAL_EXPIRED');
      expect(res.body).not.toMatch(/\+960/);
      expect((await revealContact(app, origin.provider, booking.id)).statusCode).toBe(422);
      expect((await readBooking(app, customer, booking.id)).emergency?.contactReveal).toBe(
        'expired',
      );
    });

    it('is checked against the runtime kill switch before any of the seven', async () => {
      const { customer, booking } = await matched();
      await app.deps.prisma.killSwitch.upsert({
        where: { key: 'emergency_contact_reveal' },
        create: { key: 'emergency_contact_reveal', engaged: true },
        update: { engaged: true },
      });
      const res = await revealContact(app, customer, booking.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('CONTACT_REVEAL_PAUSED');
      expect((await readBooking(app, customer, booking.id)).emergency?.contactReveal).toBe(
        'paused',
      );

      // Released without a deploy — the same process, the next request.
      await app.deps.prisma.killSwitch.update({
        where: { key: 'emergency_contact_reveal' },
        data: { engaged: false },
      });
      expect((await revealContact(app, customer, booking.id)).statusCode).toBe(200);
    });

    it('is not found for anyone who is not a party — including a provider who offered and was not chosen', async () => {
      const s = await scene();
      const rival = await another(s.island);
      const booking = await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
      await offerOn(app, s.origin.provider, booking.id, 35_000);
      await offerOn(app, rival.provider, booking.id, 45_000);
      clock.advance(seconds(90));
      const offers = (await readBooking(app, s.customer, booking.id)).emergency?.offers ?? [];
      const origins = offers.find((o) => o.calloutFeeLaari === 35_000);
      await respond(s.customer, booking.id, { offerId: origins?.id });
      expect((await revealContact(app, s.customer, booking.id)).statusCode).toBe(200);

      for (const outsider of [rival.provider, await verifiedCustomer(app)]) {
        const res = await revealContact(app, outsider, booking.id);
        expect(res.statusCode).toBe(404);
        expect(res.body).not.toMatch(/\+960/);
      }
    });
  });

  // =========================================================================
  // 2. The revocation cascade
  // =========================================================================

  describe('2. a tier drop cancels an unpaid emergency and routes a paid one to admin', () => {
    it('auto-cancels an accepted emergency, with both parties notified', async () => {
      const { customer, origin, booking } = await matched('Electrical');
      expect(booking.status).toBe('awaiting_payment');

      // Gold → silver: below Electrical's bar (the category's own, not a flat silver).
      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      const result = await app.emergency.onProviderTierChanged(origin.providerProfileId);
      expect(result.cancelled).toEqual([booking.id]);

      const after = await readBooking(app, customer, booking.id);
      expect(after.status).toBe('cancelled');
      expect(after.statusHistory?.at(-1)?.transition).toBe('verification-revoked');
      const told = notifier.for(booking.id, 'cancelled_verification_revoked').map((e) => e.userId);
      expect(told.sort()).toEqual([customer.userId, origin.provider.userId].sort());
    });

    it('leaves a payment_claimed one untouched and files it for admin, once', async () => {
      const { customer, origin, booking } = await matched('Electrical');
      await actOk(app, customer, booking.id, 'claim-payment');

      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'bronze' },
      });
      const result = await app.emergency.onProviderTierChanged(origin.providerProfileId);
      expect(result.cancelled).toEqual([]);
      expect(result.routedToAdmin).toEqual([booking.id]);
      await app.emergency.onProviderTierChanged(origin.providerProfileId);

      expect((await readBooking(app, customer, booking.id)).status).toBe('payment_claimed');
      const reports = await app.deps.prisma.report.findMany({ where: { bookingId: booking.id } });
      expect(reports).toHaveLength(1);
      expect(reports[0]?.reason).toBe('provider_verification_revoked');
      expect(reports[0]?.reporterId).toBeNull();
    });

    it('leaves a booking alone where the new tier still meets its category — AC Repair at silver', async () => {
      const { origin, booking } = await matched('AC Repair');
      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      const result = await app.emergency.onProviderTierChanged(origin.providerProfileId);
      expect(result.cancelled).not.toContain(booking.id);
    });
  });

  // =========================================================================
  // 3. The composed rule at creation
  // =========================================================================

  describe('3. an emergency on an ineligible category or from an unverified provider is rejected', () => {
    it('refuses a category that is not emergency-capable', async () => {
      const island = await randomIsland(app.deps.prisma);
      const provider = await registerUser(app, { role: 'provider' });
      const draft = await completeDraft(app, provider.headers, {
        categoryName: 'Cleaning',
        islandNames: [[island.atollAbbr, island.name]],
      });
      await publish(app, provider.headers, draft.id);
      const customer = await verifiedCustomer(app);
      const res = await createBooking(app, customer, draft.id, {
        emergency: true,
        jobNotes: 'Flooded bathroom',
        islandId: island.id,
      });
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('EMERGENCY_CATEGORY_NOT_CAPABLE');
    });

    it('refuses a listing whose provider no longer meets the tier — checked at booking time', async () => {
      const { island, origin, customer } = await scene('Plumbing');
      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'none', verificationStatus: 'unverified' },
      });
      const res = await createBooking(app, customer, origin.listingId, {
        emergency: true,
        jobNotes: 'Burst pipe',
        islandId: island.id,
      });
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('EMERGENCY_TIER_NOT_MET');
      expect(
        await app.deps.prisma.booking.count({
          where: { customerId: customer.userId, bookingMode: 'emergency' },
        }),
      ).toBe(0);
    });
  });

  // =========================================================================
  // 4. The rate limit
  // =========================================================================

  describe('4. the emergency rate limit triggers', () => {
    it('refuses a fourth request inside 24 hours, then allows one once the first ages out', async () => {
      const { island, origin, customer } = await scene();
      for (let i = 0; i < 3; i += 1) {
        await raiseEmergency(app, customer, origin.listingId, island.id);
        clock.advance(minutes(60));
      }
      const fourth = await createBooking(app, customer, origin.listingId, {
        emergency: true,
        jobNotes: 'Again',
        islandId: island.id,
      });
      expect(fourth.statusCode).toBe(422);
      expect(errorCode(fourth)).toBe('EMERGENCY_RATE_LIMITED');
      const details = fourth.json<{ error: { details: Record<string, unknown> } }>().error.details;
      expect(details.usedLast24Hours).toBe(3);
      expect(details.nextAvailableAt).toBe(
        new Date(START.getTime() + minutes(24 * 60)).toISOString(),
      );

      clock.set(new Date(START.getTime() + minutes(24 * 60) + seconds(1)));
      await raiseEmergency(app, customer, origin.listingId, island.id);
    });

    it('refuses an eleventh request inside 7 days even when the day is clear', async () => {
      const { island, origin, customer } = await scene();
      for (let i = 0; i < 10; i += 1) {
        await raiseEmergency(app, customer, origin.listingId, island.id);
        // Three a day never trips the daily limit; ten across four days does
        // trip the weekly one.
        clock.advance(i % 3 === 2 ? minutes(24 * 60) : minutes(10));
      }
      const res = await createBooking(app, customer, origin.listingId, {
        emergency: true,
        jobNotes: 'Again',
        islandId: island.id,
      });
      expect(errorCode(res)).toBe('EMERGENCY_RATE_LIMITED');
      expect(
        res.json<{ error: { details: Record<string, unknown> } }>().error.details.usedLast7Days,
      ).toBe(10);
    });

    it('does not count a rejection or a re-broadcast — only requests', async () => {
      const s = await scene();
      const booking = await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
      for (let i = 0; i < 3; i += 1) {
        const p = await another(s.island);
        await offerOn(app, p.provider, booking.id);
        clock.advance(seconds(90));
        expect((await respond(s.customer, booking.id, { rejectAll: true })).statusCode).toBe(200);
      }
      // Three rejections and three re-broadcasts inside one request; two more
      // requests are still allowed today.
      await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
      await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
    });
  });

  // =========================================================================
  // 5. The broadcast
  // =========================================================================

  describe('5. a broadcast reaches every eligible provider and nobody outside the rule', () => {
    it('pages the eligible set and none of seven kinds of ineligible provider', async () => {
      const prisma = app.deps.prisma;
      const { island, origin, customer } = await scene('Plumbing');
      const second = await another(island);

      // Seven ways to be outside the rule.
      const demoted = await another(island); // below Plumbing's gold bar
      await prisma.providerProfile.update({
        where: { id: demoted.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      const paused = await another(island); // not taking new customers
      await prisma.providerProfile.update({
        where: { id: paused.providerProfileId },
        data: { acceptingNewCustomers: false },
      });
      const suspended = await another(island); // §1a's input to visibility
      await prisma.providerProfile.update({
        where: { id: suspended.providerProfileId },
        data: { suspendedAt: START },
      });
      let elsewhereIsland = await randomIsland(prisma);
      while (elsewhereIsland.id === island.id) elsewhereIsland = await randomIsland(prisma);
      const elsewhere = await emergencyProvider(app, {
        categoryName: 'Plumbing',
        island: elsewhereIsland,
      }); // another island
      const otherTrade = await emergencyProvider(app, { categoryName: 'Electrical', island }); // another category
      const optedOut = await another(island); // no isEmergency on the listing
      await prisma.listing.update({
        where: { id: optedOut.listingId },
        data: { isEmergency: false },
      });

      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      // The customer is also a provider elsewhere? Not here — but the rule
      // excludes the customer, which `recipients` checks by user id.
      const reached = new Set(await broadcastRecipients(booking.id));

      expect(reached.has(origin.provider.userId)).toBe(true);
      expect(reached.has(second.provider.userId)).toBe(true);
      for (const outside of [demoted, paused, suspended, elsewhere, otherTrade, optedOut]) {
        expect(reached.has(outside.provider.userId)).toBe(false);
      }

      // And every recipient — including any a previous run left on this
      // island — satisfies the whole rule, checked independently here.
      const plumbing = await category('Plumbing');
      for (const userId of reached) {
        const profile = await prisma.providerProfile.findUniqueOrThrow({
          where: { userId },
          include: {
            listings: {
              where: {
                categoryId: plumbing.id,
                isEmergency: true,
                status: 'published',
                visibility: 'active',
                deletedAt: null,
                serviceAreas: { some: { islandId: island.id, removedAt: null } },
              },
            },
          },
        });
        expect(profile.listings.length).toBeGreaterThan(0);
        expect(profile.verificationTier).toBe('gold');
        expect(profile.acceptingNewCustomers).toBe(true);
        expect(profile.suspendedAt).toBeNull();
      }

      // Every page went out on the emergency path: push and email together.
      const dispatches = await prisma.pushDispatch.findMany({ where: { subjectId: booking.id } });
      expect(dispatches.every((d) => d.urgency === 'emergency')).toBe(true);
    });

    it('shows the request in each eligible provider inbox, without an address or a number', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/emergency-requests',
        headers: origin.provider.headers,
        remoteAddress: freshIp(),
      });
      const inbox = res.json<Envelope<EmergencyBroadcastDto[]>>().data;
      const item = inbox.find((i) => i.bookingId === booking.id);
      expect(item?.canOffer).toBe(true);
      // First name only (§Phase 3c's content rule), never the full name.
      const full = (
        await app.deps.prisma.user.findUniqueOrThrow({ where: { id: customer.userId } })
      ).fullName;
      expect(item?.customerFirstName).toBe(full.split(' ')[0]);
      // "Exact address is shared if the customer picks you."
      expect(res.body).not.toContain('Fehivina');
      expect(res.body).not.toMatch(/\+960|phone/i);

      // And the origin provider has no side of it yet: not in their bookings,
      // not declinable.
      const theirs = await listBookings(app, origin.provider, '?role=provider');
      expect(theirs.bookings.map((b) => b.id)).not.toContain(booking.id);
      expect((await act(app, origin.provider, booking.id, 'decline')).statusCode).toBe(404);
    });
  });

  // =========================================================================
  // 6–8. Offers coexist, collect for 90 seconds, at most three, and selection releases
  // =========================================================================

  describe('6. two simultaneous accepts both produce offers rather than one winner', () => {
    it('admits both, moves the status once, and shows the customer both', async () => {
      const { island, origin, customer } = await scene();
      const second = await another(island);
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);

      const [a, b] = await Promise.all([
        offerOn(app, origin.provider, booking.id, 35_000, 30),
        offerOn(app, second.provider, booking.id, 45_000, 15),
      ]);
      expect([a.statusCode, b.statusCode]).toEqual([200, 200]);

      const offers = await app.deps.prisma.emergencyOffer.findMany({
        where: { bookingId: booking.id },
      });
      expect(offers).toHaveLength(2);
      const history = await app.deps.prisma.bookingStatusEvent.findMany({
        where: { bookingId: booking.id, toStatus: 'emergency_offered' },
      });
      expect(history).toHaveLength(1);

      clock.advance(seconds(90));
      const read = await readBooking(app, customer, booking.id);
      expect(read.emergency?.phase).toBe('choosing');
      expect(read.emergency?.offers.map((o) => o.calloutFeeLaari).sort()).toEqual([35_000, 45_000]);
    });

    it('refuses the same provider a second open offer', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      expect((await offerOn(app, origin.provider, booking.id)).statusCode).toBe(200);
      const again = await offerOn(app, origin.provider, booking.id, 10_000, 15);
      expect(again.statusCode).toBe(409);
      expect(errorCode(again)).toBe('EMERGENCY_OFFER_ALREADY_MADE');
    });
  });

  describe('7. a collection window closes at 90 seconds and presents at most three offers', () => {
    it('holds the offers back until 90 seconds, refuses a fourth, and refuses a late one', async () => {
      const { island, origin, customer } = await scene();
      const [b, c, d] = [await another(island), await another(island), await another(island)];
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);

      expect((await offerOn(app, origin.provider, booking.id)).statusCode).toBe(200);
      clock.advance(seconds(30));
      expect((await offerOn(app, b.provider, booking.id)).statusCode).toBe(200);
      expect((await offerOn(app, c.provider, booking.id)).statusCode).toBe(200);
      const fourth = await offerOn(app, d.provider, booking.id);
      expect(errorCode(fourth)).toBe('EMERGENCY_OFFERS_FULL');

      // One second short: collecting. The count shows, the offers do not, and
      // the customer cannot choose yet.
      clock.set(new Date(START.getTime() + seconds(89)));
      const during = await readBooking(app, customer, booking.id);
      expect(during.emergency?.phase).toBe('collecting');
      expect(during.emergency?.offersReceived).toBe(3);
      expect(during.emergency?.offers).toEqual([]);
      const early = await respond(customer, booking.id, { rejectAll: true });
      expect(errorCode(early)).toBe('EMERGENCY_OFFERS_STILL_COLLECTING');

      // At 90: closed, and three on the table.
      clock.set(new Date(START.getTime() + seconds(90)));
      const after = await readBooking(app, customer, booking.id);
      expect(after.emergency?.phase).toBe('choosing');
      expect(after.emergency?.offers).toHaveLength(3);
      expect(after.emergency?.collectionClosesAt).toBe(
        new Date(START.getTime() + seconds(90)).toISOString(),
      );
      const late = await offerOn(app, d.provider, booking.id);
      expect(errorCode(late)).toBe('EMERGENCY_OFFERS_CLOSED');
    });
  });

  describe('8. selecting one releases the others immediately', () => {
    it('marks the others not_selected in the same moment, and tells them', async () => {
      const { island, origin, customer } = await scene();
      const second = await another(island);
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      await offerOn(app, origin.provider, booking.id, 35_000);
      await offerOn(app, second.provider, booking.id, 45_000);
      clock.advance(seconds(90));

      const offers = (await readBooking(app, customer, booking.id)).emergency?.offers ?? [];
      const cheaper = offers.find((o) => o.calloutFeeLaari === 35_000);
      await respond(customer, booking.id, { offerId: cheaper?.id });

      const view = (await providerView(second.provider, booking.id)).json<
        Envelope<EmergencyBroadcastDto>
      >().data;
      expect(view.myOffer?.state).toBe('not_selected');
      expect(view.canOffer).toBe(false);
      expect(notifier.for(booking.id, 'emergency_offer_not_selected').map((e) => e.userId)).toEqual(
        [second.provider.userId],
      );
      expect(notifier.for(booking.id, 'emergency_offer_selected').map((e) => e.userId)).toEqual([
        origin.provider.userId,
      ]);
    });

    it('re-points the booking at the chosen provider and their own listing', async () => {
      const { island, origin, customer } = await scene();
      const second = await another(island);
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      await offerOn(app, second.provider, booking.id, 45_000, 15);
      clock.advance(seconds(90));
      const offer = (await readBooking(app, customer, booking.id)).emergency?.offers[0];
      const selected = (await respond(customer, booking.id, { offerId: offer?.id })).json<
        Envelope<BookingDto>
      >().data;

      expect(selected.provider.userId).toBe(second.provider.userId);
      expect(selected.listingId).toBe(second.listingId);
      expect(selected.agreedAmountLaari).toBe(45_000);
      expect(selected.amountKind).toBe('callout_fee');
      // §1c: `scheduledFor` is the acceptance timestamp.
      expect(selected.scheduledFor).toBe(clock.clock().toISOString());
      // The chosen provider now has a side, and sees it in their own bookings.
      const theirs = await listBookings(app, second.provider, '?role=provider');
      expect(theirs.bookings.map((b) => b.id)).toContain(booking.id);
    });

    it('lands all of it in one transaction — a failure after the claim leaves no fee and no claim', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      await offerOn(app, origin.provider, booking.id);
      clock.advance(seconds(90));
      const offerId = (await readBooking(app, customer, booking.id)).emergency?.offers[0]?.id ?? '';

      const repo = (app.emergency as unknown as { repo: BookingRepository }).repo;
      const spy = vi.spyOn(repo, 'transition').mockImplementationOnce(() => {
        throw new Error('forced failure after the offer was claimed');
      });
      const res = await respond(customer, booking.id, { offerId });
      expect(res.statusCode).toBe(500);
      // Reached — so the test is about a failure inside the transaction, not
      // one that never got there.
      expect(spy).toHaveBeenCalledTimes(1);

      const after = await app.deps.prisma.booking.findUniqueOrThrow({ where: { id: booking.id } });
      expect(after.status).toBe('emergency_offered');
      expect(after.dispatchFeeSubmissionId).toBeNull();
      const offer = await app.deps.prisma.emergencyOffer.findUniqueOrThrow({
        where: { id: offerId },
      });
      expect(offer.state).toBe('open');
      expect(
        await app.deps.prisma.paymentSubmission.count({
          where: { payerId: customer.userId, purpose: 'emergency_dispatch_fee' },
        }),
      ).toBe(0);
    });
  });

  // =========================================================================
  // 9–10. Reject-all, and the customer's silence
  // =========================================================================

  describe('9. reject-all re-broadcasts and never returns to any provider who offered', () => {
    it('excludes every offerer from the next broadcast and from offering again', async () => {
      const { island, origin, customer } = await scene();
      const second = await another(island);
      const third = await another(island);
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      await offerOn(app, origin.provider, booking.id);
      await offerOn(app, second.provider, booking.id);
      clock.advance(seconds(90));

      const before = (await broadcastRecipients(booking.id)).length;
      const res = await respond(customer, booking.id, { rejectAll: true });
      expect(res.statusCode).toBe(200);
      const after = res.json<Envelope<BookingDto>>().data;
      expect(after.status).toBe('requested');

      const all = await broadcastRecipients(booking.id);
      const second_round = all.slice(before);
      expect(second_round).toContain(third.provider.userId);
      expect(second_round).not.toContain(origin.provider.userId);
      expect(second_round).not.toContain(second.provider.userId);

      for (const p of [origin, second]) {
        const retry = await offerOn(app, p.provider, booking.id);
        expect(retry.statusCode).not.toBe(200);
        expect(retry.body).not.toMatch(/"canOffer":true/);
      }
      expect((await offerOn(app, third.provider, booking.id)).statusCode).toBe(200);
      expect(notifier.for(booking.id, 'emergency_offer_rejected')).toHaveLength(2);
    });
  });

  describe('10. unanswered offers expire 5 minutes after the window closes, without resetting the overall window', () => {
    it('releases them at 5 minutes and not a second before, and re-broadcasts to the same providers', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      const windowEndsAt = (await readBooking(app, customer, booking.id)).emergency?.windowEndsAt;
      await offerOn(app, origin.provider, booking.id);
      const before = (await broadcastRecipients(booking.id)).length;

      clock.set(new Date(START.getTime() + seconds(90) + minutes(5) - seconds(1)));
      await app.jobs.runOnce(EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('emergency_offered');

      clock.set(new Date(START.getTime() + seconds(90) + minutes(5)));
      await app.jobs.runOnce(EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME, clock.clock());
      const after = await readBooking(app, customer, booking.id);
      expect(after.status).toBe('requested');
      expect(after.emergency?.windowEndsAt).toBe(windowEndsAt);
      expect(after.statusHistory?.at(-1)?.actorRole).toBe('system');

      const offer = await app.deps.prisma.emergencyOffer.findFirstOrThrow({
        where: { bookingId: booking.id },
      });
      expect(offer.state).toBe('expired');
      // Re-broadcast, and a silent customer is not a verdict on the provider.
      const again = (await broadcastRecipients(booking.id)).slice(before);
      expect(again).toContain(origin.provider.userId);
      expect((await offerOn(app, origin.provider, booking.id)).statusCode).toBe(200);
    });
  });

  // =========================================================================
  // 11. The dispatch fee
  // =========================================================================

  describe('11. selecting incurs the MVR 200 fee, the job proceeds, and proof — not an admin — lifts the block', () => {
    it('runs the whole of §1c’s fee rule', async () => {
      const { customer, booking } = await matched();

      // Incurred at selection, owed, and the job went straight on.
      expect(booking.status).toBe('awaiting_payment');
      const fee = booking.emergency?.dispatchFee;
      expect(fee?.amountLaari).toBe(20_000);
      expect(fee?.state).toBe('owed');

      // A new booking of any mode is refused while it is owed…
      const slot = await bookableListing(app);
      const blocked = await createBooking(app, customer, slot.listingId, {
        timeSlotId: slot.slotId,
      });
      expect(errorCode(blocked)).toBe('DISPATCH_FEE_OUTSTANDING');
      const request = await requestListing(app);
      const blockedRequest = await createBooking(app, customer, request.listingId, {
        preferredWindowChip: 'tomorrow_morning',
      });
      expect(errorCode(blockedRequest)).toBe('DISPATCH_FEE_OUTSTANDING');

      // …the existing one is unaffected…
      expect((await act(app, customer, booking.id, 'claim-payment')).statusCode).toBe(200);

      // …and submitting proof lifts it with the row still pending.
      const feeId = fee?.submissionId ?? '';
      const target = await app.inject({
        method: 'POST',
        url: `/v1/users/me/dispatch-fees/${feeId}/proof`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { contentType: 'image/jpeg' },
      });
      expect(target.statusCode).toBe(201);
      const upload =
        target.json<Envelope<{ upload: { url: string; headers: Record<string, string> } }>>().data
          .upload;
      await app.inject({
        method: 'PUT',
        url: uploadPathOf(upload.url),
        headers: upload.headers,
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      const submitted = await app.inject({
        method: 'POST',
        url: `/v1/users/me/dispatch-fees/${feeId}/submit`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
      });
      expect(submitted.statusCode).toBe(200);

      const row = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: feeId },
      });
      expect(row.status).toBe('pending');
      expect(row.reviewedByAdminId).toBeNull();
      await bookSlot(app, customer, slot.listingId, slot.slotId);
    });

    it('charges nothing for a request nobody answered', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      const plumbing = await category('Plumbing');
      clock.advance(minutes(plumbing.windowMinutes));
      await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readBooking(app, customer, booking.id)).status).toBe('declined');
      expect(
        await app.deps.prisma.paymentSubmission.count({ where: { payerId: customer.userId } }),
      ).toBe(0);
    });

    it('keeps the fee routes to dispatch fees — a subscription payment is not found through them', async () => {
      const { customer } = await matched();
      const sub = await app.deps.prisma.paymentSubmission.create({
        data: {
          payerId: customer.userId,
          purpose: 'subscription',
          amountLaari: 15_000,
          referenceCode: `RP-T${randomUUID().slice(0, 8)}`,
        },
      });
      const res = await app.inject({
        method: 'POST',
        url: `/v1/users/me/dispatch-fees/${sub.id}/submit`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(404);
    });
  });

  // =========================================================================
  // 12. The provider who does not come
  // =========================================================================

  describe('12. a provider marked as not arrived is released, takes a no-show, and the request goes out again without a second fee', () => {
    it('refuses before the window, then releases, excludes and re-broadcasts', async () => {
      const { island, origin, customer, booking } = await matched();
      const plumbing = await category('Plumbing');
      const feeId = booking.emergency?.dispatchFee?.submissionId;
      const replacement = await another(island);

      clock.advance(minutes(plumbing.windowMinutes) - seconds(1));
      const early = await act(app, customer, booking.id, 'provider-not-arrived');
      expect(errorCode(early)).toBe('EMERGENCY_NOT_ARRIVED_TOO_EARLY');

      clock.advance(seconds(2));
      const before = (await broadcastRecipients(booking.id)).length;
      const res = await act(app, customer, booking.id, 'provider-not-arrived');
      expect(res.statusCode).toBe(200);
      const after = res.json<Envelope<BookingDto>>().data;
      expect(after.status).toBe('requested');
      expect(after.agreedAmountLaari).toBeNull();

      const offer = await app.deps.prisma.emergencyOffer.findFirstOrThrow({
        where: { bookingId: booking.id, providerProfileId: origin.providerProfileId },
      });
      expect(offer.state).toBe('no_show');
      const round2 = (await broadcastRecipients(booking.id)).slice(before);
      expect(round2).toContain(replacement.provider.userId);
      expect(round2).not.toContain(origin.provider.userId);
      expect((await offerOn(app, origin.provider, booking.id)).statusCode).not.toBe(200);

      // The replacement is chosen: still one fee, the same one.
      await offerOn(app, replacement.provider, booking.id);
      clock.advance(seconds(90));
      const offerId = (await readBooking(app, customer, booking.id)).emergency?.offers[0]?.id;
      const chosen = (await respond(customer, booking.id, { offerId })).json<Envelope<BookingDto>>()
        .data;
      expect(chosen.status).toBe('awaiting_payment');
      expect(chosen.emergency?.dispatchFee?.submissionId).toBe(feeId);
      expect(
        await app.deps.prisma.paymentSubmission.count({
          where: { payerId: customer.userId, purpose: 'emergency_dispatch_fee' },
        }),
      ).toBe(1);
    });

    it('re-broadcasts on the chosen provider cancelling too — §1h, never a dead end', async () => {
      const { island, origin, customer, booking } = await matched();
      const replacement = await another(island);
      const before = (await broadcastRecipients(booking.id)).length;
      const res = await act(app, origin.provider, booking.id, 'cancel', {
        reason: 'Van broke down',
      });
      expect(res.statusCode).toBe(200);
      const after = await readBooking(app, customer, booking.id);
      expect(after.status).toBe('requested');
      const round2 = (await broadcastRecipients(booking.id)).slice(before);
      expect(round2).toContain(replacement.provider.userId);
      expect(round2).not.toContain(origin.provider.userId);
    });
  });

  // =========================================================================
  // 13. The per-category tier bar
  // =========================================================================

  describe('13. Electrical refuses a silver provider and accepts a gold one; AC Repair accepts silver', () => {
    it('reads the bar from the category', async () => {
      expect((await category('Electrical')).emergencyMinimumTier).toBe('gold');
      expect((await category('AC Repair')).emergencyMinimumTier).toBe('silver');

      const electrical = await scene('Electrical');
      const silver = await another(electrical.island, 'Electrical', 'silver');
      const booking = await raiseEmergency(
        app,
        electrical.customer,
        electrical.origin.listingId,
        electrical.island.id,
      );
      const refused = await offerOn(app, silver.provider, booking.id);
      expect(refused.statusCode).toBe(422);
      expect(errorCode(refused)).toBe('EMERGENCY_TIER_NOT_MET');
      expect((await offerOn(app, electrical.origin.provider, booking.id)).statusCode).toBe(200);

      const ac = await scene('AC Repair', 'silver');
      const acBooking = await raiseEmergency(app, ac.customer, ac.origin.listingId, ac.island.id);
      expect((await offerOn(app, ac.origin.provider, acBooking.id)).statusCode).toBe(200);
    });
  });

  // =========================================================================
  // 14 and 17. The answer window, per category
  // =========================================================================

  describe('14. the request window expires at 30 minutes for Moving exactly as for Plumbing, and offers carry an arrival estimate', () => {
    for (const name of ['Moving', 'Plumbing']) {
      it(`${name}: open a minute before the category window, declined at it`, async () => {
        const cat = await category(name);
        expect(cat.windowMinutes).toBe(30);
        const { island, origin, customer } = await scene(
          name,
          name === 'Moving' ? 'silver' : 'gold',
        );
        const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
        expect(booking.emergency?.windowEndsAt).toBe(
          new Date(START.getTime() + minutes(cat.windowMinutes)).toISOString(),
        );

        clock.advance(minutes(cat.windowMinutes - 1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readBooking(app, customer, booking.id)).status).toBe('requested');

        clock.advance(minutes(1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        const after = await readBooking(app, customer, booking.id);
        expect(after.status).toBe('declined');
        expect(after.statusHistory?.at(-1)?.transition).toBe('emergency-window-timeout');
        expect(notifier.for(booking.id, 'emergency_window_expired')).toHaveLength(1);
      });
    }

    it('stores each offer’s own arrival estimate and shows it to the customer', async () => {
      const cat = await category('Moving');
      const { island, origin, customer } = await scene('Moving', 'silver');
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      const eta = cat.emergencyEtaPresetsMinutes.at(-1) ?? 120;
      await offerOn(app, origin.provider, booking.id, 60_000, eta);
      clock.advance(seconds(90));
      const read = await readBooking(app, customer, booking.id);
      expect(read.emergency?.offers[0]?.etaMinutes).toBe(eta);
      expect(read.emergency?.etaPresetsMinutes).toEqual(cat.emergencyEtaPresetsMinutes);
    });

    it('refuses an offer with no arrival estimate', async () => {
      const { island, origin, customer } = await scene();
      const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
      const res = await act(app, origin.provider, booking.id, 'emergency-accept', {
        calloutFeeLaari: 30_000,
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('17. the emergency requested window auto-declines at the category’s emergencyAcceptWindowMinutes', () => {
    it('follows the column, not a constant — a changed window moves the deadline for the next request', async () => {
      const prisma = app.deps.prisma;
      const plumbing = await category('Plumbing');
      const { island, origin, customer } = await scene();
      try {
        await prisma.category.update({
          where: { id: plumbing.id },
          data: { emergencyAcceptWindowMinutes: plumbing.windowMinutes + 7 },
        });
        const booking = await raiseEmergency(app, customer, origin.listingId, island.id);
        clock.advance(minutes(plumbing.windowMinutes + 1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readBooking(app, customer, booking.id)).status).toBe('requested');
        clock.advance(minutes(6));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readBooking(app, customer, booking.id)).status).toBe('declined');
      } finally {
        await prisma.category.update({
          where: { id: plumbing.id },
          data: { emergencyAcceptWindowMinutes: plumbing.windowMinutes },
        });
      }
    });

    it('does not reset on a rejection — the window governs the whole request', async () => {
      const s = await scene();
      const other = await another(s.island);
      const booking = await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
      const endsAt = booking.emergency?.windowEndsAt;
      await offerOn(app, other.provider, booking.id);
      clock.advance(seconds(90));
      const rejected = (await respond(s.customer, booking.id, { rejectAll: true })).json<
        Envelope<BookingDto>
      >().data;
      expect(rejected.emergency?.windowEndsAt).toBe(endsAt);
    });
  });

  // =========================================================================
  // 15–16. Completion
  // =========================================================================

  describe('15. an emergency job cannot be completed without a final amount', () => {
    it('rejects the attempt and accepts it with one', async () => {
      const { customer, origin, booking } = await matched();
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, origin.provider, booking.id, 'confirm-payment-received');

      const without = await act(app, origin.provider, booking.id, 'complete', {});
      expect(without.statusCode).toBe(422);
      expect(errorCode(without)).toBe('FINAL_AMOUNT_REQUIRED');
      expect((await readBooking(app, customer, booking.id)).status).toBe('confirmed');

      const done = await actOk(app, origin.provider, booking.id, 'complete', {
        finalAmountLaari: 120_000,
      });
      expect(done.status).toBe('completed');
      expect(done.finalAmountLaari).toBe(120_000);
    });
  });

  describe('16. the "did this happen" flow fires for emergency bookings too', () => {
    it('prompts the customer 7 days after the acceptance timestamp', async () => {
      const { customer, origin, booking } = await matched();
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, origin.provider, booking.id, 'confirm-payment-received');

      clock.advance(minutes(7 * 24 * 60) + minutes(1));
      await app.jobs.runOnce(BOOKING_COMPLETION_TIMEOUT_JOB_NAME, clock.clock());
      const after = await readBooking(app, customer, booking.id);
      expect(after.completionPromptedAt).not.toBeNull();
      expect(notifier.for(booking.id, 'completion_prompt')).toHaveLength(1);

      const answered = await actOk(app, customer, booking.id, 'completion-answer', {
        happened: true,
      });
      expect(answered.status).toBe('completed');
    });
  });

  // =========================================================================
  // The phone rule, over every endpoint this slice adds
  // =========================================================================

  describe('standing rule — no endpoint 17.3 adds returns a phone number, except reveal-contact', () => {
    it('finds no number and no phone-shaped key in any of them', async () => {
      const s = await scene();
      const second = await another(s.island);
      const booking = await raiseEmergency(app, s.customer, s.origin.listingId, s.island.id);
      const numbers = (
        await app.deps.prisma.user.findMany({
          where: {
            id: { in: [s.customer.userId, s.origin.provider.userId, second.provider.userId] },
          },
          select: { phoneE164: true },
        })
      )
        .map((u) => u.phoneE164)
        .filter((p): p is string => p !== null);
      expect(numbers.length).toBe(3);

      const bodies: { label: string; body: string }[] = [];
      const push = (label: string, res: { body: string }) => bodies.push({ label, body: res.body });

      push('create', { body: JSON.stringify(booking) });
      push('offer', await offerOn(app, s.origin.provider, booking.id));
      push('offer 2', await offerOn(app, second.provider, booking.id));
      push(
        'inbox',
        await app.inject({
          method: 'GET',
          url: '/v1/providers/me/emergency-requests',
          headers: second.provider.headers,
          remoteAddress: freshIp(),
        }),
      );
      push('inbox item', await providerView(second.provider, booking.id));
      clock.advance(seconds(90));
      push('detail, choosing', {
        body: JSON.stringify(await readBooking(app, s.customer, booking.id)),
      });
      const offerId = (await readBooking(app, s.customer, booking.id)).emergency?.offers[0]?.id;
      push('select', await respond(s.customer, booking.id, { offerId }));
      push('detail, provider', {
        body: JSON.stringify(
          await readBooking(
            app,
            (await readBooking(app, s.customer, booking.id)).provider.userId ===
              second.provider.userId
              ? second.provider
              : s.origin.provider,
            booking.id,
          ),
        ),
      });
      push(
        'dispatch fees',
        await app.inject({
          method: 'GET',
          url: '/v1/users/me/dispatch-fees',
          headers: s.customer.headers,
          remoteAddress: freshIp(),
        }),
      );
      clock.advance(minutes(60));
      push('not arrived', await act(app, s.customer, booking.id, 'provider-not-arrived'));

      for (const { label, body } of bodies) {
        for (const n of numbers) expect(body, label).not.toContain(n);
        expect(body, label).not.toMatch(
          /"[a-zA-Z]*(phone|mobile|whatsapp|viber|msisdn)[a-zA-Z]*"\s*:/i,
        );
      }
    });
  });
});
