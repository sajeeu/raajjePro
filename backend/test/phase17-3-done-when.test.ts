import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import type { buildApp } from '../src/app.js';
import type { Island } from '../src/generated/prisma/client.js';
import {
  BOOKING_COMPLETION_TIMEOUT_JOB_NAME,
  EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME,
  EMERGENCY_WINDOW_TIMEOUT_JOB_NAME,
} from '../src/jobs/booking-lifecycle.js';
import type {
  BookingNotificationEvent,
  BookingNotifier,
} from '../src/modules/bookings/notifications.js';
import type { BookingRepository } from '../src/modules/bookings/repository.js';
import type {
  ContactRevealDto,
  EmergencyBroadcastDto,
  EmergencyRequestDto,
} from '../src/modules/bookings/types.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  act,
  actOk,
  actOnRequest,
  bookSlot,
  bookableListing,
  createBooking,
  emergencyProvider,
  errorCode,
  listBookings,
  offerOn,
  postEmergency,
  raiseEmergency,
  randomIsland,
  readBooking,
  readRequest,
  requestListing,
  revealContact,
  verifiedCustomer,
} from './helpers/bookings.js';
import { categoryByName, jpeg, uploadPathOf } from './helpers/listings.js';
import type { RegisteredUser } from './helpers/users.js';

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
  for(subjectId: string, event: string): BookingNotificationEvent[] {
    return this.events.filter((e) => e.bookingId === subjectId && e.event === event);
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
 * 🔧 **The shape these run against — owner's decisions, 2026-09-28.** An
 * emergency is an `EmergencyRequest` raised by **category and island**; the
 * broadcast, the offers and §1c's `requested` / `emergency_offered` states
 * live on it; the customer's choice creates a `Booking` at `accepted`. Every
 * eligible provider may offer, and the customer is shown the best three.
 * Clause 3's "by an unverified provider" is the provider **offering**.
 *
 * **No window in this file is a literal.** Every number the plan puts on a
 * category is read back from the seeded row; the flat ones (90 seconds, five
 * minutes, MVR 200, 3/24h and 10/7d) are §1c's own and live in `windows.ts`.
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

  /** A customer, an island, a category, and one eligible provider there. */
  async function scene(categoryName = 'Plumbing', tier: 'gold' | 'silver' = 'gold') {
    const island = await randomIsland(app.deps.prisma);
    const cat = await category(categoryName);
    const origin = await emergencyProvider(app, { categoryName, island, tier });
    const customer = await verifiedCustomer(app);
    return { island, category: cat, origin, customer };
  }

  /** One more eligible provider on the same island and category. */
  function another(island: Island, categoryName = 'Plumbing', tier: 'gold' | 'silver' = 'gold') {
    return emergencyProvider(app, { categoryName, island, tier });
  }

  function raise(s: { customer: RegisteredUser; category: { id: string }; island: Island }) {
    return raiseEmergency(app, s.customer, s.category.id, s.island.id);
  }

  /**
   * Who the broadcast for `requestId` was sent to — §Phase 3c's own record of
   * it — in dispatch order. `since` is a count from an earlier call, so a test
   * can ask who a *later* round reached.
   */
  async function broadcastRecipients(requestId: string, since = 0): Promise<string[]> {
    const rows = await app.deps.prisma.pushDispatch.findMany({
      where: { subjectId: requestId, kind: 'emergency_dispatch' },
      select: { userId: true },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.slice(since).map((r) => r.userId);
  }

  function providerView(provider: RegisteredUser, requestId: string) {
    return app.inject({
      method: 'GET',
      url: `/v1/providers/me/emergency-requests/${requestId}`,
      headers: provider.headers,
      remoteAddress: freshIp(),
    });
  }

  function inbox(provider: RegisteredUser) {
    return app.inject({
      method: 'GET',
      url: '/v1/providers/me/emergency-requests',
      headers: provider.headers,
      remoteAddress: freshIp(),
    });
  }

  function respond(customer: RegisteredUser, requestId: string, body: Record<string, unknown>) {
    return actOnRequest(app, customer, requestId, 'emergency-offer-response', body);
  }

  /** §Phase 8a's three steps against a customer's dispatch fee: target, PUT, submit. */
  async function submitFeeProof(customer: RegisteredUser, feeId: string): Promise<void> {
    const target = await app.inject({
      method: 'POST',
      url: `/v1/users/me/dispatch-fees/${feeId}/proof`,
      headers: { ...customer.headers, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      payload: { contentType: 'image/jpeg' },
    });
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
    if (submitted.statusCode !== 200) throw new Error(`submit: ${submitted.body}`);
  }

  /** A request with one offer, taken past the collection window and selected — the job is on. */
  async function matched(categoryName = 'Plumbing') {
    const s = await scene(categoryName);
    const request = await raise(s);
    expect((await offerOn(app, s.origin.provider, request.id, 40_000, 30)).statusCode).toBe(200);
    clock.advance(seconds(90));
    const offerId = (await readRequest(app, s.customer, request.id)).offers[0]?.id ?? '';
    const selected = await respond(s.customer, request.id, { offerId });
    expect(selected.statusCode).toBe(200);
    const after = selected.json<Envelope<EmergencyRequestDto>>().data;
    const booking = await readBooking(app, s.customer, after.bookingId ?? '');
    return { ...s, request: after, booking };
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
      // While the request is a broadcast there is no booking at all, so the
      // endpoint has nothing to reveal on.
      const s = await scene();
      const request = await raise(s);
      const none = await revealContact(app, s.customer, request.id);
      expect(none.statusCode).toBe(404);
      expect(none.body).not.toMatch(/\+960/);

      // And the guard itself, for a booking forced back to `requested` — the
      // condition is checked, not merely unreachable.
      const { customer, booking } = await matched();
      await app.deps.prisma.booking.update({
        where: { id: booking.id },
        data: { status: 'requested' },
      });
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
      expect((await revealContact(app, origin.provider, booking.id)).statusCode).toBe(200);
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
      const request = await raise(s);
      await offerOn(app, s.origin.provider, request.id, 35_000);
      await offerOn(app, rival.provider, request.id, 45_000);
      clock.advance(seconds(90));
      const offers = (await readRequest(app, s.customer, request.id)).offers;
      const cheaper = offers.find((o) => o.calloutFeeLaari === 35_000);
      const after = (await respond(s.customer, request.id, { offerId: cheaper?.id })).json<
        Envelope<EmergencyRequestDto>
      >().data;
      const bookingId = after.bookingId ?? '';
      expect((await revealContact(app, s.customer, bookingId)).statusCode).toBe(200);

      for (const outsider of [rival.provider, await verifiedCustomer(app)]) {
        const res = await revealContact(app, outsider, bookingId);
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

    it('waives the dispatch fee on the booking it cancels — §0.0 item 24', async () => {
      const { customer, origin, request, booking } = await matched('Electrical');
      const feeId = booking.emergency?.dispatchFee?.submissionId ?? '';
      // Owed, so the customer is blocked before the cascade runs.
      const slot = await bookableListing(app);
      expect(
        errorCode(await createBooking(app, customer, slot.listingId, { timeSlotId: slot.slotId })),
      ).toBe('DISPATCH_FEE_OUTSTANDING');

      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      await app.emergency.onProviderTierChanged(origin.providerProfileId);

      const fee = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: feeId },
      });
      expect(fee.waivedAt).not.toBeNull();
      expect(fee.waivedReason).toBe('provider_verification_revoked');
      // Nothing deleted: the amount and reference stay on the row.
      expect(fee.amountLaari).toBe(20_000);
      expect((await readRequest(app, customer, request.id)).dispatchFee?.state).toBe('waived');
      await bookSlot(app, customer, slot.listingId, slot.slotId);
    });

    it('leaves a confirmed fee alone — waiving it would erase money received', async () => {
      const { customer, origin, request, booking } = await matched('Electrical');
      const feeId = booking.emergency?.dispatchFee?.submissionId ?? '';
      await submitFeeProof(customer, feeId);
      // Set directly rather than through `confirmSubmission`, which refuses a
      // dispatch fee outright — `providerOfPayerOr422` throws
      // PAYER_IS_NOT_A_PROVIDER for a customer payer, so no admin can confirm
      // one today (ledger P17-6). The guard this pins is what protects the
      // money once they can: `dispatchFeeState` reads `waivedAt` before
      // `status`, so a waiver landing on a confirmed row would render a
      // payment RaajjePro actually received as "nothing to pay".
      await app.deps.prisma.paymentSubmission.update({
        where: { id: feeId },
        data: { status: 'confirmed' },
      });

      await app.deps.prisma.providerProfile.update({
        where: { id: origin.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      await app.emergency.onProviderTierChanged(origin.providerProfileId);

      const fee = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: feeId },
      });
      expect(fee.waivedAt).toBeNull();
      expect(fee.waivedReason).toBeNull();
      expect((await readRequest(app, customer, request.id)).dispatchFee?.state).toBe('confirmed');
    });

    it('does not waive the fee on a no-show — the customer still gets their job', async () => {
      const { customer, booking } = await matched();
      const window = (await category('Plumbing')).windowMinutes;
      clock.advance(minutes(window));
      await act(app, customer, booking.id, 'provider-not-arrived');
      const fee = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: booking.emergency?.dispatchFee?.submissionId ?? '' },
      });
      expect(fee.waivedAt).toBeNull();
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
  // 3. The composed rule
  // =========================================================================

  describe('3. an emergency on an ineligible category or from an unverified provider is rejected', () => {
    it('refuses a category that is not emergency-capable', async () => {
      const island = await randomIsland(app.deps.prisma);
      const cleaning = await categoryByName(app.deps.prisma, 'Cleaning');
      const customer = await verifiedCustomer(app);
      const res = await postEmergency(app, customer, {
        categoryId: cleaning.id,
        islandId: island.id,
        jobNotes: 'Flooded bathroom',
      });
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('EMERGENCY_CATEGORY_NOT_CAPABLE');
      expect(
        await app.deps.prisma.emergencyRequest.count({ where: { customerId: customer.userId } }),
      ).toBe(0);
    });

    it('refuses an offer from a provider who is not verified to the category’s bar', async () => {
      const s = await scene('Plumbing');
      const unverified = await another(s.island);
      await app.deps.prisma.providerProfile.update({
        where: { id: unverified.providerProfileId },
        data: { verificationTier: 'none', verificationStatus: 'unverified' },
      });
      const request = await raise(s);
      // Not paged either — the broadcast and the offer read one rule.
      expect(await broadcastRecipients(request.id)).not.toContain(unverified.provider.userId);
      const res = await offerOn(app, unverified.provider, request.id);
      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('EMERGENCY_TIER_NOT_MET');
      expect(await app.deps.prisma.emergencyOffer.count({ where: { requestId: request.id } })).toBe(
        0,
      );
    });
  });

  // =========================================================================
  // 4. The rate limit
  // =========================================================================

  describe('4. the emergency rate limit triggers', () => {
    it('refuses a fourth request inside 24 hours, then allows one once the first ages out', async () => {
      const s = await scene();
      for (let i = 0; i < 3; i += 1) {
        await raise(s);
        clock.advance(minutes(60));
      }
      const fourth = await postEmergency(app, s.customer, {
        categoryId: s.category.id,
        islandId: s.island.id,
        jobNotes: 'Again',
      });
      expect(fourth.statusCode).toBe(422);
      expect(errorCode(fourth)).toBe('EMERGENCY_RATE_LIMITED');
      const details = fourth.json<{ error: { details: Record<string, unknown> } }>().error.details;
      expect(details.usedLast24Hours).toBe(3);
      expect(details.nextAvailableAt).toBe(
        new Date(START.getTime() + minutes(24 * 60)).toISOString(),
      );

      clock.set(new Date(START.getTime() + minutes(24 * 60) + seconds(1)));
      await raise(s);
    });

    it('refuses an eleventh request inside 7 days even when the day is clear', async () => {
      const s = await scene();
      for (let i = 0; i < 10; i += 1) {
        await raise(s);
        // Three a day never trips the daily limit; ten across four days does
        // trip the weekly one.
        clock.advance(i % 3 === 2 ? minutes(24 * 60) : minutes(10));
      }
      const res = await postEmergency(app, s.customer, {
        categoryId: s.category.id,
        islandId: s.island.id,
        jobNotes: 'Again',
      });
      expect(errorCode(res)).toBe('EMERGENCY_RATE_LIMITED');
      expect(
        res.json<{ error: { details: Record<string, unknown> } }>().error.details.usedLast7Days,
      ).toBe(10);
    });

    it('does not count a rejection or a re-broadcast — only requests', async () => {
      const s = await scene();
      const request = await raise(s);
      for (let i = 0; i < 3; i += 1) {
        const p = await another(s.island);
        await offerOn(app, p.provider, request.id);
        clock.advance(seconds(90));
        expect((await respond(s.customer, request.id, { rejectAll: true })).statusCode).toBe(200);
      }
      // Three rejections and three re-broadcasts inside one request; two more
      // requests are still allowed today.
      await raise(s);
      await raise(s);
    });
  });

  // =========================================================================
  // 5. The broadcast
  // =========================================================================

  describe('5. a broadcast reaches every eligible provider and nobody outside the rule', () => {
    it('pages the eligible set and none of six kinds of ineligible provider', async () => {
      const prisma = app.deps.prisma;
      const s = await scene('Plumbing');
      const second = await another(s.island);

      const demoted = await another(s.island); // below Plumbing's gold bar
      await prisma.providerProfile.update({
        where: { id: demoted.providerProfileId },
        data: { verificationTier: 'silver' },
      });
      const paused = await another(s.island); // not taking new customers
      await prisma.providerProfile.update({
        where: { id: paused.providerProfileId },
        data: { acceptingNewCustomers: false },
      });
      const suspended = await another(s.island); // §1a's input to visibility
      await prisma.providerProfile.update({
        where: { id: suspended.providerProfileId },
        data: { suspendedAt: START },
      });
      let elsewhereIsland = await randomIsland(prisma);
      while (elsewhereIsland.id === s.island.id) elsewhereIsland = await randomIsland(prisma);
      const elsewhere = await emergencyProvider(app, {
        categoryName: 'Plumbing',
        island: elsewhereIsland,
      });
      const otherTrade = await emergencyProvider(app, {
        categoryName: 'Electrical',
        island: s.island,
      });
      const optedOut = await another(s.island); // no isEmergency on the listing
      await prisma.listing.update({
        where: { id: optedOut.listingId },
        data: { isEmergency: false },
      });

      const request = await raise(s);
      const reached = new Set(await broadcastRecipients(request.id));

      expect(reached.has(s.origin.provider.userId)).toBe(true);
      expect(reached.has(second.provider.userId)).toBe(true);
      for (const outside of [demoted, paused, suspended, elsewhere, otherTrade, optedOut]) {
        expect(reached.has(outside.provider.userId)).toBe(false);
      }
      expect(request.broadcastCount).toBe(reached.size);

      // Every recipient satisfies the whole rule, checked independently here.
      for (const userId of reached) {
        const profile = await prisma.providerProfile.findUniqueOrThrow({
          where: { userId },
          include: {
            listings: {
              where: {
                categoryId: s.category.id,
                isEmergency: true,
                status: 'published',
                visibility: 'active',
                deletedAt: null,
                serviceAreas: { some: { islandId: s.island.id, removedAt: null } },
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
      const dispatches = await prisma.pushDispatch.findMany({ where: { subjectId: request.id } });
      expect(dispatches.every((d) => d.urgency === 'emergency')).toBe(true);
    });

    it('shows the request in each eligible provider inbox, without an address or a number', async () => {
      const s = await scene();
      const request = await raise(s);
      const res = await inbox(s.origin.provider);
      const item = res
        .json<Envelope<EmergencyBroadcastDto[]>>()
        .data.find((i) => i.requestId === request.id);
      expect(item?.canOffer).toBe(true);
      // First name only (§Phase 3c's content rule), never the full name.
      const full = (
        await app.deps.prisma.user.findUniqueOrThrow({ where: { id: s.customer.userId } })
      ).fullName;
      expect(item?.customerFirstName).toBe(full.split(' ')[0]);
      // "Exact address is shared if the customer picks you."
      expect(res.body).not.toContain('Fehivina');
      expect(res.body).not.toMatch(/\+960|phone/i);
      // And nobody has a booking yet — a broadcast is not a booking.
      const theirs = await listBookings(app, s.origin.provider, '?role=provider');
      expect(theirs.bookings).toHaveLength(0);
    });

    it('records a pass, drops the request from that inbox and from a re-broadcast, and tells nobody', async () => {
      const s = await scene();
      const passer = await another(s.island);
      const offerer = await another(s.island);
      const request = await raise(s);

      const passed = await actOnRequest(app, passer.provider, request.id, 'pass');
      expect(passed.statusCode).toBe(200);
      expect(passed.json<Envelope<EmergencyBroadcastDto>>().data.passed).toBe(true);
      expect(
        await app.deps.prisma.emergencyPass.count({
          where: { requestId: request.id, providerProfileId: passer.providerProfileId },
        }),
      ).toBe(1);
      const list = (await inbox(passer.provider)).json<Envelope<EmergencyBroadcastDto[]>>().data;
      expect(list.map((i) => i.requestId)).not.toContain(request.id);

      // A re-broadcast after reject-all does not page them again.
      await offerOn(app, offerer.provider, request.id);
      clock.advance(seconds(90));
      const before = (await broadcastRecipients(request.id)).length;
      await respond(s.customer, request.id, { rejectAll: true });
      const round2 = await broadcastRecipients(request.id, before);
      expect(round2).not.toContain(passer.provider.userId);
      expect(round2).toContain(s.origin.provider.userId);
      // Nobody is told anything about a pass.
      expect(notifier.events.filter((e) => e.userId === s.customer.userId)).toHaveLength(0);
    });
  });

  // =========================================================================
  // 6–8. Offers coexist, collect for 90 seconds, three are shown, selection releases
  // =========================================================================

  describe('6. two simultaneous accepts both produce offers rather than one winner', () => {
    it('admits both, moves the status once, and shows the customer both', async () => {
      const s = await scene();
      const second = await another(s.island);
      const request = await raise(s);

      const [a, b] = await Promise.all([
        offerOn(app, s.origin.provider, request.id, 35_000, 30),
        offerOn(app, second.provider, request.id, 45_000, 15),
      ]);
      expect([a.statusCode, b.statusCode]).toEqual([200, 200]);
      expect(await app.deps.prisma.emergencyOffer.count({ where: { requestId: request.id } })).toBe(
        2,
      );

      const row = await app.deps.prisma.emergencyRequest.findUniqueOrThrow({
        where: { id: request.id },
      });
      expect(row.status).toBe('emergency_offered');
      // One collection window, opened by the first — not reset by the second.
      expect(row.offerCollectionClosesAt?.toISOString()).toBe(
        new Date(START.getTime() + seconds(90)).toISOString(),
      );

      clock.advance(seconds(90));
      const read = await readRequest(app, s.customer, request.id);
      expect(read.phase).toBe('choosing');
      expect(read.offers.map((o) => o.calloutFeeLaari)).toEqual([35_000, 45_000]);
    });

    it('refuses the same provider a second open offer', async () => {
      const s = await scene();
      const request = await raise(s);
      expect((await offerOn(app, s.origin.provider, request.id)).statusCode).toBe(200);
      const again = await offerOn(app, s.origin.provider, request.id, 10_000, 15);
      expect(again.statusCode).toBe(409);
      expect(errorCode(again)).toBe('EMERGENCY_OFFER_ALREADY_MADE');
    });
  });

  describe('7. a collection window closes at 90 seconds and presents at most three offers', () => {
    it('admits every offer, holds them back until 90 seconds, then shows the best three', async () => {
      const s = await scene();
      const [b, c, d] = [await another(s.island), await another(s.island), await another(s.island)];
      const request = await raise(s);

      // Every eligible provider may accept (§1c) — four offers, all admitted.
      expect((await offerOn(app, s.origin.provider, request.id, 60_000, 15)).statusCode).toBe(200);
      clock.advance(seconds(30));
      expect((await offerOn(app, b.provider, request.id, 30_000, 45)).statusCode).toBe(200);
      expect((await offerOn(app, c.provider, request.id, 40_000, 30)).statusCode).toBe(200);
      expect((await offerOn(app, d.provider, request.id, 30_000, 20)).statusCode).toBe(200);

      // One second short: collecting. The count shows, the offers do not, and
      // the customer cannot choose yet.
      clock.set(new Date(START.getTime() + seconds(89)));
      const during = await readRequest(app, s.customer, request.id);
      expect(during.phase).toBe('collecting');
      expect(during.offersReceived).toBe(4);
      expect(during.offers).toEqual([]);
      const early = await respond(s.customer, request.id, { rejectAll: true });
      expect(errorCode(early)).toBe('EMERGENCY_OFFERS_STILL_COLLECTING');

      // At 90: closed, four received, three shown — cheapest first, then the
      // soonest own estimate. The 60_000 one is not among them.
      clock.set(new Date(START.getTime() + seconds(90)));
      const after = await readRequest(app, s.customer, request.id);
      expect(after.phase).toBe('choosing');
      expect(after.offersReceived).toBe(4);
      expect(after.offers.map((o) => [o.calloutFeeLaari, o.etaMinutes])).toEqual([
        [30_000, 20],
        [30_000, 45],
        [40_000, 30],
      ]);
      expect(after.collectionClosesAt).toBe(new Date(START.getTime() + seconds(90)).toISOString());
      const late = await offerOn(app, (await another(s.island)).provider, request.id);
      expect(errorCode(late)).toBe('EMERGENCY_OFFERS_CLOSED');

      // An offer the customer was not shown cannot be selected…
      const hidden = await app.deps.prisma.emergencyOffer.findFirstOrThrow({
        where: { requestId: request.id, calloutFeeLaari: 60_000 },
      });
      expect(errorCode(await respond(s.customer, request.id, { offerId: hidden.id }))).toBe(
        'EMERGENCY_OFFER_NOT_FOUND',
      );
      // …and is released with the rest when one of the three is chosen.
      await respond(s.customer, request.id, { offerId: after.offers[0]?.id });
      const released = await app.deps.prisma.emergencyOffer.findUniqueOrThrow({
        where: { id: hidden.id },
      });
      expect(released.state).toBe('not_selected');
    });
  });

  describe('8. selecting one releases the others immediately', () => {
    it('marks the others not_selected in the same moment, and tells them', async () => {
      const s = await scene();
      const second = await another(s.island);
      const request = await raise(s);
      await offerOn(app, s.origin.provider, request.id, 35_000);
      await offerOn(app, second.provider, request.id, 45_000);
      clock.advance(seconds(90));

      const cheaper = (await readRequest(app, s.customer, request.id)).offers.find(
        (o) => o.calloutFeeLaari === 35_000,
      );
      await respond(s.customer, request.id, { offerId: cheaper?.id });

      const view = (await providerView(second.provider, request.id)).json<
        Envelope<EmergencyBroadcastDto>
      >().data;
      expect(view.myOffer?.state).toBe('not_selected');
      expect(view.canOffer).toBe(false);
      expect(notifier.for(request.id, 'emergency_offer_not_selected').map((e) => e.userId)).toEqual(
        [second.provider.userId],
      );
    });

    it('creates the booking at accepted against the chosen provider and their own listing', async () => {
      const s = await scene();
      const second = await another(s.island);
      const request = await raise(s);
      await offerOn(app, second.provider, request.id, 45_000, 15);
      clock.advance(seconds(90));
      const offer = (await readRequest(app, s.customer, request.id)).offers[0];
      const res = await respond(s.customer, request.id, { offerId: offer?.id });
      const after = res.json<Envelope<EmergencyRequestDto>>().data;
      expect(after.phase).toBe('matched');
      const booking = await readBooking(app, s.customer, after.bookingId ?? '');

      expect(booking.bookingMode).toBe('emergency');
      expect(booking.status).toBe('awaiting_payment');
      expect(booking.provider.userId).toBe(second.provider.userId);
      expect(booking.listingId).toBe(second.listingId);
      expect(booking.agreedAmountLaari).toBe(45_000);
      expect(booking.amountKind).toBe('callout_fee');
      expect(booking.emergency?.etaMinutes).toBe(15);
      // §1c: `scheduledFor` is the acceptance timestamp.
      expect(booking.scheduledFor).toBe(clock.clock().toISOString());
      expect(booking.statusHistory?.map((e) => e.transition)).toEqual([
        'select-offer',
        'amount-set',
      ]);
      // The chosen provider has it in their own bookings; the one not chosen has nothing.
      const theirs = await listBookings(app, second.provider, '?role=provider');
      expect(theirs.bookings.map((x) => x.id)).toContain(booking.id);
      const notTheirs = await listBookings(app, s.origin.provider, '?role=provider');
      expect(notTheirs.bookings).toHaveLength(0);
      expect(notifier.for(booking.id, 'emergency_offer_selected').map((e) => e.userId)).toEqual([
        second.provider.userId,
      ]);
    });

    it('lands all of it in one transaction — a failure after the claim leaves no booking, no fee and no claim', async () => {
      const s = await scene();
      const request = await raise(s);
      await offerOn(app, s.origin.provider, request.id);
      clock.advance(seconds(90));
      const offerId = (await readRequest(app, s.customer, request.id)).offers[0]?.id ?? '';

      const repo = (app.emergency as unknown as { repo: BookingRepository }).repo;
      const spy = vi.spyOn(repo, 'transition').mockImplementationOnce(() => {
        throw new Error('forced failure after the offer was claimed');
      });
      const res = await respond(s.customer, request.id, { offerId });
      expect(res.statusCode).toBe(500);
      // Reached — so the test is about a failure inside the transaction, not
      // one that never got there.
      expect(spy).toHaveBeenCalledTimes(1);

      const after = await app.deps.prisma.emergencyRequest.findUniqueOrThrow({
        where: { id: request.id },
      });
      expect(after.status).toBe('emergency_offered');
      expect(after.dispatchFeeSubmissionId).toBeNull();
      const offer = await app.deps.prisma.emergencyOffer.findUniqueOrThrow({
        where: { id: offerId },
      });
      expect(offer.state).toBe('open');
      expect(
        await app.deps.prisma.booking.count({ where: { emergencyRequestId: request.id } }),
      ).toBe(0);
      expect(
        await app.deps.prisma.paymentSubmission.count({
          where: { payerId: s.customer.userId, purpose: 'emergency_dispatch_fee' },
        }),
      ).toBe(0);
    });
  });

  // =========================================================================
  // 9–10. Reject-all, and the customer's silence
  // =========================================================================

  describe('9. reject-all re-broadcasts and never returns to any provider who offered', () => {
    it('excludes every offerer from the next broadcast and from offering again', async () => {
      const s = await scene();
      const second = await another(s.island);
      const third = await another(s.island);
      const request = await raise(s);
      await offerOn(app, s.origin.provider, request.id);
      await offerOn(app, second.provider, request.id);
      clock.advance(seconds(90));

      const before = (await broadcastRecipients(request.id)).length;
      const res = await respond(s.customer, request.id, { rejectAll: true });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<EmergencyRequestDto>>().data.status).toBe('requested');

      const round2 = await broadcastRecipients(request.id, before);
      expect(round2).toContain(third.provider.userId);
      expect(round2).not.toContain(s.origin.provider.userId);
      expect(round2).not.toContain(second.provider.userId);

      for (const p of [s.origin, second]) {
        expect((await offerOn(app, p.provider, request.id)).statusCode).not.toBe(200);
      }
      expect((await offerOn(app, third.provider, request.id)).statusCode).toBe(200);
      expect(notifier.for(request.id, 'emergency_offer_rejected')).toHaveLength(2);
    });
  });

  describe('10. unanswered offers expire 5 minutes after the window closes, without resetting the overall window', () => {
    it('releases them at 5 minutes and not a second before, and re-broadcasts to the same providers', async () => {
      const s = await scene();
      const request = await raise(s);
      await offerOn(app, s.origin.provider, request.id);
      const before = (await broadcastRecipients(request.id)).length;

      clock.set(new Date(START.getTime() + seconds(90) + minutes(5) - seconds(1)));
      await app.jobs.runOnce(EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readRequest(app, s.customer, request.id)).status).toBe('emergency_offered');

      clock.set(new Date(START.getTime() + seconds(90) + minutes(5)));
      await app.jobs.runOnce(EMERGENCY_OFFER_CHOICE_TIMEOUT_JOB_NAME, clock.clock());
      const after = await readRequest(app, s.customer, request.id);
      expect(after.status).toBe('requested');
      expect(after.windowEndsAt).toBe(request.windowEndsAt);

      const offer = await app.deps.prisma.emergencyOffer.findFirstOrThrow({
        where: { requestId: request.id },
      });
      expect(offer.state).toBe('expired');
      // Re-broadcast, and a silent customer is not a verdict on the provider.
      expect(await broadcastRecipients(request.id, before)).toContain(s.origin.provider.userId);
      expect((await offerOn(app, s.origin.provider, request.id)).statusCode).toBe(200);
    });
  });

  // =========================================================================
  // 11. The dispatch fee
  // =========================================================================

  describe('11. selecting incurs the MVR 200 fee, the job proceeds, and proof — not an admin — lifts the block', () => {
    it('runs the whole of §1c’s fee rule', async () => {
      const { customer, request, booking } = await matched();

      // Incurred at selection, owed, and the job went straight on.
      expect(booking.status).toBe('awaiting_payment');
      const fee = booking.emergency?.dispatchFee;
      expect(fee?.amountLaari).toBe(20_000);
      expect(fee?.state).toBe('owed');
      expect(request.dispatchFee?.submissionId).toBe(fee?.submissionId);

      // A new booking of any kind is refused while it is owed…
      const slot = await bookableListing(app);
      const blocked = await createBooking(app, customer, slot.listingId, {
        timeSlotId: slot.slotId,
      });
      expect(errorCode(blocked)).toBe('DISPATCH_FEE_OUTSTANDING');
      const req = await requestListing(app);
      const blockedRequest = await createBooking(app, customer, req.listingId, {
        preferredWindowChip: 'tomorrow_morning',
      });
      expect(errorCode(blockedRequest)).toBe('DISPATCH_FEE_OUTSTANDING');
      const blockedEmergency = await postEmergency(app, customer, {
        categoryId: request.categoryId,
        islandId: request.islandId,
        jobNotes: 'Another',
      });
      expect(errorCode(blockedEmergency)).toBe('DISPATCH_FEE_OUTSTANDING');

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

    it('re-blocks when the proof is rejected, and a fresh transfer is the way out — §0.0 item 24', async () => {
      const { customer, booking } = await matched();
      const feeId = booking.emergency?.dispatchFee?.submissionId ?? '';
      await submitFeeProof(customer, feeId);
      const slot = await bookableListing(app);
      // Submitted and pending: not blocked — the half of §1c that stands.
      const pendingBooking = await bookSlot(app, customer, slot.listingId, slot.slotId);
      await actOk(app, customer, pendingBooking.id, 'cancel');

      // The rejection path itself — §Phase 8a's, which §Phase 10a part 2's
      // panel will call (P17-6). No panel yet, so it is called directly.
      const admin = await app.adminAuth.createAdmin(
        `admin-${randomUUID()}@example.test`,
        'correct horse battery staple',
        {},
      );
      await app.subscriptions.rejectSubmission(feeId, admin.id, 'Reference does not match');

      const second = await bookableListing(app);
      expect(
        errorCode(
          await createBooking(app, customer, second.listingId, { timeSlotId: second.slotId }),
        ),
      ).toBe('DISPATCH_FEE_OUTSTANDING');

      // A fresh transfer: new reference, current fee, and still blocked until submitted.
      const retried = await app.inject({
        method: 'POST',
        url: `/v1/users/me/dispatch-fees/${feeId}/retry`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
      });
      expect(retried.statusCode).toBe(201);
      const fresh =
        retried.json<Envelope<{ id: string; referenceCode: string; state: string }>>().data;
      expect(fresh.id).not.toBe(feeId);
      expect(fresh.state).toBe('owed');
      expect(
        errorCode(
          await createBooking(app, customer, second.listingId, { timeSlotId: second.slotId }),
        ),
      ).toBe('DISPATCH_FEE_OUTSTANDING');
      await submitFeeProof(customer, fresh.id);
      await bookSlot(app, customer, second.listingId, second.slotId);

      // Only a rejected fee can be started again.
      const again = await app.inject({
        method: 'POST',
        url: `/v1/users/me/dispatch-fees/${fresh.id}/retry`,
        headers: { ...customer.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
      });
      expect(errorCode(again)).toBe('DISPATCH_FEE_NOT_REJECTED');
    });

    it('charges nothing for a request nobody answered', async () => {
      const s = await scene();
      const request = await raise(s);
      clock.advance(minutes(s.category.windowMinutes));
      await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
      expect((await readRequest(app, s.customer, request.id)).status).toBe('declined');
      expect(
        await app.deps.prisma.paymentSubmission.count({ where: { payerId: s.customer.userId } }),
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
    it('refuses before the window, then closes the booking on their record and re-broadcasts', async () => {
      const { island, origin, customer, request, booking } = await matched();
      const window = (await category('Plumbing')).windowMinutes;
      const feeId = booking.emergency?.dispatchFee?.submissionId;
      const replacement = await another(island);

      clock.advance(minutes(window) - seconds(1));
      const early = await act(app, customer, booking.id, 'provider-not-arrived');
      expect(errorCode(early)).toBe('EMERGENCY_NOT_ARRIVED_TOO_EARLY');

      clock.advance(seconds(2));
      const before = (await broadcastRecipients(request.id)).length;
      const res = await act(app, customer, booking.id, 'provider-not-arrived');
      expect(res.statusCode).toBe(200);
      const reopened = res.json<Envelope<EmergencyRequestDto>>().data;
      expect(reopened.status).toBe('requested');
      // A fresh answer window, read from the category — the original was spent.
      expect(reopened.windowEndsAt).toBe(
        new Date(clock.clock().getTime() + minutes(window)).toISOString(),
      );

      // The no-show stays on that provider's own booking and offer.
      const closed = await readBooking(app, customer, booking.id);
      expect(closed.status).toBe('cancelled');
      expect(closed.statusHistory?.at(-1)?.transition).toBe('provider-not-arrived');
      const offer = await app.deps.prisma.emergencyOffer.findUniqueOrThrow({
        where: { bookingId: booking.id },
      });
      expect(offer.state).toBe('no_show');
      expect(offer.providerProfileId).toBe(origin.providerProfileId);

      const round2 = await broadcastRecipients(request.id, before);
      expect(round2).toContain(replacement.provider.userId);
      expect(round2).not.toContain(origin.provider.userId);
      expect((await offerOn(app, origin.provider, request.id)).statusCode).not.toBe(200);

      // The replacement is chosen: a new booking, the same one fee.
      await offerOn(app, replacement.provider, request.id);
      clock.advance(seconds(90));
      const offerId = (await readRequest(app, customer, request.id)).offers[0]?.id;
      const chosen = (await respond(customer, request.id, { offerId })).json<
        Envelope<EmergencyRequestDto>
      >().data;
      expect(chosen.bookingId).not.toBe(booking.id);
      expect(chosen.dispatchFee?.submissionId).toBe(feeId);
      expect(
        await app.deps.prisma.paymentSubmission.count({
          where: { payerId: customer.userId, purpose: 'emergency_dispatch_fee' },
        }),
      ).toBe(1);
    });

    it('re-broadcasts on the chosen provider cancelling too — §1h, never a dead end', async () => {
      const { island, origin, customer, request, booking } = await matched();
      const replacement = await another(island);
      const before = (await broadcastRecipients(request.id)).length;
      const res = await act(app, origin.provider, booking.id, 'cancel', {
        reason: 'Van broke down',
      });
      expect(res.statusCode).toBe(200);
      const cancelled = await readBooking(app, customer, booking.id);
      expect(cancelled.status).toBe('cancelled');
      // §1f's row: a provider cancellation after accepted.
      expect(cancelled.cancelledByRole).toBe('provider');
      expect((await readRequest(app, customer, request.id)).status).toBe('requested');
      const round2 = await broadcastRecipients(request.id, before);
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
      const request = await raise(electrical);
      const refused = await offerOn(app, silver.provider, request.id);
      expect(refused.statusCode).toBe(422);
      expect(errorCode(refused)).toBe('EMERGENCY_TIER_NOT_MET');
      expect((await offerOn(app, electrical.origin.provider, request.id)).statusCode).toBe(200);

      const ac = await scene('AC Repair', 'silver');
      const acRequest = await raise(ac);
      expect((await offerOn(app, ac.origin.provider, acRequest.id)).statusCode).toBe(200);
    });
  });

  // =========================================================================
  // 14 and 17. The answer window, per category
  // =========================================================================

  describe('14. the request window expires at 30 minutes for Moving exactly as for Plumbing, and offers carry an arrival estimate', () => {
    for (const name of ['Moving', 'Plumbing']) {
      it(`${name}: open a minute before the category window, declined at it`, async () => {
        const s = await scene(name, name === 'Moving' ? 'silver' : 'gold');
        expect(s.category.windowMinutes).toBe(30);
        const request = await raise(s);
        expect(request.windowEndsAt).toBe(
          new Date(START.getTime() + minutes(s.category.windowMinutes)).toISOString(),
        );

        clock.advance(minutes(s.category.windowMinutes - 1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readRequest(app, s.customer, request.id)).status).toBe('requested');

        clock.advance(minutes(1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        const after = await readRequest(app, s.customer, request.id);
        expect(after.status).toBe('declined');
        expect(after.phase).toBe('closed');
        expect(notifier.for(request.id, 'emergency_window_expired')).toHaveLength(1);
      });
    }

    it('stores each offer’s own arrival estimate and shows it to the customer', async () => {
      const s = await scene('Moving', 'silver');
      const request = await raise(s);
      const eta = s.category.emergencyEtaPresetsMinutes.at(-1) ?? 120;
      await offerOn(app, s.origin.provider, request.id, 60_000, eta);
      clock.advance(seconds(90));
      expect((await readRequest(app, s.customer, request.id)).offers[0]?.etaMinutes).toBe(eta);
      const view = (await providerView(s.origin.provider, request.id)).json<
        Envelope<EmergencyBroadcastDto>
      >().data;
      expect(view.etaPresetsMinutes).toEqual(s.category.emergencyEtaPresetsMinutes);
    });

    it('refuses an offer with no arrival estimate', async () => {
      const s = await scene();
      const request = await raise(s);
      const res = await actOnRequest(app, s.origin.provider, request.id, 'emergency-accept', {
        calloutFeeLaari: 30_000,
      });
      expect(res.statusCode).toBe(400);
    });
  });

  describe('17. the emergency requested window auto-declines at the category’s emergencyAcceptWindowMinutes', () => {
    it('follows the column, not a constant — a changed window moves the deadline for the next request', async () => {
      const prisma = app.deps.prisma;
      const s = await scene();
      const window = s.category.windowMinutes;
      try {
        await prisma.category.update({
          where: { id: s.category.id },
          data: { emergencyAcceptWindowMinutes: window + 7 },
        });
        const request = await raise(s);
        clock.advance(minutes(window + 1));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readRequest(app, s.customer, request.id)).status).toBe('requested');
        clock.advance(minutes(6));
        await app.jobs.runOnce(EMERGENCY_WINDOW_TIMEOUT_JOB_NAME, clock.clock());
        expect((await readRequest(app, s.customer, request.id)).status).toBe('declined');
      } finally {
        await prisma.category.update({
          where: { id: s.category.id },
          data: { emergencyAcceptWindowMinutes: window },
        });
      }
    });

    it('does not reset on a rejection — the window governs the whole request', async () => {
      const s = await scene();
      const other = await another(s.island);
      const request = await raise(s);
      await offerOn(app, other.provider, request.id);
      clock.advance(seconds(90));
      const rejected = (await respond(s.customer, request.id, { rejectAll: true })).json<
        Envelope<EmergencyRequestDto>
      >().data;
      expect(rejected.windowEndsAt).toBe(request.windowEndsAt);
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
      const passer = await another(s.island);
      const request = await raise(s);
      const numbers = (
        await app.deps.prisma.user.findMany({
          where: {
            id: {
              in: [
                s.customer.userId,
                s.origin.provider.userId,
                second.provider.userId,
                passer.provider.userId,
              ],
            },
          },
          select: { phoneE164: true },
        })
      )
        .map((u) => u.phoneE164)
        .filter((p): p is string => p !== null);
      expect(numbers.length).toBe(4);

      const bodies: { label: string; body: string }[] = [];
      const push = (label: string, res: { body: string }) => bodies.push({ label, body: res.body });
      const get = (user: RegisteredUser, url: string) =>
        app.inject({ method: 'GET', url, headers: user.headers, remoteAddress: freshIp() });

      push('create', { body: JSON.stringify(request) });
      push('offer', await offerOn(app, s.origin.provider, request.id, 30_000));
      push('offer 2', await offerOn(app, second.provider, request.id, 40_000));
      push('pass', await actOnRequest(app, passer.provider, request.id, 'pass'));
      push('inbox', await inbox(second.provider));
      push('inbox item', await providerView(second.provider, request.id));
      push('my requests', await get(s.customer, '/v1/users/me/emergency-requests'));
      clock.advance(seconds(90));
      push('request, choosing', await get(s.customer, `/v1/emergency-requests/${request.id}`));
      const offerId = (await readRequest(app, s.customer, request.id)).offers[0]?.id;
      const selected = await respond(s.customer, request.id, { offerId });
      push('select', selected);
      const bookingId = selected.json<Envelope<EmergencyRequestDto>>().data.bookingId ?? '';
      push('booking, customer', await get(s.customer, `/v1/bookings/${bookingId}`));
      push('booking, provider', await get(s.origin.provider, `/v1/bookings/${bookingId}`));
      push('dispatch fees', await get(s.customer, '/v1/users/me/dispatch-fees'));
      clock.advance(minutes(60));
      push('not arrived', await act(app, s.customer, bookingId, 'provider-not-arrived'));
      push('cancel request', await actOnRequest(app, s.customer, request.id, 'cancel'));

      expect(bodies.every((b) => b.body.length > 2)).toBe(true);
      for (const { label, body } of bodies) {
        for (const n of numbers) expect(body, label).not.toContain(n);
        expect(body, label).not.toMatch(
          /"[a-zA-Z]*(phone|mobile|whatsapp|viber|msisdn)[a-zA-Z]*"\s*:/i,
        );
      }
    });
  });
});
