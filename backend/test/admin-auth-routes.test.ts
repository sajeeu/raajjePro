import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';

const PASSWORD = 'a long enough password';
const csrf = { 'x-requested-with': 'RaajjePro-Admin' };

function cookieFrom(res: { headers: Record<string, unknown> }): string {
  const raw = res.headers['set-cookie'];
  const first: unknown = Array.isArray(raw) ? (raw as unknown[])[0] : raw;
  return String(first).split(';')[0] ?? '';
}

describe.skipIf(databaseUrl === undefined)('admin auth routes — login and sessions', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  const time = controllableClock(new Date('2026-09-06T10:00:00Z'));
  let email: string;

  beforeAll(async () => {
    ctx = await buildTestApp({ clock: time.clock, sessionIdleMinutes: 15 });
    email = `admin-${randomUUID()}@example.test`;
    await ctx.app.adminAuth.createAdmin(email, PASSWORD, {});
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('refuses a mutating admin request without the CSRF header', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      remoteAddress: freshIp(),
      payload: { email, password: PASSWORD },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('CSRF_HEADER_MISSING');
  });

  it('logs in, sets a hardened cookie, and reports the enrolment-required state', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email, password: PASSWORD },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json<{ data: { state: string } }>().data.state).toBe('mfa_enrolment_required');
    const setCookie = String(res.headers['set-cookie']);
    expect(setCookie).toContain('rp_admin_session=');
    expect(setCookie).toContain('HttpOnly');
    expect(setCookie).toContain('SameSite=Strict');
    expect(setCookie).toContain('Path=/v1/admin');
    expect(res.body).not.toContain('passwordHash');
  });

  it('trims a whitespace-padded email before validating it', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email: `  ${email}  `, password: PASSWORD },
    });
    expect(res.statusCode).toBe(200);
  });

  it('validates the login body and rejects wrong credentials with the same code', async () => {
    const bad = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email: 'not-an-email' },
    });
    expect(bad.statusCode).toBe(400);
    const wrong = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email, password: 'wrong password 12' },
    });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.json<{ error: { code: string } }>().error.code).toBe('INVALID_CREDENTIALS');
    const unknown = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email: `x-${randomUUID()}@example.test`, password: 'wrong password 12' },
    });
    expect(unknown.json<{ error: { code: string } }>().error.code).toBe('INVALID_CREDENTIALS');
  });

  it('an unenrolled admin is refused on every guarded route with MFA_ENROLMENT_REQUIRED', async () => {
    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email, password: PASSWORD },
    });
    const cookie = cookieFrom(login);
    for (const [method, url] of [
      ['GET', '/v1/admin/auth/me'],
      ['GET', '/v1/admin/auth/sessions'],
      ['POST', '/v1/admin/auth/logout'],
      ['GET', '/v1/admin/audit-log'],
    ] as const) {
      const res = await ctx.app.inject({ method, url, headers: { cookie, ...csrf } });
      expect(res.statusCode, `${method} ${url}`).toBe(403);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('MFA_ENROLMENT_REQUIRED');
    }
  });

  it('no cookie → UNAUTHENTICATED; idle session → SESSION_EXPIRED', async () => {
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/admin/auth/me' });
    expect(none.statusCode).toBe(401);
    expect(none.json<{ error: { code: string } }>().error.code).toBe('UNAUTHENTICATED');

    const login = await ctx.app.inject({
      method: 'POST',
      url: '/v1/admin/auth/login',
      headers: csrf,
      remoteAddress: freshIp(),
      payload: { email, password: PASSWORD },
    });
    const cookie = cookieFrom(login);
    time.advance(16 * 60_000);
    const expired = await ctx.app.inject({
      method: 'GET',
      url: '/v1/admin/auth/me',
      headers: { cookie },
    });
    expect(expired.statusCode).toBe(401);
    expect(expired.json<{ error: { code: string } }>().error.code).toBe('SESSION_EXPIRED');
  });

  it('the login route carries its own stricter rate limit', async () => {
    const ip = freshIp();
    let last = 0;
    for (let i = 0; i < 11; i += 1) {
      const res = await ctx.app.inject({
        method: 'POST',
        url: '/v1/admin/auth/login',
        headers: csrf,
        remoteAddress: ip,
        payload: { email, password: 'wrong password 12' },
      });
      last = res.statusCode;
    }
    expect(last).toBe(429);
    // Other routes from the same IP still answer.
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/health', remoteAddress: ip })).statusCode,
    ).toBe(200);
  });
});
