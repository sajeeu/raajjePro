import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import { Prisma, type PrismaClient } from '../../generated/prisma/client.js';
import type { AuditService } from '../audit/service.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import type { ProviderVisibility } from '../providers/visibility.js';
import { REVIEW_FIELDS, ReviewAggregates, VISIBLE_REVIEW, type ReviewRow } from './repository.js';
import type { PostReviewBody } from './schema.js';
import {
  TAG_DISPLAY_THRESHOLD,
  type BookingReviewDto,
  type RatingSummaryDto,
  type ReviewDto,
  type ReviewTagDto,
} from './types.js';

export interface ReviewServiceDeps {
  prisma: PrismaClient;
  clock: Clock;
  audit: AuditService;
  /** §1a's gate. A provider who is not public has no public reviews either. */
  visibility: ProviderVisibility;
}

interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

/**
 * §Phase 11 — reviews and ratings.
 *
 * A review is the customer's stars, their optional tags from the category's
 * fixed set, and their optional words, about **one completed booking**.
 * Ratings and conduct are separate axes (§1f): nothing here reads a booking
 * outcome, and nothing in `modules/conduct/` reads a review.
 */
export class ReviewService {
  private readonly prisma: PrismaClient;
  private readonly clock: Clock;
  private readonly audit: AuditService;
  private readonly visibility: ProviderVisibility;
  private readonly aggregates = new ReviewAggregates();

  constructor(deps: ReviewServiceDeps) {
    this.prisma = deps.prisma;
    this.clock = deps.clock;
    this.audit = deps.audit;
    this.visibility = deps.visibility;
  }

  // =========================================================================
  // Posting
  // =========================================================================

  /**
   * `POST /v1/bookings/:id/review`.
   *
   * - **The booking's customer only.** Anyone else — the provider included —
   *   gets not-found, so the endpoint does not confirm a stranger's booking
   *   exists.
   * - **Completed only** (§Phase 11). "Completed" is `completedAt`, not the
   *   current status: §1c accepts a late dispute on a completed booking and
   *   "the booking stays completed", and a customer who disputed afterwards
   *   must still be able to say how the job went. A booking that never
   *   completed — cancelled, declined, a completion-prompt "No" — has no
   *   `completedAt` and cannot be reviewed. Auto-completion (§1c step 10) is
   *   what makes this gate safe: a provider cannot hold it shut by silence.
   * - **One per booking**, enforced by the unique key on `review.booking_id`,
   *   so two concurrent posts cannot both land; the loser is told so.
   * - **Tags from the booking's own category**, never text, never retired.
   */
  async post(userId: string, bookingId: string, body: PostReviewBody): Promise<BookingReviewDto> {
    const now = this.clock();
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      select: {
        id: true,
        customerId: true,
        completedAt: true,
        listingId: true,
        providerProfileId: true,
        listing: { select: { categoryId: true } },
        review: { select: { id: true } },
      },
    });
    if (booking?.customerId !== userId) throw new NotFoundError('No such booking');
    if (booking.completedAt === null) {
      throw new BusinessRuleError(
        'REVIEW_BOOKING_NOT_COMPLETED',
        'A booking can be reviewed once it is completed',
      );
    }
    if (booking.review !== null) throw alreadyReviewed();

    const tagIds = [...new Set(body.tagIds)];
    if (tagIds.length > 0) {
      // A listing that took a booking was published, and publishing requires a
      // category; a null here is a draft that never could have, so no tag fits.
      const categoryId = booking.listing.categoryId;
      const valid =
        categoryId === null
          ? 0
          : await this.prisma.reviewTag.count({
              where: { id: { in: tagIds }, categoryId, retiredAt: null },
            });
      if (valid !== tagIds.length) {
        throw new BusinessRuleError(
          'REVIEW_TAG_NOT_IN_CATEGORY',
          "Tags must come from this service category's fixed set",
        );
      }
    }

    try {
      const review = await this.prisma.$transaction(async (tx) => {
        const created = await tx.review.create({
          data: {
            bookingId: booking.id,
            listingId: booking.listingId,
            providerProfileId: booking.providerProfileId,
            authorId: userId,
            rating: body.rating,
            body: body.body,
            createdAt: now,
            tags: { create: tagIds.map((tagId) => ({ tagId, createdAt: now })) },
          },
          select: { id: true },
        });
        await this.aggregates.refresh(
          tx,
          { providerProfileId: booking.providerProfileId, listingId: booking.listingId },
          now,
        );
        return created;
      });
      return await this.readOne(review.id);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw alreadyReviewed();
      }
      throw error;
    }
  }

  /**
   * `GET /v1/bookings/:id/review` — either party to the booking. Answers
   * not-found when there is no review yet, which is how the client knows to
   * offer Rate This Job. Says whether moderation hid it, because both parties
   * are entitled to know what happened to a review of their own job.
   */
  async readForBooking(userId: string, bookingId: string): Promise<BookingReviewDto> {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      select: {
        customerId: true,
        providerProfile: { select: { userId: true } },
        review: { select: { id: true } },
      },
    });
    if (
      booking === null ||
      (booking.customerId !== userId && booking.providerProfile.userId !== userId)
    ) {
      throw new NotFoundError('No such booking');
    }
    if (booking.review === null) throw new NotFoundError('No review yet', 'REVIEW_NOT_FOUND');
    return this.readOne(booking.review.id);
  }

  // =========================================================================
  // Public reads
  // =========================================================================

  /** The category's fixed tag set, in display order — what Rate This Job renders. */
  async tagsForCategory(categoryId: string): Promise<ReviewTagDto[]> {
    const category = await this.prisma.category.findUnique({
      where: { id: categoryId },
      select: { id: true },
    });
    if (category === null) throw new NotFoundError('No such category');
    const tags = await this.prisma.reviewTag.findMany({
      where: { categoryId, retiredAt: null },
      orderBy: { sortOrder: 'asc' },
      select: { id: true, key: true, label: true, sentiment: true },
    });
    return tags;
  }

  /**
   * A publicly visible listing's reviews, newest first. A listing that is not
   * public — a draft, hidden, deleted, or owned by a provider §1a does not
   * show — is not found, the same answer its own page gives.
   */
  async listForListing(
    listingId: string,
    paging: { limit: number; cursor?: string | undefined },
  ): Promise<Page<ReviewDto>> {
    await this.assertListingPublic(listingId);
    return this.page({ listingId }, paging);
  }

  async listingSummary(listingId: string): Promise<RatingSummaryDto> {
    await this.assertListingPublic(listingId);
    const [aggregate, tags] = await Promise.all([
      this.prisma.listingRatingAggregate.findUnique({ where: { listingId } }),
      this.prisma.listingReviewTagCount.findMany({
        where: { listingId, customerCount: { gte: TAG_DISPLAY_THRESHOLD } },
        select: TAG_COUNT_FIELDS,
      }),
    ]);
    return toSummary(aggregate, tags);
  }

  /**
   * A visible provider's reviews across every listing — including a listing
   * since deleted, whose reviews §Phase 8 says "remain intact" and still count
   * for the provider.
   */
  async listForProvider(
    providerProfileId: string,
    paging: { limit: number; cursor?: string | undefined },
  ): Promise<Page<ReviewDto>> {
    await this.assertProviderPublic(providerProfileId);
    return this.page({ providerProfileId }, paging);
  }

  async providerSummary(providerProfileId: string): Promise<RatingSummaryDto> {
    await this.assertProviderPublic(providerProfileId);
    const [aggregate, tags] = await Promise.all([
      this.prisma.providerRatingAggregate.findUnique({ where: { providerProfileId } }),
      this.prisma.providerReviewTagCount.findMany({
        where: { providerProfileId, customerCount: { gte: TAG_DISPLAY_THRESHOLD } },
        select: TAG_COUNT_FIELDS,
      }),
    ]);
    return toSummary(aggregate, tags);
  }

  // =========================================================================
  // Moderation
  // =========================================================================

  /**
   * `POST /v1/admin/reviews/:id/hide` — "Soft-delete; a hidden review is
   * excluded from aggregates." A flag, never a delete (invariant 1d), so
   * `unhide` puts it back exactly; both recompute the aggregates in the same
   * transaction and both are audit-logged with the admin's reason. §Phase 22
   * builds the queue that decides when to call these.
   */
  async hide(
    reviewId: string,
    adminId: string,
    reason: string,
    meta: { requestId?: string | null; ipAddress?: string | null } = {},
  ): Promise<BookingReviewDto> {
    return this.setHidden(reviewId, adminId, reason, true, meta);
  }

  async unhide(
    reviewId: string,
    adminId: string,
    reason: string,
    meta: { requestId?: string | null; ipAddress?: string | null } = {},
  ): Promise<BookingReviewDto> {
    return this.setHidden(reviewId, adminId, reason, false, meta);
  }

  private async setHidden(
    reviewId: string,
    adminId: string,
    reason: string,
    hide: boolean,
    meta: { requestId?: string | null; ipAddress?: string | null },
  ): Promise<BookingReviewDto> {
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      const review = await tx.review.findUnique({
        where: { id: reviewId },
        select: { id: true, providerProfileId: true, listingId: true },
      });
      if (review === null) throw new NotFoundError('No such review', 'REVIEW_NOT_FOUND');
      // Conditional on the current state, so two admins acting at once are
      // one success and one conflict rather than two audit entries.
      const { count } = await tx.review.updateMany({
        where: { id: reviewId, hiddenAt: hide ? null : { not: null } },
        data: hide
          ? { hiddenAt: now, hiddenByAdminId: adminId, hiddenReason: reason }
          : { hiddenAt: null, hiddenByAdminId: null, hiddenReason: null },
      });
      if (count === 0) {
        throw new ConflictError(
          hide ? 'REVIEW_ALREADY_HIDDEN' : 'REVIEW_NOT_HIDDEN',
          hide ? 'This review is already hidden' : 'This review is not hidden',
        );
      }
      await this.aggregates.refresh(
        tx,
        { providerProfileId: review.providerProfileId, listingId: review.listingId },
        now,
      );
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: hide ? 'review.hidden' : 'review.unhidden',
        targetType: 'review',
        targetId: reviewId,
        reason,
        metadata: { providerProfileId: review.providerProfileId, listingId: review.listingId },
        requestId: meta.requestId ?? null,
        ipAddress: meta.ipAddress ?? null,
      });
    });
    return this.readOne(reviewId);
  }

  // =========================================================================

  private async readOne(reviewId: string): Promise<BookingReviewDto> {
    const row = await this.prisma.review.findUniqueOrThrow({
      where: { id: reviewId },
      select: REVIEW_FIELDS,
    });
    return { ...toReviewDto(row), hidden: row.hiddenAt !== null };
  }

  private async page(
    scope: Prisma.ReviewWhereInput,
    paging: { limit: number; cursor?: string | undefined },
  ): Promise<Page<ReviewDto>> {
    const after = paging.cursor === undefined ? null : decodeCursor(paging.cursor);
    const rows = await this.prisma.review.findMany({
      where: {
        AND: [
          scope,
          VISIBLE_REVIEW,
          after === null
            ? {}
            : {
                OR: [
                  { createdAt: { lt: after.createdAt } },
                  { createdAt: after.createdAt, id: { lt: after.id } },
                ],
              },
        ],
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: paging.limit + 1,
      select: REVIEW_FIELDS,
    });
    const items = rows.slice(0, paging.limit);
    const last = items.at(-1);
    return {
      items: items.map(toReviewDto),
      nextCursor:
        rows.length > paging.limit && last !== undefined
          ? encodeCursor(last.createdAt, last.id)
          : null,
    };
  }

  private async assertListingPublic(listingId: string): Promise<void> {
    const listing = await this.prisma.listing.findFirst({
      where: { id: listingId, ...PUBLICLY_VISIBLE_LISTING },
      select: { providerProfileId: true },
    });
    if (listing === null || !(await this.visibility.isVisible(listing.providerProfileId))) {
      throw new NotFoundError('No such listing');
    }
  }

  private async assertProviderPublic(providerProfileId: string): Promise<void> {
    if (!(await this.visibility.isVisible(providerProfileId))) {
      throw new NotFoundError('No such provider');
    }
  }
}

const TAG_COUNT_FIELDS = {
  applicationCount: true,
  tag: { select: { key: true, label: true, sentiment: true, sortOrder: true } },
} as const;

function alreadyReviewed(): ConflictError {
  return new ConflictError('REVIEW_ALREADY_POSTED', 'This booking already has its one review');
}

function toReviewDto(row: ReviewRow): ReviewDto {
  return {
    id: row.id,
    bookingId: row.bookingId,
    listingId: row.listingId,
    rating: row.rating,
    body: row.body,
    tags: row.tags
      .map((t) => t.tag)
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map(({ id, key, label, sentiment }) => ({ id, key, label, sentiment })),
    authorDisplayName: row.authorAnonymisedAt === null ? shortName(row.author.fullName) : null,
    createdAt: row.createdAt.toISOString(),
  };
}

/** "Aishath Nadheem" → "Aishath N."; a single name stays as it is. */
export function shortName(fullName: string): string | null {
  const parts = fullName
    .trim()
    .split(/\s+/)
    .filter((p) => p.length > 0);
  const first = parts[0];
  if (first === undefined) return null;
  const last = parts.length > 1 ? parts.at(-1) : undefined;
  return last === undefined ? first : `${first} ${last.charAt(0).toUpperCase()}.`;
}

function toSummary(
  aggregate: {
    reviewCount: number;
    ratingSum: number;
    stars1: number;
    stars2: number;
    stars3: number;
    stars4: number;
    stars5: number;
  } | null,
  tags: {
    applicationCount: number;
    tag: { key: string; label: string; sentiment: 'positive' | 'negative'; sortOrder: number };
  }[],
): RatingSummaryDto {
  const count = aggregate?.reviewCount ?? 0;
  return {
    reviewCount: count,
    averageRating:
      aggregate === null || count === 0
        ? null
        : Math.round((aggregate.ratingSum / count) * 100) / 100,
    starBreakdown: {
      1: aggregate?.stars1 ?? 0,
      2: aggregate?.stars2 ?? 0,
      3: aggregate?.stars3 ?? 0,
      4: aggregate?.stars4 ?? 0,
      5: aggregate?.stars5 ?? 0,
    },
    // Most-applied first, the order "On time (31) · Fair price (28) · Arrived
    // late (3)" reads in; the category's own order breaks a tie.
    tags: tags
      .sort((a, b) => b.applicationCount - a.applicationCount || a.tag.sortOrder - b.tag.sortOrder)
      .map((t) => ({
        key: t.tag.key,
        label: t.tag.label,
        sentiment: t.tag.sentiment,
        count: t.applicationCount,
      })),
  };
}

function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}

function decodeCursor(cursor: string): { createdAt: Date; id: string } | null {
  const [at, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  if (at === undefined || id === undefined) return null;
  const createdAt = new Date(at);
  return Number.isNaN(createdAt.getTime()) ? null : { createdAt, id };
}
