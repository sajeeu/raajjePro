import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl } from './helpers/app.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface Summary {
  id: string;
  fullName: string;
  memberSince: string;
  isProvider: boolean;
}

/**
 * §Phase 6's Done-when list, from the backend's side.
 *
 * > Profile reflects live data; every row navigates; switching to provider
 * > mode for the first time reaches the onboarding flow, and reaches My
 * > Services Dashboard directly on every subsequent switch.
 *
 * Two of the three lines are the Flutter app's —
 * `frontend/test/features/profile/phase6_done_when_test.dart` drives them
 * through the real route table. What the server owes is the **first** line
 * and the **signal the third one turns on**: the summary is the live row, and
 * `isProvider` distinguishes a first switch from a later one without the
 * client asking a second question.
 */
describe.skipIf(databaseUrl === undefined)('§Phase 6 Done-when', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const summary = (headers: Record<string, string>) =>
    ctx.app
      .inject({ method: 'GET', url: '/v1/users/me/profile-summary', headers })
      .then((r) => r.json<Envelope<Summary>>().data);

  describe('Profile reflects live data', () => {
    it('follows a change made through another endpoint, with no cache in between', async () => {
      const u = await registerUser(ctx.app);
      const before = await summary(u.headers);

      await ctx.app.inject({
        method: 'PATCH',
        url: '/v1/users/me',
        headers: u.headers,
        payload: { fullName: 'Aishath Naeema' },
      });

      const after = await summary(u.headers);
      expect(before.fullName).not.toBe('Aishath Naeema');
      expect(after.fullName).toBe('Aishath Naeema');
      // The join date is the row's, not the read's.
      expect(after.memberSince).toBe(before.memberSince);
    });

    it('is one request, not one per section of the screen', async () => {
      // §Phase 6: "one call for the Profile screen". Everything the screen
      // renders comes back from this single read.
      const u = await registerUser(ctx.app);
      const body = await summary(u.headers);
      expect(body.fullName).not.toBe('');
      expect(Date.parse(body.memberSince)).not.toBeNaN();
      expect(typeof body.isProvider).toBe('boolean');
    });
  });

  describe('the role switcher can tell a first switch from a later one', () => {
    it('a customer reads false; the same account reads true once a profile exists', async () => {
      const u = await registerUser(ctx.app);
      expect((await summary(u.headers)).isProvider).toBe(false);

      // The write is what creates the provider profile — §Phase 6a's
      // onboarding is one of §1a's creation moments, and this is the endpoint
      // it persists payment details through.
      const created = await ctx.app.inject({
        method: 'PATCH',
        url: '/v1/providers/me',
        headers: u.headers,
        payload: { businessName: 'Naeema Cleaning' },
      });
      expect(created.statusCode).toBe(200);

      expect((await summary(u.headers)).isProvider).toBe(true);
    });

    it('a provider who registered as one reads true from their first read', async () => {
      // §Phase 3 creates a minimal profile when a *provider* registers, so
      // this account must never be routed into onboarding.
      const p = await registerUser(ctx.app, { role: 'provider' });
      expect((await summary(p.headers)).isProvider).toBe(true);
    });

    it('reading the profile screen does not flip the signal', async () => {
      // The failure this guards is a customer who opens Profile once and is
      // thereafter routed to a dashboard they never set up — and, because
      // nothing is ever hard-deleted (invariant 8), permanently.
      const u = await registerUser(ctx.app);
      await summary(u.headers);
      await ctx.app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: u.headers,
      });
      await summary(u.headers);
      expect((await summary(u.headers)).isProvider).toBe(false);
      expect(await ctx.prisma.providerProfile.count({ where: { userId: u.userId } })).toBe(0);
    });

    it('a bad path is still a plain 404, so the signal is unambiguous', async () => {
      // The client routes on `isProvider`; the 404 from `GET /v1/providers/me`
      // is the fallback and has to stay legible
      // (`docs/decisions/17-phase-5-provider-profiles.md`).
      const u = await registerUser(ctx.app);
      const noProfile = await ctx.app.inject({
        method: 'GET',
        url: '/v1/providers/me',
        headers: u.headers,
      });
      expect(noProfile.statusCode).toBe(404);
      expect(noProfile.json<{ error: { code: string } }>().error.code).toBe(
        'PROVIDER_PROFILE_NOT_FOUND',
      );

      const typo = await ctx.app.inject({
        method: 'GET',
        url: '/v1/users/me/profile-summry',
        headers: u.headers,
      });
      expect(typo.statusCode).toBe(404);
      expect(typo.json<{ error: { code: string } }>().error.code).toBe('NOT_FOUND');
    });
  });
});
