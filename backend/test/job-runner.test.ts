import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import {
  HEARTBEAT_STALE_AFTER_MS,
  NOOP_JOB_NAME,
  isMissingCronSchema,
  readHeartbeat,
} from '../src/jobs/heartbeat.js';

// The heartbeat is written by pg_cron, which lives in exactly one database —
// the one named by the server's cron.database_name, i.e. the application's,
// not the `_test` database the rest of the suite writes to. test/setup.ts
// carries it across as CRON_DATABASE_URL. This is an environment check: it
// asserts the local runner is actually firing.
const databaseUrl = process.env.CRON_DATABASE_URL ?? process.env.DATABASE_URL;

// Needs a migrated database (docker compose up -d && npm run db:migrate).
describe.skipIf(databaseUrl === undefined)('job runner', () => {
  let prisma: PrismaClient;

  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('registers the no-op heartbeat job on a one-minute schedule', async () => {
    const report = await readHeartbeat(prisma);

    expect(report.job).not.toBeNull();
    expect(report.job?.jobname).toBe(NOOP_JOB_NAME);
    expect(report.job?.schedule).toBe('* * * * *');
    expect(report.job?.active).toBe(true);
  });

  it('judges the runner stale once the last heartbeat is older than the threshold', async () => {
    // The rule under test is the staleness cut-off, not the clock: evaluate the
    // same database state against a "now" pushed past the window.
    const live = await readHeartbeat(prisma);
    if (live.lastFiredAt === null) {
      // No heartbeat yet — the runner has not had a minute since migration.
      // The firing judgement must then be false rather than throwing.
      expect(live.firing).toBe(false);
      return;
    }

    const justInside = new Date(live.lastFiredAt.getTime() + HEARTBEAT_STALE_AFTER_MS);
    const justOutside = new Date(justInside.getTime() + 1);

    expect((await readHeartbeat(prisma, justInside)).firing).toBe(true);
    expect((await readHeartbeat(prisma, justOutside)).firing).toBe(false);
  });
});

/**
 * pg_cron installs into exactly one database — the one named by the server's
 * cron.database_name. Every other database this schema is applied to (the
 * `_test` one the suite runs against, Prisma's shadow database, a managed
 * host that will not grant CREATE EXTENSION) has job_heartbeat and no cron
 * schema at all.
 *
 * Before this was handled, the cron.job query threw and /v1/health caught it
 * as INFRASTRUCTURE_UNAVAILABLE — reporting a perfectly reachable database as
 * down, on the endpoint §5 measures availability against. A runner that is
 * not there is `not-firing`, which is a different fact.
 */
describe('a database without pg_cron', () => {
  // The shape Prisma actually produces: P2010 on the outside, the SQLSTATE
  // that matters two levels down in the driver adapter's cause. Captured from
  // a real failed query rather than guessed.
  const missingRelation = Object.assign(
    new Error('Raw query failed. Code: `42P01`. Message: `relation "cron.job" does not exist`'),
    {
      code: 'P2010',
      meta: {
        driverAdapterError: {
          name: 'DriverAdapterError',
          cause: { originalCode: '42P01', kind: 'TableDoesNotExist', table: 'cron.job' },
        },
      },
    },
  );

  it("recognises the missing relation through Prisma's wrapper", () => {
    expect(isMissingCronSchema(missingRelation)).toBe(true);
    expect(isMissingCronSchema(new Error('connection refused'))).toBe(false);
    expect(isMissingCronSchema(Object.assign(new Error('x'), { code: 'P2002' }))).toBe(false);
  });

  it('reads as not-firing rather than throwing', async () => {
    const stub = {
      jobHeartbeat: { findUnique: () => Promise.resolve(null) },
      $queryRaw: () => Promise.reject(missingRelation),
    } as unknown as PrismaClient;

    const report = await readHeartbeat(stub);
    expect(report.job).toBeNull();
    expect(report.firing).toBe(false);
    expect(report.lastFiredAt).toBeNull();
  });

  it('still propagates a genuine database failure', async () => {
    const stub = {
      jobHeartbeat: { findUnique: () => Promise.resolve(null) },
      $queryRaw: () => Promise.reject(new Error('connection refused')),
    } as unknown as PrismaClient;

    await expect(readHeartbeat(stub)).rejects.toThrow('connection refused');
  });
});
