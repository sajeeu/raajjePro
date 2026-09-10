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
 * §Phase 5 was sequenced before §Phase 8, so there was no `Listing` table for
 * this file to join against and inventing one would have been building ahead
 * into Phase 8's schema. So the rule lives here and the *predicate* that
 * answers its listing half is injected — the same pattern Phase 3 used for
 * `DeletionBlocker`.
 *
 * 🔧 **Phase 8 filled it, and the shape changed with it — ledger row P5-1,
 * 2026-09-10.** The seam used to hand back a `Set` of provider ids, because
 * a set is all a fake can produce and a page therefore had to be filled by
 * scanning candidates in batches until it was full. Now that a real `listing`
 * table exists the predicate goes **into** the candidate query, so a page is
 * one indexed query with `take: limit + 1` and the batch-accumulating loop is
 * gone. `docs/decisions/17-phase-5-provider-profiles.md` decision 2 recorded
 * this as the change to make; every caller of `findVisibleProviders` is
 * unaffected, which is what that note predicted.
 *
 * `NO_PUBLISHED_LISTINGS` remains the honest default for a build with the
 * seam unfilled: nobody is publicly visible, so a public directory correctly
 * renders empty.
 */

/**
 * Narrows a `ProviderProfile` query to those holding at least one published,
 * active listing — the derived half of §1a, and nothing else.
 *
 * **Suspension is not this source's business.** §1a makes it an input to the
 * helper below precisely so one change covers search, Home and the public
 * profile; a source that filtered on it would be the second copy of the rule.
 *
 * A predicate rather than a lookup so the whole rule is one SQL statement.
 * The listings module supplies the real one; a test supplies an id list.
 */
export interface PublishedListingSource {
  havingPublishedListing(): Prisma.ProviderProfileWhereInput;
}

/**
 * The default when nothing fills the seam. `id IN ()` matches nobody, which
 * is the truthful answer for a build with no listings table wired up — not an
 * empty object, which would match *everybody* and quietly turn every draft-only
 * provider public.
 */
export const NO_PUBLISHED_LISTINGS: PublishedListingSource = {
  havingPublishedListing: () => ({ id: { in: [] } }),
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
    const after = paging.cursor === undefined ? null : decodeCursor(paging.cursor);

    // One query. `take: limit + 1` decides whether a next cursor exists
    // without a second count, and the whole rule — suspension, account
    // status, the caller's filters and the published-listing requirement — is
    // one indexed scan. Until Phase 8 this was a batch-scan loop, because the
    // listing half could not be expressed in SQL (ledger P5-1).
    const rows = await this.prisma.providerProfile.findMany({
      where: {
        AND: [candidateWhere(filters, after), this.listings.havingPublishedListing()],
      },
      orderBy: { id: 'asc' },
      take: limit + 1,
    });

    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    return {
      items: page,
      nextCursor: rows.length > limit && last !== undefined ? encodeCursor(last.id) : null,
    };
  }

  /**
   * The §1a rule for one provider, by profile id. Phase 13's public profile
   * calls this: a provider with no published listing is **not found** even by
   * direct id, rather than rendering an empty profile.
   */
  async isVisible(providerId: string): Promise<boolean> {
    const row = await this.prisma.providerProfile.findFirst({
      where: {
        AND: [{ id: providerId }, candidateWhere({}, null), this.listings.havingPublishedListing()],
      },
      select: { id: true },
    });
    return row !== null;
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
