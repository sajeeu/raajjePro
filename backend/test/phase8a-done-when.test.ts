import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { FREE_TIER_ACTIVE_LISTING_CAP } from '../src/modules/listings/entitlements.js';
import { TRIAL_DAYS, addDays, GRACE_DAYS } from '../src/modules/subscriptions/period.js';
import {
  INTRODUCTORY_PRICE_LAARI,
  STANDARD_PRICE_LAARI,
} from '../src/modules/subscriptions/pricing.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { createEnrolledAdmin } from './helpers/admin.js';
import { ensureIslandsSeeded } from './helpers/islands.js';
import { completeDraft, ensureCategoriesSeeded, publish } from './helpers/listings.js';
import {
  ADMIN_SUBMISSIONS,
  FakeBookings,
  RecordingBillingNotifier,
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
 * §Phase 8a's own Done-when list, one describe per clause:
 *
 *   1. a trial starts on first confirmed booking *and* independently on an
 *      explicit request, and never twice
 *   2. an admin resolving `payment_unresolved` to `confirmed` fires the trial
 *      hook
 *   3. pause behaves identically during trial and paid period and correctly
 *      shifts the billing anchor
 *   4. a downgrade skips hiding any listing with a confirmed future booking
 *      and hides it the moment that booking completes
 *   5. a `pending` submission grants exactly nothing
 *   6. a reversal restores prior state and is audit-logged
 *
 * Clauses 1 and 2 have a half nothing can assert yet: there is no `Booking`
 * until §Phase 17.1, so the transition is driven through the injected source
 * this phase built for it (`FakeBookings`, ledger row **P8A-2**). What is
 * asserted is the whole of the rule — that the hook starts a trial, that it
 * is the same `startTrial` the explicit endpoint reaches, and that neither
 * can produce a second trial.
 *
 * Clause 3's rule is also asserted field-for-field, without a database, in
 * `test/subscriptions-pause.test.ts`; clause 4's ranking in
 * `test/subscriptions-downgrade.test.ts`.
 */
/** Comfortably past the furthest this file moves the clock — §1b's twelve-month introductory window plus its thirty days' notice. */
const CLOCK_HORIZON_DAYS = 4_000;

describe.skipIf(databaseUrl === undefined)('§Phase 8a Done-when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let admin: Awaited<ReturnType<typeof createEnrolledAdmin>>;
  const bookings = new FakeBookings();
  const notifier = new RecordingBillingNotifier();
  const time = controllableClock(new Date('2026-09-10T08:00:00.000Z'));

  /**
   * A test that walks the clock forward captures where it started from
   * `time.clock()` rather than from a literal, and puts it back at the end.
   *
   * Not a stylistic preference: a literal makes the test depend on every
   * earlier test in the file having restored the clock, and one that forgot
   * silently shifts a later test's billing anchor — which is exactly how the
   * introductory-conversion case first failed here.
   */

  beforeAll(async () => {
    ({ app } = await buildTestApp({
      clock: time.clock,
      // Credentials that survive the clock jumps below.
      //
      // These tests walk time forward by up to §1b's twelve-month
      // introductory window, and both an admin session (15-minute idle,
      // 12-hour absolute — §Phase 2) and a provider's access token (15
      // minutes — §Phase 3) are measured against this same clock. With the
      // real values every call after a jump 401s, and re-authenticating on
      // each one runs into the MFA route's own per-admin rate limit. Both
      // expiries are their own phases' rules and are tested there; here they
      // are noise, so the windows are set past the furthest this file ever
      // moves the clock.
      sessionIdleMinutes: CLOCK_HORIZON_DAYS * 24 * 60,
      sessionAbsoluteHours: CLOCK_HORIZON_DAYS * 24,
      accessTokenMinutes: CLOCK_HORIZON_DAYS * 24 * 60,
      deps: { subscriptionBookings: bookings, billingNotifier: notifier },
    }));
    await ensureCategoriesSeeded(app.deps.prisma);
    await ensureIslandsSeeded(app.deps.prisma);
    admin = await createEnrolledAdmin(app);
  });

  afterAll(async () => {
    await app.close();
  });

  /** A registered provider with a provider profile — what every clause below starts from. */
  async function provider() {
    const user = await registerUser(app, { role: 'provider' });
    const profile = await app.providers.getOrCreateProviderProfile(user.userId);
    return { ...user, profileId: profile.id };
  }

  // -------------------------------------------------------------------------

  describe('a trial starts on either trigger, and never twice', () => {
    it('starts on an explicit request, for 30 days, and grants premium at once', async () => {
      const p = await provider();
      const before = await readStatus(app, p.headers);
      expect(before.tier).toBe('free');
      expect(before.trial.available).toBe(true);
      expect(before.entitlements.activeListingCap).toBe(FREE_TIER_ACTIVE_LISTING_CAP);

      const res = await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      expect(res.statusCode).toBe(200);
      const status = res.json<Envelope<Awaited<ReturnType<typeof readStatus>>>>().data;

      // 🔧 Thirty days, not sixty: §0.4's number went stale when Round 12
      // halved it, and §0.0's precedence rule settles it (corrected in the
      // plan itself on 2026-09-10).
      expect(status.status).toBe('trialing');
      expect(status.tier).toBe('premium');
      expect(status.trial.endsAt).toBe(addDays(time.clock(), TRIAL_DAYS).toISOString());
      expect(status.trial.daysRemaining).toBe(TRIAL_DAYS);
      // §1b: the trial is "full premium access", and premium's cap is
      // unlimited — rendered as null, meaning no limit rather than unknown.
      expect(status.entitlements.activeListingCap).toBeNull();
      expect(status.entitlements.analytics).toBe(true);
    });

    it('starts on the booking hook, independently, for a provider who never asked', async () => {
      // §Phase 8a's first trigger, through the seam §Phase 17.1 will fill.
      const p = await provider();
      expect((await app.subscriptions.onBookingConfirmed(p.profileId)).started).toBe(true);
      const status = await readStatus(app, p.headers);
      expect(status.status).toBe('trialing');
      expect(status.trial.available).toBe(false);
    });

    it('never runs twice — not from the same trigger, not from the other one', async () => {
      // §1b's abuse prevention: "one trial per user account". `startTrial`
      // "is a no-op if a trial has ever run for that account", so the two
      // triggers cannot add up to two trials.
      const p = await provider();
      expect((await post(app, p.headers, `${SUBSCRIPTION}/start-trial`)).statusCode).toBe(200);
      const endsAt = (await readStatus(app, p.headers)).trial.endsAt;

      const again = await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      expect(again.statusCode).toBe(422);
      expect(again.json<ErrorEnvelope>().error.code).toBe('TRIAL_ALREADY_USED');

      expect((await app.subscriptions.onBookingConfirmed(p.profileId)).started).toBe(false);
      expect((await readStatus(app, p.headers)).trial.endsAt).toBe(endsAt);
    });

    it('still refuses after the trial has ended and been downgraded', async () => {
      // The check is `trialStartedAt !== null` on a column nothing clears —
      // not "is a trial running" — so a provider cannot wait it out and take
      // a second one.
      const p = await provider();
      await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      await app.deps.prisma.providerSubscription.update({
        where: { providerProfileId: p.profileId },
        data: { status: 'free', tier: 'free', downgradedAt: time.clock() },
      });
      const res = await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      expect(res.json<ErrorEnvelope>().error.code).toBe('TRIAL_ALREADY_USED');
    });

    it('prompts rather than starts, 7 days after a first published listing', async () => {
      // 🔧 §Phase 8a's third trigger, decided 2026-09-10: it **prompts**. A
      // trial is one per account and non-renewable, and this fires precisely
      // when no booking has landed — starting it there would spend the
      // provider's only trial when premium is worth least.
      const start = time.clock();
      const p = await provider();
      const draft = await completeDraft(app, p.headers);
      expect((await publish(app, p.headers, draft.id)).statusCode).toBe(200);

      // Six days: nothing yet.
      time.set(addDays(start, 6));
      await app.subscriptions.runTrialPrompts(time.clock());
      expect(notifier.eventsFor(p.profileId)).toEqual([]);

      time.set(addDays(start, 8));
      await app.subscriptions.runTrialPrompts(time.clock());
      expect(notifier.eventsFor(p.profileId)).toEqual(['trial_prompt']);

      // The trial is *not* running, and is still available for the provider
      // to take when it is worth something to them.
      const status = await readStatus(app, p.headers);
      expect(status.status).toBe('free');
      expect(status.trial.available).toBe(true);

      // And it is sent once, however often the hourly job runs.
      await app.subscriptions.runTrialPrompts(time.clock());
      await app.subscriptions.runTrialPrompts(addDays(time.clock(), 1));
      expect(notifier.eventsFor(p.profileId)).toEqual(['trial_prompt']);
      time.set(start);
    });

    it('does not prompt a provider whose booking has already landed', async () => {
      // The condition §Phase 8a states — "if no booking has landed" — read
      // through the injected source.
      const p = await provider();
      const draft = await completeDraft(app, p.headers);
      await publish(app, p.headers, draft.id);
      bookings.giveBooking(p.profileId);

      await app.subscriptions.runTrialPrompts(addDays(time.clock(), 30));
      expect(notifier.eventsFor(p.profileId)).toEqual([]);
    });
  });

  // -------------------------------------------------------------------------

  describe('an admin resolving payment_unresolved to confirmed fires the trial hook', () => {
    it('fires from the hook rather than from any one endpoint', async () => {
      // §0.5 recorded this as a specification fix: "hook was on one endpoint;
      // an admin resolving `payment_unresolved` also reaches `confirmed` and
      // would not have fired it". So the hook takes a provider id and
      // nothing about how the transition happened — there is deliberately no
      // parameter a caller could use to distinguish the admin path, because
      // a hook that could tell them apart is one that could be wired to only
      // one of them.
      const p = await provider();

      // Two different callers, standing in for the two paths §Phase 17.1
      // will wire: the customer-facing confirmation and the admin resolving
      // `payment_unresolved`. Both reach the same method with the same
      // argument, and the first one to arrive starts the trial.
      expect((await app.subscriptions.onBookingConfirmed(p.profileId)).started).toBe(true);
      expect((await app.subscriptions.onBookingConfirmed(p.profileId)).started).toBe(false);
      expect((await readStatus(app, p.headers)).status).toBe('trialing');

      // The signature is the assertion: one required argument, so §Phase
      // 17.1 cannot wire a path-specific variant by accident.
      expect(app.subscriptions.onBookingConfirmed.bind(app.subscriptions)).toHaveLength(1);
    });
  });

  // -------------------------------------------------------------------------

  describe('pause behaves identically during trial and paid period', () => {
    it('pauses a trial through the toggle and through the billing endpoint alike', async () => {
      // 🔧 §1b's "pause keys off the provider-level `acceptingNewCustomers`
      // toggle" is literal (confirmed 2026-09-10): one function, two doors.
      const viaEndpoint = await provider();
      await post(app, viaEndpoint.headers, `${SUBSCRIPTION}/start-trial`);
      expect((await post(app, viaEndpoint.headers, `${SUBSCRIPTION}/pause`)).statusCode).toBe(200);
      const endpointStatus = await readStatus(app, viaEndpoint.headers);
      expect(endpointStatus.status).toBe('paused');
      expect(endpointStatus.pause.paused).toBe(true);
      // The toggle moved with it: they are one state, not two.
      expect(endpointStatus.acceptingNewCustomers).toBe(false);

      const viaToggle = await provider();
      await post(app, viaToggle.headers, `${SUBSCRIPTION}/start-trial`);
      const patched = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: viaToggle.headers,
        remoteAddress: freshIp(),
        payload: { acceptingNewCustomers: false },
      });
      expect(patched.statusCode).toBe(200);
      const toggleStatus = await readStatus(app, viaToggle.headers);
      expect(toggleStatus.status).toBe('paused');
      expect(toggleStatus.pause.paused).toBe(true);
    });

    it('shifts the billing anchor by the paused duration, on a paid period', async () => {
      // §1b: "a subscription bills every 30 days from an anchor date set at
      // first confirmed payment. **Pausing shifts the anchor by the paused
      // duration.**"
      const start = time.clock();
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);

      const paid = await readStatus(app, p.headers);
      const anchor = paid.billing.anchorAt;
      const periodEnd = paid.billing.currentPeriodEnd;
      expect(anchor).toBe(time.clock().toISOString());
      expect(periodEnd).toBe(addDays(time.clock(), 30).toISOString());

      await post(app, p.headers, `${SUBSCRIPTION}/pause`);
      time.set(addDays(time.clock(), 4));
      expect((await post(app, p.headers, `${SUBSCRIPTION}/resume`)).statusCode).toBe(200);

      const resumed = await readStatus(app, p.headers);
      expect(resumed.status).toBe('active');
      expect(resumed.billing.anchorAt).toBe(addDays(new Date(anchor ?? ''), 4).toISOString());
      expect(resumed.billing.currentPeriodEnd).toBe(
        addDays(new Date(periodEnd ?? ''), 4).toISOString(),
      );
      expect(resumed.pause.cumulativePausedDays).toBe(4);
      expect(resumed.pause.remainingPauseAllowanceDays).toBe(6);
      time.set(start);
    });

    it('forcibly resumes the clock at the 10-day cap and leaves the toggle alone', async () => {
      // §1b: "at the cap, pause auto-ends and the clock forcibly resumes."
      // 🔧 The toggle is deliberately untouched (2026-09-10): whether a
      // provider takes work is theirs to decide, and only the billing clock
      // is capped.
      const start = time.clock();
      const p = await provider();
      await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      await post(app, p.headers, `${SUBSCRIPTION}/pause`);

      time.set(addDays(start, 11));
      const report = await app.subscriptions.runLifecycle(time.clock());
      expect(report.resumedAtCap).toBeGreaterThanOrEqual(1);

      const status = await readStatus(app, p.headers);
      expect(status.status).toBe('trialing');
      expect(status.pause.remainingPauseAllowanceDays).toBe(0);
      expect(status.acceptingNewCustomers).toBe(false);
      // Ten days of pause, not eleven: the pause ended at the cap whether or
      // not the job was watching.
      expect(status.trial.endsAt).toBe(addDays(start, TRIAL_DAYS + 10).toISOString());
      time.set(start);
    });

    it('refuses a pause with no clock to stop, and never traps the toggle off', async () => {
      const p = await provider();
      const refused = await post(app, p.headers, `${SUBSCRIPTION}/pause`);
      expect(refused.statusCode).toBe(422);
      expect(refused.json<ErrorEnvelope>().error.code).toBe('SUBSCRIPTION_NOT_PAUSABLE');
      // The toggle did not move, because the pause never happened.
      expect((await readStatus(app, p.headers)).acceptingNewCustomers).toBe(true);

      // Resume is tolerant where pause is strict: a billing endpoint must
      // never be able to leave a provider stuck at "not accepting customers".
      expect((await post(app, p.headers, `${SUBSCRIPTION}/resume`)).statusCode).toBe(200);
    });
  });

  // -------------------------------------------------------------------------

  describe('a downgrade skips a listing with a confirmed future booking', () => {
    it('runs the whole lifecycle: warning, grace, downgrade, protection and win-back', async () => {
      const start = time.clock();
      const p = await provider();
      const performer = await completeDraft(app, p.headers);
      await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      await publish(app, p.headers, performer.id);
      const committed = await completeDraft(app, p.headers);
      await publish(app, p.headers, committed.id);

      // The first listing is the one §1b's ranking would keep — "confirmed
      // bookings over the trailing 90 days" — and the second is the one with
      // a committed future job. Set up this way round on purpose: it makes
      // the protection the *only* reason the second listing survives the cap,
      // which is what the Done-when clause is about.
      await app.deps.prisma.listingEvent.createMany({
        data: [
          { listingId: performer.id, kind: 'booking', occurredAt: start },
          { listingId: performer.id, kind: 'booking', occurredAt: start },
        ],
      });
      bookings.commit(committed.id);

      // §1b: "**Warning** 7 days before trial or subscription period end."
      time.set(addDays(start, TRIAL_DAYS - 6));
      await app.subscriptions.runLifecycle(time.clock());
      expect(notifier.eventsFor(p.profileId)).toContain('trial_ending_7d');
      expect((await readStatus(app, p.headers)).status).toBe('trialing');

      // §1b: "**Grace:** 7 days after expiry with nothing changing". So
      // `expired` still carries premium, and both listings stay live.
      time.set(addDays(start, TRIAL_DAYS + 1));
      await app.subscriptions.runLifecycle(time.clock());
      const inGrace = await readStatus(app, p.headers);
      expect(inGrace.status).toBe('expired');
      expect(inGrace.tier).toBe('premium');
      expect(inGrace.entitlements.activeListingCap).toBeNull();

      // …"then downgrade to free". The protected listing survives the cap;
      // the other does not.
      time.set(addDays(start, TRIAL_DAYS + GRACE_DAYS + 1));
      const report = await app.subscriptions.runLifecycle(time.clock());
      expect(report.downgraded).toBeGreaterThanOrEqual(1);
      const free = await readStatus(app, p.headers);
      expect(free.status).toBe('free');
      expect(free.tier).toBe('free');
      expect(free.entitlements.activeListingCap).toBe(FREE_TIER_ACTIVE_LISTING_CAP);
      expect(notifier.eventsFor(p.profileId)).toContain('downgraded_to_free');

      const visibility = async (id: string) =>
        (
          await app.deps.prisma.listing.findUniqueOrThrow({
            where: { id },
            select: { visibility: true },
          })
        ).visibility;
      // The protected listing survives the cap even though the other one
      // out-performs it — "stays visible **regardless of cap**".
      expect(await visibility(committed.id)).toBe('active');
      expect(await visibility(performer.id)).toBe('hidden_over_cap');

      // §Phase 8a's Done-when: "…and hides it the moment that booking
      // completes". The protection is re-asked on every sweep, so it goes
      // when the booking reaches a terminal state — and the cap then applies
      // to both, which brings the higher-performing listing back in its
      // place. The provider is never left with nothing live.
      bookings.complete(committed.id);
      await app.subscriptions.runLifecycle(time.clock());
      expect(await visibility(committed.id)).toBe('hidden_over_cap');
      expect(await visibility(performer.id)).toBe('active');

      // §1b's win-back pair: "at 7 and 30 days reminding them their hidden
      // listings are intact and one confirmed payment restores them."
      time.set(addDays(start, TRIAL_DAYS + GRACE_DAYS + 9));
      await app.subscriptions.runLifecycle(time.clock());
      expect(notifier.eventsFor(p.profileId)).toContain('winback_7d');
      expect(notifier.eventsFor(p.profileId)).not.toContain('winback_30d');

      time.set(addDays(start, TRIAL_DAYS + GRACE_DAYS + 32));
      await app.subscriptions.runLifecycle(time.clock());
      const events = notifier.eventsFor(p.profileId);
      expect(events).toContain('winback_30d');
      // Each notification once, however many times the hourly job ran.
      expect(events.filter((e) => e === 'winback_7d')).toHaveLength(1);
      expect(events.filter((e) => e === 'downgraded_to_free')).toHaveLength(1);

      // "Any confirmed payment restores everything."
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      expect(await visibility(performer.id)).toBe('active');
      expect(await visibility(committed.id)).toBe('active');
      time.set(start);
    });

    it('leaves the verification badge alone through the whole lapse', async () => {
      // §1b and §1e: "**the badge is gated by `verificationTier` alone, never
      // by subscription state.** A lapsed-but-verified provider keeps their
      // tier — it is a safety signal, not a payment status."
      const start = time.clock();
      const p = await provider();
      await app.deps.prisma.providerProfile.update({
        where: { id: p.profileId },
        data: { verificationTier: 'gold', verificationStatus: 'verified' },
      });
      await post(app, p.headers, `${SUBSCRIPTION}/start-trial`);
      time.set(addDays(start, TRIAL_DAYS + GRACE_DAYS + 1));
      await app.subscriptions.runLifecycle(time.clock());

      const profile = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { id: p.profileId },
      });
      expect(profile.verificationTier).toBe('gold');
      expect(profile.verificationStatus).toBe('verified');
      time.set(start);
    });
  });

  // -------------------------------------------------------------------------

  describe('a pending submission grants exactly nothing', () => {
    it('leaves the provider on the free tier, with their listings still hidden', async () => {
      // §1b: "**nothing is granted on submission.** A `pending` submission
      // produces entitlements identical to no payment at all.
      // `getProviderEntitlements` reads live database state on every call and
      // never caches."
      const p = await provider();
      const before = await readStatus(app, p.headers);
      const submission = await submitPayment(app, p.headers);

      const after = await readStatus(app, p.headers);
      expect(submission.status).toBe('pending');
      expect(submission.submittedAt).not.toBeNull();
      expect(after.tier).toBe(before.tier);
      expect(after.status).toBe(before.status);
      expect(after.entitlements).toEqual(before.entitlements);
      expect(after.billing.currentPeriodEnd).toBeNull();
      // And no subscription row was created by the submission at all.
      expect(
        await app.deps.prisma.providerSubscription.findUnique({
          where: { providerProfileId: p.profileId },
        }),
      ).toBeNull();

      // Nor is the price written: §1b sets it "at their first confirmed
      // payment", and a pending submission is not one.
      const profile = await app.deps.prisma.providerProfile.findUniqueOrThrow({
        where: { id: p.profileId },
      });
      expect(profile.subscriptionPriceLaari).toBeNull();
    });

    it('keeps an unsubmitted intent out of the admin queue', async () => {
      // §1b's mechanism is four steps and the row exists from step 1, which
      // is what generates the reference code the provider writes on the
      // transfer. `pending` in the queue has to mean step 3 — a provider who
      // tapped Upgrade and never transferred is not work for an admin.
      const p = await provider();
      const requested = await post(app, p.headers, `${SUBSCRIPTION}/upgrade-request`);
      expect(requested.statusCode).toBe(201);
      const { submission } = requested.json<
        Envelope<{
          submission: { id: string; referenceCode: string; submittedAt: string | null };
        }>
      >().data;
      expect(submission.submittedAt).toBeNull();
      expect(submission.referenceCode).toMatch(/^RP-[A-Z2-9]{4}-[A-Z2-9]{4}$/);

      const queue = await app.inject({
        method: 'GET',
        url: ADMIN_SUBMISSIONS,
        headers: { cookie: admin.cookie },
        remoteAddress: freshIp(),
      });
      expect(queue.statusCode).toBe(200);
      const ids = queue.json<Envelope<{ id: string }[]>>().data.map((row) => row.id);
      expect(ids).not.toContain(submission.id);
    });

    it('confirms only once when two admins decide at the same moment', async () => {
      // backend/CLAUDE.md: concurrency is tested where the plan names it, and
      // "simultaneous admin confirmation" is on that list. A read-then-write
      // here would confirm twice, issue two invoices and extend the period by
      // sixty days.
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      const second = await createEnrolledAdmin(app);

      const [a, b] = await Promise.all([
        adminDecide(app, admin.cookie, submission.id, 'confirm', {}),
        adminDecide(app, second.cookie, submission.id, 'confirm', {}),
      ]);
      const codes = [a.statusCode, b.statusCode].sort((x, y) => x - y);
      expect(codes).toEqual([200, 409]);
      expect(
        await app.deps.prisma.invoice.count({ where: { paymentSubmissionId: submission.id } }),
      ).toBe(1);
    });
  });

  // -------------------------------------------------------------------------

  describe('a confirmation grants the entitlement, sets the price and issues an invoice', () => {
    it('quotes the provider’s own price, writes it at the first payment, and never moves it', async () => {
      // §1b: the price "lives on the provider record, set at their first
      // confirmed payment and honoured on every renewal thereafter… never a
      // global constant and never a range".
      //
      // Which of the two price points a new provider is quoted depends on how
      // many providers already have one, and this suite's rows are never
      // deleted — so the hundredth priced provider is somewhere in its
      // history and the boundary itself is asserted in
      // `test/subscriptions-pricing.test.ts` against the pure rule. What is
      // asserted here is what the boundary is *for*: the quote, the write,
      // and that nothing later moves it.
      const p = await provider();
      const quoted = await readStatus(app, p.headers);
      expect([INTRODUCTORY_PRICE_LAARI, STANDARD_PRICE_LAARI]).toContain(
        quoted.billing.nextPaymentAmountLaari,
      );
      expect(quoted.billing.priceLaari).toBeNull();

      const submission = await submitPayment(app, p.headers);
      // A provider is charged what they were shown.
      expect(submission.amountLaari).toBe(quoted.billing.nextPaymentAmountLaari);
      const confirmed = await confirmPayment(app, admin.cookie, submission.id);
      expect(confirmed.status).toBe('confirmed');

      const paid = await readStatus(app, p.headers);
      expect(paid.status).toBe('active');
      expect(paid.tier).toBe('premium');
      expect(paid.billing.priceLaari).toBe(submission.amountLaari);
      expect(paid.billing.currentPeriodEnd).toBe(addDays(time.clock(), 30).toISOString());

      // Honoured on renewal: the second payment quotes the *field*, not the
      // cohort rule, so a provider's price never changes because of somebody
      // else's signup.
      const renewal = await submitPayment(app, p.headers);
      expect(renewal.amountLaari).toBe(submission.amountLaari);
      await confirmPayment(app, admin.cookie, renewal.id);
      expect((await readStatus(app, p.headers)).billing.priceLaari).toBe(submission.amountLaari);
    });

    it('issues a downloadable PDF invoice per confirmed payment', async () => {
      // §1b step 6, and §Phase 10a's invoice list.
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);

      const list = await app.inject({
        method: 'GET',
        url: '/v1/providers/me/invoices',
        headers: p.headers,
        remoteAddress: freshIp(),
      });
      expect(list.statusCode).toBe(200);
      const invoices =
        list.json<Envelope<{ invoiceNumber: string; amountLaari: number; pdfUrl: string }[]>>()
          .data;
      expect(invoices).toHaveLength(1);
      const invoice = invoices[0];
      if (invoice === undefined) throw new Error('no invoice');
      expect(invoice.invoiceNumber).toMatch(/^RP-\d{6}$/);
      expect(invoice.amountLaari).toBe(submission.amountLaari);

      // The URL is a short-lived signed one over the media transport, and it
      // serves a real PDF with its real content type.
      const pdf = await app.inject({
        method: 'GET',
        url: invoice.pdfUrl.replace(/^https?:\/\/[^/]+/, ''),
        remoteAddress: freshIp(),
      });
      expect(pdf.statusCode).toBe(200);
      expect(pdf.headers['content-type']).toBe('application/pdf');
      expect(pdf.rawPayload.subarray(0, 5).toString('latin1')).toBe('%PDF-');
      expect(pdf.rawPayload.toString('latin1')).toContain(submission.referenceCode);
    });

    it('lets a premium provider publish past the free cap, and a free one not', async () => {
      // 🔧 §Phase 8's cap seam, filled. `FREE_TIER_ONLY` used to answer 1 for
      // everybody; the reader is now the live database read and
      // `ListingService` did not change.
      const p = await provider();
      const first = await completeDraft(app, p.headers);
      expect((await publish(app, p.headers, first.id)).statusCode).toBe(200);

      const second = await completeDraft(app, p.headers);
      const refused = await publish(app, p.headers, second.id);
      expect(refused.statusCode).toBe(422);
      const error = refused.json<ErrorEnvelope>().error;
      expect(error.code).toBe('LISTING_CAP_REACHED');
      expect(error.details).toMatchObject({ activeListingCap: FREE_TIER_ACTIVE_LISTING_CAP });

      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      expect((await publish(app, p.headers, second.id)).statusCode).toBe(200);
      const third = await completeDraft(app, p.headers);
      expect((await publish(app, p.headers, third.id)).statusCode).toBe(200);
    });

    it('rejects with a reason the provider can see, and lets them resubmit at once', async () => {
      // §1b steps 4–5: "rejects (reason required)… on rejection the provider
      // sees the reason and may **resubmit immediately** — no cooldown."
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      const rejected = await adminDecide(app, admin.cookie, submission.id, 'reject', {
        reason: 'The receipt shows MVR 40, not the amount claimed',
      });
      expect(rejected.statusCode).toBe(200);

      const status = await readStatus(app, p.headers);
      expect(status.tier).toBe('free');
      expect(status.latestSubmission?.status).toBe('rejected');
      expect(status.latestSubmission?.rejectionReason).toBe(
        'The receipt shows MVR 40, not the amount claimed',
      );

      // No cooldown: a fresh submission is the resubmit, and it works
      // immediately.
      const resubmitted = await submitPayment(app, p.headers);
      expect(resubmitted.status).toBe('pending');
      expect(resubmitted.id).not.toBe(submission.id);
      expect(resubmitted.referenceCode).not.toBe(submission.referenceCode);
    });
  });

  // -------------------------------------------------------------------------

  describe('a reversal restores prior state and is audit-logged', () => {
    it('takes back the period, voids the invoice, re-hides the listings and records why', async () => {
      // §1b: "an admin can reverse a confirmed payment (mistake, bank
      // reversal). **Explicit endpoint with an audit-log entry, never a
      // database edit.**"
      const p = await provider();
      const first = await completeDraft(app, p.headers);
      const second = await completeDraft(app, p.headers);
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      await publish(app, p.headers, first.id);
      await publish(app, p.headers, second.id);

      const reason = 'Bank reversed the transfer three days later';
      const reversed = await adminDecide(app, admin.cookie, submission.id, 'reverse', { reason });
      expect(reversed.statusCode).toBe(200);
      const dto = reversed.json<Envelope<{ status: string; reversedAt: string | null }>>().data;
      expect(dto.status).toBe('rejected');
      expect(dto.reversedAt).not.toBeNull();

      // Prior state: no paid period, no premium, and the listings the upgrade
      // let through are back over the cap.
      const status = await readStatus(app, p.headers);
      expect(status.tier).toBe('free');
      expect(status.billing.currentPeriodEnd).toBe(time.clock().toISOString());
      const visibilities = await app.deps.prisma.listing.findMany({
        where: { id: { in: [first.id, second.id] } },
        select: { visibility: true },
      });
      expect(visibilities.map((row) => row.visibility).sort()).toEqual([
        'active',
        'hidden_over_cap',
      ]);

      // The invoice is voided, not deleted (invariant 8): a document that was
      // issued cannot be made never to have existed.
      const invoice = await app.deps.prisma.invoice.findUniqueOrThrow({
        where: { paymentSubmissionId: submission.id },
      });
      expect(invoice.voidedAt).not.toBeNull();
      expect(invoice.voidedReason).toBe(reason);

      // Audit-logged, with the reason and no payment content.
      const entry = await app.deps.prisma.auditLogEntry.findFirst({
        where: { action: 'payment_submission.reversed', targetId: submission.id },
      });
      expect(entry?.actorType).toBe('admin');
      expect(entry?.actorId).toBe(admin.adminId);
      expect(entry?.reason).toBe(reason);
      expect(JSON.stringify(entry?.metadata)).not.toContain(p.email);
    });

    it('refuses to reverse anything that was not confirmed', async () => {
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      const res = await adminDecide(app, admin.cookie, submission.id, 'reverse', {
        reason: 'Nothing to reverse here at all',
      });
      expect(res.statusCode).toBe(422);
      expect(res.json<ErrorEnvelope>().error.code).toBe('PAYMENT_SUBMISSION_NOT_CONFIRMED');
    });

    it('keeps a second confirmed period when only one of two payments is reversed', async () => {
      // "Restores prior state" is about the payment reversed, not about the
      // subscription: reversing one payment of two must not cancel the other.
      const p = await provider();
      const first = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, first.id);
      const second = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, second.id);
      expect((await readStatus(app, p.headers)).billing.currentPeriodEnd).toBe(
        addDays(time.clock(), 60).toISOString(),
      );

      await adminDecide(app, admin.cookie, second.id, 'reverse', {
        reason: 'Duplicate confirmation of the same transfer',
      });
      const status = await readStatus(app, p.headers);
      expect(status.tier).toBe('premium');
      expect(status.status).toBe('active');
      expect(status.billing.currentPeriodEnd).toBe(addDays(time.clock(), 30).toISOString());
    });
  });

  // -------------------------------------------------------------------------

  describe('the introductory rate converts on §1b’s schedule', () => {
    it('gives 30 days’ notice, then re-prices to standard', async () => {
      // §1b: honoured "for 12 months from the billing anchor, then converts
      // to standard with 30 days' notice". 🔧 §Phase 8a's fifth scheduled
      // job, added 2026-09-10 — no other phase owned it.
      const start = time.clock();
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      // Put them on the introductory rate explicitly rather than relying on
      // the cohort count: this suite's history is long past the hundredth
      // priced provider (see the pricing test), and what is under test here
      // is the *conversion*, whose contract is "a provider whose price is the
      // introductory rate converts 12 months after their billing anchor".
      await app.deps.prisma.providerProfile.update({
        where: { id: p.profileId },
        data: { subscriptionPriceLaari: INTRODUCTORY_PRICE_LAARI },
      });
      expect((await readStatus(app, p.headers)).billing.priceLaari).toBe(INTRODUCTORY_PRICE_LAARI);

      // Eleven months in: nothing. The rate is honoured for the whole window.
      time.set(addDays(start, 300));
      expect(await app.subscriptions.runIntroductoryConversion(time.clock())).toEqual({
        noticed: 0,
        converted: 0,
      });

      // Thirty days out: the notice goes, and the price has not moved.
      time.set(addDays(start, 335));
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).noticed).toBe(1);
      expect(notifier.eventsFor(p.profileId)).toContain('introductory_price_converting');
      expect((await readStatus(app, p.headers)).billing.priceLaari).toBe(INTRODUCTORY_PRICE_LAARI);
      expect((await readStatus(app, p.headers)).billing.introductoryConvertsAt).toBe(
        addDays(start, 365).toISOString(),
      );

      // Twelve months and the notice both served: it converts, once, and the
      // conversion is audit-logged as a system action.
      time.set(addDays(start, 366));
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).converted).toBe(1);
      const converted = await readStatus(app, p.headers);
      expect(converted.billing.priceLaari).toBe(STANDARD_PRICE_LAARI);
      expect(converted.billing.introductory).toBe(false);
      expect(converted.billing.nextPaymentAmountLaari).toBe(STANDARD_PRICE_LAARI);

      expect(await app.subscriptions.runIntroductoryConversion(time.clock())).toEqual({
        noticed: 0,
        converted: 0,
      });
      // Looked up by target rather than through the paged query: this suite's
      // audit log is never pruned and its entries carry the *injected* clock,
      // so a page of the ten most recent is a page from whichever run
      // happened to be dated furthest in the future.
      const entry = await app.deps.prisma.auditLogEntry.findFirst({
        where: { action: 'provider.subscription_price.converted', targetId: p.profileId },
      });
      expect(entry?.actorType).toBe('system');
      expect(entry?.metadata).toMatchObject({
        fromLaari: INTRODUCTORY_PRICE_LAARI,
        toLaari: STANDARD_PRICE_LAARI,
      });
      time.set(start);
    });

    it('gives the full 30 days even when the notice goes out late', async () => {
      // §1b says "converts to standard **with 30 days' notice**", and the
      // notice is the provider's warning that their bill is about to double.
      // A job that was down for a week must not be able to shorten it, so
      // the effective date is the later of the twelve months and the notice
      // plus thirty days.
      const start = time.clock();
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);
      await app.deps.prisma.providerProfile.update({
        where: { id: p.profileId },
        data: { subscriptionPriceLaari: INTRODUCTORY_PRICE_LAARI },
      });

      // The notice goes ten days late — the twelve months are already up.
      time.set(addDays(start, 375));
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).noticed).toBe(1);
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).converted).toBe(0);

      // Twenty-nine days after that notice: still the introductory rate.
      time.set(addDays(start, 404));
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).converted).toBe(0);
      expect((await readStatus(app, p.headers)).billing.priceLaari).toBe(INTRODUCTORY_PRICE_LAARI);

      time.set(addDays(start, 406));
      expect((await app.subscriptions.runIntroductoryConversion(time.clock())).converted).toBe(1);
      expect((await readStatus(app, p.headers)).billing.priceLaari).toBe(STANDARD_PRICE_LAARI);
      time.set(start);
    });
  });

  // -------------------------------------------------------------------------

  describe('no response in this module carries a phone number', () => {
    it('not the provider’s status, not the invoice list, not the admin queue', async () => {
      // §1c: exactly one endpoint in the whole system may return a phone
      // number to another user, and it is the emergency reveal. Asserted for
      // its ABSENCE (backend/CLAUDE.md), including the admin queue — which is
      // the one place here that renders somebody else's account details.
      const p = await provider();
      const submission = await submitPayment(app, p.headers);
      await confirmPayment(app, admin.cookie, submission.id);

      const bodies = await Promise.all(
        [
          { url: SUBSCRIPTION, headers: p.headers },
          { url: '/v1/providers/me/invoices', headers: p.headers },
          { url: ADMIN_SUBMISSIONS, headers: { cookie: admin.cookie } },
          { url: `${ADMIN_SUBMISSIONS}?status=confirmed`, headers: { cookie: admin.cookie } },
        ].map(
          async (target) =>
            (
              await app.inject({
                method: 'GET',
                url: target.url,
                headers: target.headers,
                remoteAddress: freshIp(),
              })
            ).body,
        ),
      );
      for (const body of bodies) {
        expect(body).not.toContain(p.phone);
        expect(body).not.toContain('phoneE164');
        expect(body).not.toContain('+960');
      }
    });

    it('and no provider’s own bank details leave through it either', async () => {
      // §Phase 5 allows those in exactly one place — a booking's payment step
      // — and nothing in this module reads them. The bank details that *do*
      // appear are RaajjePro's own, from configuration.
      const p = await provider();
      await app.deps.prisma.providerProfile.update({
        where: { id: p.profileId },
        data: {
          bankName: 'Bank of Maldives',
          bankAccountName: 'Test Trade',
          bankAccountNumber: '7701234567890',
        },
      });
      const submission = await submitPayment(app, p.headers);

      // Read back through the admin DTO for *this* submission — the confirm
      // response is the same mapper the queue page uses. The queue itself is
      // asserted below for the absence, but it cannot be asserted to contain
      // this row: it is ordered oldest-first on `submittedAt` (§1b's 48-hour
      // SLA) and this suite's rows are never deleted, so page one belongs to
      // the first run that ever wrote one.
      const confirmed = await confirmPayment(app, admin.cookie, submission.id);
      const body = JSON.stringify(confirmed);
      expect(body).toContain(submission.referenceCode);
      expect(body).toContain(p.profileId);
      expect(body).not.toContain('7701234567890');
      expect(body).not.toContain('bankAccountNumber');

      const queue = await app.inject({
        method: 'GET',
        url: ADMIN_SUBMISSIONS,
        headers: { cookie: admin.cookie },
        remoteAddress: freshIp(),
      });
      expect(queue.body).not.toContain('7701234567890');
      expect(queue.body).not.toContain('bankAccountNumber');
    });
  });

  // -------------------------------------------------------------------------

  describe('every submission-creating call requires an idempotency key', () => {
    it('refuses without one and replays with one', async () => {
      // §Phase 8a: "**Idempotency key required** on every submission-creating
      // call." Without one, a double tap issues two reference codes and the
      // provider writes the wrong one on their transfer.
      const p = await provider();
      const without = await app.inject({
        method: 'POST',
        url: `${SUBSCRIPTION}/upgrade-request`,
        headers: p.headers,
        remoteAddress: freshIp(),
      });
      expect(without.statusCode).toBe(400);
      expect(without.json<ErrorEnvelope>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');

      const key = randomUUID();
      const first = await app.inject({
        method: 'POST',
        url: `${SUBSCRIPTION}/upgrade-request`,
        headers: { ...p.headers, 'idempotency-key': key },
        remoteAddress: freshIp(),
      });
      const replay = await app.inject({
        method: 'POST',
        url: `${SUBSCRIPTION}/upgrade-request`,
        headers: { ...p.headers, 'idempotency-key': key },
        remoteAddress: freshIp(),
      });
      expect(replay.statusCode).toBe(201);
      expect(replay.headers['idempotent-replayed']).toBe('true');
      expect(replay.body).toBe(first.body);
      expect(await app.deps.prisma.paymentSubmission.count({ where: { payerId: p.userId } })).toBe(
        1,
      );
    });

    it('and the trial cannot be started twice by a retried request', async () => {
      const p = await provider();
      const key = randomUUID();
      const send = () =>
        app.inject({
          method: 'POST',
          url: `${SUBSCRIPTION}/start-trial`,
          headers: { ...p.headers, 'idempotency-key': key },
          remoteAddress: freshIp(),
        });
      expect((await send()).statusCode).toBe(200);
      const replay = await send();
      // The replay returns the ORIGINAL success rather than the
      // already-used refusal, which is what an idempotent POST has to mean
      // for a client that lost the first response.
      expect(replay.statusCode).toBe(200);
      expect(replay.headers['idempotent-replayed']).toBe('true');
    });
  });

  // -------------------------------------------------------------------------

  describe('authorization', () => {
    it('keeps the admin queue and the decisions behind real admin auth', async () => {
      const p = await provider();
      const submission = await submitPayment(app, p.headers);

      // A signed-in provider is not an admin, and the read is guarded too —
      // the queue names payers and amounts.
      for (const path of [ADMIN_SUBMISSIONS, `${ADMIN_SUBMISSIONS}/${submission.id}/confirm`]) {
        const res = await app.inject({
          method: path.endsWith('confirm') ? 'POST' : 'GET',
          url: path,
          headers: { ...p.headers, 'idempotency-key': randomUUID() },
          remoteAddress: freshIp(),
        });
        expect([401, 403]).toContain(res.statusCode);
      }
    });

    it('does not let one provider touch another’s submission', async () => {
      const owner = await provider();
      const stranger = await provider();
      const submission = await submitPayment(app, owner.headers);

      const res = await app.inject({
        method: 'POST',
        url: `/v1/providers/me/payment-submissions/${submission.id}/proof`,
        headers: { ...stranger.headers, 'idempotency-key': randomUUID() },
        remoteAddress: freshIp(),
        payload: { contentType: 'image/jpeg' },
      });
      // Not found rather than forbidden: ownership is in the WHERE, so ids
      // cannot be probed.
      expect(res.statusCode).toBe(404);
    });

    it('refuses a trial and a payment to an account with no provider profile', async () => {
      // §1a's creation moments are onboarding, the first draft save and the
      // profile PATCH. A trial is one per account and non-renewable, so
      // handing one to an account that has never acted as a provider would
      // spend it on somebody who cannot use it.
      const customer = await registerUser(app);
      for (const path of [`${SUBSCRIPTION}/start-trial`, `${SUBSCRIPTION}/upgrade-request`]) {
        const res = await post(app, customer.headers, path);
        expect(res.statusCode).toBe(404);
        expect(res.json<ErrorEnvelope>().error.code).toBe('PROVIDER_PROFILE_NOT_FOUND');
      }
    });
  });
});
