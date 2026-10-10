import type { PublicListingCardDto } from '../public-listings/types.js';
import type { PublicProviderDto } from '../providers/types.js';

/**
 * §Phase 15's shapes, **built only from the public ones**: the contact gate
 * that §Phases 12–14 hold also holds here. `PublicListingCardDto` and
 * `PublicProviderDto` have no field that could carry a phone number or a
 * payment detail, and nothing in this file adds one.
 */

/** One result card. */
export interface SearchResultDto {
  /** Carries `bookingMode`, so every card can state its booking mode (Done when). */
  listing: PublicListingCardDto;
  provider: PublicProviderDto;
  /**
   * True when priority placement moved this result up: "any paid influence
   * on ordering carries a visible 'Sponsored' label". It is the same fact
   * that ordered the result, so a result cannot be boosted without the label,
   * and it cannot carry the label without being boosted.
   */
  sponsored: boolean;
}

export interface SearchPageDto {
  /** How many results match, across every page — the screen's "18 services". */
  total: number;
  items: SearchResultDto[];
}
