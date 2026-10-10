import { z } from 'zod';

export const listingParams = z.object({ listingId: z.uuid() });
export const providerParams = z.object({ providerId: z.uuid() });

export const listFavoritesQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  cursor: z.string().max(200).optional(),
});

/**
 * Comma-separated ids, at most one screen's worth. Bounded so the lookup can
 * never become an unpaged read of everything a customer saved.
 */
const idList = z
  .string()
  .optional()
  .transform((raw) => (raw === undefined || raw === '' ? [] : raw.split(',')))
  .pipe(z.array(z.uuid()).max(100));

export const favoriteStatusQuery = z.object({
  listingIds: idList,
  providerIds: idList,
});
