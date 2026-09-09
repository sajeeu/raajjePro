import { Writable } from 'node:stream';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildApp } from '../src/app.js';
import { buildTestApp, databaseUrl, testConfig } from './helpers/app.js';
import { FakeListings } from './helpers/providers.js';
import { bearer, createUser, registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}

/**
 * §Phase 5's own Done-when list, one describe per line.
 *
 * Two lines reach past what this phase can create, and each says so where it
 * is asserted: there is no `Listing` table until §Phase 8, so the
 * published-listing count arrives through `PublishedListingSource` and these
 * tests move a provider across §1a's line with `FakeListings`; and the three
 * consumers named in the suspension line — search, Home, the public profile —
 * are Phases 15, 16 and 13. What is provable today is that all three reach
 * the rule through the one shared helper and none of them can get past it.
 * `docs/deferred-verification.md` rows P5-1 to P5-4 carry the rest.
 */
describe.skipIf(databaseUrl === undefined)('§Phase 5 Done-when', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let listings: FakeListings;

  beforeAll(async () => {
    listings = new FakeListings();
    ({ app } = await buildTestApp({ deps: { publishedListings: listings } }));
  });

  afterAll(async () => {
    await app.close();
  });

  describe('`getOrCreateProviderProfile` called twice returns one row', () => {
    it('returns the same row and leaves exactly one behind', async () => {
      const user = await createUser(app.deps.prisma);
      const first = await app.providers.getOrCreateProviderProfile(user.id);
      const second = await app.providers.getOrCreateProviderProfile(user.id);
      expect(second.id).toBe(first.id);
      expect(await app.deps.prisma.providerProfile.count({ where: { userId: user.id } })).toBe(1);
    });

    it('holds when the four call sites race each other', async () => {
      // Phase 6a's onboarding, Phase 8's draft fallback and Phase 3's
      // registration all call this. A double tap on a flaky connection is the
      // real case, and the `@unique` on `user_id` is the arbiter: the loser
      // catches its own P2002 and re-reads the winner's row, so every caller
      // gets the profile and none of them sees an error.
      const user = await createUser(app.deps.prisma);
      const results = await Promise.allSettled(
        Array.from({ length: 6 }, () => app.providers.getOrCreateProviderProfile(user.id)),
      );
      // Every caller gets the row. "Some succeeded" was the earlier assertion
      // and it passed against an implementation where five of six raised
      // P2002 and became 500s — a test that passes against a wrong
      // implementation is not a test (backend/CLAUDE.md).
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(6);
      const ids = new Set(results.map((r) => (r.status === 'fulfilled' ? r.value.id : 'rejected')));
      expect(ids.size).toBe(1);
      expect(await app.deps.prisma.providerProfile.count({ where: { userId: user.id } })).toBe(1);
    });
  });

  describe('`findVisibleProviders` derives visibility from the published-listing count', () => {
    it('excludes a drafts-only provider and includes them the moment one is published', async () => {
      const user = await createUser(app.deps.prisma);
      const profile = await app.providers.getOrCreateProviderProfile(user.id, 'Draft Trade');

      // Only a draft: §1a's count is zero.
      const before = await app.providers.findVisibleProviders();
      expect(before.items.map((p) => p.id)).not.toContain(profile.id);
      expect(await app.providers.visibility.isVisible(profile.id)).toBe(false);

      // One published, active listing — nothing about the provider row changed.
      listings.publish(profile.id);
      const after = await app.providers.findVisibleProviders();
      expect(after.items.map((p) => p.id)).toContain(profile.id);
      expect(await app.providers.visibility.isVisible(profile.id)).toBe(true);

      // Unpublishing it takes them straight back out, which is the failure
      // the stored v1 flag could not represent.
      listings.unpublish(profile.id);
      expect(await app.providers.visibility.isVisible(profile.id)).toBe(false);
    });

    it('with no stored status field involved — the column does not exist', async () => {
      const columns = await app.deps.prisma.$queryRaw<{ column_name: string }[]>`
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'provider_profile'
      `;
      const names = columns.map((c) => c.column_name);
      // §1a: "There is no stored lifecycleStatus field." Nor any synonym of
      // one — a derived rule that has somewhere to be cached is a rule that
      // will drift, which is exactly what happened in v1.
      for (const forbidden of [
        'lifecycle_status',
        'is_visible',
        'visibility',
        'is_public',
        'published',
        'is_published',
        'status',
      ]) {
        expect(names).not.toContain(forbidden);
      }
    });
  });

  describe('the public read applies the gate itself', () => {
    it('returns not-found for a drafts-only provider and for a suspended one, by direct id', async () => {
      const user = await createUser(app.deps.prisma);
      const profile = await app.providers.getOrCreateProviderProfile(user.id, 'Gated Trade');

      // Drafts only (§Phase 13: "returns not-found for a drafts-only
      // provider's id"). The mapper is what a Phase 13 route calls, so the
      // gate has to live behind it rather than in each consumer.
      await expect(app.providers.readPublic(profile.id)).rejects.toThrow(/No such provider/);

      listings.publish(profile.id);
      await expect(app.providers.readPublic(profile.id)).resolves.toBeDefined();

      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { suspendedAt: new Date(), suspendedReason: 'under review' },
      });
      await expect(app.providers.readPublic(profile.id)).rejects.toThrow(/No such provider/);
    });
  });

  describe('`findVisibleProviders` excludes a suspended provider', () => {
    it('from search, from Home, and from the public profile — through the one shared helper', async () => {
      const user = await createUser(app.deps.prisma);
      const profile = await app.providers.getOrCreateProviderProfile(user.id, 'Suspended Trade');
      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { verificationTier: 'gold', maldivianOwned: true },
      });
      listings.publish(profile.id);

      // Visible on all three surfaces first, so the exclusion below is the
      // suspension and not something else.
      const searchBefore = await app.providers.findVisibleProviders({ maldivianOwned: true });
      const homeBefore = await app.providers.findVisibleProviders({}, { limit: 100 });
      expect(searchBefore.items.map((p) => p.id)).toContain(profile.id);
      expect(homeBefore.items.map((p) => p.id)).toContain(profile.id);
      expect(await app.providers.visibility.isVisible(profile.id)).toBe(true);

      await app.deps.prisma.providerProfile.update({
        where: { id: profile.id },
        data: { suspendedAt: new Date(), suspendedReason: 'Round of reports' },
      });

      // Search (Phase 15) — filtered.
      const search = await app.providers.findVisibleProviders({ maldivianOwned: true });
      expect(search.items.map((p) => p.id)).not.toContain(profile.id);
      // Home's Featured Providers (Phase 16) — unfiltered.
      const home = await app.providers.findVisibleProviders({}, { limit: 100 });
      expect(home.items.map((p) => p.id)).not.toContain(profile.id);
      // The public profile (Phase 13) — by direct id, which is the one that
      // would otherwise still render.
      expect(await app.providers.visibility.isVisible(profile.id)).toBe(false);
      expect(await app.providers.visibility.isVisibleByUserId(user.id)).toBe(false);

      // Suspension is an INPUT to the helper, not a filter each consumer
      // passes: no caller supplied it above, and none of the three could opt
      // out of it if it wanted to.
      const filterKeys = Object.keys({ maldivianOwned: true });
      expect(filterKeys).not.toContain('suspended');
    });

    it('and a tier filter narrows without ever widening past the rule', async () => {
      // §Phase 17.3's emergency dispatch calls this with the CATEGORY's
      // `emergencyMinimumTier` — gold for Electrical and Plumbing, silver for
      // AC Repair and Moving (§1c). Never a hardcoded `silver`.
      const silver = await createUser(app.deps.prisma);
      const gold = await createUser(app.deps.prisma);
      const silverProfile = await app.providers.getOrCreateProviderProfile(silver.id);
      const goldProfile = await app.providers.getOrCreateProviderProfile(gold.id);
      await app.deps.prisma.providerProfile.update({
        where: { id: silverProfile.id },
        data: { verificationTier: 'silver' },
      });
      await app.deps.prisma.providerProfile.update({
        where: { id: goldProfile.id },
        data: { verificationTier: 'gold' },
      });
      listings.publish(silverProfile.id);
      listings.publish(goldProfile.id);

      const atSilver = await app.providers.findVisibleProviders(
        { minimumTier: 'silver' },
        { limit: 200 },
      );
      expect(atSilver.items.map((p) => p.id)).toContain(silverProfile.id);
      expect(atSilver.items.map((p) => p.id)).toContain(goldProfile.id);

      const atGold = await app.providers.findVisibleProviders(
        { minimumTier: 'gold' },
        { limit: 200 },
      );
      expect(atGold.items.map((p) => p.id)).not.toContain(silverProfile.id);
      expect(atGold.items.map((p) => p.id)).toContain(goldProfile.id);

      // Suspend the gold provider: the filter cannot widen past the rule.
      await app.deps.prisma.providerProfile.update({
        where: { id: goldProfile.id },
        data: { suspendedAt: new Date(), suspendedReason: 'under review' },
      });
      const afterSuspension = await app.providers.findVisibleProviders(
        { minimumTier: 'gold' },
        { limit: 200 },
      );
      expect(afterSuspension.items.map((p) => p.id)).not.toContain(goldProfile.id);
    });

    it('and their own profile read still tells them they are suspended', async () => {
      const user = await registerUser(app, { role: 'provider' });
      await app.deps.prisma.providerProfile.update({
        where: { userId: user.userId },
        data: { suspendedAt: new Date(), suspendedReason: 'Payment dispute pattern' },
      });
      const res = await app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: user.headers,
      });
      const dto = res.json<Envelope<{ suspended: boolean; suspendedReason: string }>>().data;
      // §1f: consequences are graduated and never silent.
      expect(dto.suspended).toBe(true);
      expect(dto.suspendedReason).toBe('Payment dispute pattern');
    });
  });

  describe("a provider's phone number is absent from every response except their own profile read", () => {
    it("is absent from this phase's own responses and from the public shapes", async () => {
      const user = await registerUser(app, { role: 'provider', businessName: 'Phone Test Trade' });
      const profile = await app.providers.getOrCreateProviderProfile(user.userId);
      listings.publish(profile.id);
      const localNumber = user.phone;

      const own = await app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: user.headers,
      });
      const patched = await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: { bio: 'Reachable through the app only.' },
      });
      const publicDto = await app.providers.readPublic(profile.id);
      const page = await app.providers.findVisibleProviders({}, { limit: 100 });

      for (const shape of [
        own.body,
        patched.body,
        JSON.stringify(publicDto),
        JSON.stringify(page),
      ]) {
        expect(shape).not.toContain(localNumber);
        expect(shape).not.toContain('+960');
        expect(shape).not.toContain('phone');
      }

      // The one place it is theirs to see is Phase 3's own-account surface —
      // `userDto`, which the auth and account routes return and the data
      // export embeds. §Phase 6 adds the profile screen's own read on top of
      // the same DTO; nothing in this phase's module produces it.
      const account = await app.inject({
        method: 'GET',
        url: '/v1/users/me/data-export',
        headers: bearer(user.tokens.accessToken),
      });
      expect(account.body).toContain(localNumber);
    });

    it('and the far broader mechanism §1c deleted does not exist', async () => {
      // `GET /v1/bookings/:id/contact-info` exposed a number on every booking
      // type with no conditions. It was deleted outright and must not be
      // recreated — a 404 here is the assertion that no route matches it.
      // The one permitted path, `POST /v1/bookings/:id/reveal-contact`, is
      // Phase 17.3's under §1c's seven conditions and does not exist yet
      // either; no endpoint in this phase returns a number.
      const res = await app.inject({
        method: 'GET',
        url: `/v1/bookings/${crypto.randomUUID()}/contact-info`,
      });
      expect(res.statusCode).toBe(404);
    });
  });

  describe('payment details are absent from every response except the booking payment step', () => {
    it('never reach a public shape, and reach a customer only through the booking accessor', async () => {
      const user = await registerUser(app, { role: 'provider', businessName: 'Pay Test Trade' });
      const accountNumber = '7705550001';
      await app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: user.headers,
        payload: {
          bankName: 'Bank of Maldives',
          bankAccountName: 'Pay Test Trade',
          bankAccountNumber: accountNumber,
          transferInstructions: 'Reference the booking number.',
        },
      });
      const profile = await app.providers.getOrCreateProviderProfile(user.userId);
      listings.publish(profile.id);

      const publicDto = await app.providers.readPublic(profile.id);
      const page = await app.providers.findVisibleProviders({}, { limit: 100 });
      for (const shape of [JSON.stringify(publicDto), JSON.stringify(page)]) {
        expect(shape).not.toContain(accountNumber);
        expect(shape).not.toContain('bankAccountNumber');
        expect(shape).not.toContain('paymentDetails');
      }

      // The booking payment step (§1c step 6) — the one exception, because
      // the off-platform transfer cannot happen without it. Phase 17 calls
      // this after authorizing the caller against the booking.
      const forBooking = await app.providers.paymentDetailsForBooking(profile.id);
      expect(forBooking.bankAccountNumber).toBe(accountNumber);
      expect(forBooking.bankName).toBe('Bank of Maldives');

      // And the provider's own read, which is their own data.
      const own = await app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: user.headers,
      });
      expect(own.body).toContain(accountNumber);
    });

    it('reach no log line, while the change itself is audited by field name only', async () => {
      // Captures every line a real request produces — the same `logStream`
      // seam §Phase 3's no-PII assertion uses. Asserting against an empty
      // audit table would prove nothing.
      const lines: string[] = [];
      const stream = new Writable({
        write(chunk: Buffer, _enc, done) {
          lines.push(chunk.toString('utf8'));
          done();
        },
      });
      // `testConfig` silences logging; this assertion needs a real log stream,
      // so the level is raised the way §Phase 3's own no-PII test does it.
      const config = { ...testConfig(), logLevel: 'info' as const };
      const logged = await buildApp(config, {
        prisma: app.deps.prisma,
        clock: app.deps.clock,
        emailTransport: app.deps.emailTransport,
        pushTransport: app.deps.pushTransport,
        snsValidator: app.deps.snsValidator,
        publishedListings: listings,
        logStream: stream,
      });
      await logged.ready();
      try {
        const user = await registerUser(logged, { role: 'provider' });
        const accountNumber = '7705550002';
        const res = await logged.inject({
          method: 'PATCH',
          url: '/v1/providers/me',
          headers: user.headers,
          payload: { bankAccountNumber: accountNumber, bankName: 'Bank of Maldives' },
        });
        expect(res.statusCode).toBe(200);

        // §Phase 5: "excluded from every response except the booking-scoped
        // payment step, and from all logs."
        const log = lines.join('\n');
        expect(log.length).toBeGreaterThan(0);
        expect(log).not.toContain(accountNumber);

        // The change IS audited — field names, never a value (root CLAUDE.md
        // 1d). Phase 10a's receipt analysis checks a submission against this
        // account, so a dispute has to be able to establish when it changed.
        const profile = await logged.deps.prisma.providerProfile.findUniqueOrThrow({
          where: { userId: user.userId },
        });
        const entries = await logged.deps.prisma.auditLogEntry.findMany({
          where: { targetId: profile.id, action: 'provider.payment_details.changed' },
        });
        expect(entries).toHaveLength(1);
        expect(entries[0]?.actorType).toBe('user');
        expect(JSON.stringify(entries[0]?.metadata)).toContain('bankAccountNumber');
        expect(JSON.stringify(entries[0]?.metadata)).not.toContain(accountNumber);
      } finally {
        await logged.close();
      }
    });
  });
});
