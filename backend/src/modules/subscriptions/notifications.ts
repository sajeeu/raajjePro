/**
 * The billing events §1b requires a provider to be told about — as a seam,
 * because **§Phase 19 owns notification content and this phase does not**.
 *
 * §Phase 19's own type list already contains five of these by name:
 * `trial_ending_7d`, `subscription_ending_7d`, `downgraded_to_free`,
 * `winback_7d`, `winback_30d` — plus `payment_submission_confirmed` and
 * `payment_submission_rejected`. Writing the copy here would put it in two
 * phases, and §Phase 19's Done-when ("each event type fires through Phase 3c's
 * sender") is the assertion that it goes out through one path.
 *
 * So this phase's jobs and service **fire** the events, at the moments §1b
 * specifies, and the delivery is registered by whoever can do it. The default
 * logs and drops, which is honest: nothing pretends a provider was told.
 * `docs/deferred-verification.md` carries the row.
 *
 * ## Why not send an email directly
 *
 * §Phase 3c's `NotificationDispatcher` is "the only place the fallback chain
 * is written", and its `NotificationContext` is booking-shaped (booking type,
 * customer first name, island). Reshaping it for billing copy would be a
 * refactor of a built phase to serve an unbuilt one (invariant 5), and calling
 * `EmailSender` around it would put a second delivery path next to the one
 * §Phase 3c exists to be.
 */

/**
 * 🔧 One of these has no §Phase 19 type yet.
 *
 * 🔧 **Two of these have no §Phase 19 type yet**, and both are flagged rather
 * than silently renamed onto a neighbouring type.
 *
 * `introductory_price_converting` is §1b's "converts to standard with **30
 * days' notice** delivered through Phase 19"; §Phase 19's list predates Round
 * 9's introductory pricing. A provider whose price is about to double should
 * not be told through the trial-ending template.
 *
 * `trial_prompt` is §Phase 8a's third trigger, which as of 2026-09-10 prompts
 * rather than starts. §Phase 19's list has `trial_ending_7d` but nothing for
 * the invitation, which is the one notification in this set that is trying to
 * sell something rather than report a fact — so it is also the one whose copy
 * a marketing-channel decision affects (§Phase 3c's three configuration
 * sets).
 */
export type BillingEvent =
  /** §1b: "**Warning** 7 days before trial or subscription period end." */
  | 'trial_ending_7d'
  | 'subscription_ending_7d'
  /** §1b: the grace period ran out and the listings over the cap are now hidden. */
  | 'downgraded_to_free'
  /** §1b's win-back pair: "their hidden listings are intact and one confirmed payment restores them". */
  | 'winback_7d'
  | 'winback_30d'
  /**
   * §Phase 8a's third trigger — 🔧 **it prompts and does not start** (decided
   * 2026-09-10). A trial is one per account and non-renewable, and this fires
   * precisely when no booking has landed, so starting it there would spend
   * the provider's only trial when premium is worth least: analytics over no
   * data, priority placement in a market with no demand. The bullet's stated
   * problem is discovery, and a prompt solves that at no cost.
   *
   * Like `introductory_price_converting`, this has no §Phase 19 type yet.
   */
  | 'trial_prompt'
  /** §1b step 4/5, from the admin's decision. The rejection carries its reason. */
  | 'payment_submission_confirmed'
  | 'payment_submission_rejected'
  /** §1b's 12-month introductory honouring, ending in 30 days. No §Phase 19 type yet — see above. */
  | 'introductory_price_converting';

export interface BillingEventInput {
  event: BillingEvent;
  /** Who to tell. A user id, because that is what §Phase 19's `Notification` keys on. */
  userId: string;
  providerProfileId: string;
  /**
   * IDs, enums, counts and dates only — never an email address, a phone
   * number, a bank detail or a payment-proof reference (root CLAUDE.md 1d:
   * product and analytics event logs follow the same no-PII rule as
   * structured logging).
   */
  detail?: Record<string, string | number | boolean>;
}

export interface BillingNotifier {
  notify(input: BillingEventInput): Promise<void>;
}

export interface BillingNotifierLogger {
  info(obj: Record<string, unknown>, msg: string): void;
}

/**
 * The default. Records that the event fired and that nothing delivered it.
 *
 * Deliberately **not** silent: a job whose only observable effect was a
 * database column would give no way to tell "the rule fired and Phase 19 is
 * missing" from "the rule never fired at all", and those are different bugs.
 */
export function loggingBillingNotifier(log: BillingNotifierLogger): BillingNotifier {
  return {
    notify(input: BillingEventInput): Promise<void> {
      log.info(
        {
          event: input.event,
          providerProfileId: input.providerProfileId,
          ...(input.detail ?? {}),
          delivered: false,
          owedBy: 'Phase 19',
        },
        'billing notification fired with no delivery registered',
      );
      return Promise.resolve();
    },
  };
}
