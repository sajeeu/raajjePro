import type {
  Island,
  Listing,
  ListingMedia,
  ListingServiceArea,
  Prisma,
  PrismaClient,
} from '../../generated/prisma/client.js';
import { COUNTS_AGAINST_CAP } from './visibility.js';

/** A Prisma client or an open transaction — publish does several writes that must land together. */
type Db = PrismaClient | Prisma.TransactionClient;

export type ListingServiceAreaWithIsland = ListingServiceArea & { island: Island };

/**
 * Listing reads and writes (§Phase 8).
 *
 * **Every read filters out soft-deleted rows, here rather than at the call
 * site** (backend/CLAUDE.md: "every query that returns user-visible data
 * filters on the visibility/status field"). A caller cannot forget, because
 * no method on this class can return a deleted listing at all — which is also
 * why deleting one twice answers not-found rather than doing it again.
 */
export class ListingRepository {
  constructor(private readonly prisma: PrismaClient) {}

  create(data: Prisma.ListingUncheckedCreateInput): Promise<Listing> {
    return this.prisma.listing.create({ data });
  }

  /**
   * One listing owned by one provider, soft-deleted rows excluded.
   *
   * `findFirst` with the owner in the WHERE rather than `findUnique` by id
   * followed by an ownership check: a query that cannot return another
   * provider's row is stronger than one that returns it and then remembers
   * to compare. The two cases a caller must distinguish — "not yours" and
   * "does not exist" — deliberately collapse to the same not-found, so this
   * endpoint cannot be used to discover which listing ids exist.
   */
  findOwned(id: string, providerProfileId: string, db: Db = this.prisma): Promise<Listing | null> {
    return db.listing.findFirst({ where: { id, providerProfileId, deletedAt: null } });
  }

  /** The owner's My Services page. Newest-touched first, which is the order a draft-in-progress wants. */
  findOwnedPage(
    providerProfileId: string,
    limit: number,
    after: { updatedAt: Date; id: string } | null,
    status?: 'draft' | 'published',
  ): Promise<Listing[]> {
    return this.prisma.listing.findMany({
      where: {
        providerProfileId,
        deletedAt: null,
        ...(status === undefined ? {} : { status }),
        ...(after === null
          ? {}
          : {
              OR: [
                { updatedAt: { lt: after.updatedAt } },
                { updatedAt: after.updatedAt, id: { gt: after.id } },
              ],
            }),
      },
      orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    });
  }

  update(id: string, data: Prisma.ListingUncheckedUpdateInput, db: Db = this.prisma) {
    return db.listing.update({ where: { id }, data });
  }

  /**
   * §1b's cap question: how many listings is this provider holding live?
   *
   * Counts exactly the set the public sees — `COUNTS_AGAINST_CAP` is the same
   * constant `PublishedListings` reads. If the two ever diverged a provider
   * could be over their cap with nothing visible, or under it with two
   * listings live.
   *
   * `excludeId` is for the listing being published or unhidden, so it is not
   * counted against itself.
   */
  countActive(providerProfileId: string, excludeId?: string): Promise<number> {
    return this.prisma.listing.count({
      where: {
        providerProfileId,
        ...COUNTS_AGAINST_CAP,
        ...(excludeId === undefined ? {} : { id: { not: excludeId } }),
      },
    });
  }

  /** The one other listing an over-cap message can name — the wizard's sheet says which service is already live. */
  findActive(providerProfileId: string, excludeId?: string): Promise<Listing[]> {
    return this.prisma.listing.findMany({
      where: {
        providerProfileId,
        ...COUNTS_AGAINST_CAP,
        ...(excludeId === undefined ? {} : { id: { not: excludeId } }),
      },
      orderBy: { publishedAt: 'asc' },
    });
  }

  /**
   * Every published listing of this provider that still claims emergency
   * work — the set Round 17's downward-tier re-evaluation walks.
   *
   * Published only: a draft claiming emergency work advertises nothing, and
   * clearing the flag on one would silently edit a form the provider is in
   * the middle of. Publish re-checks it anyway.
   */
  findPublishedEmergency(providerProfileId: string) {
    return this.prisma.listing.findMany({
      where: {
        providerProfileId,
        isEmergency: true,
        status: 'published',
        deletedAt: null,
      },
      include: { category: true },
    });
  }

  // -------------------------------------------------------------------------
  // Service areas — the listing's own (ledger P7-3)
  // -------------------------------------------------------------------------

  findServiceAreas(
    listingId: string,
    db: Db = this.prisma,
  ): Promise<ListingServiceAreaWithIsland[]> {
    return db.listingServiceArea.findMany({
      where: { listingId, removedAt: null },
      include: { island: true },
      orderBy: [{ island: { name: 'asc' } }, { island: { atollAbbr: 'asc' } }],
    });
  }

  countServiceAreas(listingId: string, db: Db = this.prisma): Promise<number> {
    return db.listingServiceArea.count({ where: { listingId, removedAt: null } });
  }

  /**
   * Replaces the listing's areas with [islandIds] — the shape a multi-select
   * step PATCHes.
   *
   * Invariant 8 throughout: an island dropped from the set is stamped
   * `removedAt` rather than deleted, and one added back revives the same row
   * through the unique `(listingId, islandId)` pair. The same pattern
   * `ProviderServiceArea` uses, and the reason re-adding an island does not
   * accumulate rows.
   */
  async replaceServiceAreas(
    listingId: string,
    islandIds: string[],
    now: Date,
    db: Db = this.prisma,
  ): Promise<void> {
    const wanted = new Set(islandIds);
    await db.listingServiceArea.updateMany({
      where: { listingId, removedAt: null, islandId: { notIn: [...wanted] } },
      data: { removedAt: now },
    });
    for (const islandId of wanted) {
      await db.listingServiceArea.upsert({
        where: { listingId_islandId: { listingId, islandId } },
        create: { listingId, islandId, addedAt: now },
        update: { removedAt: null, addedAt: now },
      });
    }
  }

  // -------------------------------------------------------------------------
  // Media
  // -------------------------------------------------------------------------

  createMedia(data: Prisma.ListingMediaUncheckedCreateInput): Promise<ListingMedia> {
    return this.prisma.listingMedia.create({ data });
  }

  /**
   * An image a viewer may be shown, and the shared definition of that.
   *
   * **Two independent gates, and they must stay independent** (§1b's
   * reasoning applied to a media row): `removedAt` is the provider taking
   * their own photo down, `hiddenByAdminAt` is §Phase 22's moderation
   * hiding a reported one. Under a single field, un-hiding a moderated image
   * would resurrect one the provider had deliberately removed.
   */
  static readonly RENDERABLE_MEDIA = {
    removedAt: null,
    hiddenByAdminAt: null,
  } as const satisfies Prisma.ListingMediaWhereInput;

  /**
   * One of this listing's images that a write may still touch.
   *
   * Filters `removedAt` only, **not** `hiddenByAdminAt`: a provider must be
   * able to see and replace an image moderation has hidden. What they cannot
   * do is make it their cover — `assertRenderableMedia` in the service is
   * the gate for that.
   */
  findMedia(listingId: string, mediaId: string): Promise<ListingMedia | null> {
    return this.prisma.listingMedia.findFirst({
      where: { id: mediaId, listingId, removedAt: null },
    });
  }

  /**
   * The gallery, in order. The cover is excluded by the caller — it is named
   * separately, not a gallery slot.
   *
   * A moderated image drops out here, which is the point of §Phase 22 being
   * able to hide one: the listing stays up and the reported photo does not
   * render.
   */
  findGallery(listingId: string, db: Db = this.prisma): Promise<ListingMedia[]> {
    return db.listingMedia.findMany({
      where: { listingId, ...ListingRepository.RENDERABLE_MEDIA, sortOrder: { not: null } },
      orderBy: { sortOrder: 'asc' },
    });
  }

  findCover(coverMediaId: string | null, db: Db = this.prisma): Promise<ListingMedia | null> {
    if (coverMediaId === null) return Promise.resolve(null);
    return db.listingMedia.findUnique({ where: { id: coverMediaId } });
  }

  updateMedia(
    id: string,
    data: Prisma.ListingMediaUncheckedUpdateInput,
    db: Db = this.prisma,
  ): Promise<ListingMedia> {
    return db.listingMedia.update({ where: { id }, data });
  }

  /** Runs `fn` in a transaction, so publish's several writes land together or not at all. */
  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }
}
