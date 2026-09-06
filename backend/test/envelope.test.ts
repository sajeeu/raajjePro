import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { BusinessRuleError } from '../src/core/errors.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('response envelope and error handling', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        app.post(
          '/v1/_test/validated',
          {
            schema: { body: z.object({ name: z.string().min(2), amountLaari: z.number().int() }) },
          },
          (request) => ({ data: request.body }),
        );
        app.get('/v1/_test/business-rule', () => {
          throw new BusinessRuleError('EMAIL_NOT_VERIFIED', 'Verify your email first');
        });
        app.get('/v1/_test/explode', () => {
          throw new Error('database password is hunter2');
        });
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('wraps a Zod violation in the envelope with path and message only', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/validated',
      payload: { name: 'x', amountLaari: 1.5 },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json<{
      error: { code: string; details: { path: string; message: string }[] };
      requestId: string;
    }>();
    expect(body.error.code).toBe('VALIDATION_FAILED');
    expect(body.error.details.map((d) => d.path).sort()).toEqual(['amountLaari', 'name']);
    for (const detail of body.error.details) {
      expect(Object.keys(detail).sort()).toEqual(['message', 'path']);
    }
    expect(body.requestId).toBe(res.headers['x-request-id']);
  });

  it('wraps invalid JSON as MALFORMED_BODY', async () => {
    const res = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/validated',
      headers: { 'content-type': 'application/json' },
      payload: '{ not json',
    });
    expect(res.statusCode).toBe(400);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('MALFORMED_BODY');
  });

  it('wraps an unknown route as NOT_FOUND', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/nowhere' });
    expect(res.statusCode).toBe(404);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('NOT_FOUND');
  });

  it('carries a business-rule code at 422', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/business-rule' });
    expect(res.statusCode).toBe(422);
    expect(res.json<{ error: { code: string; message: string } }>().error).toEqual({
      code: 'EMAIL_NOT_VERIFIED',
      message: 'Verify your email first',
    });
  });

  it('never leaks an unexpected error', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/_test/explode' });
    expect(res.statusCode).toBe(500);
    expect(res.body).not.toContain('hunter2');
    expect(res.body).not.toContain('stack');
    expect(res.json<{ error: { code: string } }>().error.code).toBe('INTERNAL_ERROR');
  });

  it('honours a UUID X-Request-Id and replaces anything else', async () => {
    const given = '5a3d0e8c-2c3a-4d8e-9f1b-7c6a5b4d3e2f';
    const honoured = await ctx.app.inject({
      method: 'GET',
      url: '/v1/nowhere',
      headers: { 'x-request-id': given },
    });
    expect(honoured.headers['x-request-id']).toBe(given);
    const replaced = await ctx.app.inject({
      method: 'GET',
      url: '/v1/nowhere',
      headers: { 'x-request-id': 'evil\nheader' },
    });
    expect(replaced.headers['x-request-id']).not.toBe('evil\nheader');
    expect(replaced.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
  });
});
