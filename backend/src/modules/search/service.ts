import { Prisma, type PrismaClient } from '../../generated/prisma/client.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import type { ProviderVisibility } from '../providers/visibility.js';
import type { PublicListingService } from '../public-listings/service.js';
import { priorityPlacementProviderIds } from '../subscriptions/entitlements.js';
import { searchTokens } from './fold.js';
import type { SearchQuery, SearchSort } from './schema.js';
import type { SearchPageDto, SearchResultDto } from './types.js';

export interface SearchServiceDeps {
  prisma: PrismaClient;
  visibility: ProviderVisibility;
  publicListings: PublicListingService;
}

/**
 * §Phase 15 — Search & Discovery.
 *
 * The work splits into three steps, each with one job:
 *
 * 1. **Membership** (`candidates`), which is Prisma throughout. A result is a
 *    listing `PUBLICLY_VISIBLE_LISTING` shows, whose provider passes
 *    `ProviderVisibility.visibleWhere` (§1a's one helper, so suspension is
 *    still an input to it and nothing here re-states it), and which matches
 *    every filter and every word of the query. Priority placement plays no
 *    part in this step, so it **cannot affect membership**, which the Done
 *    when requires.
 * 2. **Placement** (`priorityPlacementProviderIds`), billing's own
 *    entitlement mapping, read once for the providers in the set.
 * 3. **Order** (`orderedPage`), raw SQL, because the sort keys are computed:
 *    how many islands a listing serves, its average rating and its headline
 *    price. Keyset-paged, so a page boundary never duplicates or skips a
 *    result, including across the boosted and unboosted groups.
 *
 * Who may call: anyone, a guest included (§8: guests browse freely). Nothing
 * here reads who is asking, and every viewer gets the same answer.
 */
export class SearchService {
  constructor(private readonly deps: SearchServiceDeps) {}

  async search(query: SearchQuery): Promise<{ page: SearchPageDto; nextCursor: string | null }> {
    const candidates = await this.candidates(query);
    if (candidates.length === 0) return { page: { total: 0, items: [] }, nextCursor: null };

    const boosted = await priorityPlacementProviderIds(this.deps.prisma, [
      ...new Set(candidates.map((row) => row.providerProfileId)),
    ]);

    const after = decodeCursor(query.cursor, query.sort);
    const rows = await this.orderedPage({
      ids: candidates.map((row) => row.id),
      boostedProviderIds: [...boosted],
      sort: query.sort,
      after,
      take: query.limit + 1,
    });
    const page = rows.slice(0, query.limit);
    const last = page[page.length - 1];

    const cards = await this.deps.publicListings.cardsByIds(page.map((row) => row.id));
    const items: SearchResultDto[] = page.flatMap((row) => {
      const card = cards.get(row.id);
      // Gone between the two reads: hidden, unpublished, or the provider
      // suspended in the last few milliseconds. It is absent, never an error.
      return card === undefined
        ? []
        : [{ listing: card.listing, provider: card.provider, sponsored: row.g === '0' }];
    });

    return {
      page: { total: candidates.length, items },
      nextCursor:
        rows.length > query.limit && last !== undefined ? encodeCursor(query.sort, last) : null,
    };
  }

  /**
   * Step 1: which listings are results at all. Every predicate is
   * conjunctive, and none of them reads the subscription.
   */
  private async candidates(
    query: SearchQuery,
  ): Promise<{ id: string; providerProfileId: string }[]> {
    const tokens = searchTokens(query.q);
    const textMatched = tokens.length === 0 ? null : await this.textMatches(tokens);
    if (textMatched?.length === 0) return [];

    const where: Prisma.ListingWhereInput = {
      ...PUBLICLY_VISIBLE_LISTING,
      providerProfile: this.deps.visibility.visibleWhere({
        // Ruling Q6: the toggle "hides every service at once" (§Phase 5).
        // This is about availability, never about verification.
        acceptingNewCustomers: true,
        ...(query.maldivianOwned ? { maldivianOwned: true } : {}),
      }),
      ...(query.categoryId === undefined ? {} : { categoryId: query.categoryId }),
      ...(query.mode === undefined ? {} : { bookingMode: query.mode }),
      // The island gate reads the *listing's* own service areas by id. The
      // provider's account-level default does not count (ledger P7-3).
      ...(query.islandId === undefined
        ? {}
        : { serviceAreas: { some: { islandId: query.islandId, removedAt: null } } }),
      AND: [
        priceWhere(query.priceMinLaari, query.priceMaxLaari),
        textMatched === null ? {} : { id: { in: textMatched } },
      ],
    };

    return this.deps.prisma.listing.findMany({
      where,
      select: { id: true, providerProfileId: true },
    });
  }

  /**
   * The listings whose text holds every token (ruling Q4). Each token must be
   * found in at least one of these: the listing's name, short description or
   * tags, its category's name, or its provider's business name.
   *
   * **No personal name and no contact field is ever read**: `user` is not
   * joined. The expressions are the ones the migration's trigram indexes are
   * built on, character for character, so the planner can use them.
   *
   * The published, active and undeleted clauses are only a narrowing, there
   * to keep this set small. Step 1 applies the real rule
   * (`PUBLICLY_VISIBLE_LISTING` and §1a) to whatever comes back.
   */
  private async textMatches(tokens: string[]): Promise<string[]> {
    const clauses = tokens.map((token) => {
      const pattern = `%${token}%`;
      return Prisma.sql`(
        public.rp_listing_search_doc(l.name, l.short_description, l.tags) LIKE ${pattern}
        OR public.rp_search_fold(c.name) LIKE ${pattern}
        OR public.rp_search_fold(coalesce(p.business_name, '')) LIKE ${pattern}
      )`;
    });
    const rows = await this.deps.prisma.$queryRaw<{ id: string }[]>`
      SELECT l.id::text AS id
      FROM listing l
      JOIN category c ON c.id = l.category_id
      JOIN provider_profile p ON p.id = l.provider_profile_id
      WHERE l.status = 'published' AND l.visibility = 'active' AND l.deleted_at IS NULL
        AND ${Prisma.join(clauses, ' AND ')}
    `;
    return rows.map((row) => row.id);
  }

  /**
   * Step 3: one page of the set, in order.
   *
   * Every result gets a five-part key, compared ascending as one row value:
   *
   *   `g`: 0 when priority placement boosted it and 1 otherwise. The group
   *   comes first, so boosted results lead **under every sort** (ruling Q2),
   *   and the chosen sort still orders each group within itself.
   *   `k1, k2, k3`: the sort's own keys (see `SORT_KEYS`).
   *   `id`: the tiebreak that makes the order total.
   *
   * Paging uses the row value as a keyset: `(g, k1, k2, k3, id) > cursor`.
   * The order is total and every key is carried back in the cursor, so no
   * result is repeated or skipped across a page boundary, including the one
   * between the two groups.
   */
  private async orderedPage(input: {
    ids: string[];
    boostedProviderIds: string[];
    sort: SearchSort;
    after: CursorKey | null;
    take: number;
  }): Promise<OrderedRow[]> {
    const [k1, k2, k3] = SORT_KEYS[input.sort];
    const after =
      input.after === null
        ? Prisma.empty
        : Prisma.sql`WHERE (g, k1, k2, k3, id) > (${input.after.g}::int, ${input.after.k1}::numeric, ${input.after.k2}::numeric, ${input.after.k3}::numeric, ${input.after.id}::uuid)`;

    return this.deps.prisma.$queryRaw<OrderedRow[]>`
      WITH keyed AS (
        SELECT
          l.id,
          CASE WHEN l.provider_profile_id = ANY(${input.boostedProviderIds}::uuid[]) THEN 0 ELSE 1 END AS g,
          (SELECT count(*) FROM listing_service_area a
             WHERE a.listing_id = l.id AND a.removed_at IS NULL)::numeric AS islands,
          -- Higher is better, so it is negated to sort ascending. No rating
          -- at all is +1, which puts it after every rated listing.
          coalesce(-(r.rating_sum::numeric / nullif(r.review_count, 0)), 1) AS neg_rating,
          (-coalesce(r.review_count, 0))::numeric AS neg_reviews,
          -- The headline number a card prints: the price, or the "from"
          -- figure of a range. A quote has none and goes last (ruling Q3).
          coalesce(
            CASE l.pricing_model
              WHEN 'range' THEN l.price_min_laari
              WHEN 'quote' THEN NULL
              ELSE l.price_laari
            END,
            2147483647
          )::numeric AS price
        FROM listing l
        LEFT JOIN listing_rating_aggregate r ON r.listing_id = l.id
        WHERE l.id = ANY(${input.ids}::uuid[])
      ),
      ordered AS (
        SELECT id, g, ${Prisma.raw(k1)} AS k1, ${Prisma.raw(k2)} AS k2, ${Prisma.raw(k3)} AS k3
        FROM keyed
      )
      SELECT id::text AS id, g::text AS g, k1::text AS k1, k2::text AS k2, k3::text AS k3
      FROM ordered
      ${after}
      -- Qualified, so the order is on the numeric keys and the uuid rather than
      -- on the text the SELECT list casts them to for the cursor.
      ORDER BY ordered.g, ordered.k1, ordered.k2, ordered.k3, ordered.id
      LIMIT ${input.take}
    `;
  }
}

/**
 * The three sorts' keys, in comparison order. Each one is a column of
 * `keyed` and nothing a client sends: `Prisma.raw` only ever receives these
 * literals.
 *
 * **`distance` is an island-relative proxy, not a measurement** (ruling Q1,
 * consistent with decision 30). The schema knows islands and nothing finer.
 * Once an island is chosen, every result serves it, so a listing serving
 * fewer islands ranks first: a Malé-only plumber is more local than one
 * covering thirty. Ties go to the higher rating. With no island chosen, the
 * same order applies without the gate.
 */
const SORT_KEYS: Record<SearchSort, [string, string, string]> = {
  distance: ['islands', 'neg_rating', 'neg_reviews'],
  rating: ['neg_rating', 'neg_reviews', 'islands'],
  price: ['price', 'neg_rating', 'neg_reviews'],
};

/**
 * Ruling Q3. A fixed, hourly or daily listing matches on its price. A range
 * listing matches when its range overlaps the filter. A quote listing has no
 * price to compare, so it is excluded whenever a bound is set.
 *
 * Units are **not** normalised: MVR 300/hour and MVR 500/job compare on the
 * number. That is knowingly imprecise (decision 36).
 */
function priceWhere(min: number | undefined, max: number | undefined): Prisma.ListingWhereInput {
  if (min === undefined && max === undefined) return {};
  const between = {
    ...(min === undefined ? {} : { gte: min }),
    ...(max === undefined ? {} : { lte: max }),
  };
  return {
    OR: [
      { pricingModel: { in: ['fixed', 'hourly', 'daily'] }, priceLaari: between },
      {
        pricingModel: 'range',
        ...(max === undefined ? {} : { priceMinLaari: { lte: max } }),
        ...(min === undefined ? {} : { priceMaxLaari: { gte: min } }),
      },
    ],
  };
}

interface OrderedRow {
  id: string;
  g: string;
  k1: string;
  k2: string;
  k3: string;
}

interface CursorKey {
  g: number;
  k1: string;
  k2: string;
  k3: string;
  id: string;
}

/**
 * The cursor carries the sort it was issued under along with every key, so a
 * page never resumes from a position under a different order. The keys
 * travel as the database's own decimal text, so an average such as 4.333…
 * comes back with exactly the precision it left with.
 */
function encodeCursor(sort: SearchSort, row: OrderedRow): string {
  return Buffer.from(
    JSON.stringify({ s: sort, g: Number(row.g), k: [row.k1, row.k2, row.k3], id: row.id }),
    'utf8',
  ).toString('base64url');
}

/**
 * A malformed cursor, or one issued under another sort, reads as "from the
 * beginning" rather than a 500. This is `ProviderVisibility`'s precedent for
 * a client-supplied opaque string on a public page. Every part is
 * shape-checked before it reaches a cast, because Postgres turns a bad
 * `::uuid` or `::numeric` into an error the global handler can only report
 * as a 500.
 */
function decodeCursor(cursor: string | undefined, sort: SearchSort): CursorKey | null {
  if (cursor === undefined) return null;
  try {
    const parsed = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown;
    if (typeof parsed !== 'object' || parsed === null) return null;
    const { s, g, k, id } = parsed as Record<string, unknown>;
    if (s !== sort || (g !== 0 && g !== 1) || typeof id !== 'string' || !UUID.test(id)) {
      return null;
    }
    if (!Array.isArray(k) || k.length !== 3) return null;
    const [k1, k2, k3] = k as unknown[];
    if (![k1, k2, k3].every((v) => typeof v === 'string' && DECIMAL.test(v))) return null;
    return { g, k1: k1 as string, k2: k2 as string, k3: k3 as string, id };
  } catch {
    return null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DECIMAL = /^-?\d{1,12}(\.\d{1,40})?$/;
