import { z } from 'zod';

/**
 * Request validation for the location surface (§Phase 7).
 *
 * Note what is **not** here: a `limit`, a `cursor` or any other way to
 * truncate an island search. §0.0 item 12 requires every match to be returned
 * with no cap and no "show more", because truncating hides the one island the
 * customer came for. See `LocationService.searchIslands` for why that does not
 * breach `backend/CLAUDE.md`'s pagination rule.
 */

/**
 * The search term. Optional — no term lists every active island, which is what
 * the picker shows before the customer types.
 *
 * Length-capped only to bound the work; the value is normalised to `[a-z0-9]`
 * before it reaches the database, so it cannot carry a `LIKE` wildcard.
 */
export const listIslandsQuery = z.object({
  search: z.string().max(120).optional(),
});

/** An island is addressed by its UUID. Never by name — names are not unique (§0.0 item 12). */
export const serviceAreaBody = z.object({
  islandId: z.uuid(),
});

export const serviceAreaParams = z.object({
  islandId: z.uuid(),
});

export type ListIslandsQuery = z.infer<typeof listIslandsQuery>;
export type ServiceAreaBody = z.infer<typeof serviceAreaBody>;
