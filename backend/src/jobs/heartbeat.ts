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

/**
 * Reads what pg_cron knows about the no-op job and what the job itself wrote.
 * Both are consulted because they fail differently: a job that is scheduled
 * but never runs shows in cron.job with no heartbeat rows; a runner that is
 * firing but erroring shows runs with status 'failed' and no heartbeat rows.
 */
export async function readHeartbeat(
  prisma: PrismaClient,
  now: Date = new Date(),
): Promise<HeartbeatReport> {
  const jobs = await prisma.$queryRaw<ScheduledJob[]>`
    SELECT jobid, jobname, schedule, active
    FROM cron.job
    WHERE jobname = ${NOOP_JOB_NAME}
  `;
  const job = jobs[0] ?? null;

  const heartbeat = await prisma.jobHeartbeat.findUnique({
    where: { jobName: NOOP_JOB_NAME },
    select: { firedAt: true },
  });
  const lastFiredAt = heartbeat?.firedAt ?? null;

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
