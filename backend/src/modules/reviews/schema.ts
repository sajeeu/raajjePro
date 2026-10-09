import { z } from 'zod';

const uuid = z.uuid();

export const bookingParams = z.object({ id: uuid });
export const listingParams = z.object({ id: uuid });
export const providerParams = z.object({ id: uuid });
export const categoryParams = z.object({ id: uuid });
export const reviewParams = z.object({ id: uuid });

/**
 * `Rate This Job.dc.html`. §1f: "Rating a booking must be **two taps
 * minimum**: stars, then optional tags." The rating is the only required
 * field; tags and the written review default to nothing, so a body of
 * `{ "rating": 5 }` is a complete review.
 *
 * Tags arrive as ids from the category's fixed set, never as text (§1f:
 * "never free text"). Membership of the set is the service's check, because
 * it depends on the booking's category.
 */
export const postReviewBody = z.object({
  rating: z.number().int().min(1).max(5),
  tagIds: z.array(uuid).max(8).default([]),
  body: z
    .string()
    .trim()
    .max(2000)
    .optional()
    .transform((v) => (v === undefined || v.length === 0 ? null : v)),
});

export const reviewListQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  cursor: z.string().max(200).optional(),
});

/** Invariant 1d: every moderation action records why. */
export const moderateReviewBody = z.object({ reason: z.string().trim().min(1).max(500) });

export type PostReviewBody = z.infer<typeof postReviewBody>;
