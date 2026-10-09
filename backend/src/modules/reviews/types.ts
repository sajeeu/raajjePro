import type { ReviewTagSentiment } from '../../generated/prisma/enums.js';

/**
 * The shapes a review reaches a client in.
 *
 * ## What is structurally absent
 *
 * **No DTO here carries `authorId`** (§Phase 11: authorship is "never shown
 * publicly, never returned in any response"), and none carries a phone
 * number, an email or anything else from the author's user row except the
 * short display name below. The mappers select what they print; there is no
 * field an omission could leak through.
 *
 * **No DTO carries an editorial label** (§1f). A review is the customer's
 * stars, their tags and their own words, and nothing the platform says about
 * the provider.
 */

export interface ReviewTagDto {
  id: string;
  key: string;
  label: string;
  sentiment: ReviewTagSentiment;
}

export interface ReviewDto {
  id: string;
  bookingId: string;
  listingId: string;
  rating: number;
  body: string | null;
  tags: ReviewTagDto[];
  /**
   * "Aishath N." — first name and last initial, the form the Service Preview
   * prototype prints. **Null once the author's account is anonymised**; the
   * client renders its own placeholder, and nothing about who wrote it is
   * returned.
   */
  authorDisplayName: string | null;
  createdAt: string;
}

/** The two parties' view of one booking's review, which also says whether moderation hid it. */
export interface BookingReviewDto extends ReviewDto {
  hidden: boolean;
}

/**
 * §1f's tag count as the profile prints it — "On time (31)". Only tags that
 * three **different customers** have applied appear at all (decision 32), so
 * a count below that never reaches a client to be rendered by mistake.
 */
export interface TagCountDto {
  key: string;
  label: string;
  sentiment: ReviewTagSentiment;
  count: number;
}

export interface RatingSummaryDto {
  reviewCount: number;
  /** Mean of the visible ratings to two places, or null with no reviews — never 0. */
  averageRating: number | null;
  /** How many visible reviews gave each star value. */
  starBreakdown: { 1: number; 2: number; 3: number; 4: number; 5: number };
  tags: TagCountDto[];
}

/** §1f: "a tag is only shown once it has been applied three times" — by three different customers. */
export const TAG_DISPLAY_THRESHOLD = 3;
