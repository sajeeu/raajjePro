import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { BILLING_PERIOD_DAYS, addDays } from '../src/modules/subscriptions/period.js';
import type {
  PaymentSubmissionDto,
  UpgradeRequestDto,
} from '../src/modules/subscriptions/types.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { createEnrolledAdmin } from './helpers/admin.js';
import { ensureIslandsSeeded } from './helpers/islands.js';
import { ensureCategoriesSeeded } from './helpers/listings.js';
import {
  SUBSCRIPTION,
  adminDecide,
  confirmPayment,
  post,
  readStatus,
  submitPayment,
} from './helpers/subscriptions.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface ErrorEnvelope {
  error: { code: string; message: string; details?: unknown };
}

/**
 * The backend §Phase 10a part 1 stands on, beyond what §Phase 8a built:
 *
 *   - §1b step 5's **appeal for re-review**, as a stamp on the rejected row
 *     (closing ledger row P8A-1). It changes no status and grants nothing.
 *   - the **period a payment would buy** on the upgrade request, so the pay
 *     screen prints the same dates the invoice will carry (invariant 4: the
 *     anchor rule lives here, never in Flutter).
 *
 * The Done-when lines this backs — "a provider submits with proof and sees
 * pending" and "a rejection surfaces its reason with working resubmit and
 * appeal" — are asserted end to end in the Flutter suite against these
 * responses; here the rule itself is asserted.
 */
describe.skipIf(databaseUrl === undefined)('§Phase 10a part 1 — appeal and period quote', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let admin: Awaited<ReturnType<typeof createEnrolledAdmin>>;
  const time = controllableClock(new Date('2026-09-15T08:00:00.000Z'));

  beforeAll(async () => {
    ({ app } = await buildTestApp({ clock: time.clock }));
    await ensureCategoriesSeeded(app.deps.prisma);
    await ensureIslandsSeeded(app.deps.prisma);
    admin = await createEnrolledAdmin(app);
  });

  afterAll(async () => {
    await app.close();
  });

  async function provider() {
    const user = await registerUser(app, { role: 'provider' });
    const profile = await app.providers.getOrCreateProviderProfile(user.userId);
    return { ...user, profileId: profile.id };
  }

  function appeal(headers: Record<string, string>, id: string, note?: string) {
    return app.inject({
      method: 'POST',
      url: `/v1/providers/me/payment-submissions/${id}/appeal`,
      headers: { ...headers, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      ...(note === undefined ? {} : { payload: { note } }),
    });
  }

  async function rejected(headers: Record<string, string>): Promise<PaymentSubmissionDto> {
    const submission = await submitPayment(app, headers);
    const res = await adminDecide(app, admin.cookie, submission.id, 'reject', {
      reason: 'The receipt shows MVR 57, and the period costs MVR 75',
    });
    expect(res.statusCode).toBe(200);
    return submission;
  }

  // -------------------------------------------------------------------------

  describe('an appeal is a re-review request on the rejected row', () => {
    it('stamps the row, keeps it rejected, grants nothing, and is audit-logged as the provider', async () => {
      const p = await provider();
      const submission = await rejected(p.headers);

      const res = await appeal(
        p.headers,
        submission.id,
        'The bank took MVR 75 — see the second line',
      );
      expect(res.statusCode).toBe(200);
      const dto = res.json<Envelope<PaymentSubmissionDto>>().data;
      // §1b step 5: the provider asked for the *same* submission to be read
      // again. The status is unchanged — an appeal is not a state a payment
      // sits in (P8A-1) — and the reason they are appealing stays visible.
      expect(dto.status).toBe('rejected');
      expect(dto.appealedAt).not.toBeNull();
      expect(dto.appealNote).toBe('The bank took MVR 75 — see the second line');
      expect(dto.rejectionReason).toBe('The receipt shows MVR 57, and the period costs MVR 75');

      // Nothing is granted by asking: the entitlement is exactly what a
      // rejection leaves (§1b: "nothing is granted on submission", and an
      // appeal is less than a submission).
      const status = await readStatus(app, p.headers);
      expect(status.tier).toBe('free');
      expect(status.latestSubmission?.appealedAt).toBe(dto.appealedAt);

      const entry = await app.deps.prisma.auditLogEntry.findFirst({
        where: { action: 'payment_submission.appealed', targetId: submission.id },
      });
      expect(entry?.actorType).toBe('user');
      expect(entry?.actorId).toBe(p.userId);
      // Metadata carries ids, enums and amounts only — never the note (root
      // CLAUDE.md 1d).
      expect(JSON.stringify(entry?.metadata)).not.toContain('second line');
    });

    it('is complete without a note', async () => {
      const p = await provider();
      const submission = await rejected(p.headers);
      const res = await appeal(p.headers, submission.id);
      expect(res.statusCode).toBe(200);
      const dto = res.json<Envelope<PaymentSubmissionDto>>().data;
      expect(dto.appealedAt).not.toBeNull();
      expect(dto.appealNote).toBeNull();
    });

    it('is refused a second time, and refused on a pending or confirmed submission', async () => {
      const p = await provider();
      const submission = await rejected(p.headers);
      expect((await appeal(p.headers, submission.id)).statusCode).toBe(200);

      const again = await appeal(p.headers, submission.id, 'once more');
      expect(again.statusCode).toBe(422);
      expect(again.json<ErrorEnvelope>().error.code).toBe('PAYMENT_APPEAL_ALREADY_FILED');
      // The first note survives the refused second attempt.
      const status = await readStatus(app, p.headers);
      expect(status.latestSubmission?.appealNote).toBeNull();

      const q = await provider();
      const pending = await submitPayment(app, q.headers);
      const early = await appeal(q.headers, pending.id);
      expect(early.statusCode).toBe(422);
      expect(early.json<ErrorEnvelope>().error.code).toBe('PAYMENT_SUBMISSION_NOT_REJECTED');

      await confirmPayment(app, admin.cookie, pending.id);
      const late = await appeal(q.headers, pending.id);
      expect(late.statusCode).toBe(422);
      expect(late.json<ErrorEnvelope>().error.code).toBe('PAYMENT_SUBMISSION_NOT_REJECTED');
    });

    it('answers not-found for somebody else’s submission, so ids cannot be probed', async () => {
      const owner = await provider();
      const submission = await rejected(owner.headers);
      const stranger = await provider();
      const res = await appeal(stranger.headers, submission.id, 'not mine');
      expect(res.statusCode).toBe(404);
      const row = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: submission.id },
      });
      expect(row.appealedAt).toBeNull();
    });

    it('a reversed payment lands rejected and is appealable', async () => {
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      const reversed = await adminDecide(app, admin.cookie, submission.id, 'reverse', {
        reason: 'Bank reversed the transfer three days later',
      });
      expect(reversed.statusCode).toBe(200);

      const res = await appeal(p.headers, submission.id, 'My bank says the transfer stood');
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<PaymentSubmissionDto>>().data.reversedAt).not.toBeNull();
    });

    it('a resubmission after an appeal is a new intent and leaves the appealed row alone', async () => {
      // §1b step 5's two actions are independent: appealing does not stop
      // the provider paying again properly, and paying again does not
      // withdraw the appeal — the admin sees both.
      const p = await provider();
      const submission = await rejected(p.headers);
      expect((await appeal(p.headers, submission.id)).statusCode).toBe(200);
      const fresh = await submitPayment(app, p.headers);
      expect(fresh.id).not.toBe(submission.id);
      expect(fresh.status).toBe('pending');
      expect(fresh.appealedAt).toBeNull();
      const old = await app.deps.prisma.paymentSubmission.findUniqueOrThrow({
        where: { id: submission.id },
      });
      expect(old.status).toBe('rejected');
      expect(old.appealedAt).not.toBeNull();
    });

    it('replays the original result on the same idempotency key', async () => {
      const p = await provider();
      const submission = await rejected(p.headers);
      const key = randomUUID();
      const send = () =>
        app.inject({
          method: 'POST',
          url: `/v1/providers/me/payment-submissions/${submission.id}/appeal`,
          headers: { ...p.headers, 'idempotency-key': key },
          remoteAddress: freshIp(),
          payload: { note: 'double tap' },
        });
      const first = await send();
      const second = await send();
      expect(first.statusCode).toBe(200);
      expect(second.statusCode).toBe(200);
      expect(second.json()).toEqual(first.json());
    });
  });

  // -------------------------------------------------------------------------

  describe('the upgrade request quotes the period the payment would buy', () => {
    it('runs 30 days from now for a provider with no clock', async () => {
      const p = await provider();
      const res = await post(app, p.headers, `${SUBSCRIPTION}/upgrade-request`);
      expect(res.statusCode).toBe(201);
      const { period } = res.json<Envelope<UpgradeRequestDto>>().data;
      const now = time.clock();
      expect(new Date(period.start).getTime()).toBe(now.getTime());
      expect(new Date(period.end).getTime()).toBe(addDays(now, BILLING_PERIOD_DAYS).getTime());
    });

    it('runs from the current period end for an active subscriber, and matches the invoice', async () => {
      // §1b: 30 days from the anchor, never a calendar month. A provider
      // paying early keeps the days they already have, so the quoted period
      // starts where the current one ends — and the invoice the confirmation
      // writes must say the same thing, or the screen lied.
      const p = await provider();
      const first = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, first.id);
      const status = await readStatus(app, p.headers);
      const currentEnd = status.billing.currentPeriodEnd;
      expect(currentEnd).not.toBeNull();

      const res = await post(app, p.headers, `${SUBSCRIPTION}/upgrade-request`);
      const { period, submission } = res.json<Envelope<UpgradeRequestDto>>().data;
      expect(period.start).toBe(currentEnd);
      expect(new Date(period.end).getTime()).toBe(
        addDays(new Date(currentEnd ?? ''), BILLING_PERIOD_DAYS).getTime(),
      );

      // Then pay it: the invoice carries the quoted period.
      const target = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/payment-submissions/${submission.id}/proof`,
        headers: { ...p.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { contentType: 'image/jpeg' },
      });
      expect(target.statusCode).toBe(201);
      const second = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, second.id);
      const invoice = await app.deps.prisma.invoice.findUniqueOrThrow({
        where: { paymentSubmissionId: second.id },
      });
      expect(invoice.periodStart.toISOString()).toBe(period.start);
      expect(invoice.periodEnd.toISOString()).toBe(period.end);
    });

    it('starts where a running trial ends, so a provider paying mid-trial keeps their days', async () => {
      const p = await provider();
      expect((await post(app, p.headers, `${SUBSCRIPTION}/start-trial`)).statusCode).toBe(200);
      const status = await readStatus(app, p.headers);
      const res = await post(app, p.headers, `${SUBSCRIPTION}/upgrade-request`);
      const { period } = res.json<Envelope<UpgradeRequestDto>>().data;
      expect(period.start).toBe(status.trial.endsAt);
    });
  });
});
