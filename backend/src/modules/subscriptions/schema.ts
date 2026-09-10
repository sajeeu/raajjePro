import { z } from 'zod';

/**
 * Request validation for §Phase 8a's surfaces.
 *
 * ## Note what nobody can send
 *
 * Absent keys are the enforcement — an unknown key is stripped, so no handler
 * has to remember to ignore one. Four things in particular have **no body
 * field anywhere in this module**:
 *
 *   - **An amount.** A provider does not choose what they pay; the amount is
 *     read from their own `subscriptionPriceLaari` or §1b's cohort rule when
 *     the intent is created (`pricing.ts`). A client-supplied amount is how a
 *     provider pays MVR 1 for a month.
 *   - **A reference code.** Generated server-side and unique, because it is
 *     what an admin matches a bank statement row against.
 *   - **A tier, a status or a period end.** Those follow from a confirmed
 *     payment, and there is no endpoint that writes them directly.
 *   - **An object key.** §Phase 8's media rule: the server chooses it, or one
 *     payer can overwrite another's proof.
 */

/**
 * The proof photo. Shaped exactly like §Phase 8's `createListingMediaBody`,
 * and for the same reason: the declared type is a client assertion checked
 * against the allowlist by `MediaService` — which answers
 * `MEDIA_TYPE_NOT_ACCEPTED` naming the three types — and checked again
 * against the real bytes at `finalise`, which is the check that counts.
 * Enumerating the types here as well would give the same rejection two
 * different error codes depending on which layer noticed.
 */
export const paymentProofBody = z.object({
  contentType: z.string().min(1).max(100),
});

export const paymentSubmissionParams = z.object({ id: z.uuid() });

export const invoiceListQuery = z.object({
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

export const adminSubmissionListQuery = z.object({
  /**
   * Defaults to `pending`, which is the queue §Phase 10a opens on. The other
   * two are reachable because an admin looking for what they decided
   * yesterday should not have to query the database.
   */
  status: z.enum(['pending', 'confirmed', 'rejected']).default('pending'),
  purpose: z.enum(['subscription', 'emergency_dispatch_fee']).optional(),
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

/**
 * §1b step 4: "rejects (**reason required**)". Required in the Zod schema
 * rather than checked in the handler, so a client cannot reach the service
 * without one — and the same text is what the provider is shown (step 5:
 * "the provider sees the reason"), which is why there is a floor on its
 * length. "no" is not a reason somebody can act on.
 */
export const rejectSubmissionBody = z.object({
  reason: z.string().trim().min(10).max(500),
});

/**
 * §1b's reversal: "mistake, bank reversal. Explicit endpoint with an
 * audit-log entry, never a database edit." The reason is required for the
 * same reason the rejection's is, plus one more — this one reverses money
 * that was already granted, and the audit entry is the only record of why.
 */
export const reverseSubmissionBody = z.object({
  reason: z.string().trim().min(10).max(500),
});

/**
 * Confirmation takes an optional note and nothing else.
 *
 * Optional rather than required, deliberately: the reason for a confirmation
 * is *the bank statement*, and requiring an admin to type a sentence 200
 * times a month produces two hundred sentences reading "ok". The audit entry
 * carries a fixed reason when no note is given, and the note is there for the
 * confirmation that needs explaining.
 */
export const confirmSubmissionBody = z
  .object({ note: z.string().trim().min(1).max(500).optional() })
  .optional();

export type PaymentProofBody = z.infer<typeof paymentProofBody>;
export type AdminSubmissionListQuery = z.infer<typeof adminSubmissionListQuery>;
export type InvoiceListQuery = z.infer<typeof invoiceListQuery>;
