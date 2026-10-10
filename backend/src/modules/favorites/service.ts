import type { Clock } from '../../core/clock.js';
import { NotFoundError } from '../../core/errors.js';
import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import type { AnonymisationHooks } from '../account/anonymise.js';
import type { ExportContributor } from '../account/export.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import type { ProviderProfileService } from '../providers/service.js';
import type { ProviderVisibility } from '../providers/visibility.js';
import type { PublicListingService } from '../public-listings/service.js';
import type { ReviewService } from '../reviews/service.js';
import type {
  FavoriteCountsDto,
  FavoriteListingDto,
  FavoriteProviderDto,
  FavoriteStatusDto,
} from './types.js';

/**
 * What "shown on the Saved screen" means, as a predicate — one definition for
 * the lists and the counts, so Profile's number is the screen's number.
 *
 * A saved listing shows while it is publicly visible and its provider passes
 * §1a; a saved provider shows while they pass §1a. Neither rule is restated
 * here: the listing half is `PUBLICLY_VISIBLE_LISTING` and the provider half
 * is `ProviderVisibility.visibleWhere()`, the same gate every public read
 * uses. A favourite that stops showing is **kept**, not stamped — it comes
 * back if the provider republishes, and the customer did not unsave it.
 */
function shownListings(
  visibility: ProviderVisibility,
  userId: string,
): Prisma.FavoriteListingWhereInput {
  return {
    userId,
    deletedAt: null,
    listing: { is: { ...PUBLICLY_VISIBLE_LISTING, providerProfile: visibility.visibleWhere() } },
  };
}

function shownProviders(
  visibility: ProviderVisibility,
  userId: string,
): Prisma.FavoriteProviderWhereInput {
  return { userId, deletedAt: null, providerProfile: { is: visibility.visibleWhere() } };
}

/**
 * The two counts on their own, because `AccountService` is built before the
 * public-listing service this module's lists depend on, and `profile-summary`
 * needs only the numbers (§Phase 14 Done-when: "Profile's count updates").
 */
export class FavoriteCounts {
  constructor(private readonly deps: { prisma: PrismaClient; visibility: ProviderVisibility }) {}

  async countFor(userId: string): Promise<FavoriteCountsDto> {
    const [services, providers] = await Promise.all([
      this.deps.prisma.favoriteListing.count({
        where: shownListings(this.deps.visibility, userId),
      }),
      this.deps.prisma.favoriteProvider.count({
        where: shownProviders(this.deps.visibility, userId),
      }),
    ]);
    return { services, providers };
  }
}

export interface FavoritesServiceDeps {
  prisma: PrismaClient;
  clock: Clock;
  providers: ProviderProfileService;
  publicListings: PublicListingService;
  reviews: ReviewService;
}

/**
 * §Phase 14 — saved services and, since Round 15, saved providers.
 *
 * Every method is the signed-in caller's own: the user id is the principal's,
 * never the request's, so there is no shape of any call that reads or writes
 * somebody else's favourites.
 *
 * **Save and unsave are idempotent.** The heart is optimistic on the client
 * and a retry after a dropped response must land on the same state, so saving
 * a saved thing and unsaving an unsaved one both succeed and change nothing.
 */
export class FavoritesService {
  private readonly visibility: ProviderVisibility;

  constructor(private readonly deps: FavoritesServiceDeps) {
    this.visibility = deps.providers.visibility;
  }

  /**
   * `PUT /v1/users/me/favorites/listings/:listingId`.
   *
   * Only something a customer could be looking at can be saved: a listing §1a
   * and `PUBLICLY_VISIBLE_LISTING` do not show is the same 404 the public page
   * gives, so this endpoint never confirms that a hidden listing exists.
   */
  async saveListing(userId: string, listingId: string): Promise<{ saved: true }> {
    const shown = await this.deps.prisma.listing.findFirst({
      where: {
        id: listingId,
        ...PUBLICLY_VISIBLE_LISTING,
        providerProfile: this.visibility.visibleWhere(),
      },
      select: { id: true },
    });
    if (shown === null) throw new NotFoundError('No such listing');

    const now = this.deps.clock();
    // `ON CONFLICT DO NOTHING`: two taps racing both land, neither 500s. A
    // live row keeps its place; a stamped one is revived below and moves to
    // the top.
    await this.deps.prisma.favoriteListing.createMany({
      data: [{ userId, listingId, savedAt: now }],
      skipDuplicates: true,
    });
    await this.deps.prisma.favoriteListing.updateMany({
      where: { userId, listingId, deletedAt: { not: null } },
      data: { deletedAt: null, savedAt: now },
    });
    return { saved: true };
  }

  /** `DELETE /v1/users/me/favorites/listings/:listingId`. A stamp, never a delete (invariant 8). */
  async unsaveListing(userId: string, listingId: string): Promise<{ saved: false }> {
    await this.deps.prisma.favoriteListing.updateMany({
      where: { userId, listingId, deletedAt: null },
      data: { deletedAt: this.deps.clock() },
    });
    return { saved: false };
  }

  /** `PUT /v1/users/me/favorites/providers/:providerId`. Not found unless §1a shows the provider. */
  async saveProvider(userId: string, providerId: string): Promise<{ saved: true }> {
    if (!(await this.visibility.isVisible(providerId))) {
      throw new NotFoundError('No such provider');
    }

    const now = this.deps.clock();
    await this.deps.prisma.favoriteProvider.createMany({
      data: [{ userId, providerProfileId: providerId, savedAt: now }],
      skipDuplicates: true,
    });
    await this.deps.prisma.favoriteProvider.updateMany({
      where: { userId, providerProfileId: providerId, deletedAt: { not: null } },
      data: { deletedAt: null, savedAt: now },
    });
    return { saved: true };
  }

  /** `DELETE /v1/users/me/favorites/providers/:providerId`. */
  async unsaveProvider(userId: string, providerId: string): Promise<{ saved: false }> {
    await this.deps.prisma.favoriteProvider.updateMany({
      where: { userId, providerProfileId: providerId, deletedAt: null },
      data: { deletedAt: this.deps.clock() },
    });
    return { saved: false };
  }

  /**
   * `GET /v1/users/me/favorites/status` — which of these ids the caller has
   * saved. Every heart on a screen asks once, in one call, rather than every
   * public read growing a viewer-dependent field: §Phase 13's profile is
   * deliberately the same for every viewer, and stays so.
   */
  async status(
    userId: string,
    ids: { listingIds: string[]; providerIds: string[] },
  ): Promise<FavoriteStatusDto> {
    const [listings, providers] = await Promise.all([
      ids.listingIds.length === 0
        ? []
        : this.deps.prisma.favoriteListing.findMany({
            where: { userId, deletedAt: null, listingId: { in: ids.listingIds } },
            select: { listingId: true },
          }),
      ids.providerIds.length === 0
        ? []
        : this.deps.prisma.favoriteProvider.findMany({
            where: { userId, deletedAt: null, providerProfileId: { in: ids.providerIds } },
            select: { providerProfileId: true },
          }),
    ]);
    return {
      listingIds: listings.map((row) => row.listingId),
      providerIds: providers.map((row) => row.providerProfileId),
    };
  }

  /** `GET /v1/users/me/favorites/listings` — newest saved first, paged. */
  async listListings(
    userId: string,
    paging: { limit: number; cursor: string | null },
  ): Promise<{ items: FavoriteListingDto[]; nextCursor: string | null }> {
    const after = decodeCursor(paging.cursor);
    const rows = await this.deps.prisma.favoriteListing.findMany({
      where: { AND: [shownListings(this.visibility, userId), afterCursor(after)] },
      orderBy: [{ savedAt: 'desc' }, { id: 'desc' }],
      take: paging.limit + 1,
    });
    const page = rows.slice(0, paging.limit);

    const cards = await this.deps.publicListings.cardsByIds(page.map((row) => row.listingId));
    const items = page.flatMap((row) => {
      const card = cards.get(row.listingId);
      // Absent only if it stopped being public between the two reads.
      return card === undefined ? [] : [{ savedAt: row.savedAt.toISOString(), ...card }];
    });
    return { items, nextCursor: nextCursorOf(rows, paging.limit) };
  }

  /** `GET /v1/users/me/favorites/providers` — newest saved first, paged. */
  async listProviders(
    userId: string,
    paging: { limit: number; cursor: string | null },
  ): Promise<{ items: FavoriteProviderDto[]; nextCursor: string | null }> {
    const after = decodeCursor(paging.cursor);
    const rows = await this.deps.prisma.favoriteProvider.findMany({
      where: { AND: [shownProviders(this.visibility, userId), afterCursor(after)] },
      orderBy: [{ savedAt: 'desc' }, { id: 'desc' }],
      take: paging.limit + 1,
    });
    const page = rows.slice(0, paging.limit);

    const items = await Promise.all(
      page.map(async (row): Promise<FavoriteProviderDto | null> => {
        try {
          const [provider, summary, categories] = await Promise.all([
            this.deps.providers.readPublic(row.providerProfileId),
            this.deps.reviews.providerSummary(row.providerProfileId),
            this.categoriesOf(row.providerProfileId),
          ]);
          return {
            savedAt: row.savedAt.toISOString(),
            provider,
            rating: { reviewCount: summary.reviewCount, averageRating: summary.averageRating },
            categories,
          };
        } catch (error) {
          // Stopped being public between the two reads.
          if (error instanceof NotFoundError) return null;
          throw error;
        }
      }),
    );
    return {
      items: items.filter((item): item is FavoriteProviderDto => item !== null),
      nextCursor: nextCursorOf(rows, paging.limit),
    };
  }

  /** The categories a provider's published services are in — the row's subtitle. */
  private async categoriesOf(providerProfileId: string) {
    const rows = await this.deps.prisma.category.findMany({
      where: { listings: { some: { providerProfileId, ...PUBLICLY_VISIBLE_LISTING } } },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    });
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      iconIdentifier: row.iconIdentifier,
      colorToken: row.colorToken,
    }));
  }
}

function afterCursor(after: { savedAt: Date; id: string } | null) {
  return after === null
    ? {}
    : {
        OR: [{ savedAt: { lt: after.savedAt } }, { savedAt: after.savedAt, id: { lt: after.id } }],
      };
}

function nextCursorOf(rows: { savedAt: Date; id: string }[], limit: number): string | null {
  const last = rows[limit - 1];
  return rows.length > limit && last !== undefined
    ? Buffer.from(`${last.savedAt.toISOString()}|${last.id}`).toString('base64url')
    : null;
}

/**
 * A malformed cursor reads as "from the start" rather than a 500: the id goes
 * into a `uuid` comparison, which Postgres would refuse.
 */
function decodeCursor(cursor: string | null): { savedAt: Date; id: string } | null {
  if (cursor === null) return null;
  const [at, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  if (at === undefined || id === undefined || !UUID.test(id)) return null;
  const savedAt = new Date(at);
  return Number.isNaN(savedAt.getTime()) ? null : { savedAt, id };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The caller's own favourites leave with their data export — every live one,
 * including those not public right now, because the export is what the
 * platform holds about them, not what the Saved screen shows.
 */
export function favoritesExportContributor(prisma: PrismaClient): ExportContributor {
  return {
    key: 'favorites',
    collect: async (userId: string) => {
      const [listings, providers] = await Promise.all([
        prisma.favoriteListing.findMany({
          where: { userId, deletedAt: null },
          orderBy: { savedAt: 'desc' },
          select: { listingId: true, savedAt: true },
        }),
        prisma.favoriteProvider.findMany({
          where: { userId, deletedAt: null },
          orderBy: { savedAt: 'desc' },
          select: { providerProfileId: true, savedAt: true },
        }),
      ]);
      return {
        listings: listings.map((row) => ({
          listingId: row.listingId,
          savedAt: row.savedAt.toISOString(),
        })),
        providers: providers.map((row) => ({
          providerId: row.providerProfileId,
          savedAt: row.savedAt.toISOString(),
        })),
      };
    },
  };
}

/**
 * §Phase 3's anonymisation. Who a person saved is theirs; on deletion every
 * live favourite is stamped — never removed (invariant 8).
 */
export function registerFavoritesAnonymisation(hooks: AnonymisationHooks): void {
  hooks.register('favorites', async (tx, userId, now) => {
    await tx.favoriteListing.updateMany({
      where: { userId, deletedAt: null },
      data: { deletedAt: now },
    });
    await tx.favoriteProvider.updateMany({
      where: { userId, deletedAt: null },
      data: { deletedAt: now },
    });
  });
}
