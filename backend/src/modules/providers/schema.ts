import { z } from 'zod';

/**
 * Request validation for the provider profile surface.
 *
 * Note what a provider **cannot** send. Four stored columns are absent from
 * `updateOwnProviderBody` on purpose, and their absence is the enforcement —
 * an unknown key is stripped, so no handler has to remember to ignore one:
 *
 *   - `verificationTier` / `verificationStatus` — admin-transitioned (§1e),
 *     except the auto-granted 5-clean-bookings route to Silver. Self-serve
 *     verification is the whole thing the tier exists to prevent.
 *   - `maldivianOwned` — §1g: **verified rather than self-declared**,
 *     evidenced by the registration document Gold review collects. A
 *     self-declared local-ownership flag is a marketing field, not a trust
 *     signal.
 *   - `subscriptionPriceLaari` — §1b: written once at the provider's first
 *     confirmed payment, by Phase 8a. A provider setting their own price is
 *     not a feature.
 *   - `suspendedAt` / `suspendedReason` — Phase 10b's admin action, and
 *     un-suspending yourself would defeat it.
 *
 * There is no phone field here either. The account phone is Phase 3's, edited
 * through `PATCH /v1/users/me/phone` with its own re-verification path;
 * §Phase 5 keeps exactly one copy of it and this module is not where it lives.
 */

/**
 * §Phase 6a caps the introduction at 160 characters. Enforced here because
 * §Phase 6a reuses this endpoint ("reuse Phase 5's existing update endpoint,
 * do not create a parallel one") and invariant 4 puts the rule server-side.
 * The database column matches at `VARCHAR(160)`.
 */
const bio = z.string().trim().max(160);

/** Nullable throughout: clearing a field is a real edit, and a draft profile may hold none of them. */
export const updateOwnProviderBody = z
  .object({
    businessName: z.string().trim().min(1).max(120).nullable(),
    bio: bio.nullable(),
    /** A working life, not an age. Zero is meaningful — "just starting out". */
    yearsOfExperience: z.int().min(0).max(80).nullable(),

    // Payment details (§Phase 5). Required at onboarding by §Phase 6a, never
    // here: a profile exists from first publish onward and may legitimately
    // carry none of them yet.
    bankName: z.string().trim().min(1).max(120).nullable(),
    bankAccountName: z.string().trim().min(1).max(160).nullable(),
    /**
     * Digits, spaces and dashes. Not pattern-matched to a Maldivian format:
     * providers hold foreign accounts, the same reason §Phase 6a refuses to
     * restrict phone numbers to the 7-digit local pattern (Round 17).
     */
    bankAccountNumber: z
      .string()
      .trim()
      .min(4)
      .max(40)
      .regex(/^[0-9][0-9 -]*$/, 'Use digits, spaces and dashes only')
      .nullable(),
    transferInstructions: z.string().trim().min(1).max(500).nullable(),

    /** §Phase 5: account-level, gating every listing at once. */
    acceptingNewCustomers: z.boolean(),
  })
  .partial()
  .refine((body) => Object.keys(body).length > 0, { message: 'Change at least one field' });

export type UpdateOwnProviderBody = z.infer<typeof updateOwnProviderBody>;
