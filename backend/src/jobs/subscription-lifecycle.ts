import type { SubscriptionService } from '../modules/subscriptions/service.js';
import type { JobDefinition, JobLogger } from './runner.js';

export const SUBSCRIPTION_LIFECYCLE_JOB_NAME = 'subscription-lifecycle';
export const SUBSCRIPTION_TRIAL_PROMPT_JOB_NAME = 'subscription-trial-prompt';
export const SUBSCRIPTION_INTRODUCTORY_JOB_NAME = 'subscription-introductory-conversion';

/**
 * Why an hour.
 *
 * Every deadline §1b defines is measured in days — 7 days of warning, 7 days
 * of grace, 10 days of pause, 30-day periods, win-back at 7 and 30 — so the
 * finest granularity any of them needs is a day, and an hour gives every one
 * of them a comfortable margin without a sweep a minute. It is also short
 * enough that "hides it the moment that booking completes" (§Phase 8a's
 * Done-when) is an hour rather than a day; §Phase 17.1 can call
 * `reconcileVisibility` on the terminal transition to make it exact.
 */
const EVERY_HOUR = 60 * 60_000;

/**
 * §Phase 8a's scheduled lifecycle work: the 7-day-out warning, expiry →
 * grace, grace → downgrade, and the win-back notifications at 7 and 30 days
 * post-downgrade — plus the forced resume at the pause cap and a reconcile of
 * the listings a downgrade hid.
 *
 * **On the runner, never check-on-read** (§Phase 8a, backend/CLAUDE.md: "if a
 * transition should happen at a time, a job makes it happen at that time").
 * That is what lets `getProviderEntitlements` be a plain read of a stored
 * status: the status is advanced here, so no reader has to recompute it and
 * no two readers can disagree about it.
 */
export function subscriptionLifecycleJob(
  subscriptions: SubscriptionService,
  log: JobLogger,
): JobDefinition {
  return {
    name: SUBSCRIPTION_LIFECYCLE_JOB_NAME,
    everyMs: EVERY_HOUR,
    async run(now) {
      const report = await subscriptions.runLifecycle(now);
      // Named rather than summed reflectively: `Object.values` over an
      // interface with no index signature is `any[]`, and a job that logged
      // nothing because a new counter was added to the report and not to the
      // sum is a silent regression.
      const moved =
        report.resumedAtCap +
        report.warned +
        report.expired +
        report.downgraded +
        report.winbacks +
        report.listingsHidden +
        report.listingsRestored;
      if (moved > 0) {
        log.info({ job: SUBSCRIPTION_LIFECYCLE_JOB_NAME, ...report }, 'subscription lifecycle ran');
      }
    },
  };
}

/**
 * §Phase 8a's third trial trigger — 🔧 **a prompt, not a start** (decided
 * 2026-09-10): "prompt 'Try Premium' automatically 7 days after a provider's
 * first published listing if no booking has landed and no trial has started."
 *
 * Its own job rather than a step in the lifecycle sweep, because its
 * candidates are the providers with **no subscription row at all** — the
 * lifecycle sweep reads `provider_subscription` and these providers are not
 * in it yet. Folding them together would mean one job scanning two different
 * tables for two unrelated reasons.
 */
export function subscriptionTrialPromptJob(
  subscriptions: SubscriptionService,
  log: JobLogger,
): JobDefinition {
  return {
    name: SUBSCRIPTION_TRIAL_PROMPT_JOB_NAME,
    everyMs: EVERY_HOUR,
    async run(now) {
      const { prompted } = await subscriptions.runTrialPrompts(now);
      if (prompted > 0) {
        log.info({ job: SUBSCRIPTION_TRIAL_PROMPT_JOB_NAME, prompted }, 'try-premium prompts sent');
      }
    },
  };
}

/**
 * 🔧 §Phase 8a's **fifth** scheduled job, added 2026-09-10: §1b's
 * introductory rate is "honoured for 12 months from the billing anchor, then
 * converts to standard with 30 days' notice".
 *
 * Separate from the lifecycle sweep because it reads a different clock — the
 * billing anchor, twelve months back — and because its action is a **price**
 * rather than a status. No other phase owns it: §Phase 10a is the billing UI
 * and §Phase 10c only measures the conversion, so leaving it unnamed meant
 * nobody built the thing being measured.
 */
export function subscriptionIntroductoryConversionJob(
  subscriptions: SubscriptionService,
  log: JobLogger,
): JobDefinition {
  return {
    name: SUBSCRIPTION_INTRODUCTORY_JOB_NAME,
    everyMs: EVERY_HOUR,
    async run(now) {
      const result = await subscriptions.runIntroductoryConversion(now);
      if (result.noticed > 0 || result.converted > 0) {
        log.info(
          { job: SUBSCRIPTION_INTRODUCTORY_JOB_NAME, ...result },
          'introductory pricing advanced',
        );
      }
    },
  };
}
