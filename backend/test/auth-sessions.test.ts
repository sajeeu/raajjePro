import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { TokenPair } from '../src/modules/auth/service.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import { bearer, createUser, RecordingEmailTransport } from './helpers/users.js';

interface Err {
  error: { code: string };
}

describe.skipIf(databaseUrl === undefined)('user sessions — refresh, logout, me, sessions', () => {
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

  async function openSession(
    deviceName = 'Test phone',
  ): Promise<{ userId: string; tokens: TokenPair }> {
    const user = await createUser(ctx.prisma);
    const full = await ctx.prisma.user.findUniqueOrThrow({
      where: { id: user.id },
      include: { providerProfile: true },
    });
    const tokens = await ctx.app.auth.openSession(
      full,
      { ip: freshIp(), userAgent: 'vitest', requestId: 'r' },
      time.clock(),
      deviceName,
    );
    return { userId: user.id, tokens };
  }

  it('GET /me returns the DTO — never the hash, never a token — and no header is 401 UNAUTHENTICATED', async () => {
    const { userId, tokens } = await openSession();
    const res = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(tokens.accessToken),
    });
    expect(res.statusCode).toBe(200);
    const me = res.json<{ data: Record<string, unknown> }>().data;
    expect(me.id).toBe(userId);
    expect(me.emailVerified).toBe(false);
    expect(me.status).toBe('active');
    expect(me.isProvider).toBe(false);
    expect(res.body).not.toContain('passwordHash');
    expect(res.body).not.toContain(tokens.refreshToken);
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/auth/me' });
    expect(none.statusCode).toBe(401);
    expect(none.json<Err>().error.code).toBe('UNAUTHENTICATED');
  });

  it('an expired access token is ACCESS_TOKEN_EXPIRED; a revoked session is SESSION_EXPIRED', async () => {
    const { tokens } = await openSession();
    time.advance(16 * 60_000);
    const expired = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(tokens.accessToken),
    });
    expect(expired.statusCode).toBe(401);
    expect(expired.json<Err>().error.code).toBe('ACCESS_TOKEN_EXPIRED');
    time.advance(-16 * 60_000);
    await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/logout',
      headers: bearer(tokens.accessToken),
    });
    const revoked = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(tokens.accessToken),
    });
    expect(revoked.statusCode).toBe(401);
    expect(revoked.json<Err>().error.code).toBe('SESSION_EXPIRED');
  });

  it('refresh rotates: the new pair works, the old refresh token is refused, reuse after 30 s revokes the session', async () => {
    const { tokens } = await openSession();
    const first = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(first.statusCode).toBe(200);
    const next = first.json<{ data: { tokens: TokenPair } }>().data.tokens;
    expect(next.refreshToken).not.toBe(tokens.refreshToken);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(next.accessToken),
        })
      ).statusCode,
    ).toBe(200);

    // Inside the grace window: a client retry, not theft.
    time.advance(10_000);
    const retry = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(retry.statusCode).toBe(401);
    expect(retry.json<Err>().error.code).toBe('REFRESH_TOKEN_ROTATED');
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(next.accessToken),
        })
      ).statusCode,
    ).toBe(200);

    // Past the grace window: replay of a rotated token revokes everything.
    time.advance(31_000);
    const reuse = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(reuse.statusCode).toBe(401);
    expect(reuse.json<Err>().error.code).toBe('SESSION_EXPIRED');
    const dead = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: bearer(next.accessToken),
    });
    expect(dead.json<Err>().error.code).toBe('SESSION_EXPIRED');
    const deadRefresh = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: next.refreshToken },
    });
    expect(deadRefresh.statusCode).toBe(401);
  });

  it('two concurrent refreshes with one token → exactly one success', async () => {
    const { tokens } = await openSession();
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        ctx.app.inject({
          method: 'POST',
          url: '/v1/auth/refresh',
          remoteAddress: freshIp(),
          payload: { refreshToken: tokens.refreshToken },
        }),
      ),
    );
    expect(results.filter((r) => r.statusCode === 200)).toHaveLength(1);
    expect(
      results.filter(
        (r) => r.json<{ error?: { code: string } }>().error?.code === 'REFRESH_TOKEN_ROTATED',
      ),
    ).toHaveLength(4);
  });

  it('an expired refresh token is SESSION_EXPIRED and marks the session refresh_expired', async () => {
    const { tokens } = await openSession();
    time.advance(31 * 24 * 3_600_000);
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: tokens.refreshToken },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json<Err>().error.code).toBe('SESSION_EXPIRED');
    time.advance(-31 * 24 * 3_600_000);
    const unknown = await ctx.app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      remoteAddress: freshIp(),
      payload: { refreshToken: 'a'.repeat(43) },
    });
    expect(unknown.json<Err>().error.code).toBe('UNAUTHENTICATED');
  });

  it('sessions list marks the current device; revoking one leaves the other live; a foreign id is 404', async () => {
    const user = await createUser(ctx.prisma);
    const full = await ctx.prisma.user.findUniqueOrThrow({
      where: { id: user.id },
      include: { providerProfile: true },
    });
    const meta = { ip: freshIp(), userAgent: 'vitest', requestId: 'r' };
    const phone = await ctx.app.auth.openSession(full, meta, time.clock(), 'iPhone 14');
    const tablet = await ctx.app.auth.openSession(full, meta, time.clock(), 'Pixel 7');
    const list = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/sessions',
      headers: bearer(phone.accessToken),
    });
    const rows = list.json<{ data: { id: string; deviceName: string; current: boolean }[] }>().data;
    expect(rows).toHaveLength(2);
    expect(rows.find((r) => r.current)?.deviceName).toBe('iPhone 14');
    expect(list.body).not.toContain('ipAddress');
    const other = rows.find((r) => !r.current);
    const revoke = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/auth/sessions/${other?.id ?? ''}`,
      headers: bearer(phone.accessToken),
    });
    expect(revoke.statusCode).toBe(200);
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(tablet.accessToken),
        })
      ).json<Err>().error.code,
    ).toBe('SESSION_EXPIRED');
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/auth/me',
          headers: bearer(phone.accessToken),
        })
      ).statusCode,
    ).toBe(200);

    const stranger = await openSession();
    const foreign = await ctx.app.inject({
      method: 'DELETE',
      url: `/v1/auth/sessions/${rows[0]?.id ?? ''}`,
      headers: bearer(stranger.tokens.accessToken),
    });
    expect(foreign.statusCode).toBe(404);
  });

  it('an admin cookie never satisfies a user route', async () => {
    const res = await ctx.app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: { cookie: 'rp_admin_session=whatever' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('DELETE /sessions/:id with no token is 401, not 400, even though the id is not a UUID', async () => {
    const res = await ctx.app.inject({ method: 'DELETE', url: '/v1/auth/sessions/not-a-uuid' });
    expect(res.statusCode).toBe(401);
    expect(res.json<Err>().error.code).toBe('UNAUTHENTICATED');
  });
});
