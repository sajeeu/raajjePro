import { z } from 'zod';

export const evidenceQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  cursor: z.string().max(200).optional(),
});

export const bookingParams = z.object({ id: z.uuid() });

/** Invariant 1d: every moderation action records why. */
export const conductExclusionBody = z.object({ reason: z.string().trim().min(1).max(500) });
