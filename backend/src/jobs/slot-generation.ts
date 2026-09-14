import {
  SLOT_GENERATION_BATCH,
  SLOT_GENERATION_BUDGET_MS,
  type SlotGenerator,
} from '../modules/availability/generation.js';
import type { ReservationService } from '../modules/availability/reservations.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const SLOT_GENERATION_JOB_NAME = 'slot-generation';
export const RESERVATION_EXPIRY_JOB_NAME = 'reservation-expiry';

/**
 * Why five minutes.
 *
 * The rolling horizon only needs extending once a Maldives day, so the
 * schedule is not driven by the horizon — it is driven by how long a listing
 * may sit stale if its inline regeneration failed. A rule edit regenerates
 * **inside the transaction that saved it**, so in the normal case this job has
 * nothing to do for that listing at all; five minutes is how quickly it
 * catches the abnormal case without sweeping for no reason.
 */
const EVERY_FIVE_MINUTES = 5 * 60_000;

/**
 * §Phase 9a's slot generation, "incremental and per-provider, not a global
 * nightly sweep", with "a stated wall-clock budget and a §Phase 21 alert on
 * overrun".
 *
 * The budget is `SLOT_GENERATION_BUDGET_MS`, stated and reasoned about where
 * it is defined. The overrun signal is the structured
 * `slot_generation_overrun` warning `SlotGenerator.run` emits; §Phase 21 gives
 * that a destination. Nothing is lost on an overrun — `ListingSlotState` is a
 * durable work list and the next tick resumes from it.
 */
export function slotGenerationJob(generator: SlotGenerator, log: JobLogger): JobDefinition {
  return {
    name: SLOT_GENERATION_JOB_NAME,
    everyMs: EVERY_FIVE_MINUTES,
    async run(now) {
      const report = await generator.run(now);
      if (report.considered > 0) {
        log.info(
          {
            job: SLOT_GENERATION_JOB_NAME,
            budgetMs: SLOT_GENERATION_BUDGET_MS,
            batch: SLOT_GENERATION_BATCH,
            ...report,
          },
          'slot generation ran',
        );
      }
    },
  };
}

/**
 * §Phase 9a: "Provisional reservations for offered quotes, with expiry swept
 * by a scheduled job."
 *
 * On the runner rather than checked on read (backend/CLAUDE.md), so a lapsed
 * quote stops holding a provider's calendar even if nobody opens the booking.
 * Every minute, because the shortest approval window in the catalogue is four
 * hours (§1c's 240 minutes for the household trades) but the *effect* of a
 * late release is a time nobody can book — and a provider watching their own
 * calendar should see it come back promptly.
 *
 * The candidate query carries the whole condition and is indexed on
 * `(kind, released_at, expires_at)`, so a sweep with nothing to do reads
 * nothing.
 */
export function reservationExpiryJob(
  reservations: ReservationService,
  log: JobLogger,
): JobDefinition {
  return {
    name: RESERVATION_EXPIRY_JOB_NAME,
    everyMs: 60_000,
    async run(now) {
      const { released } = await reservations.sweepExpiredHolds(now);
      if (released > 0) {
        log.info({ job: RESERVATION_EXPIRY_JOB_NAME, released }, 'provisional holds released');
      }
    },
  };
}
