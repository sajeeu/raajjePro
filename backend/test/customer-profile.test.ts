import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';
import { freshPhone, registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface Err {
  error: { code: string; details?: { path: string }[] };
}
interface Summary {
  id: string;
  fullName: string;
  memberSince: string;
  isProvider: boolean;
}

/**
 * The customer profile surface (plan §Phase 6) — `GET /v1/users/me/profile-summary`
 * and `PATCH /v1/users/me`.
 *
 * §Phase 6 names both endpoints and no fields on either, so what is asserted
 * here is the reasoning recorded in `src/modules/account/dto.ts` and
 * `docs/decisions/18-phase-6-customer-profile.md`: the summary is the caller's
 * own live row, it carries no phone number, and reading it never turns a
 * customer into a provider.
 */
describe.skipIf(databaseUrl === undefined)('customer profile', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp();
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const summary = (headers: Record<string, string>) =>
    ctx.app.inject({ method: 'GET', url: '/v1/users/me/profile-summary', headers });

  const patch = (headers: Record<string, string>, payload: Record<string, unknown>) =>
    ctx.app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload });

  describe('GET profile-summary', () => {
    it('answers with the caller’s own live row', async () => {
      const u = await registerUser(ctx.app);
      const res = await summary(u.headers);
      expect(res.statusCode).toBe(200);

      const body = res.json<Envelope<Summary>>().data;
      const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      expect(body.id).toBe(u.userId);
      expect(body.fullName).toBe(row.fullName);
      expect(body.memberSince).toBe(row.createdAt.toISOString());
      expect(body.isProvider).toBe(false);
    });

    it('is scoped to the token and cannot be pointed at anyone else', async () => {
      // There is no id in the path — the subject is always the principal — so
      // the wrong-user case is two tokens each getting their own row, and the
      // absence of any parameter that could redirect either one.
      const a = await registerUser(ctx.app);
      const b = await registerUser(ctx.app);
      expect(a.userId).not.toBe(b.userId);
      expect((await summary(a.headers)).json<Envelope<Summary>>().data.id).toBe(a.userId);
      expect((await summary(b.headers)).json<Envelope<Summary>>().data.id).toBe(b.userId);

      // A query parameter naming the other account changes nothing.
      const spoofed = await ctx.app.inject({
        method: 'GET',
        url: `/v1/users/me/profile-summary?userId=${b.userId}`,
        headers: a.headers,
      });
      expect(spoofed.json<Envelope<Summary>>().data.id).toBe(a.userId);
    });

    it('rejects an unauthenticated read', async () => {
      const res = await ctx.app.inject({
        method: 'GET',
        url: '/v1/users/me/profile-summary',
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(401);
    });

    it('carries no phone number, at any depth', async () => {
      // backend/CLAUDE.md: any endpoint near a phone number is tested for its
      // ABSENCE. The number is on `User`, which this DTO maps from, so the
      // assertion is against the serialised body rather than a field list.
      const phone = freshPhone();
      const u = await registerUser(ctx.app, { phone });
      const body = (await summary(u.headers)).body;
      expect(body).not.toContain(phone);
      expect(body).not.toContain(`+960${phone}`);
      expect(JSON.parse(body)).toMatchObject({
        data: { id: u.userId, isProvider: false },
      });
      expect(Object.keys((JSON.parse(body) as Envelope<Summary>).data).sort()).toEqual([
        'fullName',
        'id',
        'isProvider',
        'memberSince',
      ]);
    });

    it('reads `isProvider` true for a provider, and false is not sticky', async () => {
      const p = await registerUser(ctx.app, { role: 'provider' });
      expect((await summary(p.headers)).json<Envelope<Summary>>().data.isProvider).toBe(true);
    });

    it('never creates a provider profile — the switcher’s signal stays truthful', async () => {
      // `docs/decisions/17-phase-5-provider-profiles.md` decision 11: a read
      // must not turn a customer into a provider, because nothing is ever
      // hard-deleted and §Phase 6a's "never sees onboarding again" routes on
      // this exact field. Phase 6 is the phase that consumes it, so the rule
      // is re-asserted from this route.
      const u = await registerUser(ctx.app);
      for (let i = 0; i < 3; i += 1) {
        expect((await summary(u.headers)).json<Envelope<Summary>>().data.isProvider).toBe(false);
      }
      expect(await ctx.prisma.providerProfile.count({ where: { userId: u.userId } })).toBe(0);
    });
  });

  describe('PATCH /v1/users/me', () => {
    it('changes the name, and the next summary read reflects it', async () => {
      const u = await registerUser(ctx.app);
      const res = await patch(u.headers, { fullName: 'Aishath Naeema' });
      expect(res.statusCode).toBe(200);
      expect(res.json<Envelope<{ fullName: string }>>().data.fullName).toBe('Aishath Naeema');
      expect((await summary(u.headers)).json<Envelope<Summary>>().data.fullName).toBe(
        'Aishath Naeema',
      );
      const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      expect(row.fullName).toBe('Aishath Naeema');
    });

    it('audits the change by name of the action, never by value', async () => {
      const u = await registerUser(ctx.app);
      await patch(u.headers, { fullName: 'Mariyam Hussain' });
      const entry = await ctx.prisma.auditLogEntry.findFirst({
        where: { actorId: u.userId, action: 'user.name.changed' },
      });
      expect(entry).not.toBeNull();
      expect(entry?.targetId).toBe(u.userId);
      // A name is a PII value; the log takes IDs, enums and counts only.
      expect(JSON.stringify(entry)).not.toContain('Mariyam');
    });

    it('trims, and refuses a blank or oversized name at the field', async () => {
      const u = await registerUser(ctx.app);
      expect((await patch(u.headers, { fullName: '  Ibrahim Rasheed  ' })).statusCode).toBe(200);
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).fullName).toBe(
        'Ibrahim Rasheed',
      );

      for (const bad of ['', '   ', 'x'.repeat(121)]) {
        const res = await patch(u.headers, { fullName: bad });
        expect(res.statusCode).toBe(400);
        expect(res.json<Err>().error.details?.[0]?.path).toBe('fullName');
      }
      // Nothing landed from the rejected attempts.
      expect((await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).fullName).toBe(
        'Ibrahim Rasheed',
      );
    });

    it('cannot reach any column it does not own, even when one is named', async () => {
      const u = await registerUser(ctx.app);
      const before = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      const res = await patch(u.headers, {
        fullName: 'Legitimate Change',
        email: 'attacker@example.test',
        phoneE164: '+9607654321',
        status: 'anonymised',
        emailVerifiedAt: new Date().toISOString(),
        passwordHash: 'nope',
      });
      expect(res.statusCode).toBe(200);

      const after = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
      // The one field it owns landed; the five it does not are untouched.
      expect(after.fullName).toBe('Legitimate Change');
      expect(after.email).toBe(before.email);
      expect(after.phoneE164).toBe(before.phoneE164);
      expect(after.status).toBe(before.status);
      expect(after.emailVerifiedAt).toEqual(before.emailVerifiedAt);
      expect(after.passwordHash).toBe(before.passwordHash);
    });

    it('is refused on a frozen account, whose name anonymisation is about to replace', async () => {
      const u = await registerUser(ctx.app);
      expect(
        (
          await ctx.app.inject({
            method: 'POST',
            url: '/v1/users/me/deletion-request',
            headers: u.headers,
          })
        ).statusCode,
      ).toBe(202);

      const res = await patch(u.headers, { fullName: 'Too Late' });
      expect(res.statusCode).toBe(422);
      expect(res.json<Err>().error.code).toBe('ACCOUNT_FROZEN');
      expect(
        (await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } })).fullName,
      ).not.toBe('Too Late');
    });

    it('rejects an unauthenticated write before it validates the body', async () => {
      const res = await ctx.app.inject({
        method: 'PATCH',
        url: '/v1/users/me',
        remoteAddress: freshIp(),
        payload: { fullName: '' },
      });
      expect(res.statusCode).toBe(401);
    });
  });
});
