import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildTestApp, databaseUrl, freshIp } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('rate limiting', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      anonPerMinute: 3,
      authPerMinute: 5,
      routes: (app) => {
        app.get('/v1/_test/open', () => ({ data: 'open' }));
        app.get(
          '/v1/_test/strict',
          { config: { rateLimit: { max: 1, timeWindow: '15 minutes' } } },
          () => ({
            data: 'strict',
          }),
        );
        // Pretend-authenticated route: sets a principal so the store keys on the user, not the IP.
        app.get(
          '/v1/_test/as-user',
          {
            onRequest: (request, _reply, done) => {
              request.principal = {
                kind: 'admin',
                id: String(request.headers['x-test-user']),
                sessionId: '',
                mfaVerified: true,
                totpEnrolled: true,
                reauthenticatedAt: null,
              };
              done();
            },
          },
          () => ({ data: 'user' }),
        );
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('blocks the request after the anonymous tier with the envelope and Retry-After', async () => {
    const ip = freshIp();
    for (let i = 0; i < 3; i += 1) {
      const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip });
      expect(res.statusCode).toBe(200);
    }
    const blocked = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/open',
      remoteAddress: ip,
    });
    expect(blocked.statusCode).toBe(429);
    const body = blocked.json<{
      error: { code: string; details: { retryAfterSeconds: number } };
    }>();
    expect(body.error.code).toBe('RATE_LIMITED');
    expect(body.error.details.retryAfterSeconds).toBeGreaterThan(0);
    // The anonymous tier's window is 1 minute — retryAfterSeconds is computed
    // entirely from Postgres's own clock (window_started_at vs its own now()),
    // so a bound here also catches a regression back to mixing it with
    // Node's Date.now().
    expect(body.error.details.retryAfterSeconds).toBeLessThanOrEqual(60);
    expect(body.error.details.retryAfterSeconds).toBeGreaterThanOrEqual(1);
    expect(Number(blocked.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('keys an authenticated request by principal, not IP', async () => {
    const ip = freshIp();
    const user = randomUUID();
    for (let i = 0; i < 5; i += 1) {
      const res = await ctx.app.inject({
        method: 'GET',
        url: '/v1/_test/as-user',
        remoteAddress: ip,
        headers: { 'x-test-user': user },
      });
      expect(res.statusCode).toBe(200);
    }
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/_test/as-user',
          remoteAddress: ip,
          headers: { 'x-test-user': user },
        })
      ).statusCode,
    ).toBe(429);
    // Same IP, different user: not affected.
    expect(
      (
        await ctx.app.inject({
          method: 'GET',
          url: '/v1/_test/as-user',
          remoteAddress: ip,
          headers: { 'x-test-user': randomUUID() },
        })
      ).statusCode,
    ).toBe(200);
  });

  it('a per-route override replaces the global tier for that route only', async () => {
    const ip = freshIp();
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/_test/strict', remoteAddress: ip }))
        .statusCode,
    ).toBe(200);
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/_test/strict', remoteAddress: ip }))
        .statusCode,
    ).toBe(429);
    expect(
      (await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip }))
        .statusCode,
    ).toBe(200);
  });

  it('counters survive an app restart because they live in the database', async () => {
    const ip = freshIp();
    for (let i = 0; i < 3; i += 1) {
      await ctx.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip });
    }
    const second = await buildTestApp({
      anonPerMinute: 3,
      routes: (app) => {
        app.get('/v1/_test/open', () => ({ data: 'open' }));
      },
    });
    try {
      expect(
        (await second.app.inject({ method: 'GET', url: '/v1/_test/open', remoteAddress: ip }))
          .statusCode,
      ).toBe(429);
    } finally {
      await second.app.close();
      await second.prisma.$disconnect();
    }
  });
});
