import type { ListingEvents } from '../modules/listings/events.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const LISTING_COUNT_ROLLUP_JOB_NAME = 'listing-count-rollup';

/**
 * §Phase 8: "view and booking counts come from an event log with periodic
 * rollup, not per-request counter writes". This is the periodic half.
 *
 * Every five minutes. The counters are a display number on My Services and
 * an input to §1b's downgrade ranking — neither is a deadline, so a minute of
 * granularity would buy nothing and cost a sweep. The windowed questions
 * (§1b's "confirmed bookings over the trailing 90 days") read the event log
 * directly and are never stale at all, which is the other reason this can
 * afford to be unhurried.
 */
export function listingCountRollupJob(events: ListingEvents, log: JobLogger): JobDefinition {
  return {
    name: LISTING_COUNT_ROLLUP_JOB_NAME,
    everyMs: 5 * 60_000,
    async run(now) {
      const { listingsUpdated, eventsCounted } = await events.rollUp(now);
      if (listingsUpdated > 0) {
        log.info(
          { job: LISTING_COUNT_ROLLUP_JOB_NAME, listings: listingsUpdated, events: eventsCounted },
          'listing counts rolled up',
        );
      }
    },
  };
}
