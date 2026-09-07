import type { Clock } from '../core/clock.js';
import type { PrismaClient } from '../generated/prisma/client.js';

export interface JobDefinition {
  name: string;
  everyMs: number;
  run(now: Date): Promise<void>;
}

export interface JobLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
  error(obj: Record<string, unknown>, msg: string): void;
}

/**
 * Node-side scheduled work (plan §2 "pg_cron or equivalent"; backend/CLAUDE.md:
 * a transition that should happen at a time is made to happen by a job, never
 * check-on-read). pg_cron stays for SQL-only jobs; this runs jobs that call
 * into Node — anonymisation runs hooks that reach a bucket, which SQL cannot.
 *
 * One transaction-scoped advisory lock per job means two API instances never
 * run the same job at once. A successful run upserts the Phase 0 heartbeat
 * row, so `readHeartbeat`'s notion of "observably firing" covers these jobs
 * with no second mechanism. A failure is logged and the schedule continues.
 */
export class JobRunner {
  private readonly jobs = new Map<string, JobDefinition>();
  private readonly timers: NodeJS.Timeout[] = [];

  constructor(private readonly deps: { prisma: PrismaClient; clock: Clock; log: JobLogger }) {}

  register(job: JobDefinition): void {
    if (this.jobs.has(job.name)) throw new Error(`job already registered: ${job.name}`);
    this.jobs.set(job.name, job);
  }

  /** Runs one job now. Returns 'skipped' when another instance holds its lock. Tests call this; start() calls it on a timer. */
  async runOnce(
    name: string,
    now: Date = this.deps.clock(),
  ): Promise<'ran' | 'skipped' | 'failed'> {
    const job = this.jobs.get(name);
    if (job === undefined) throw new Error(`no such job: ${name}`);
    try {
      // This transaction holds one connection from the pool for its entire
      // duration, including while `job.run(now)` executes. A job whose own
      // work opens further transactions on `this.deps.prisma` (as
      // `AccountAnonymiser` does, one per user) requests additional
      // connections from that same pool while this one is still checked out
      // — the pool must be configured with at least two connections
      // (`connection_limit` on `DATABASE_URL`), or that request can never be
      // satisfied and the two transactions deadlock against each other.
      //
      // The 60s timeout below is on this outer transaction only. If the
      // job's inner work independently commits rows before the timeout
      // fires but the whole call takes longer than 60s in aggregate, the
      // real work already landed but this transaction still aborts —
      // the `jobHeartbeat` upsert below never runs, so that run looks like
      // it never fired even though it did the work.
      return await this.deps.prisma.$transaction(
        async (tx) => {
          const [lock] = await tx.$queryRaw<
            { locked: boolean }[]
          >`SELECT pg_try_advisory_xact_lock(hashtext(${`job:${name}`})) AS locked`;
          if (lock?.locked !== true) return 'skipped';
          await job.run(now);
          await tx.jobHeartbeat.upsert({
            where: { jobName: name },
            create: { jobName: name, firedAt: now },
            update: { firedAt: now },
          });
          return 'ran';
        },
        { timeout: 60_000 },
      );
    } catch (error) {
      this.deps.log.error({ err: error, job: name }, 'job failed');
      return 'failed';
    }
  }

  start(): void {
    for (const job of this.jobs.values()) {
      const timer = setInterval(() => {
        void this.runOnce(job.name);
      }, job.everyMs);
      timer.unref();
      this.timers.push(timer);
    }
    this.deps.log.info({ jobs: [...this.jobs.keys()] }, 'job runner started');
  }

  stop(): void {
    for (const timer of this.timers) clearInterval(timer);
    this.timers.length = 0;
  }
}
