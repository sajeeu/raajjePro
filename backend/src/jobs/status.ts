/**
 * `npm run jobs:status` — prints the state of the scheduled no-op job.
 *
 * This is the Phase 0 "observably firing" check. Exit code 0 when the job
 * fired within the last two minutes, 1 otherwise, so it can gate a script.
 */
import { requireEnv } from '../config/env.js';
import { createPrismaClient } from '../db/client.js';
import { HEARTBEAT_STALE_AFTER_MS, NOOP_JOB_NAME, readHeartbeat } from './heartbeat.js';

const prisma = createPrismaClient(requireEnv('DATABASE_URL'));

try {
  const report = await readHeartbeat(prisma);

  if (report.job === null) {
    console.log(`${NOOP_JOB_NAME}: not scheduled — has the first migration been applied?`);
  } else {
    console.log(
      `${report.job.jobname}: schedule "${report.job.schedule}", ` +
        `${report.job.active ? 'active' : 'INACTIVE'} (cron.job id ${String(report.job.jobid)})`,
    );
  }

  console.log(
    report.lastFiredAt === null
      ? 'last heartbeat: never'
      : `last heartbeat: ${report.lastFiredAt.toISOString()}`,
  );

  if (report.recentRuns.length > 0) {
    console.log('recent runs:');
    for (const run of report.recentRuns) {
      const started = run.start_time?.toISOString() ?? '-';
      console.log(`  ${started}  ${run.status.padEnd(9)} ${run.return_message ?? ''}`);
    }
  }

  const staleMinutes = HEARTBEAT_STALE_AFTER_MS / 60_000;
  console.log(
    report.firing
      ? `runner: FIRING (heartbeat within ${String(staleMinutes)} min)`
      : `runner: NOT FIRING (no heartbeat within ${String(staleMinutes)} min)`,
  );
  process.exitCode = report.firing ? 0 : 1;
} finally {
  await prisma.$disconnect();
}
