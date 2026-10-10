/**
 * The free-text fold, query side. Its SQL twin is `rp_search_fold` in the
 * Phase 15 migration, and the two must agree: a token produced here is
 * matched with `LIKE '%token%'` against text folded there.
 *
 * Both sides apply island search's three rules (§0.0 item 12,
 * `location/normalise.ts`): accents are ignored, so `male` finds `Malé`; the
 * Dhivehi apostrophe is ignored, so `kondey` finds `Kon'dey`; and case is
 * ignored.
 *
 * Unlike an island name, a query is several words, and every word has to
 * match somewhere (decision 36). So the fold splits words rather than running
 * them together. "ahmed plumbing" then finds Ahmed's business through its
 * name and the plumbing through the category, in either order.
 *
 * Every token is reduced to `[a-z0-9]`, so a token can never carry a `LIKE`
 * wildcard into the query.
 */

/** Bounds the number of `LIKE` clauses one request can build. */
export const MAX_TOKENS = 8;

const APOSTROPHES = /['’ʼ`]/g;

export function searchTokens(query: string | undefined): string[] {
  if (query === undefined) return [];
  const words = query
    .normalize('NFD')
    .replace(/\p{Mn}/gu, '')
    .replace(APOSTROPHES, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length > 0);
  return [...new Set(words)].slice(0, MAX_TOKENS);
}
