import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 2 schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('keeps rate_limit_counter UNLOGGED', async () => {
    // relpersistence is Postgres's internal "char" type (OID 18); the pg
    // driver adapter can't deserialize it raw, so cast to text — the value
    // asserted is unchanged.
    const rows = await prisma.$queryRaw<{ relpersistence: string }[]>`
      SELECT relpersistence::text AS "relpersistence" FROM pg_class WHERE relname = 'rate_limit_counter'`;
    expect(rows[0]?.relpersistence).toBe('u');
  });

  it('allows one active suppression per address but keeps lifted ones', async () => {
    const address = `dup-${randomUUID()}@example.test`;
    await prisma.emailSuppression.create({ data: { address, reason: 'manual' } });
    await expect(
      prisma.emailSuppression.create({ data: { address, reason: 'manual' } }),
    ).rejects.toThrow();
    await prisma.emailSuppression.updateMany({
      where: { address },
      data: { liftedAt: new Date(), liftReason: 'test' },
    });
    await expect(
      prisma.emailSuppression.create({ data: { address, reason: 'manual' } }),
    ).resolves.toBeDefined();
  });
});
