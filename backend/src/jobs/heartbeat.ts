import type { PrismaClient } from '../generated/prisma/client.js';

/** The name the first migration registered the no-op job under, in cron.job. */
export const NOOP_JOB_NAME = 'noop-heartbeat';

/** How long the runner may go quiet before we call it stopped. The job runs every minute. */
export const HEARTBEAT_STALE_AFTER_MS = 2 * 60 * 1000;

export interface ScheduledJob {
  jobid: bigint;
  jobname: string;
  schedule: string;
  active: boolean;
}

export interface JobRun {
  runid: bigint;
  status: string;
  start_time: Date | null;
  end_time: Date | null;
  return_message: string | null;
}

export interface HeartbeatReport {
  job: ScheduledJob | null;
  lastFiredAt: Date | null;
  /** True when the job exists and fired within HEARTBEAT_STALE_AFTER_MS of `now`. */
  firing: boolean;
  recentRuns: JobRun[];
}

/** Postgres SQLSTATEs for "that schema does not exist" and "that table does not exist". */
const MISSING_RELATION = new Set(['3F000', '42P01']);

/**
 * Prisma reports a raw-query failure as P2010 and keeps the SQLSTATE that
 * actually matters two levels down, in the driver adapter's cause. Both are
 * checked: the nested code is the precise one, the message is the fallback if
 * a future Prisma reshapes that object.
 */
export function isMissingCronSchema(error: unknown): boolean {
  const nested = (
    error as {
      meta?: { driverAdapterError?: { cause?: { originalCode?: unknown } } };
    }
  ).meta?.driverAdapterError?.cause?.originalCode;
  if (typeof nested === 'string' && MISSING_RELATION.has(nested)) return true;

  const code = (error as { code?: unknown }).code;
  if (typeof code === 'string' && MISSING_RELATION.has(code)) return true;

  const message = error instanceof Error ? error.message : '';
  return [...MISSING_RELATION].some((sqlstate) => message.includes(`Code: \`${sqlstate}\``));
}

/**
 * Reads what pg_cron knows about the no-op job and what the job itself wrote.
 * Both are consulted because they fail differently: a job that is scheduled
 * but never runs shows in cron.job with no heartbeat rows; a runner that is
 * firing but erroring shows runs with status 'failed' and no heartbeat rows.
 *
 * The heartbeat table is read first because it is the honest reachability
 * probe: it is an ordinary table this migration always creates. The cron
 * schema is read second and its absence is tolerated — pg_cron can only be
 * installed into the one database named by cron.database_name, so every other
 * database (the `_test` one, a managed host that will not grant CREATE
 * EXTENSION, the shadow database) has the table and no cron schema. That is a
 * runner that is not firing, not a database that cannot be reached, and
 * /v1/health must not report it as the latter — §5 measures availability
 * against that endpoint.
 */
export async function readHeartbeat(
  prisma: PrismaClient,
  now: Date = new Date(),
): Promise<HeartbeatReport> {
  const heartbeat = await prisma.jobHeartbeat.findUnique({
    where: { jobName: NOOP_JOB_NAME },
    select: { firedAt: true },
  });
  const lastFiredAt = heartbeat?.firedAt ?? null;

  let job: ScheduledJob | null = null;
  try {
    const jobs = await prisma.$queryRaw<ScheduledJob[]>`
      SELECT jobid, jobname, schedule, active
      FROM cron.job
      WHERE jobname = ${NOOP_JOB_NAME}
    `;
    job = jobs[0] ?? null;
  } catch (error) {
    if (!isMissingCronSchema(error)) throw error;
  }

  const recentRuns =
    job === null
      ? []
      : await prisma.$queryRaw<JobRun[]>`
          SELECT runid, status, start_time, end_time, return_message
          FROM cron.job_run_details
          WHERE jobid = ${job.jobid}
          ORDER BY start_time DESC
          LIMIT 5
        `;

  const firing =
    job !== null &&
    job.active &&
    lastFiredAt !== null &&
    now.getTime() - lastFiredAt.getTime() <= HEARTBEAT_STALE_AFTER_MS;

  return { job, lastFiredAt, firing, recentRuns };
}
