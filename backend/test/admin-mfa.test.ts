import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  CSRF,
  PASSWORD,
  cookieFrom,
  createEnrolledAdmin,
  loginAndVerify,
  totpNow,
} from './helpers/admin.js';

describe.skipIf(databaseUrl === undefined)('admin MFA', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date());

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, reauthMinutes: 5 });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('enrolment: uri + secret once, confirm with a valid code, recovery codes returned exactly once, then /me works', async () => {
    const email = `admin-${randomUUID()}@example.test`;
    await ctx.app.adminAuth.createAdmin(email, PASSWORD, {});
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email, password: PASSWORD },
    });
    const cookie = cookieFrom(login);

    const enrol = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/enrol',
      headers: { cookie, ...CSRF },
    });
    expect(enrol.statusCode).toBe(200);
    const { secret, otpauthUri } = enrol.json<{ data: { secret: string; otpauthUri: string } }>()
      .data;
    expect(otpauthUri).toMatch(/^otpauth:\/\/totp\/RaajjePro/);
    expect(otpauthUri).toContain(secret);

    const wrong = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/enrol/confirm',
      headers: { cookie, ...CSRF },
      payload: { code: '000000' },
    });
    expect(wrong.statusCode).toBe(422);
    expect(wrong.json<{ error: { code: string } }>().error.code).toBe('INVALID_MFA_CODE');

    const confirm = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/enrol/confirm',
      headers: { cookie, ...CSRF },
      payload: { code: await totpNow(secret) },
    });
    expect(confirm.statusCode).toBe(200);
    const { recoveryCodes } = confirm.json<{ data: { recoveryCodes: string[] } }>().data;
    expect(recoveryCodes).toHaveLength(10);

    const me = await ctx.app.inject({
      method: 'GET',
      url: '/v1/admin/auth/me',
      headers: { cookie },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json<{ data: { totpEnrolled: boolean } }>().data.totpEnrolled).toBe(true);

    const again = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/enrol',
      headers: { cookie, ...CSRF },
    });
    expect(again.statusCode).toBe(422);
    expect(again.json<{ error: { code: string } }>().error.code).toBe('MFA_ALREADY_ENROLLED');
  });

  it('a new session on an enrolled account is MFA_REQUIRED until verified', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email: admin.email, password: PASSWORD },
    });
    expect(login.json<{ data: { state: string } }>().data.state).toBe('mfa_required');
    const cookie = cookieFrom(login);
    const me = await ctx.app.inject({
      method: 'GET',
      url: '/v1/admin/auth/me',
      headers: { cookie },
    });
    expect(me.statusCode).toBe(401);
    expect(me.json<{ error: { code: string } }>().error.code).toBe('MFA_REQUIRED');
    const verify = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/verify',
      headers: { cookie, ...CSRF },
      payload: { code: await totpNow(admin.secret) },
    });
    expect(verify.statusCode).toBe(200);
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me', headers: { cookie } }))
        .statusCode,
    ).toBe(200);
  });

  it('a recovery code verifies once and is refused on reuse', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const code = admin.recoveryCodes[0] ?? '';
    const first = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email: admin.email, password: PASSWORD },
    });
    const c1 = cookieFrom(first);
    const ok1 = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/verify',
      headers: { cookie: c1, ...CSRF },
      payload: { code },
    });
    expect(ok1.statusCode).toBe(200);
    expect(ok1.json<{ data: { method: string } }>().data.method).toBe('recovery_code');

    const second = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email: admin.email, password: PASSWORD },
    });
    const c2 = cookieFrom(second);
    const reused = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/verify',
      headers: { cookie: c2, ...CSRF },
      payload: { code },
    });
    expect(reused.statusCode).toBe(422);
    const audit = await ctx.prisma.auditLogEntry.count({
      where: { action: 'admin.mfa.recovery_code_used', actorId: admin.adminId },
    });
    expect(audit).toBe(1);
  });

  it('five failed verifications revoke the session', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email: admin.email, password: PASSWORD },
    });
    const cookie = cookieFrom(login);
    for (let i = 0; i < 5; i += 1) {
      const res = await ctx.app.inject({
        method: 'POST',
        url: '/v1/admin/auth/mfa/verify',
        headers: { cookie, ...CSRF },
        payload: { code: '000000' },
      });
      expect(res.statusCode).toBe(422);
    }
    const after = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/verify',
      headers: { cookie, ...CSRF },
      payload: { code: await totpNow(admin.secret) },
    });
    expect(after.statusCode).toBe(401);
    const row = await ctx.prisma.adminSession.findFirst({
      where: { adminId: admin.adminId, revokedReason: 'mfa_failures' },
    });
    expect(row).not.toBeNull();
  });

  it('re-authentication gates the recovery-code regeneration and expires after the configured window', async () => {
    const admin = await createEnrolledAdmin(ctx.app);
    const { cookie } = await loginAndVerify(ctx.app, admin.email, admin.secret);
    const url = '/v1/admin/auth/mfa/recovery-codes/regenerate';
    const before = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(before.statusCode).toBe(403);
    expect(before.json<{ error: { code: string } }>().error.code).toBe('REAUTHENTICATION_REQUIRED');

    const badReauth = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/reauth',
      headers: { cookie, ...CSRF },
      payload: { password: 'wrong password 12', code: await totpNow(admin.secret) },
    });
    expect(badReauth.statusCode).toBe(401);
    const reauth = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/reauth',
      headers: { cookie, ...CSRF },
      payload: { password: PASSWORD, code: await totpNow(admin.secret) },
    });
    expect(reauth.statusCode).toBe(200);

    const regenerated = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(regenerated.statusCode).toBe(200);
    const fresh = regenerated.json<{ data: { recoveryCodes: string[] } }>().data.recoveryCodes;
    expect(fresh).toHaveLength(10);
    expect(fresh).not.toContain(admin.recoveryCodes[1]);
    // The old set is revoked.
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: CSRF,
      remoteAddress: freshIp(),
      payload: { email: admin.email, password: PASSWORD },
    });
    const oldCode = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/mfa/verify',
      headers: { cookie: cookieFrom(login), ...CSRF },
      payload: { code: admin.recoveryCodes[1] ?? '' },
    });
    expect(oldCode.statusCode).toBe(422);

    time.advance(5 * 60_000 + 1000);
    const stale = await ctx.app.inject({ method: 'POST', url, headers: { cookie, ...CSRF } });
    expect(stale.statusCode).toBe(403);
    time.set(new Date());
  });
});
