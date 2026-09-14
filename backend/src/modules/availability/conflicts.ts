/** Any half-open interval. `[startsAt, endsAt)`, matching the `tstzrange` the constraint uses. */
export interface Interval {
  startsAt: Date;
  endsAt: Date;
}

/**
 * Whether two half-open intervals overlap. Touching ends do not — 10:00–12:00
 * and 12:00–14:00 are adjacent, which is what makes a back-to-back grid
 * generated from one rule bookable at all.
 *
 * The same comparison the database makes with `&&` on a `[)` `tstzrange`. It
 * exists in TypeScript as well because the *constraint* is what guarantees
 * correctness under concurrency, while **this** is what keeps an unavailable
 * time off the screen in the first place — §1c: "no picker ever shows an
 * unavailable time".
 */
export function overlaps(a: Interval, b: Interval): boolean {
  return a.startsAt.getTime() < b.endsAt.getTime() && b.startsAt.getTime() < a.endsAt.getTime();
}

/**
 * Whether an interval collides with anything a provider is already holding.
 *
 * **This is why a slot can be unavailable while its own row still says
 * `open`.** A reservation is provider-scoped: a request-based plumbing quote
 * held for 11:00–13:00 blocks the cleaning slot at 12:00 on a different
 * listing, and that slot's row knows nothing about it. Rather than write a
 * `reserved` status onto rows a booking does not belong to — which could not
 * be unwound correctly when it is released — the collision is resolved on
 * read, against the small set of holds in the window being looked at.
 */
export function overlapsAny(candidate: Interval, held: readonly Interval[]): boolean {
  return held.some((interval) => overlaps(candidate, interval));
}
