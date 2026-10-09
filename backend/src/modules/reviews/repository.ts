import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';

export type Db = PrismaClient | Prisma.TransactionClient;

/** What every review read selects. `authorId` is not here, and that is the point (types.ts). */
export const REVIEW_FIELDS = {
  id: true,
  bookingId: true,
  listingId: true,
  rating: true,
  body: true,
  hiddenAt: true,
  authorAnonymisedAt: true,
  createdAt: true,
  author: { select: { fullName: true } },
  tags: {
    select: {
      tag: { select: { id: true, key: true, label: true, sentiment: true, sortOrder: true } },
    },
  },
} as const satisfies Prisma.ReviewSelect;

export type ReviewRow = Prisma.ReviewGetPayload<{ select: typeof REVIEW_FIELDS }>;

/** A visible review — the one predicate every aggregate and public read uses. */
export const VISIBLE_REVIEW = { hiddenAt: null } as const satisfies Prisma.ReviewWhereInput;

/**
 * §Phase 11's "rating aggregation per listing and per provider; star
 * breakdown, **computed transactionally on write**".
 *
 * ## Recomputed, not incremented
 *
 * Every write that changes what is visible — a post, a hide, an unhide —
 * calls `refresh` inside its own transaction, and `refresh` rebuilds the
 * aggregate from the visible reviews rather than adding or subtracting one.
 * An increment is correct only if every earlier increment was; a recompute is
 * correct by construction, and "hiding a review recomputes the aggregate" is
 * then literally what happens.
 *
 * ## Serialised per provider
 *
 * The aggregate row is locked first — an `INSERT … ON CONFLICT DO UPDATE`,
 * which takes the row lock and holds it to commit. Two reviews posted at once
 * for the same provider therefore queue on that lock, and under READ
 * COMMITTED the second one's recompute sees the first one's committed row.
 * Without the lock both would count from a snapshot missing the other, and
 * one review would vanish from the aggregate until the next write. Provider
 * before listing, always, so two writers can never hold them in opposite
 * orders.
 */
export class ReviewAggregates {
  async refresh(
    tx: Prisma.TransactionClient,
    target: { providerProfileId: string; listingId: string },
    now: Date,
  ): Promise<void> {
    await tx.providerRatingAggregate.upsert({
      where: { providerProfileId: target.providerProfileId },
      create: { providerProfileId: target.providerProfileId },
      update: { updatedAt: now },
    });
    await tx.listingRatingAggregate.upsert({
      where: { listingId: target.listingId },
      create: { listingId: target.listingId },
      update: { updatedAt: now },
    });

    const providerStars = await starCounts(tx, { providerProfileId: target.providerProfileId });
    await tx.providerRatingAggregate.update({
      where: { providerProfileId: target.providerProfileId },
      data: providerStars,
    });
    const listingStars = await starCounts(tx, { listingId: target.listingId });
    await tx.listingRatingAggregate.update({
      where: { listingId: target.listingId },
      data: listingStars,
    });

    await this.refreshProviderTags(tx, target.providerProfileId);
    await this.refreshListingTags(tx, target.listingId);
  }

  private async refreshProviderTags(
    tx: Prisma.TransactionClient,
    providerProfileId: string,
  ): Promise<void> {
    const counts = await tagCounts(tx, { providerProfileId });
    for (const [tagId, count] of counts) {
      await tx.providerReviewTagCount.upsert({
        where: { providerProfileId_tagId: { providerProfileId, tagId } },
        create: { providerProfileId, tagId, ...count },
        update: count,
      });
    }
    // A tag whose every application was hidden falls to zero rather than
    // keeping its last count. Rows are never deleted (invariant 8).
    await tx.providerReviewTagCount.updateMany({
      where: { providerProfileId, tagId: { notIn: [...counts.keys()] } },
      data: { applicationCount: 0, customerCount: 0 },
    });
  }

  private async refreshListingTags(tx: Prisma.TransactionClient, listingId: string): Promise<void> {
    const counts = await tagCounts(tx, { listingId });
    for (const [tagId, count] of counts) {
      await tx.listingReviewTagCount.upsert({
        where: { listingId_tagId: { listingId, tagId } },
        create: { listingId, tagId, ...count },
        update: count,
      });
    }
    await tx.listingReviewTagCount.updateMany({
      where: { listingId, tagId: { notIn: [...counts.keys()] } },
      data: { applicationCount: 0, customerCount: 0 },
    });
  }
}

interface StarCounts {
  reviewCount: number;
  ratingSum: number;
  stars1: number;
  stars2: number;
  stars3: number;
  stars4: number;
  stars5: number;
}

async function starCounts(db: Db, scope: Prisma.ReviewWhereInput): Promise<StarCounts> {
  const groups = await db.review.groupBy({
    by: ['rating'],
    where: { ...scope, ...VISIBLE_REVIEW },
    _count: { _all: true },
  });
  const byStar = (n: number) => groups.find((g) => g.rating === n)?._count._all ?? 0;
  const counts = [1, 2, 3, 4, 5].map(byStar);
  return {
    reviewCount: counts.reduce((a, b) => a + b, 0),
    ratingSum: counts.reduce((sum, c, i) => sum + c * (i + 1), 0),
    stars1: byStar(1),
    stars2: byStar(2),
    stars3: byStar(3),
    stars4: byStar(4),
    stars5: byStar(5),
  };
}

/**
 * Per tag: how many visible reviews carry it, and how many **different
 * authors** wrote those reviews. The second number is what §1f's display
 * threshold reads (decision 32) — one customer reviewing the same provider
 * three times must not be able to brand them alone.
 */
async function tagCounts(
  db: Db,
  scope: Prisma.ReviewWhereInput,
): Promise<Map<string, { applicationCount: number; customerCount: number }>> {
  const rows = await db.reviewTagApplication.findMany({
    where: { review: { ...scope, ...VISIBLE_REVIEW } },
    select: { tagId: true, review: { select: { authorId: true } } },
  });
  const byTag = new Map<string, { applications: number; authors: Set<string> }>();
  for (const row of rows) {
    const entry = byTag.get(row.tagId) ?? { applications: 0, authors: new Set<string>() };
    entry.applications += 1;
    entry.authors.add(row.review.authorId);
    byTag.set(row.tagId, entry);
  }
  return new Map(
    [...byTag].map(([tagId, e]) => [
      tagId,
      { applicationCount: e.applications, customerCount: e.authors.size },
    ]),
  );
}
