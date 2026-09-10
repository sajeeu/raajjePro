/**
 * The entitlement cap, as a seam (§Phase 8's publish bullet, 🔧 note decided
 * 2026-09-10).
 *
 * ## Why this file exists instead of a call to `getProviderEntitlements`
 *
 * §Phase 8's publish path has to know how many active listings this provider
 * is allowed. §Phase 8a owns `getProviderEntitlements` — "the single source
 * of tier truth, live DB read every call, no caching" — and it does not exist
 * yet, because it reads a `ProviderSubscription` table Phase 8a creates and
 * fires trial triggers that hook booking state transitions §Phase 9a has not
 * built. Building any of that here would be building ahead into a phase whose
 * own Done-when could not be tested.
 *
 * So Phase 8 defines **the narrow thing it needs** and nothing else: how many
 * active listings, for one provider. Phase 8a replaces the body with the live
 * database read and **its callers do not change** — the interface is what
 * survives, which is the same pattern §Phase 5 used for
 * `PublishedListingSource` (ledger row P5-1) and Phase 3 used for
 * `DeletionBlocker`.
 *
 * ## Why "1" is not a guess
 *
 * §1b's v1 scope table sets the free tier at **1 active listing**, and a
 * provider with no `ProviderSubscription` row is on the free tier by
 * definition — there is no table for them to be in. Until Phase 8a creates
 * that table, every provider is in exactly that state, so the free-tier value
 * is not a placeholder standing in for the real answer: today it *is* the real
 * answer for every account.
 *
 * ## What is deliberately not here
 *
 * No `ProviderSubscription`, no trial, no pause, no grace period, no
 * downgrade sweep, and no notion of a tier. `activeListingCap` is one number.
 * A richer interface guessed now is a richer interface Phase 8a has to
 * either honour or break.
 */

/**
 * §1b: "Free tier — 1 active listing, full search visibility (never
 * paywalled), no analytics."
 *
 * Exported so the test that asserts the cap reads the same constant the rule
 * does, and so Phase 8a can assert its own free-tier answer against it rather
 * than re-typing a 1.
 */
export const FREE_TIER_ACTIVE_LISTING_CAP = 1;

export interface ProviderEntitlementReader {
  /**
   * How many listings this provider may hold at `status: 'published'` and
   * `visibility: 'active'` at once (§1b).
   *
   * "Active" is that pair and nothing else — drafts do not count, and neither
   * does a listing the provider hid themselves or one moderation took down.
   * A cap that counted drafts would contradict §Phase 8's own correction:
   * v1 checked the cap at draft creation, "so drafts made during a trial
   * could all be published after downgrade".
   */
  activeListingCap(providerProfileId: string): Promise<number>;
}

/**
 * What Phase 8 ships with. Phase 8a replaces the registration in `app.ts`,
 * not this file.
 *
 * It ignores the provider id on purpose: there is nothing per-provider to
 * read yet, and pretending otherwise — a lookup that always misses, say —
 * would suggest a subscription table exists.
 */
export const FREE_TIER_ONLY: ProviderEntitlementReader = {
  activeListingCap(): Promise<number> {
    return Promise.resolve(FREE_TIER_ACTIVE_LISTING_CAP);
  },
};
