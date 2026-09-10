import type { Prisma } from '../../generated/prisma/client.js';
import type { PublishedListingSource } from '../providers/visibility.js';

/**
 * What "publicly visible listing" means, written once (§1b Round 17,
 * §Phase 8, ledger row P5-1).
 *
 * > A listing is publicly visible only at `active` **and**
 * > `status: 'published'`.
 *
 * …plus not soft-deleted, which §Phase 8's Done-when adds: "a soft-deleted
 * listing disappears from public queries while its bookings and reviews
 * remain intact".
 *
 * **Every consumer composes this fragment rather than restating the three
 * clauses.** §1a's whole argument is that a rule copied per query is a rule
 * that drifts, and this is the listing-side twin of `findVisibleProviders`:
 * Phase 12's listing page, Phase 15's search and Phase 16's Home all narrow
 * *on top of* it and none of them may rebuild it. A consumer that writes
 * `status: 'published'` on its own has already lost the deleted case.
 */
export const PUBLICLY_VISIBLE_LISTING = {
  status: 'published',
  visibility: 'active',
  deletedAt: null,
} as const satisfies Prisma.ListingWhereInput;

/**
 * The same predicate as the *entitlement* question: "how many listings is
 * this provider holding live right now?" (§1b's free tier of 1 active
 * listing).
 *
 * It is deliberately the identical set. §1b's cap is on "active listings",
 * and if the cap counted a different set from the one the public sees, a
 * provider could be over their cap with nothing visible or under it with two
 * listings live. Aliased rather than duplicated so that stays true.
 */
export const COUNTS_AGAINST_CAP = PUBLICLY_VISIBLE_LISTING;

/**
 * §Phase 5's `PublishedListingSource`, over the real `listing` table — the
 * implementation ledger row **P5-1** was opened for.
 *
 * §1a's rule is `count(listings WHERE status='published' AND
 * visibility='active') > 0`, and this answers exactly the count half; the
 * suspension half stays an input to `findVisibleProviders`, which is where
 * §1a puts it. This source must never learn about suspension — that is the
 * per-consumer reimplementation §1a exists to prevent.
 *
 * `some` rather than a count: the rule is "at least one", so the database can
 * stop at the first matching row, and the composite index
 * `(provider_profile_id, status, visibility, deleted_at)` covers it exactly.
 */
export const PUBLISHED_LISTINGS: PublishedListingSource = {
  havingPublishedListing: () => ({ listings: { some: PUBLICLY_VISIBLE_LISTING } }),
};
