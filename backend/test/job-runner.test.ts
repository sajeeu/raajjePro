import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { HEARTBEAT_STALE_AFTER_MS, NOOP_JOB_NAME, readHeartbeat } from '../src/jobs/heartbeat.js';

const databaseUrl = process.env.DATABASE_URL;

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
