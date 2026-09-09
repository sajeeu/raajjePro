/**
 * The read surface for §1f's conduct metrics.
 *
 * §Phase 5 assigns this phase the *display* half of conduct: "the read surface
 * for §1f's conduct metrics, which Phase 11 computes and Phases 5 and 12
 * display." Nothing here computes a metric, and nothing here stores one — the
 * numbers come from booking outcomes, and there is no `Booking` entity until
 * Phase 17. What Phase 5 owns is the shape those numbers reach a client in,
 * and the two display rules §1f states as invariants:
 *
 *   1. **Numbers only, never an editorial label.** "Prone to cancel" and
 *      "Price hiking" were considered in Round 15 and rejected as automated
 *      public accusations with real defamation exposure in a market this
 *      small. There is deliberately no field on any DTO here that could carry
 *      one, euphemistic or otherwise — the customer draws their own
 *      conclusion from the rates.
 *   2. **Nothing displays below a ten-completed-booking floor.** One
 *      cancellation out of two bookings is 50% and means nothing.
 *
 * The source is an injected seam, the same pattern Phase 3 used for
 * `DeletionBlocker` and `ExportContributors`: Phase 11 registers the real
 * implementation, and until then `noConductRecorded` answers honestly rather
 * than optimistically.
 */

/**
 * What a conduct source reports for one provider. Every rate is a fraction in
 * `[0, 1]` or null, and null means *not computable* — no denominator — which
 * is a different statement from zero. §1f defines each one; a source must not
 * reinterpret them:
 *
 *  - `completionRate` — completed ÷ (completed + provider-cancelled + no-show)
 *  - `cancellationRate` — provider-initiated cancellations after `accepted` ÷
 *    accepted. Customer cancellations never count against a provider.
 *  - `noShowRate` — confirmed no-shows ÷ accepted
 *  - `onTimeRate` — arrivals within 15 minutes of the promised time ÷
 *    completed with an arrival mark. **All three booking modes (Round 22):**
 *    slot and request measure against `scheduledFor`, emergency against the
 *    accepted offer's own `etaMinutes`. §1f's older "emergency has no
 *    scheduled time" exclusion is obsolete.
 *  - `priceAdherenceRate` — completions where `finalAmount` ≤ `agreedAmount` ÷
 *    completions with both
 *  - `acceptanceRate` — accepted ÷ (accepted + declined), **explicit responses
 *    only**; a timeout feeds response rate, not this
 *  - `medianResponseSeconds` — median prompt-to-explicit-response, timeouts
 *    excluded from the median
 */
export interface ProviderConductRecord {
  /**
   * Lifetime completed bookings, **derived from the booking event log, never a
   * hand-maintained counter** (§Phase 5). This is the "47 jobs completed"
   * number, and it is the only figure that still shows below the floor.
   */
  jobsCompletedCount: number;
  /**
   * Completed bookings inside the rolling 90-day window — the denominator the
   * floor is measured against, not the lifetime count. A provider with forty
   * jobs two years ago and one this quarter would otherwise show a 100% rate
   * computed from a single booking, which is exactly what the floor exists to
   * prevent.
   */
  completedInWindow: number;
  completionRate: number | null;
  cancellationRate: number | null;
  noShowRate: number | null;
  onTimeRate: number | null;
  priceAdherenceRate: number | null;
  acceptanceRate: number | null;
  medianResponseSeconds: number | null;
}

/**
 * Where conduct numbers come from. Phase 11 implements this over the booking
 * event log on a rolling 90-day window, recomputing on transition rather than
 * on read (backend/CLAUDE.md: scheduled work, never check-on-read).
 *
 * Batched by design: a search page asks about many providers at once, and one
 * query per card is how a list endpoint becomes slow enough to be rewritten
 * later under pressure.
 */
export interface ProviderConductSource {
  metricsFor(providerIds: string[]): Promise<Map<string, ProviderConductRecord>>;
}

/** A provider the source knows nothing about: no jobs, and no rate computable from none. */
export const NO_CONDUCT: ProviderConductRecord = {
  jobsCompletedCount: 0,
  completedInWindow: 0,
  completionRate: null,
  cancellationRate: null,
  noShowRate: null,
  onTimeRate: null,
  priceAdherenceRate: null,
  acceptanceRate: null,
  medianResponseSeconds: null,
};

/**
 * The default until Phase 11 lands. It reports nothing rather than zeroes for
 * every rate, because "0% on time" and "no data yet" are different claims and
 * only one of them is true of a provider who has never been booked.
 */
export const noConductRecorded: ProviderConductSource = {
  metricsFor(): Promise<Map<string, ProviderConductRecord>> {
    return Promise.resolve(new Map<string, ProviderConductRecord>());
  },
};

/**
 * §1f's floor. Ten *completed bookings in the window*, below which the public
 * profile shows "New provider" and the job count and nothing else.
 */
export const CONDUCT_DISPLAY_FLOOR = 10;

export function meetsConductFloor(record: ProviderConductRecord): boolean {
  return record.completedInWindow >= CONDUCT_DISPLAY_FLOOR;
}
