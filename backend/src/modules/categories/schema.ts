import { z } from 'zod';

/**
 * Request validation for the category admin surface.
 *
 * Note what is **not** here: any check of `name` against a known list. The
 * catalogue is unlimited (§Phase 4) and the Done-when requires a thirteenth
 * category added through this endpoint to appear in Explore with no rebuild,
 * so nothing may enumerate it. `bookingMode` is a closed set because it is
 * the booking machine's shape, not the catalogue's.
 *
 * The cross-field coherence rules (`emergencyCapable` implying a tier bar and
 * an answer window, the two quote windows moving together) are enforced in
 * the service, not here: a PATCH is partial, so those rules can only be
 * checked against the row that would result, and invariant 4 puts the rule in
 * one server-side place either way.
 */

/** A client-resolved token: a glyph name or a design-system accent. Never a hex value or an asset path. */
const token = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .regex(/^[A-Za-z][A-Za-z0-9_-]*$/, 'Use a token name, not a value');

const minutes = z.int().min(1).max(43_200); // up to 30 days

export const categoryIdParams = z.object({ id: z.uuid() });

/** Cursor paging on the public list. Both optional; the default page holds the seeded twelve many times over. */
export const listCategoriesQuery = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  cursor: z.string().min(1).max(200).optional(),
});

/** Every admin write records a reason — `AuditService.record` rejects an empty one. */
const reason = z.string().trim().min(1).max(500);

const categoryFields = {
  name: z.string().trim().min(1).max(60),
  description: z.string().trim().min(1).max(280),
  iconIdentifier: token,
  colorToken: token,
  sortOrder: z.int().min(0).max(10_000),
  bookingMode: z.enum(['slot', 'request']),
  emergencyCapable: z.boolean(),
  minimumLeadTimeMinutes: z.int().min(0).max(43_200),
  emergencyAcceptWindowMinutes: minutes.nullable(),
  emergencyMinimumTier: z.enum(['none', 'bronze', 'silver', 'gold']).nullable(),
  emergencyEtaPresetsMinutes: z.array(minutes).max(8),
  quoteExpiryMinutes: minutes.nullable(),
  quoteApprovalMinutes: minutes.nullable(),
  callbackEligible: z.boolean(),
  occasionPresets: z.array(z.string().trim().min(1).max(40)).max(20),
};

export const createCategoryBody = z.object({
  ...categoryFields,
  // Defaults keep a create honest without making the caller state every
  // number: a new category is non-emergency, non-callback and quotes nowhere
  // until someone says otherwise.
  emergencyCapable: categoryFields.emergencyCapable.default(false),
  emergencyAcceptWindowMinutes: categoryFields.emergencyAcceptWindowMinutes.default(null),
  emergencyMinimumTier: categoryFields.emergencyMinimumTier.default(null),
  emergencyEtaPresetsMinutes: categoryFields.emergencyEtaPresetsMinutes.default([]),
  quoteExpiryMinutes: categoryFields.quoteExpiryMinutes.default(null),
  quoteApprovalMinutes: categoryFields.quoteApprovalMinutes.default(null),
  callbackEligible: categoryFields.callbackEligible.default(false),
  occasionPresets: categoryFields.occasionPresets.default([]),
  isActive: z.boolean().default(true),
  reason,
});

export const updateCategoryBody = z
  .object({ ...categoryFields, isActive: z.boolean() })
  .partial()
  .extend({ reason })
  .refine((body) => Object.keys(body).some((k) => k !== 'reason'), {
    message: 'Change at least one field',
  });

export const deleteCategoryBody = z.object({ reason });

export type CreateCategoryBody = z.infer<typeof createCategoryBody>;
export type UpdateCategoryBody = z.infer<typeof updateCategoryBody>;
