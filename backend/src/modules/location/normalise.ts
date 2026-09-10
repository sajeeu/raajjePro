/**
 * Island-name normalisation — the one place §0.0 item 12's matching rules are
 * written (plan §Phase 7).
 *
 * The rule the plan states, and what each step of this function is for:
 *
 *   - **ignores case** — `lowercase`.
 *   - **ignores accents**, so `male` finds `Malé` — NFD decomposition then
 *     dropping the combining marks. The register itself writes `Male'`; the
 *     accented spelling is display-only, and a customer may type either.
 *   - **ignores the Dhivehi apostrophe on both sides**, so `Angolhitheemu`
 *     finds `An'golhitheemu` and the reverse — dropped with all other
 *     punctuation. Twenty-five register names carry one and it transliterates
 *     a Thaana glottal, so it is preserved in the *stored* name and only ever
 *     dropped for matching.
 *   - **matches the atoll code too**, so `dh mee` and `dhmee` both find
 *     `Dh. Meedhoo` — whitespace and the convention's full stop are dropped,
 *     which is what lets a typed qualifier run into the name.
 *
 * Reducing to `[a-z0-9]` also removes `%` and `_` from anything a client
 * sends, so a normalised query cannot carry SQL `LIKE` wildcards into a
 * `contains` filter.
 */
export function normaliseIslandText(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Mn}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

/**
 * The two normalised forms an island is matched on.
 *
 * `qualified` is the atoll code followed by the name — `dhmeedhoo`. One
 * column covers both halves of the rule: every substring of `bare` is also a
 * substring of `qualified`, so a single "contains" over `qualified` matches
 * anywhere in the name *and* answers `gdh` with that whole atoll.
 */
export function islandSearchForms(
  name: string,
  atollAbbr: string,
): { bare: string; qualified: string } {
  const bare = normaliseIslandText(name);
  return { bare, qualified: `${normaliseIslandText(atollAbbr)}${bare}` };
}

/**
 * §0.0 item 12: "ranks prefix matches first". A prefix of either form counts —
 * typing `mee` should put `Dh. Meedhoo` above `Rasmaadhoo`, and typing `dhmee`
 * should do the same thing.
 *
 * Rank 0 sorts before rank 1; ties are broken by the caller, on the name.
 */
export function islandMatchRank(query: string, forms: { bare: string; qualified: string }): 0 | 1 {
  return forms.bare.startsWith(query) || forms.qualified.startsWith(query) ? 0 : 1;
}
