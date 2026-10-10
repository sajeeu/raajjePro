import { z } from 'zod';

/**
 * The three sorts, in §Phase 15's order (Round 12): distance, then rating,
 * then price. `distance` is the default because "a provider who cannot reach
 * your island is not a result at all".
 */
export const SEARCH_SORTS = ['distance', 'rating', 'price'] as const;
export type SearchSort = (typeof SEARCH_SORTS)[number];

/** A non-negative whole number of laari (invariant 7), at most what a 32-bit column holds. */
const laari = z.coerce.number().int().min(0).max(2_147_483_647);

/**
 * `GET /v1/search/listings`.
 *
 * What is **not** here matters as much as what is:
 *
 *   - **No emergency filter (Round 23).** Dispatch never targets a provider,
 *     so narrowing by emergency produces result sets the customer cannot act
 *     on.
 *   - **No verification-tier filter.** "No visibility difference between
 *     verified and unverified providers in baseline search." The tier is
 *     neither a filter nor an input to the ranking.
 *   - **No nationality.** §1g's filter is about the *business*, and it is
 *     the only local-preference input there is.
 */
export const searchQuery = z
  .object({
    /** Free text over listing name, short description, tags, category and business name. */
    q: z.string().trim().max(100).optional(),
    /** The customer's browsing island, by id and never by name (§0.0 item 12). The membership gate. */
    islandId: z.uuid().optional(),
    categoryId: z.uuid().optional(),
    /** `slot` is "Pick a time" and `request` is "Request a time" (§1c). */
    mode: z.enum(['slot', 'request']).optional(),
    priceMinLaari: laari.optional(),
    priceMaxLaari: laari.optional(),
    /** §1g. Only `true` narrows. Below Gold the attribute is absent, so those providers never match. */
    maldivianOwned: z
      .enum(['true', 'false'])
      .optional()
      .transform((value) => value === 'true'),
    sort: z.enum(SEARCH_SORTS).default('distance'),
    /** One page of the result screen ("Show 12 more"). */
    limit: z.coerce.number().int().min(1).max(50).default(12),
    cursor: z.string().max(400).optional(),
  })
  .refine(
    (query) =>
      query.priceMinLaari === undefined ||
      query.priceMaxLaari === undefined ||
      query.priceMinLaari <= query.priceMaxLaari,
    { message: 'priceMinLaari must not exceed priceMaxLaari', path: ['priceMinLaari'] },
  );

export type SearchQuery = z.infer<typeof searchQuery>;
