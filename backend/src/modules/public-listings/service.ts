import type { FastifyBaseLogger } from 'fastify';

import type { Clock } from '../../core/clock.js';
import { NotFoundError } from '../../core/errors.js';
import type { Category, Listing, PrismaClient } from '../../generated/prisma/client.js';
import type { AvailabilityService } from '../availability/service.js';
import { EMERGENCY_DISPATCH_FEE_LAARI } from '../bookings/windows.js';
import { emergencyEligibility } from '../listings/emergency.js';
import type { ListingEvents } from '../listings/events.js';
import { ListingRepository } from '../listings/repository.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import { toIslandDto } from '../location/types.js';
import type { MediaService } from '../media/service.js';
import type { ProviderProfileService } from '../providers/service.js';
import type { PublicProviderDto } from '../providers/types.js';
import type { ReviewService } from '../reviews/service.js';
import {
  toPublicListingCardDto,
  toPublicListingDto,
  type PublicListingCardDto,
  type PublicListingDto,
  type PublicProviderProfileDto,
  type PublicProviderSummaryDto,
  type PublicSecondSignalDto,
} from './types.js';

export interface PublicListingServiceDeps {
  prisma: PrismaClient;
  clock: Clock;
  providers: ProviderProfileService;
  reviews: ReviewService;
  availability: AvailabilityService;
  media: MediaService;
  events: ListingEvents;
  log: FastifyBaseLogger;
}

/**
 * §Phase 12 — the public listing page and the provider summary beside it.
 *
 * Both reads are **open to a guest** (§8: guests browse freely), and both
 * answer a not-found for anything §1a and `PUBLICLY_VISIBLE_LISTING` do not
 * show. A draft, a hidden listing, a deleted one and a suspended provider's
 * are all the same 404 — the endpoint never confirms that a hidden thing
 * exists.
 */
export class PublicListingService {
  private readonly deps: PublicListingServiceDeps;
  private readonly listings: ListingRepository;

  constructor(deps: PublicListingServiceDeps) {
    this.deps = deps;
    this.listings = new ListingRepository(deps.prisma);
  }

  /**
   * `GET /v1/listings/:id/public`.
   *
   * Who may call: anyone. `viewerUserId` is the caller when a valid session
   * rode the request, and is used for exactly two things — `viewerIsOwner`
   * (the Edit control) and not counting an owner looking at their own page as
   * a view. A guest, or a stale token, simply reads as not-the-owner.
   */
  async readPublic(listingId: string, viewerUserId: string | null): Promise<PublicListingDto> {
    const listing = await this.deps.prisma.listing.findFirst({
      where: { id: listingId, ...PUBLICLY_VISIBLE_LISTING },
      include: { category: true, providerProfile: { select: { userId: true } } },
    });
    if (listing?.category == null) throw notFound();

    // §1a's one shared helper. `readPublic` re-checks visibility itself, which
    // is what turns a suspended provider into the same 404 a hidden listing gets.
    const provider = await this.deps.providers.readPublic(listing.providerProfileId);
    const category = listing.category;

    const [areas, cover, gallery, rating] = await Promise.all([
      this.listings.findServiceAreas(listing.id),
      this.listings.findCover(listing.coverMediaId),
      this.listings.findGallery(listing.id),
      this.deps.reviews.listingSummary(listing.id),
    ]);

    const viewerIsOwner = viewerUserId !== null && listing.providerProfile.userId === viewerUserId;

    const secondSignal = await this.secondSignal(listing, provider);

    // Re-derived from the provider's tier as of now rather than trusting the
    // stored flag alone: the tier-drop sweep clears `isEmergency`, but this
    // page must not advertise an emergency door for the gap before it runs.
    const emergencyAvailable =
      listing.isEmergency &&
      emergencyEligibility({ category, providerTier: provider.verificationTier }).eligible;

    if (!viewerIsOwner) await this.recordView(listing.id);

    return toPublicListingDto({
      listing,
      category,
      cover,
      gallery: gallery.filter((row) => row.id !== listing.coverMediaId),
      serviceAreas: areas.map((row) => toIslandDto(row.island)),
      emergencyAvailable,
      dispatchFeeLaari: EMERGENCY_DISPATCH_FEE_LAARI,
      secondSignal,
      rating,
      provider,
      viewerIsOwner,
      mediaUrl: (objectKey) => this.deps.media.readUrl(objectKey),
    });
  }

  /** `GET /v1/providers/:id/public-summary` — who may call: anyone, for a provider §1a shows. */
  async readProviderSummary(providerProfileId: string): Promise<PublicProviderSummaryDto> {
    const provider = await this.deps.providers.readPublic(providerProfileId);
    const { reviewCount, averageRating } =
      await this.deps.reviews.providerSummary(providerProfileId);
    return { provider, rating: { reviewCount, averageRating } };
  }

  /**
   * `GET /v1/providers/:id/public` — §Phase 13's public profile.
   *
   * Who may call: anyone, including a guest. **Not found unless §1a shows the
   * provider**, by the same `readPublic` → `findVisibleProviders` gate the
   * listing page uses — so a drafts-only provider is a 404 even by direct id,
   * and so is a suspended one, with the same body as an id that never existed.
   *
   * The response is the same viewer-independent shape for everyone: nothing
   * here reads who is asking, so there is no viewer for whom it could carry
   * more.
   */
  async readProviderProfile(providerProfileId: string): Promise<PublicProviderProfileDto> {
    const provider = await this.deps.providers.readPublic(providerProfileId);

    // Unpaged on purpose: what a provider can hold published is bounded by
    // §1b's entitlement cap, and the profile's job is to show all of it.
    const rows = await this.deps.prisma.listing.findMany({
      where: { providerProfileId, ...PUBLICLY_VISIBLE_LISTING },
      include: { category: true },
      orderBy: [{ publishedAt: 'desc' }, { id: 'asc' }],
    });
    const published = rows.flatMap((row) =>
      row.category === null ? [] : [{ listing: row, category: row.category, provider }],
    );

    const [summary, cards] = await Promise.all([
      this.deps.reviews.providerSummary(providerProfileId),
      this.toCards(published),
    ]);

    return {
      provider,
      rating: { reviewCount: summary.reviewCount, averageRating: summary.averageRating },
      tags: summary.tags,
      listings: cards,
    };
  }

  /**
   * 🔧 §Phase 14. The cards for a set of listings, each beside its provider —
   * what the Saved screen prints, since its services belong to many providers.
   *
   * **Only what is public right now comes back.** The listing must match
   * `PUBLICLY_VISIBLE_LISTING` and its provider must pass the same
   * `readPublic` → `findVisibleProviders` gate every public read uses; an id
   * that fails either is simply absent from the map, never an error, because
   * a saved thing going quiet is not the saver's fault. Same no-contact,
   * no-payment shapes as the profile's cards.
   */
  async cardsByIds(
    listingIds: string[],
  ): Promise<Map<string, { listing: PublicListingCardDto; provider: PublicProviderDto }>> {
    const rows = await this.deps.prisma.listing.findMany({
      where: { id: { in: listingIds }, ...PUBLICLY_VISIBLE_LISTING },
      include: { category: true },
    });

    const providers = new Map<string, PublicProviderDto>();
    for (const providerId of new Set(rows.map((row) => row.providerProfileId))) {
      try {
        providers.set(providerId, await this.deps.providers.readPublic(providerId));
      } catch (error) {
        if (!(error instanceof NotFoundError)) throw error;
      }
    }

    const published = rows.flatMap((row) => {
      const provider = providers.get(row.providerProfileId);
      return row.category === null || provider === undefined
        ? []
        : [{ listing: row, category: row.category, provider }];
    });
    const cards = await this.toCards(published);

    const byId = new Map<string, { listing: PublicListingCardDto; provider: PublicProviderDto }>();
    published.forEach(({ provider }, i) => {
      const card = cards[i];
      if (card !== undefined) byId.set(card.id, { listing: card, provider });
    });
    return byId;
  }

  /**
   * One definition of a card for the profile's grid and the Saved list, so the
   * two can never print the same listing differently.
   */
  private async toCards(
    published: { listing: Listing; category: Category; provider: PublicProviderDto }[],
  ): Promise<PublicListingCardDto[]> {
    const coverIds = published.flatMap(({ listing }) =>
      listing.coverMediaId === null ? [] : [listing.coverMediaId],
    );
    const [ratings, covers, extras] = await Promise.all([
      this.deps.reviews.listingRatings(published.map(({ listing }) => listing.id)),
      this.deps.prisma.listingMedia.findMany({ where: { id: { in: coverIds } } }),
      Promise.all(
        published.map(async ({ listing, provider }) => ({
          areas: await this.listings.findServiceAreas(listing.id),
          secondSignal: await this.secondSignal(listing, provider),
        })),
      ),
    ]);
    const coverById = new Map(covers.map((row) => [row.id, row]));

    return published.map(({ listing, category }, i) =>
      toPublicListingCardDto({
        listing,
        category,
        cover: listing.coverMediaId === null ? null : (coverById.get(listing.coverMediaId) ?? null),
        serviceAreas: (extras[i]?.areas ?? []).map((row) => toIslandDto(row.island)),
        secondSignal: extras[i]?.secondSignal ?? { kind: 'next_open', nextOpenAt: null },
        rating: ratings.get(listing.id) ?? { reviewCount: 0, averageRating: null },
        mediaUrl: (objectKey) => this.deps.media.readUrl(objectKey),
      }),
    );
  }

  /**
   * The mode-appropriate second signal (§1c, Round 23) — one definition for
   * the listing page and every card on the profile, so the two can never
   * disagree about the same listing.
   */
  private async secondSignal(
    listing: Pick<Listing, 'id' | 'bookingMode'>,
    provider: PublicProviderDto,
  ): Promise<PublicSecondSignalDto> {
    return listing.bookingMode === 'slot'
      ? { kind: 'next_open', nextOpenAt: await this.nextOpenAt(listing.id) }
      : {
          kind: 'response_time',
          // Already null below §1f's floor — see `PublicSecondSignalDto`.
          medianResponseSeconds: provider.conduct.metrics?.medianResponseSeconds ?? null,
        };
  }

  /**
   * The first time a customer could actually book. Read through the same
   * picker query a customer's own picker uses, so the page can never promise a
   * time the picker would then refuse (§1c).
   */
  private async nextOpenAt(listingId: string): Promise<string | null> {
    try {
      const open = await this.deps.availability.listOpenSlots(listingId, {});
      return open.slots[0]?.startsAt ?? null;
    } catch (error) {
      // A page that cannot work out its second signal is still a page.
      this.deps.log.warn({ err: error, listingId }, 'next open time unavailable');
      return null;
    }
  }

  /** An impression must never be the reason a page fails to load. */
  private async recordView(listingId: string): Promise<void> {
    try {
      await this.deps.events.record(listingId, 'view');
    } catch (error) {
      this.deps.log.warn({ err: error, listingId }, 'listing view not recorded');
    }
  }
}

function notFound(): NotFoundError {
  return new NotFoundError('No such listing');
}
