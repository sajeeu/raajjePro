import type {
  Prisma,
  PrismaClient,
  ProviderProfile,
  VerificationTier,
} from '../../generated/prisma/client.js';

/**
 * `findVisibleProviders` — the single shared gate (§1a, §Phase 5).
 *
 * **Public visibility is derived, never stored.** A provider is publicly
 * visible if and only if
 *
 *     count(listings WHERE status='published' AND visibility='active') > 0
 *
 * AND they are not suspended. There is no `lifecycleStatus` column and there
 * must never be one: v1 had one, flipped one-way on first publish, and it
 * drifted — a provider who unpublished their only listing stayed `active`
 * forever with an empty public profile.
 *
 * Every consumer calls this one function. Search (Phase 15), Featured
 * Providers on Home (Phase 16) and the public profile (Phase 13) must not
 * reimplement the rule, and in particular must not add their own suspension
 * filter: §1a makes suspension an **input** to this helper precisely so that
 * one change covers all three.
 *
 * ## Why the listing count arrives through a seam
 *
 * §Phase 5 is sequenced before §Phase 8, so there is no `Listing` table for
 * this file to join against and inventing one would be building ahead into
 * Phase 8's schema. So the count comes from an injected
 * `PublishedListingSource`, the same pattern Phase 3 used for
 * `DeletionBlocker` — the *rule* lives here in one place from today, and
 * Phase 8 supplies the query that answers it.
 *
 * `NO_PUBLISHED_LISTINGS` is the honest default: before Phase 8 there are no
 * listings, so nobody is publicly visible, and any caller that renders a
 * public directory before listings exist correctly renders an empty one.
 */

/**
 * Answers "which of these providers hold at least one published, active
 * listing?" — the derived half of §1a, and nothing else. Suspension is not
 * this source's business; the helper applies it.
 *
 * Batched rather than per-provider so that Phase 8's implementation is one
 * `groupBy` over `listing`, not one query per candidate.
 */
export interface PublishedListingSource {
  providersWithPublishedListing(providerIds: string[]): Promise<Set<string>>;
}

/** Phase 8 replaces this. Until listings exist, nobody has one. */
export const NO_PUBLISHED_LISTINGS: PublishedListingSource = {
  providersWithPublishedListing(): Promise<Set<string>> {
    return Promise.resolve(new Set());
  },
};

/**
 * Filters a caller may add on top of the rule. They narrow the candidate set;
 * none of them can widen it, so no consumer can filter its way past
 * suspension or past the published-listing requirement.
 */
export interface VisibleProviderFilters {
  /**
   * §1g's local preference — a filter, never a ranking boost. `true` matches
   * only providers whose Gold review evidenced Maldivian ownership; the
   * attribute is *absent* rather than false below Gold, so those providers do
   * not match either way.
   */
  maldivianOwned?: boolean;
  /**
   * Minimum verification tier. Callers pass the *category's*
   * `emergencyMinimumTier` here rather than a literal — `gold` for Electrical
   * and Plumbing, `silver` for AC Repair and Moving (§1c). Never hardcode
   * `silver`.
   */
  minimumTier?: VerificationTier;
  /**
   * §Phase 5's provider-level toggle. Discovery surfaces pass `true`; a
   * provider who has turned it off is still *visible* in the §1a sense — the
   * toggle hides their services from new bookings, and Phase 8a's billing
   * pause keys off it — so it is an opt-in filter here and not part of the
   * rule.
   */
  acceptingNewCustomers?: boolean;
}

export interface VisibleProviderPage {
  items: ProviderProfile[];
  nextCursor: string | null;
}

const TIER_ORDER: VerificationTier[] = ['none', 'bronze', 'silver', 'gold'];

/**
 * The tiers at or above `minimum` — an `in` list, so the filter stays a
 * database predicate.
 *
 * Throws on a value outside the enum rather than answering. `slice(indexOf)`
 * with a `-1` index returns `['gold']`, which is a *silently wrong* and
 * silently stricter answer — and §Phase 17.3's emergency dispatch reads the
 * category's `emergencyMinimumTier` through here, so the failure would be an
 * emergency broadcast reaching nobody but Gold providers with nothing logged.
 */
export function tiersAtOrAbove(minimum: VerificationTier): VerificationTier[] {
  const from = TIER_ORDER.indexOf(minimum);
  if (from === -1) throw new Error(`not a verification tier: ${minimum}`);
  return TIER_ORDER.slice(from);
}

/** One page is a search page; the cursor is what keeps this endpoint bounded. */
const DEFAULT_PAGE = 24;

/**
 * How many candidates to pull per round trip while filling a page. The
 * published-listing predicate is applied outside SQL until Phase 8, so a page
 * is filled by scanning candidates in batches until it is full or they run
 * out. Over-fetching keeps the page a full page — a caller must never receive
 * a short page and conclude there is no more data.
 */
const CANDIDATE_BATCH = 200;

export class ProviderVisibility {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly listings: PublishedListingSource,
  ) {}

  /**
   * Who may call: anyone. This returns only what §1a makes public, and every
   * consumer maps it through `toPublicProviderDto`, which carries no phone
   * number and no payment detail.
   */
  async findVisibleProviders(
    filters: VisibleProviderFilters = {},
    paging: { limit?: number; cursor?: string } = {},
  ): Promise<VisibleProviderPage> {
    const limit = paging.limit ?? DEFAULT_PAGE;
    const items: ProviderProfile[] = [];
    let after = paging.cursor === undefined ? null : decodeCursor(paging.cursor);
    let exhausted = false;

    // One extra beyond `limit` decides whether a next cursor exists, without a
    // second count query.
    while (items.length <= limit && !exhausted) {
      const candidates = await this.prisma.providerProfile.findMany({
        where: candidateWhere(filters, after),
        orderBy: { id: 'asc' },
        take: CANDIDATE_BATCH,
      });
      if (candidates.length < CANDIDATE_BATCH) exhausted = true;
      if (candidates.length === 0) break;

      const withListing = await this.listings.providersWithPublishedListing(
        candidates.map((c) => c.id),
      );
      for (const candidate of candidates) {
        if (withListing.has(candidate.id)) items.push(candidate);
      }
      const last = candidates[candidates.length - 1];
      if (last !== undefined) after = { id: last.id };
    }

    const page = items.slice(0, limit);
    const last = page[page.length - 1];
    return {
      items: page,
      nextCursor: items.length > limit && last !== undefined ? encodeCursor(last.id) : null,
    };
  }

  /**
   * The §1a rule for one provider, by profile id. Phase 13's public profile
   * calls this: a provider with no published listing is **not found** even by
   * direct id, rather than rendering an empty profile.
   */
  async isVisible(providerId: string): Promise<boolean> {
    const row = await this.prisma.providerProfile.findFirst({
      where: { id: providerId, ...candidateWhere({}, null) },
      select: { id: true },
    });
    if (row === null) return false;
    const withListing = await this.listings.providersWithPublishedListing([providerId]);
    return withListing.has(providerId);
  }

  /** Same rule, addressed by the owning user — the shape Phase 13 gets from a search result row. */
  async isVisibleByUserId(userId: string): Promise<boolean> {
    const row = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true },
    });
    return row === null ? false : this.isVisible(row.id);
  }
}

/**
 * The half of the rule that IS a database predicate: not suspended (§1a's
 * input), and an account that still exists. `anonymised` and `frozen` are
 * excluded for the same reason suspension is — a deleted or freezing account
 * must not be bookable, and putting it here means no consumer has to remember.
 */
function candidateWhere(
  filters: VisibleProviderFilters,
  after: { id: string } | null,
): Prisma.ProviderProfileWhereInput {
  return {
    suspendedAt: null,
    user: { is: { status: 'active' } },
    ...(filters.maldivianOwned === undefined ? {} : { maldivianOwned: filters.maldivianOwned }),
    ...(filters.minimumTier === undefined
      ? {}
      : { verificationTier: { in: tiersAtOrAbove(filters.minimumTier) } }),
    ...(filters.acceptingNewCustomers === undefined
      ? {}
      : { acceptingNewCustomers: filters.acceptingNewCustomers }),
    ...(after === null ? {} : { id: { gt: after.id } }),
  };
}

/** Keyed on `id` alone: it is the only ordering column, and unlike a name it cannot change underneath a paging client. */
function encodeCursor(id: string): string {
  return Buffer.from(id, 'utf8').toString('base64url');
}

/**
 * A malformed cursor reads as "start from the beginning" rather than 500ing —
 * it is a client-supplied opaque string over a public page.
 *
 * The shape check is load-bearing, not decoration: `id` goes into a `uuid`
 * comparison, and Postgres rejects a non-UUID with a Prisma error the global
 * handler can only turn into a 500. Checking here is what makes the sentence
 * above true.
 */
function decodeCursor(cursor: string): { id: string } | null {
  const id = Buffer.from(cursor, 'base64url').toString('utf8');
  return UUID.test(id) ? { id } : null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
