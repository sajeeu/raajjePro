import { randomUUID } from 'node:crypto';

import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { ownSlots } from './helpers/availability.js';
import {
  acceptedBooking,
  actOk,
  bookableListing,
  bookSlot,
  errorCode,
  readBooking,
} from './helpers/bookings.js';
import type { RegisteredUser } from './helpers/users.js';

/**
 * §1h — the locked agreement.
 *
 * "At `accepted`, the agreed price, date, time and scope are locked. Neither
 * party can alter them unilaterally. Any change requires an explicit in-app
 * amendment the other party accepts. The original terms and the amendment are
 * both retained. **Every amendment attempt is recorded, accepted or not**, and
 * feeds price adherence."
 *
 * **This is what "payment hold" means here** (invariant 12). Nothing below
 * holds money, and no test asserts that anything does — the immovability of
 * the agreement is the entire mechanism.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — §1h, the locked agreement', () => {
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

  function propose(user: RegisteredUser, bookingId: string, body: Record<string, unknown>) {
    return app.inject({
      method: 'POST',
      url: `/v1/bookings/${bookingId}/amendments`,
      headers: { ...user.headers, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      payload: body,
    });
  }

  /** The amendment a proposal just created — always the newest, so always first. */
  function amendmentIdOf(res: { body: string }): string {
    const body = JSON.parse(res.body) as { data: { amendments: { id: string }[] } };
    const id = body.data.amendments[0]?.id;
    if (id === undefined) throw new Error(`no amendment in response: ${res.body}`);
    return id;
  }

  function respond(user: RegisteredUser, bookingId: string, amendmentId: string, accept: boolean) {
    return app.inject({
      method: 'PATCH',
      url: `/v1/bookings/${bookingId}/amendments/${amendmentId}`,
      headers: user.headers,
      remoteAddress: freshIp(),
      payload: { accept },
    });
  }

  it('records the attempt on proposal, with the original terms beside the proposed ones', async () => {
    const { provider, customer, booking } = await acceptedBooking(app);
    const originalAmount = booking.agreedAmountLaari;

    const res = await propose(provider, booking.id, {
      amountLaari: (originalAmount ?? 0) + 5000,
      reason: 'The job needs a second cleaner',
    });

    expect(res.statusCode).toBe(201);
    const view = await readBooking(app, customer, booking.id);
    expect(view.amendments).toHaveLength(1);
    const amendment = view.amendments[0];
    expect(amendment?.status).toBe('proposed');
    expect(amendment?.previousAmountLaari).toBe(originalAmount);
    expect(amendment?.proposedAmountLaari).toBe((originalAmount ?? 0) + 5000);
    // Unilateral change is exactly what this prevents: the live terms have
    // not moved.
    expect(view.agreedAmountLaari).toBe(originalAmount);
  });

  it('keeps a rejected attempt on the record — §1f counts proposals, not survivors', async () => {
    const { provider, customer, booking } = await acceptedBooking(app);
    const original = booking.agreedAmountLaari ?? 0;
    const proposed = await propose(provider, booking.id, { amountLaari: original + 9000 });
    const amendmentId = amendmentIdOf(proposed);

    const answered = await respond(customer, booking.id, amendmentId, false);

    expect(answered.statusCode).toBe(200);
    const view = await readBooking(app, customer, booking.id);
    expect(view.amendments[0]?.status).toBe('rejected');
    expect(view.amendments[0]?.proposedAmountLaari).toBe(original + 9000);
    expect(view.agreedAmountLaari).toBe(original);
  });

  it('moves the live terms only when the counterparty accepts', async () => {
    const { provider, customer, booking } = await acceptedBooking(app);
    const original = booking.agreedAmountLaari ?? 0;
    const proposed = await propose(provider, booking.id, { amountLaari: original + 2500 });
    const amendmentId = amendmentIdOf(proposed);

    await respond(customer, booking.id, amendmentId, true);

    const view = await readBooking(app, customer, booking.id);
    expect(view.agreedAmountLaari).toBe(original + 2500);
    expect(view.amendments[0]?.status).toBe('accepted');
    // The original is still readable — "the original terms and the amendment
    // are both retained".
    expect(view.amendments[0]?.previousAmountLaari).toBe(original);
  });

  it('refuses the proposer accepting their own proposal', async () => {
    const { provider, booking } = await acceptedBooking(app);
    const proposed = await propose(provider, booking.id, {
      amountLaari: (booking.agreedAmountLaari ?? 0) + 1000,
    });
    const amendmentId = amendmentIdOf(proposed);

    const res = await respond(provider, booking.id, amendmentId, true);

    expect(res.statusCode).toBe(422);
    expect(errorCode(res)).toBe('AMENDMENT_NEEDS_THE_OTHER_PARTY');
  });

  it('refuses an amendment that changes nothing', async () => {
    const { provider, booking } = await acceptedBooking(app);

    const res = await propose(provider, booking.id, { reason: 'just checking in' });

    expect(res.statusCode).toBe(422);
    expect(errorCode(res)).toBe('AMENDMENT_CHANGES_NOTHING');
  });

  it('refuses a second open proposal', async () => {
    const { provider, booking } = await acceptedBooking(app);
    await propose(provider, booking.id, { amountLaari: 12345 });

    const res = await propose(provider, booking.id, { amountLaari: 23456 });

    expect(res.statusCode).toBe(409);
    expect(errorCode(res)).toBe('AMENDMENT_ALREADY_OPEN');
  });

  it('refuses an amendment before there is an agreement to amend', async () => {
    const { customer, listingId, slotId, provider } = await bookableListing(app);
    const booking = await bookSlot(app, customer, listingId, slotId);

    const res = await propose(provider, booking.id, { amountLaari: 1000 });

    expect(res.statusCode).toBe(422);
    expect(errorCode(res)).toBe('BOOKING_NOT_AMENDABLE');
  });

  it('moves the reservation with the time, in one transaction, and frees the old slot', async () => {
    const { provider, customer, booking, listingId, slotId } = await acceptedBooking(app);
    const newTime = new Date(new Date(booking.scheduledFor ?? START).getTime() + 3 * 60 * 60_000);

    const proposed = await propose(provider, booking.id, {
      scheduledFor: newTime.toISOString(),
      reason: 'Earlier job overran',
    });
    const amendmentId = amendmentIdOf(proposed);
    await respond(customer, booking.id, amendmentId, true);

    const view = await readBooking(app, customer, booking.id);
    expect(new Date(view.scheduledFor ?? '').toISOString()).toBe(newTime.toISOString());
    // The published slot went back to the grid — the booking no longer sits
    // on one, it sits on a time the two parties agreed.
    expect(view.timeSlotId).toBeNull();
    const slots = await ownSlots(app, provider, listingId);
    expect(slots.find((s) => s.id === slotId)?.status).toBe('open');

    // Exactly one live hold, at the new time — never both the old and the new,
    // which is what "in the same transaction" buys.
    const live = await app.deps.prisma.reservation.count({
      where: {
        listingId,
        releasedAt: null,
        startsAt: newTime,
      },
    });
    expect(live).toBe(1);
  });

  it('lets the proposer withdraw, and keeps the row', async () => {
    const { provider, customer, booking } = await acceptedBooking(app);
    const proposed = await propose(provider, booking.id, { amountLaari: 4321 });
    const amendmentId = amendmentIdOf(proposed);

    const res = await app.inject({
      method: 'DELETE',
      url: `/v1/bookings/${booking.id}/amendments/${amendmentId}`,
      headers: provider.headers,
      remoteAddress: freshIp(),
    });

    expect(res.statusCode).toBe(200);
    const view = await readBooking(app, customer, booking.id);
    expect(view.amendments).toHaveLength(1);
    expect(view.amendments[0]?.status).toBe('withdrawn');
  });

  it('records a final amount above the agreed one rather than refusing it', async () => {
    const { provider, customer, booking } = await acceptedBooking(app);
    await actOk(app, customer, booking.id, 'claim-payment');
    await actOk(app, provider, booking.id, 'confirm-payment-received');

    const completed = await actOk(app, provider, booking.id, 'complete', {
      finalAmountLaari: (booking.agreedAmountLaari ?? 0) + 7500,
    });

    // §1h makes this "a price-adherence failure… visible on the profile as
    // one" — a number §Phase 11 computes, never an error this endpoint throws.
    expect(completed.status).toBe('completed');
    expect(completed.finalAmountLaari).toBe((booking.agreedAmountLaari ?? 0) + 7500);
  });
});
