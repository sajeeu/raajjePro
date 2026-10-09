import type { ConductService } from '../modules/conduct/service.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const CONDUCT_RECOMPUTE_JOB_NAME = 'conduct-recompute';

/**
 * §Phase 11: conduct is "recomputed on booking terminal transitions rather
 * than on read". A terminal transition marks the provider's snapshot stale
 * in its own transaction; this recomputes the stale ones every minute, and
 * once a day every snapshot, because a rolling 90-day window moves when
 * nothing happens at all. See `ConductService` for why the recompute is not
 * inline.
 */
export function conductRecomputeJob(conduct: ConductService, log: JobLogger): JobDefinition {
  return {
    name: CONDUCT_RECOMPUTE_JOB_NAME,
    everyMs: 60_000,
    async run(now) {
      const { recomputed } = await conduct.recomputeDue(now);
      if (recomputed > 0) {
        log.info({ job: CONDUCT_RECOMPUTE_JOB_NAME, providers: recomputed }, 'conduct recomputed');
      }
    },
  };
}
