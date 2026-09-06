import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import { buildTestApp, databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('GET /v1/health', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;

  beforeAll(async () => {
    ctx = await buildTestApp();
  });

  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  it('returns 200 with the database reachable and the job runner state', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/v1/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { status: string; database: string; jobRunner: string } }>();
    expect(body.data.status).toBe('ok');
    expect(body.data.database).toBe('reachable');
    expect(['firing', 'not-firing']).toContain(body.data.jobRunner);
  });

  it('returns 503 INFRASTRUCTURE_UNAVAILABLE when the database cannot be reached', async () => {
    const dead = createPrismaClient(
      'postgresql://nobody:nothing@127.0.0.1:1/none?connect_timeout=1',
    );
    const broken = await buildTestApp({ deps: { prisma: dead } });
    try {
      const res = await broken.app.inject({ method: 'GET', url: '/v1/health' });
      expect(res.statusCode).toBe(503);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('INFRASTRUCTURE_UNAVAILABLE');
    } finally {
      await broken.app.close();
      await dead.$disconnect();
    }
  });
});
