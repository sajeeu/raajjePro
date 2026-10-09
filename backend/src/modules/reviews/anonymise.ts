import type { AnonymisationHooks } from '../account/anonymise.js';

/**
 * What account deletion does to the author's reviews (§Phase 3, §Phase 11).
 *
 * **The reviews stay, and stay counted.** §Phase 3: "listings and reviews
 * preserved so provider rating aggregates stay intact" — a provider must not
 * lose a five-star review because the customer deleted their account, nor
 * shed a one-star review the same way. So nothing here touches `rating`, the
 * tags, the body or `hiddenAt`, and no aggregate moves.
 *
 * **The attribution goes.** The stamp is what turns the public display name
 * to null, independently of whatever the anonymiser writes into `fullName`.
 *
 * **The author is retained.** `authorId` is deliberately left pointing at the
 * anonymised user row: §Phase 11 keeps authorship internally "so a disputed
 * review can still be traced and adjudicated" — otherwise a customer could
 * post a fabricated review, delete their account and leave the provider with
 * nobody to contest. It is never returned in any response.
 */
export function registerReviewAnonymisation(hooks: AnonymisationHooks): void {
  hooks.register('review-attribution', async (tx, userId, now) => {
    await tx.review.updateMany({
      where: { authorId: userId, authorAnonymisedAt: null },
      data: { authorAnonymisedAt: now },
    });
  });
}
