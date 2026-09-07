import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { UserPrincipal } from '../src/core/principal.js';
import {
  requireActiveAccount,
  requireAuth,
  requireEmailVerified,
} from '../src/modules/auth/guards.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

function principalFrom(header: unknown): UserPrincipal | undefined {
  if (typeof header !== 'string' || header === '') return undefined;
  const [emailVerified, status] = header.split(':');
  return {
    kind: 'user',
    id: '11111111-1111-4111-8111-111111111111',
    sessionId: '22222222-2222-4222-8222-222222222222',
    emailVerified: emailVerified === 'verified',
    status: status === 'frozen' ? 'frozen' : 'active',
  };
}

describe.skipIf(databaseUrl === undefined)('user guards', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        const inject = (
          request: { principal?: unknown; headers: Record<string, unknown> },
          _r: unknown,
          done: () => void,
        ) => {
          const p = principalFrom(request.headers['x-test-principal']);
          if (p !== undefined) request.principal = p;
          done();
        };
        // eslint-disable-next-line @typescript-eslint/require-await
        app.get('/v1/_test/auth', { onRequest: inject, preHandler: requireAuth }, async () => ({
          data: 'ok',
        }));
        app.get(
          '/v1/_test/verified',
          { onRequest: inject, preHandler: requireEmailVerified },
          // eslint-disable-next-line @typescript-eslint/require-await
          async () => ({ data: 'ok' }),
        );
        app.get(
          '/v1/_test/active',
          { onRequest: inject, preHandler: requireActiveAccount },
          // eslint-disable-next-line @typescript-eslint/require-await
          async () => ({ data: 'ok' }),
        );
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const code = (res: { json: () => { error: { code: string } } }) => res.json().error.code;

  it('requireAuth: no principal → 401 UNAUTHENTICATED; a user → 200', async () => {
    const none = await ctx.app.inject({ method: 'GET', url: '/v1/_test/auth' });
    expect(none.statusCode).toBe(401);
    expect(code(none)).toBe('UNAUTHENTICATED');
    const ok = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/auth',
      headers: { 'x-test-principal': 'unverified:active' },
    });
    expect(ok.statusCode).toBe(200);
  });

  it('requireEmailVerified: unverified → 422 EMAIL_NOT_VERIFIED; verified → 200; browsing routes stay open', async () => {
    const no = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/verified',
      headers: { 'x-test-principal': 'unverified:active' },
    });
    expect(no.statusCode).toBe(422);
    expect(code(no)).toBe('EMAIL_NOT_VERIFIED');
    const yes = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/verified',
      headers: { 'x-test-principal': 'verified:active' },
    });
    expect(yes.statusCode).toBe(200);
    const anon = await ctx.app.inject({ method: 'GET', url: '/v1/_test/verified' });
    expect(anon.statusCode).toBe(401);
    const browse = await ctx.app.inject({
      method: 'GET',
      url: '/v1/health',
      headers: { 'x-test-principal': 'unverified:active' },
    });
    expect(browse.statusCode).toBe(200);
  });

  it('requireActiveAccount: frozen → 422 ACCOUNT_FROZEN; active → 200', async () => {
    const frozen = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/active',
      headers: { 'x-test-principal': 'verified:frozen' },
    });
    expect(frozen.statusCode).toBe(422);
    expect(code(frozen)).toBe('ACCOUNT_FROZEN');
    const active = await ctx.app.inject({
      method: 'GET',
      url: '/v1/_test/active',
      headers: { 'x-test-principal': 'verified:active' },
    });
    expect(active.statusCode).toBe(200);
  });
});
