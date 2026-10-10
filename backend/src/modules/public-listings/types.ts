import type {
  BookingMode,
  Category,
  Listing,
  ListingMedia,
  PriceUnit,
  PricingModel,
} from '../../generated/prisma/client.js';
import type { IslandDto } from '../location/types.js';
import type { ListingFaqDto, SelfDeclaredCoverDto } from '../listings/types.js';
import type { PublicProviderDto } from '../providers/types.js';
import type { RatingSummaryDto } from '../reviews/types.js';
import { readFaqs } from '../listings/types.js';

/**
 * What a customer sees on the Service Preview (§Phase 12).
 *
 * **This file is the structural gate**, the public twin of `OwnListingDto`'s.
 * §Phase 12 is unambiguous — "neither response ever contains contact or
 * payment details. Not 'for now', not behind a flag" — and the only way to
 * make that true under every circumstance is for no field here to be able to
 * hold one:
 *
 *   - **No phone number, at any depth.** The provider arrives as
 *     `PublicProviderDto`, which has none, and nothing here reads a `User`
 *     row. §1c allows exactly one endpoint in the system to return a number
 *     to another user, and it is `POST /v1/bookings/:id/reveal-contact`.
 *   - **No payment detail.** A listing carries a *price*. Where a customer's
 *     money goes is `paymentDetailsForBooking`'s, at a booking's payment step.
 *   - **No editorial label.** Conduct travels as numbers inside
 *     `PublicProviderDto.conduct` (§1f).
 *
 * It also has no draft state, no `missingRequiredFields` and no upload
 * statuses — those are the owner's, and the reason `/v1/listings/:id` was kept
 * from inheriting `OwnListingDto` (decision 21).
 */

export interface PublicMediaDto {
  id: string;
  /** A short-lived signed URL, re-issued on every read. */
  url: string;
}

export interface PublicCategoryDto {
  id: string;
  name: string;
  iconIdentifier: string;
  colorToken: string;
}

export interface PublicPricingDto {
  model: PricingModel;
  priceLaari: number | null;
  priceMinLaari: number | null;
  priceMaxLaari: number | null;
  unit: PriceUnit | null;
}

/**
 * Emergency alongside the normal path (§Phase 12, §1c). It is presented as a
 * second door, never as a marker on the listing: dispatch broadcasts to every
 * eligible provider and never targets this one (Round 23).
 */
export interface PublicEmergencyDto {
  /** `listing.isEmergency` AND the provider still meeting the category's bar right now. */
  available: boolean;
  /** MVR 200 in laari, charged to the customer when they pick an offer — stated up front. Null where unavailable. */
  dispatchFeeLaari: number | null;
  /** The category the ASAP request is raised against; the request is by category and island, never by listing. */
  categoryId: string | null;
}

/**
 * The mode-appropriate second signal (§1c, Round 23): next open time for a
 * `slot` listing, median response time for a `request` one. Never both.
 *
 * The response time is the provider's, and §1f hides it below ten completed
 * bookings in the window — so it is read from `provider.conduct`, which is
 * where that floor is already applied, rather than from a second source that
 * could forget to apply it.
 */
export type PublicSecondSignalDto =
  | { kind: 'next_open'; nextOpenAt: string | null }
  | { kind: 'response_time'; medianResponseSeconds: number | null };

export interface PublicListingDto {
  id: string;
  name: string;
  shortDescription: string | null;
  longDescription: string | null;
  tags: string[];
  category: PublicCategoryDto;
  cover: PublicMediaDto | null;
  gallery: PublicMediaDto[];
  pricing: PublicPricingDto;
  /** `slot` → pick a published time; `request` → propose a window and receive a quote. */
  bookingMode: BookingMode;
  secondSignal: PublicSecondSignalDto;
  serviceAreas: IslandDto[];
  whatsIncluded: string | null;
  whatsNotIncluded: string | null;
  faqs: ListingFaqDto[];
  /** The provider's own words; the client attributes them ("Provider states: …"). Nothing here is verified. */
  selfDeclared: SelfDeclaredCoverDto;
  /** Offered on the listing AND the category is `callbackEligible` (Round 28). */
  callbackGuarantee: boolean;
  emergency: PublicEmergencyDto;
  rating: RatingSummaryDto;
  provider: PublicProviderDto;
  /** True only when the signed-in caller owns this listing — the Edit control's one source. */
  viewerIsOwner: boolean;
}

/** `GET /v1/providers/:id/public-summary` — what the Provider section prints. */
export interface PublicProviderSummaryDto {
  provider: PublicProviderDto;
  rating: Pick<RatingSummaryDto, 'reviewCount' | 'averageRating'>;
}

export interface PublicListingInput {
  listing: Listing;
  category: Category;
  cover: ListingMedia | null;
  gallery: ListingMedia[];
  serviceAreas: IslandDto[];
  emergencyAvailable: boolean;
  dispatchFeeLaari: number;
  secondSignal: PublicSecondSignalDto;
  rating: RatingSummaryDto;
  provider: PublicProviderDto;
  viewerIsOwner: boolean;
  mediaUrl: (objectKey: string) => string;
}

export function toPublicListingDto(input: PublicListingInput): PublicListingDto {
  const { listing, category } = input;
  return {
    id: listing.id,
    // Publish requires a name, a category, a pricing model and a booking mode;
    // the service refuses to build this for a row that lacks one.
    name: listing.name ?? '',
    shortDescription: listing.shortDescription,
    longDescription: listing.longDescription,
    tags: listing.tags,
    category: {
      id: category.id,
      name: category.name,
      iconIdentifier: category.iconIdentifier,
      colorToken: category.colorToken,
    },
    cover: input.cover === null ? null : toPublicMedia(input.cover, input.mediaUrl),
    gallery: input.gallery.flatMap((row) => {
      const media = toPublicMedia(row, input.mediaUrl);
      return media === null ? [] : [media];
    }),
    pricing: {
      model: listing.pricingModel ?? 'quote',
      priceLaari: listing.priceLaari,
      priceMinLaari: listing.priceMinLaari,
      priceMaxLaari: listing.priceMaxLaari,
      unit: listing.priceUnit,
    },
    bookingMode: listing.bookingMode ?? 'request',
    secondSignal: input.secondSignal,
    serviceAreas: input.serviceAreas,
    whatsIncluded: listing.whatsIncluded,
    whatsNotIncluded: listing.whatsNotIncluded,
    faqs: readFaqs(listing.faqs),
    selfDeclared: {
      warrantyOffered: listing.warrantyOffered,
      warrantyTermsText: listing.warrantyOffered ? listing.warrantyTermsText : null,
      insuranceDeclared: listing.insuranceDeclared,
      insuranceDetailText: listing.insuranceDeclared ? listing.insuranceDetailText : null,
    },
    callbackGuarantee: listing.callbackGuaranteeOffered && category.callbackEligible,
    emergency: {
      available: input.emergencyAvailable,
      dispatchFeeLaari: input.emergencyAvailable ? input.dispatchFeeLaari : null,
      categoryId: input.emergencyAvailable ? category.id : null,
    },
    rating: input.rating,
    provider: input.provider,
    viewerIsOwner: input.viewerIsOwner,
  };
}

function toPublicMedia(
  row: ListingMedia,
  mediaUrl: (objectKey: string) => string,
): PublicMediaDto | null {
  // A pending, removed or moderated image has nothing a customer should see.
  if (row.status !== 'stored' || row.removedAt !== null || row.hiddenByAdminAt !== null) {
    return null;
  }
  return { id: row.id, url: mediaUrl(row.objectKey) };
}
