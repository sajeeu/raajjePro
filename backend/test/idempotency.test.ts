import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('idempotency middleware', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  let handlerRuns = 0;

  beforeAll(async () => {
    ctx = await buildTestApp({
      routes: (app) => {
        app.post(
          '/v1/_test/create',
          {
            config: { idempotency: { operation: 'test.create' } },
            schema: { body: z.object({ name: z.string() }) },
            onRequest: (request, _reply, done) => {
              request.principal = {
                kind: 'admin',
                id: String(request.headers['x-test-user'] ?? 'anon-user'),
                sessionId: '',
                mfaVerified: true,
                totpEnrolled: true,
                reauthenticatedAt: null,
              };
              done();
            },
          },
          async (request, reply) => {
            handlerRuns += 1;
            await new Promise((r) => setTimeout(r, 25));
            const body = request.body as { name: string };
            return reply
              .code(201)
              .send({ data: { id: randomUUID(), name: body.name, run: handlerRuns } });
          },
        );
        app.post(
          '/v1/_test/fails',
          { config: { idempotency: { operation: 'test.fails' } } },
          () => {
            throw new Error('boom');
          },
        );
      },
    });
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (key: string | undefined, body: Record<string, unknown>, user = randomUUID()) =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/create',
      payload: body,
      headers: { 'x-test-user': user, ...(key === undefined ? {} : { 'idempotency-key': key }) },
    });

  it('requires the header on an opted-in route', async () => {
    const res = await post(undefined, { name: 'a' });
    expect(res.statusCode).toBe(400);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
  });

  it('replays the original status and body on a repeat', async () => {
    const key = randomUUID();
    const user = randomUUID();
    const before = handlerRuns;
    const first = await post(key, { name: 'a' }, user);
    const second = await post(key, { name: 'a' }, user);
    expect(first.statusCode).toBe(201);
    expect(second.statusCode).toBe(201);
    expect(second.body).toBe(first.body);
    expect(second.headers['idempotent-replayed']).toBe('true');
    expect(first.headers['idempotent-replayed']).toBeUndefined();
    expect(handlerRuns).toBe(before + 1);
  });

  it('rejects the same key with a different body', async () => {
    const key = randomUUID();
    const user = randomUUID();
    await post(key, { name: 'a' }, user);
    const res = await post(key, { name: 'b' }, user);
    expect(res.statusCode).toBe(422);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('IDEMPOTENCY_KEY_REUSED');
  });

  it('scopes the key to the subject: two users may use the same key', async () => {
    const key = randomUUID();
    const before = handlerRuns;
    await post(key, { name: 'a' }, randomUUID());
    await post(key, { name: 'a' }, randomUUID());
    expect(handlerRuns).toBe(before + 2);
  });

  it('runs the handler once under concurrent duplicates', async () => {
    const key = randomUUID();
    const user = randomUUID();
    const before = handlerRuns;
    const results = await Promise.all(
      Array.from({ length: 20 }, () => post(key, { name: 'c' }, user)),
    );
    expect(handlerRuns).toBe(before + 1);
    const statuses = results.map((r) => r.statusCode);
    expect(statuses.filter((s) => s === 201).length).toBeGreaterThanOrEqual(1);
    for (const s of statuses) expect([201, 409]).toContain(s);
    const winners = results.filter((r) => r.statusCode === 201).map((r) => r.body);
    expect(new Set(winners).size).toBe(1);
  });

  it('does not pin a 5xx: a retry after a crash runs the handler again', async () => {
    const key = randomUUID();
    const first = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/fails',
      payload: {},
      headers: { 'idempotency-key': key },
    });
    expect(first.statusCode).toBe(500);
    const record = await ctx.prisma.idempotencyRecord.findFirst({ where: { clientKey: key } });
    expect(record?.status).toBe('abandoned');
    const second = await ctx.app.inject({
      method: 'POST',
      url: '/v1/_test/fails',
      payload: {},
      headers: { 'idempotency-key': key },
    });
    expect(second.statusCode).toBe(500);
    expect(second.headers['idempotent-replayed']).toBeUndefined();
  });
});
