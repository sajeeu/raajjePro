import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { BOOKING_PAYMENT_SILENCE_JOB_NAME } from '../src/jobs/booking-lifecycle.js';
import { buildTestApp, controllableClock, databaseUrl } from './helpers/app.js';
import { act, acceptedBooking, actOk, errorCode, readBooking } from './helpers/bookings.js';

const DAY = 24 * 60 * 60_000;

/**
 * §1c's payment attestation, end to end.
 *
 * **This is two humans saying what they did, not a verification.** Nothing in
 * this system can see a bank transfer, so every assertion below is about what
 * was *recorded*, never about what was *checked* — and the tests that matter
 * most are the ones asserting that nothing further is unlocked.
 *
 * It is a different mechanism from `PaymentSubmission`, which is RaajjePro's
 * own subscription money and does have an admin confirming it. Nothing here
 * touches that table, which is itself asserted below.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — payment attestation', () => {
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

  describe('the happy path', () => {
    it('claims, confirms and completes, keeping every transition in the history', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);

      const claimed = await actOk(app, customer, booking.id, 'claim-payment');
      expect(claimed.status).toBe('payment_claimed');
      expect(claimed.paymentClaimedAt).not.toBeNull();

      const confirmed = await actOk(app, provider, booking.id, 'confirm-payment-received');
      expect(confirmed.status).toBe('confirmed');
      expect(confirmed.paymentAttestedAt).not.toBeNull();

      const completed = await actOk(app, provider, booking.id, 'complete');
      expect(completed.status).toBe('completed');
      expect(completed.completedVia).toBe('confirmed');

      const detail = await readBooking(app, customer, booking.id);
      expect((detail.statusHistory ?? []).map((e) => e.transition)).toEqual([
        'create',
        'accept',
        'amount-set',
        'claim-payment',
        'confirm-payment-received',
        'complete',
      ]);
    });

    it('files nothing into PaymentSubmission — that table is subscriptions only', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      const before = await app.deps.prisma.paymentSubmission.count();

      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');

      expect(await app.deps.prisma.paymentSubmission.count()).toBe(before);
    });

    it('fires §Phase 8a’s trial hook on the transition into confirmed, once', async () => {
      const { customer, provider, booking, providerProfileId } = await acceptedBooking(app);

      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { trialHookFiredAt: true },
      });
      expect(row.trialHookFiredAt).not.toBeNull();

      // §Phase 8a's own rule: the first confirmed booking starts the trial.
      const subscription = await app.deps.prisma.providerSubscription.findFirst({
        where: { providerProfileId },
        select: { status: true, trialStartedAt: true },
      });
      expect(subscription?.trialStartedAt).not.toBeNull();
    });
  });

  describe('withdrawing a claim — Round 24', () => {
    it('returns the booking to awaiting_payment and keeps both transitions visible', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      const withdrawn = await actOk(app, customer, booking.id, 'withdraw-payment-claim');

      expect(withdrawn.status).toBe('awaiting_payment');
      expect(withdrawn.paymentClaimedAt).toBeNull();
      expect(withdrawn.paymentClaimWithdrawnAt).not.toBeNull();

      const detail = await readBooking(app, customer, booking.id);
      const transitions = (detail.statusHistory ?? []).map((e) => e.transition);
      expect(transitions).toContain('claim-payment');
      expect(transitions).toContain('withdraw-payment-claim');
    });

    it('files no Report — a withdrawal is not a dispute (§1f, Round 24)', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      await actOk(app, customer, booking.id, 'withdraw-payment-claim');

      const reports = await app.deps.prisma.report.count({ where: { bookingId: booking.id } });
      expect(reports).toBe(0);
    });

    it('is rejected once the provider has confirmed', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'confirm-payment-received');

      const res = await act(app, customer, booking.id, 'withdraw-payment-claim');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_TRANSITION_NOT_ALLOWED');
    });

    it('is rejected once the provider has disputed', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, provider, booking.id, 'dispute', { reason: 'payment_dispute' });

      const res = await act(app, customer, booking.id, 'withdraw-payment-claim');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_TRANSITION_NOT_ALLOWED');
    });

    it('is rejected on a second attempt — once per booking, never a toggle', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, customer, booking.id, 'withdraw-payment-claim');
      await actOk(app, customer, booking.id, 'claim-payment');

      const res = await act(app, customer, booking.id, 'withdraw-payment-claim');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('PAYMENT_CLAIM_ALREADY_WITHDRAWN');
    });

    it('is rejected while the booking is still awaiting payment', async () => {
      const { customer, booking } = await acceptedBooking(app);

      const res = await act(app, customer, booking.id, 'withdraw-payment-claim');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_TRANSITION_NOT_ALLOWED');
    });

    it('is not the provider’s to call', async () => {
      const { customer, provider, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      const res = await act(app, provider, booking.id, 'withdraw-payment-claim');

      expect(res.statusCode).toBe(422);
      expect(errorCode(res)).toBe('BOOKING_ACTOR_NOT_ALLOWED');
    });
  });

  describe('seven days of provider silence — §1c step 9', () => {
    it('escalates to payment_unresolved, not confirmed, and unlocks nothing', async () => {
      const { customer, booking, providerProfileId } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      clock.advance(7 * DAY + 60_000);
      const ran = await app.jobs.runOnce(BOOKING_PAYMENT_SILENCE_JOB_NAME, clock.clock());
      expect(ran).toBe('ran');

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { status: true, trialHookFiredAt: true, paymentAttestedAt: true },
      });
      expect(row.status).toBe('payment_unresolved');
      // "Nothing further is unlocked by this transition."
      expect(row.trialHookFiredAt).toBeNull();
      expect(row.paymentAttestedAt).toBeNull();
      const subscription = await app.deps.prisma.providerSubscription.findFirst({
        where: { providerProfileId },
        select: { trialStartedAt: true },
      });
      expect(subscription?.trialStartedAt ?? null).toBeNull();
    });

    it('files a Report with the system as reporter, not a person', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      clock.advance(7 * DAY + 60_000);
      await app.jobs.runOnce(BOOKING_PAYMENT_SILENCE_JOB_NAME, clock.clock());

      const report = await app.deps.prisma.report.findFirstOrThrow({
        where: { bookingId: booking.id },
      });
      expect(report.reporterId).toBeNull();
      expect(report.targetType).toBe('booking');
      expect(report.reason).toBe('payment_dispute');
      expect(report.status).toBe('open');
    });

    it('leaves a claim younger than seven days alone', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');

      clock.advance(6 * DAY);
      await app.jobs.runOnce(BOOKING_PAYMENT_SILENCE_JOB_NAME, clock.clock());

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { status: true },
      });
      expect(row.status).toBe('payment_claimed');
    });

    it('does not escalate a claim the customer withdrew', async () => {
      const { customer, booking } = await acceptedBooking(app);
      await actOk(app, customer, booking.id, 'claim-payment');
      await actOk(app, customer, booking.id, 'withdraw-payment-claim');

      clock.advance(7 * DAY + 60_000);
      await app.jobs.runOnce(BOOKING_PAYMENT_SILENCE_JOB_NAME, clock.clock());

      const row = await app.deps.prisma.booking.findUniqueOrThrow({
        where: { id: booking.id },
        select: { status: true },
      });
      expect(row.status).toBe('awaiting_payment');
    });
  });
});
