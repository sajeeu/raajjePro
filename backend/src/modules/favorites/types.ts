import type { PublicCategoryDto, PublicListingCardDto } from '../public-listings/types.js';
import type { PublicProviderDto } from '../providers/types.js';
import type { RatingSummaryDto } from '../reviews/types.js';

/**
 * §Phase 14's shapes.
 *
 * **Built only from the public shapes**, so the gate §Phases 12 and 13 hold
 * holds here too: `PublicListingCardDto` and `PublicProviderDto` have no field
 * that could carry a phone number or a payment detail, and nothing in this
 * file adds one. A saved provider is the on-platform substitute for taking
 * their number (Round 15) — the list of them must not become a way to get it.
 */

/** One saved service, as the Saved screen's card prints it. */
export interface FavoriteListingDto {
  savedAt: string;
  listing: PublicListingCardDto;
  /** The card names the provider and draws their badge; services here belong to many providers. */
  provider: PublicProviderDto;
}

/** One saved provider — `Discovery.dc.html`'s "Saved providers" row. */
export interface FavoriteProviderDto {
  savedAt: string;
  provider: PublicProviderDto;
  rating: Pick<RatingSummaryDto, 'reviewCount' | 'averageRating'>;
  /** What they offer, from their published services — distinct, in catalogue order. */
  categories: PublicCategoryDto[];
}

/** Which of the ids a screen asked about the caller has saved. */
export interface FavoriteStatusDto {
  listingIds: string[];
  providerIds: string[];
}

/**
 * How many saved things the Saved screen would show right now — the same
 * visibility rule as the lists, so Profile's count can never disagree with
 * the screen it opens.
 */
export interface FavoriteCountsDto {
  services: number;
  providers: number;
}
