/**
 * The two questions this phase has to ask about bookings, and cannot —
 * because there is no `Booking` until §Phase 17.1.
 *
 * ## Why a seam rather than a table
 *
 * §Phase 8a's brief is explicit: "there is no `Booking` until §Phase 17.1, so
 * the confirmed-booking trial trigger and the downgrade listing-protection
 * both take an injected source — build the rules here, assert them with a
 * fake, and do **not** create a `Booking` table."
 *
 * This is the fourth use of a pattern this build has been right about three
 * times: `DeletionBlocker` (§Phase 3), `PublishedListingSource` (§Phase 5,
 * ledger row **P5-1**, closed by Phase 8) and `ProviderEntitlementReader`
 * (§Phase 8, filled by this phase). The rule is built and tested one phase
 * before its data source lands, the interface is what survives, and no caller
 * changes when the real implementation arrives.
 *
 * ## Why both questions live behind one interface
 *
 * Because §Phase 17.1 implements one class over one table. Two interfaces
 * would mean two registrations in `app.ts` for a single source of truth, and
 * a later reader would have to check both to know what this phase assumes
 * about bookings.
 *
 * ## Why the default answers "no bookings" rather than throwing
 *
 * It is the **true** answer today, not a placeholder: no booking exists, so
 * no provider has one and no listing is protected by one. Every rule built on
 * top of it is therefore correct as it stands — the proactive trial prompt
 * fires (nobody has a booking), and a downgrade protects nothing (nothing is
 * committed). When §Phase 17.1 lands, the same rules start seeing real rows.
 */
export interface SubscriptionBookingSource {
  /**
   * Has any booking landed for this provider?
   *
   * Read by §Phase 8a's third trial trigger — "prompt 'Try Premium'
   * automatically 7 days after a provider's first published listing **if no
   * booking has landed** and no trial has started".
   *
   * Deliberately "any", not "any confirmed". The trigger exists because
   * reaching `confirmed` "requires publish → accept → payment → attestation
   * → provider confirmation, realistically days to weeks after signup", so
   * the question it is really asking is whether this provider has any
   * booking activity at all. A provider whose first booking is mid-flight
   * will get their trial from the first trigger within days, and
   * `startTrial` is a no-op if a trial has ever run, so the two readings
   * cannot both fire.
   */
  hasAnyBooking(providerProfileId: string): Promise<boolean>;

  /**
   * Which of these listings carry a **committed future job** (§1b's
   * protected-listing rule)?
   *
   * §1b: "a listing with a booking in `accepted`, `awaiting_payment`,
   * `payment_claimed`, `payment_unresolved`, or `confirmed` status and a
   * future `scheduledFor` **stays visible regardless of cap**, until that
   * booking reaches a terminal state (`completed` / `cancelled` /
   * `declined` / `dispute_resolved`)."
   *
   * The status list belongs to the implementation, not to the interface: this
   * phase has no booking-status enum to name and §Phase 17.1 owns it. What
   * this phase owns is the *rule* — that such a listing is never hidden by an
   * entitlement downgrade — which is why the question is phrased as the
   * answer the rule needs.
   *
   * Takes the candidate set rather than a provider id so the implementation
   * is one indexed query over the listings actually at risk of being hidden,
   * and returns ids rather than rows so nothing here has to know a booking's
   * shape.
   */
  listingIdsWithCommittedBooking(listingIds: string[]): Promise<string[]>;
}

/**
 * What ships until §Phase 17.1 arrives — and, again, the true answer rather
 * than a stub: with no `Booking` table, no provider has a booking and no
 * listing is protected by one.
 */
export const NO_BOOKINGS: SubscriptionBookingSource = {
  hasAnyBooking(): Promise<boolean> {
    return Promise.resolve(false);
  },
  listingIdsWithCommittedBooking(): Promise<string[]> {
    return Promise.resolve([]);
  },
};
