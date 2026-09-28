import type { BillingBankDetails } from '../../config/env.js';
import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import type { PaymentSubmission, PrismaClient } from '../../generated/prisma/client.js';
import { generateReferenceCode } from '../subscriptions/pricing.js';
import type { SubscriptionService } from '../subscriptions/service.js';
import type { PaymentSubmissionDto } from '../subscriptions/types.js';
import type { UploadTarget } from '../media/types.js';
import type { Db } from './repository.js';
import { EMERGENCY_DISPATCH_FEE_LAARI } from './windows.js';

/**
 * §1c's MVR 200 emergency dispatch fee — the first and only money RaajjePro
 * takes from a customer.
 *
 * ## What it rides on, and what it deliberately does not
 *
 * §1c: "Settled afterwards through the existing `PaymentSubmission` flow
 * against a generated reference code, with admin confirmation. This is what
 * `PaymentSubmission`'s open `purpose` enum was left open for." So a fee is a
 * `PaymentSubmission` row with `purpose: emergency_dispatch_fee`, created
 * **owed** — `submittedAt` null — at the moment the customer selects an
 * offer, and the proof upload and submission are §Phase 8a's own two steps,
 * reached here rather than rewritten.
 *
 * It is **not** the booking's payment attestation. "I've Paid" / "Payment
 * Received" is two humans each saying what they did about the provider's
 * money; this is RaajjePro's own money, and an admin confirms it. The two
 * never touch.
 *
 * ## The block, and exactly when it lifts
 *
 * §1c: "An unsettled fee blocks **all** new bookings, not only emergency
 * ones", and "**the block lifts the moment the customer submits proof of
 * transfer, not when an admin confirms it**." So *unsettled* means one thing
 * here — an owed row with no proof submitted — and nothing about the admin's
 * later decision re-enters the rule.
 *
 * 🔧 **An admin rejecting a submitted proof does not re-impose the block.**
 * The plan says the admin "verifies afterwards and acts on anything false"
 * and calls a fabricated receipt "a moderation matter (§Phase 22), not a
 * reason to make everyone wait". It does not say a rejection blocks again,
 * and inventing that would make the block turn on the admin queue after all.
 * Recorded in `docs/decisions/30-phase-17-3-emergency.md`.
 */

/** The prisma predicate for "owed and not yet evidenced". One place, three readers. */
function outstandingWhere(customerId: string) {
  return {
    payerId: customerId,
    purpose: 'emergency_dispatch_fee' as const,
    status: 'pending' as const,
    submittedAt: null,
  };
}

export async function findOutstandingDispatchFee(
  db: Db,
  customerId: string,
): Promise<PaymentSubmission | null> {
  return db.paymentSubmission.findFirst({
    where: outstandingWhere(customerId),
    orderBy: { createdAt: 'asc' },
  });
}

export class DispatchFeeOutstandingError extends BusinessRuleError {
  constructor(fee: PaymentSubmission) {
    super(
      'DISPATCH_FEE_OUTSTANDING',
      'Settle the MVR 200 emergency dispatch fee to make a new booking',
      // What `Dispatch Fee.dc.html`'s "New bookings are on hold" state needs
      // to send the customer straight to settling it.
      { submissionId: fee.id, amountLaari: fee.amountLaari, referenceCode: fee.referenceCode },
    );
  }
}

/**
 * The gate every booking-creation path passes. Existing bookings are
 * untouched by it — §1c: "The account is not suspended and existing bookings
 * are unaffected — the customer simply cannot start anything new while owing."
 */
export async function assertNoOutstandingDispatchFee(db: Db, customerId: string): Promise<void> {
  const fee = await findOutstandingDispatchFee(db, customerId);
  if (fee !== null) throw new DispatchFeeOutstandingError(fee);
}

/**
 * Records the fee as owed, inside the selection's own transaction — so a
 * selection that fails leaves no fee behind, and a fee never exists without
 * the selection that incurred it.
 */
export function createOwedDispatchFee(db: Db, customerId: string) {
  return db.paymentSubmission.create({
    data: {
      payerId: customerId,
      purpose: 'emergency_dispatch_fee',
      amountLaari: EMERGENCY_DISPATCH_FEE_LAARI,
      referenceCode: generateReferenceCode(),
      status: 'pending',
      submittedAt: null,
    },
  });
}

/** One fee as the customer's `Dispatch Fee.dc.html` renders it. */
export interface DispatchFeeDto {
  id: string;
  /** The emergency it was incurred on — "For dispatching Ibrahim Rasheed to your Emergency plumbing call-out". */
  bookingId: string | null;
  amountLaari: number;
  referenceCode: string;
  /**
   * `owed` until proof is submitted, which is the only state that blocks.
   * The admin's later decision is reported as-is and does not block.
   */
  state: 'owed' | 'submitted' | 'confirmed' | 'rejected';
  submittedAt: string | null;
  rejectionReason: string | null;
  proofUploaded: boolean;
  createdAt: string;
}

export function dispatchFeeState(row: PaymentSubmission): DispatchFeeDto['state'] {
  if (row.status === 'confirmed') return 'confirmed';
  if (row.status === 'rejected') return 'rejected';
  return row.submittedAt === null ? 'owed' : 'submitted';
}

/**
 * The customer's side of settling a fee: list, upload the receipt, submit.
 *
 * The upload and the submit are **§Phase 8a's methods**, which authorize by
 * `payerId` and know nothing about purpose. What this adds is the one check
 * they cannot make — that the row really is a dispatch fee — so these routes
 * cannot become a second door onto a subscription payment.
 */
export class DispatchFeeService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      subscriptions: SubscriptionService;
      bankDetails: BillingBankDetails | null;
    },
  ) {}

  /** Who may call: the signed-in user, for their own fees. Newest first; a customer accumulates a handful at most. */
  async listOwn(
    userId: string,
  ): Promise<{ fees: DispatchFeeDto[]; bankTransfer: BillingBankDetails | null }> {
    const rows = await this.deps.prisma.paymentSubmission.findMany({
      where: { payerId: userId, purpose: 'emergency_dispatch_fee' },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { dispatchFeeFor: { select: { id: true } } },
    });
    return {
      fees: rows.map((row) => ({
        id: row.id,
        bookingId: row.dispatchFeeFor?.id ?? null,
        amountLaari: row.amountLaari,
        referenceCode: row.referenceCode,
        state: dispatchFeeState(row),
        submittedAt: row.submittedAt?.toISOString() ?? null,
        rejectionReason: row.rejectionReason,
        proofUploaded: row.proofByteSize !== null,
        createdAt: row.createdAt.toISOString(),
      })),
      // RaajjePro's own account, never a provider's — the artboard says so in
      // as many words ("The platform's own account — never a provider's").
      bankTransfer: this.deps.bankDetails,
    };
  }

  /** Who may call: the customer who owes it. */
  async createProofUpload(
    userId: string,
    feeId: string,
    contentType: string,
  ): Promise<{ submission: PaymentSubmissionDto; upload: UploadTarget }> {
    await this.ownFeeOr404(userId, feeId);
    return this.deps.subscriptions.createProofUpload(userId, feeId, contentType);
  }

  /**
   * Who may call: the customer who owes it. Stamping `submittedAt` here is
   * what lifts §1c's block — nothing else does, and no admin is involved.
   */
  async submitProof(userId: string, feeId: string): Promise<PaymentSubmissionDto> {
    await this.ownFeeOr404(userId, feeId);
    return this.deps.subscriptions.submitProof(userId, feeId);
  }

  private async ownFeeOr404(userId: string, feeId: string): Promise<void> {
    const row = await this.deps.prisma.paymentSubmission.findFirst({
      where: { id: feeId, payerId: userId, purpose: 'emergency_dispatch_fee' },
      select: { id: true },
    });
    // Not-found covers "not yours" and "not a dispatch fee" alike.
    if (row === null) throw new NotFoundError('No such dispatch fee', 'DISPATCH_FEE_NOT_FOUND');
  }
}
