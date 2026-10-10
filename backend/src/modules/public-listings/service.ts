import type { FastifyBaseLogger } from 'fastify';

import type { Clock } from '../../core/clock.js';
import { NotFoundError } from '../../core/errors.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { AvailabilityService } from '../availability/service.js';
import { EMERGENCY_DISPATCH_FEE_LAARI } from '../bookings/windows.js';
import { emergencyEligibility } from '../listings/emergency.js';
import type { ListingEvents } from '../listings/events.js';
import { ListingRepository } from '../listings/repository.js';
import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import { toIslandDto } from '../location/types.js';
import type { MediaService } from '../media/service.js';
import type { ProviderProfileService } from '../providers/service.js';
import type { ReviewService } from '../reviews/service.js';
import {
  toPublicListingDto,
  type PublicListingDto,
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

    const secondSignal: PublicSecondSignalDto =
      listing.bookingMode === 'slot'
        ? { kind: 'next_open', nextOpenAt: await this.nextOpenAt(listing.id) }
        : {
            kind: 'response_time',
            // Already null below §1f's floor — see `PublicSecondSignalDto`.
            medianResponseSeconds: provider.conduct.metrics?.medianResponseSeconds ?? null,
          };

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
