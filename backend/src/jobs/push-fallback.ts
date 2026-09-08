import type { FallbackSweep } from '../modules/push/sweep.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const FALLBACK_SWEEP_JOB_NAME = 'push-fallback-sweep';

/**
 * Every minute. The rung it serves is a 30-minute deadline, so a minute of
 * granularity costs at most a minute of lateness on a half-hour promise — and
 * the query behind it is a partial index on work outstanding, so a run with
 * nothing due is nearly free.
 */
export function pushFallbackJob(sweep: FallbackSweep, log: JobLogger): JobDefinition {
  return {
    name: FALLBACK_SWEEP_JOB_NAME,
    everyMs: 60_000,
    async run(now) {
      const { sent, skipped } = await sweep.run(now);
      if (sent > 0 || skipped > 0) {
        log.info({ job: FALLBACK_SWEEP_JOB_NAME, sent, skipped }, 'fallback sweep complete');
      }
    },
  };
}
