import type { BookingService } from '../modules/bookings/service.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const BOOKING_ACCEPT_TIMEOUT_JOB_NAME = 'booking-accept-timeout';
export const BOOKING_PAYMENT_SILENCE_JOB_NAME = 'booking-payment-silence';
export const BOOKING_COMPLETION_TIMEOUT_JOB_NAME = 'booking-completion-timeout';

/**
 * §Phase 17's scheduled work, on the runner rather than checked on read
 * (backend/CLAUDE.md: "a transition that should happen at a time is made to
 * happen by a job, never check-on-read"). A booking that timed out has timed
 * out whether or not anybody opens it.
 *
 * **Three jobs rather than one**, because §Phase 17 item 7 names three
 * distinct conditions and they run on different clocks — and because a failure
 * sweeping payment silence must not stop the accept window from expiring. The
 * fourth condition item 7 lists, `quote_offered` on the category's
 * `quoteApprovalMinutes`, is §Phase 17.2's and is not here; the emergency
 * window is §Phase 17.3's.
 *
 * ## Why these cadences
 *
 * The accept window is 24 hours and the payment one is 7 days, so neither
 * needs a tight tick — a booking auto-declining a few minutes after hour 24 is
 * indistinguishable to everyone involved. Five minutes is chosen for the same
 * reason the slot generator's is: it bounds how stale a sweep can get without
 * sweeping for no reason. The completion pair runs hourly, because its two
 * halves are 7 days and 3 days apart and nothing about either is urgent.
 */
const EVERY_FIVE_MINUTES = 5 * 60_000;
const EVERY_HOUR = 60 * 60_000;

/**
 * §1c step 4: "Slot and request-based: **24 hours** → auto-decline, release
 * the slot or reservation, notify the customer to look elsewhere."
 *
 * §1f reads the actor rather than the status to tell this apart from a
 * provider who actually said no: "timeouts feed response rate, not acceptance
 * rate."
 */
export function bookingAcceptTimeoutJob(bookings: BookingService, log: JobLogger): JobDefinition {
  return {
    name: BOOKING_ACCEPT_TIMEOUT_JOB_NAME,
    everyMs: EVERY_FIVE_MINUTES,
    async run(now) {
      const { declined } = await bookings.runAcceptTimeouts(now);
      if (declined > 0) {
        log.info({ job: BOOKING_ACCEPT_TIMEOUT_JOB_NAME, declined }, 'bookings auto-declined');
      }
    },
  };
}

/**
 * §1c step 9: seven days of provider silence on a payment claim →
 * `payment_unresolved`, **not** `confirmed`, with both parties notified and a
 * Report filed. "**Nothing further is unlocked by this transition.**"
 */
export function bookingPaymentSilenceJob(bookings: BookingService, log: JobLogger): JobDefinition {
  return {
    name: BOOKING_PAYMENT_SILENCE_JOB_NAME,
    everyMs: EVERY_FIVE_MINUTES,
    async run(now) {
      const { escalated } = await bookings.runPaymentSilenceTimeouts(now);
      if (escalated > 0) {
        log.info(
          { job: BOOKING_PAYMENT_SILENCE_JOB_NAME, escalated },
          'payment claims escalated to payment_unresolved',
        );
      }
    },
  };
}

/**
 * §1c step 10, both halves in one job because the second is the first's
 * consequence: prompt the customer 7 days past `scheduledFor`, then
 * auto-complete as `unconfirmed` 3 days after the prompt if they never answer.
 *
 * §Phase 11 depends on this existing: "auto-completion (Phase 17) is what
 * makes [gating reviews on completion] safe. A provider must not be able to
 * block reviews forever by staying silent."
 */
export function bookingCompletionTimeoutJob(
  bookings: BookingService,
  log: JobLogger,
): JobDefinition {
  return {
    name: BOOKING_COMPLETION_TIMEOUT_JOB_NAME,
    everyMs: EVERY_HOUR,
    async run(now) {
      const report = await bookings.runCompletionTimeouts(now);
      if (report.prompted > 0 || report.autoCompleted > 0) {
        log.info({ job: BOOKING_COMPLETION_TIMEOUT_JOB_NAME, ...report }, 'completion sweep ran');
      }
    },
  };
}
