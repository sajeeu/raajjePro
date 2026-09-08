import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { assertRecoverableByEmail } from '../src/modules/account/service.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  bearer,
  freshEmail,
  freshPhone,
  RecordingEmailTransport,
  registerUser,
} from './helpers/users.js';

interface Err {
  error: { code: string; details?: { path: string }[] };
}

describe.skipIf(databaseUrl === undefined)('account settings', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  const mail = new RecordingEmailTransport();

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, deps: { emailTransport: mail } });
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const login = (email: string, password: string, deviceName = 'other') =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      remoteAddress: freshIp(),
      payload: { email, password, deviceName },
    });

  it('change password: wrong current → INVALID_CREDENTIALS at the field; right → other sessions revoked, this one kept, new password works', async () => {
    const u = await registerUser(ctx.app);
    const other = (await login(u.email, u.password)).json<{
      data: { tokens: { accessToken: string } };
    }>().data.tokens;
    const wrong = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-password',
      headers: u.headers,
      payload: { currentPassword: 'nope nope nope', newPassword: 'a brand new password' },
    });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<Err>().error.code).toBe('INVALID_CREDENTIALS');
    const ok = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-password',
      headers: u.headers,
      payload: { currentPassword: u.password, newPassword: 'a brand new password' },
    });
    expect(ok.statusCode).toBe(200);
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/auth/me', headers: u.headers })).statusCode,
    ).toBe(200);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(other.accessToken),
        })
      ).json<Err>().error.code,
    ).toBe('SESSION_EXPIRED');
    expect((await login(u.email, u.password)).statusCode).toBe(401);
    expect((await login(u.email, 'a brand new password')).statusCode).toBe(200);
    const row = await ctx.prisma.user.findUniqueOrThrow({ where: { id: u.userId } });
    expect(row.passwordChangedAt.getTime()).toBe(time.clock().getTime());
  });

  it('change email: OTP goes to the NEW address, an in-use address is refused, confirm switches and re-verifies, other sessions revoked', async () => {
    const u = await registerUser(ctx.app);
    const taken = await registerUser(ctx.app);
    const inUse = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/request',
      headers: u.headers,
      payload: { newEmail: taken.email, currentPassword: u.password },
    });
    expect(inUse.statusCode).toBe(409);
    expect(inUse.json<Err>().error.code).toBe('EMAIL_IN_USE');
    const same = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/request',
      headers: u.headers,
      payload: { newEmail: u.email, currentPassword: u.password },
    });
    expect(same.json<Err>().error.code).toBe('EMAIL_UNCHANGED');
    const badPw = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/request',
      headers: u.headers,
      payload: { newEmail: freshEmail(), currentPassword: 'wrong wrong wrong' },
    });
    expect(badPw.json<Err>().error.code).toBe('INVALID_CREDENTIALS');

    const newEmail = freshEmail();
    const other = (await login(u.email, u.password)).json<{
      data: { tokens: { accessToken: string } };
    }>().data.tokens;
    const req = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/request',
      headers: u.headers,
      payload: { newEmail, currentPassword: u.password },
    });
    expect(req.statusCode).toBe(200);
    expect(mail.latestCodeFor(newEmail)).toMatch(/^\d{6}$/);
    expect(mail.latestCodeFor(u.email)).not.toBe(mail.latestCodeFor(newEmail));
    const confirm = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/confirm',
      headers: u.headers,
      payload: { code: mail.latestCodeFor(newEmail) ?? '' },
    });
    expect(confirm.statusCode).toBe(200);
    const me = confirm.json<{ data: { email: string; emailVerified: boolean } }>().data;
    expect(me.email).toBe(newEmail.toLowerCase());
    expect(me.emailVerified).toBe(true);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(other.accessToken),
        })
      ).json<Err>().error.code,
    ).toBe('SESSION_EXPIRED');
    expect((await login(newEmail, u.password)).statusCode).toBe(200);
    expect((await login(u.email, u.password)).statusCode).toBe(401);
    const audit = await ctx.prisma.auditLogEntry.findFirst({
      where: { action: 'user.email.changed', actorId: u.userId },
    });
    expect(JSON.stringify(audit)).not.toContain(newEmail.toLowerCase());
  });

  it('change email confirm refuses an address that became in-use between request and confirm', async () => {
    const u = await registerUser(ctx.app);
    const target = freshEmail();
    await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/request',
      headers: u.headers,
      payload: { newEmail: target, currentPassword: u.password },
    });
    // Capture the code before the second registration also emails `target` —
    // that registration's own verify-email send would otherwise become the
    // "latest" message to that address and shadow the one under test.
    const code = mail.latestCodeFor(target) ?? '';
    await registerUser(ctx.app, { email: target });
    const confirm = await ctx.app.inject({
      method: 'POST',
      url: '/v1/users/me/change-email/confirm',
      headers: u.headers,
      payload: { code },
    });
    expect(confirm.statusCode).toBe(409);
    expect(confirm.json<Err>().error.code).toBe('EMAIL_IN_USE');
  });

  it('change phone: format re-checked, Bronze-uniqueness re-checked, stored as entered, never marked verified', async () => {
    const u = await registerUser(ctx.app);
    const bad = await ctx.app.inject({
      method: 'PATCH',
      url: '/v1/users/me/phone',
      headers: u.headers,
      payload: { dialCode: '+960', number: '12' },
    });
    expect(bad.statusCode).toBe(400);
    expect(bad.json<Err>().error.details?.[0]?.path).toBe('phone');
    const bronze = await registerUser(ctx.app, { role: 'provider' });
    await ctx.prisma.providerProfile.update({
      where: { userId: bronze.userId },
      data: { verificationTier: 'bronze' },
    });
    const held = await ctx.app.inject({
      method: 'PATCH',
      url: '/v1/users/me/phone',
      headers: u.headers,
      payload: { dialCode: '+960', number: bronze.phone },
    });
    expect(held.statusCode).toBe(409);
    expect(held.json<Err>().error.code).toBe('PHONE_IN_USE');
    const fresh = freshPhone();
    const ok = await ctx.app.inject({
      method: 'PATCH',
      url: '/v1/users/me/phone',
      headers: u.headers,
      payload: { dialCode: '+44', number: fresh },
    });
    expect(ok.statusCode).toBe(200);
    const dto = ok.json<{ data: Record<string, unknown> }>().data;
    expect(dto.phone).toEqual({ dialCode: '+44', number: fresh });
    expect(JSON.stringify(dto)).not.toMatch(/phoneVerified|verified":true/);
    // Keeping your own number is fine even at Bronze.
    await ctx.prisma.providerProfile.create({
      data: { userId: u.userId, verificationTier: 'bronze' },
    });
    expect(
      (
        await ctx.app.inject({
          method: 'PATCH',
          url: '/v1/users/me/phone',
          headers: u.headers,
          payload: { dialCode: '+44', number: fresh },
        })
      ).statusCode,
    ).toBe(200);
  });

  it("assertRecoverableByEmail: unverified throws EMAIL_NOT_VERIFIED, verified passes (the rule Phase 3b's reset calls)", () => {
    expect(() => {
      assertRecoverableByEmail({ emailVerifiedAt: null });
    }).toThrow(/EMAIL_NOT_VERIFIED|Verify/);
    expect(() => {
      assertRecoverableByEmail({ emailVerifiedAt: new Date() });
    }).not.toThrow();
  });

  it('every account route is 401 without a token', async () => {
    for (const [method, url] of [
      ['POST', '/v1/users/me/change-password'],
      ['POST', '/v1/users/me/change-email/request'],
      ['POST', '/v1/users/me/change-email/confirm'],
      ['PATCH', '/v1/users/me/phone'],
    ] as const) {
      const res = await ctx.app.inject({ method, url, payload: {} });
      expect(res.statusCode, `${method} ${url}`).toBe(401);
    }
  });
});
