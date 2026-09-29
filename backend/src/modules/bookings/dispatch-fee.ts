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
 * transfer, not when an admin confirms it**."
 *
 * 🔧 **Unsettled, as decided by the owner on 2026-09-29 (§0.0 item 24):** the
 * request's *current* fee is either owed with no proof submitted, **or
 * rejected** — "a rejected proof means the fee is still unsettled, so the
 * block returns. Without this, one invalid submission is a permanent bypass."
 * A proof that is submitted and still awaiting the admin does **not** block;
 * that is the half of §1c that stands. A **waived** fee never blocks (the
 * platform cancelled the booking itself — see `EmergencyService`'s revocation
 * cascade).
 *
 * "Current" is `EmergencyRequest.dispatchFeeSubmissionId`: after a rejection
 * the customer starts a fresh transfer with a new reference ([retry]), which
 * replaces the pointer, and the rejected row stays behind as history without
 * blocking anyone.
 */

/** "Still owed": nothing submitted, or submitted and rejected. Never a waived row. */
const UNSETTLED = {
  purpose: 'emergency_dispatch_fee' as const,
  waivedAt: null,
  OR: [{ status: 'pending' as const, submittedAt: null }, { status: 'rejected' as const }],
};

export async function findOutstandingDispatchFee(
  db: Db,
  customerId: string,
): Promise<PaymentSubmission | null> {
  const request = await db.emergencyRequest.findFirst({
    where: { customerId, dispatchFeeSubmission: { is: UNSETTLED } },
    orderBy: { createdAt: 'asc' },
    select: { dispatchFeeSubmission: true },
  });
  return request?.dispatchFeeSubmission ?? null;
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
  /** The emergency request it was incurred on — "For dispatching … to your Emergency plumbing call-out". */
  requestId: string | null;
  amountLaari: number;
  referenceCode: string;
  /**
   * `owed` until proof is submitted. `owed` and `rejected` block new
   * bookings (§0.0 item 24); `submitted` and `waived` do not.
   */
  state: 'owed' | 'submitted' | 'confirmed' | 'rejected' | 'waived';
  submittedAt: string | null;
  rejectionReason: string | null;
  proofUploaded: boolean;
  createdAt: string;
}

export function dispatchFeeState(
  row: Pick<PaymentSubmission, 'status' | 'submittedAt' | 'waivedAt'>,
): DispatchFeeDto['state'] {
  if (row.waivedAt !== null) return 'waived';
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
        requestId: row.dispatchFeeFor?.id ?? null,
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

  /**
   * Who may call: the customer whose **rejected** fee this is.
   *
   * §0.0 item 24 makes a rejection re-block, so there has to be a way out of
   * it: a fresh transfer against a fresh reference — the same move §1b step 5
   * gives a provider ("resubmit immediately — no cooldown"), which there too
   * creates a new intent rather than reopening the rejected one. The new row
   * becomes the request's current fee; the rejected one stays as history.
   * The amount is §1c's flat MVR 200, not re-derived from anything.
   */
  async retry(userId: string, feeId: string): Promise<DispatchFeeDto> {
    const request = await this.deps.prisma.emergencyRequest.findFirst({
      where: { customerId: userId, dispatchFeeSubmissionId: feeId },
      include: { dispatchFeeSubmission: true },
    });
    const fee = request?.dispatchFeeSubmission ?? null;
    if (request === null || fee === null) {
      throw new NotFoundError('No such dispatch fee', 'DISPATCH_FEE_NOT_FOUND');
    }
    if (fee.status !== 'rejected' || fee.waivedAt !== null) {
      throw new BusinessRuleError(
        'DISPATCH_FEE_NOT_REJECTED',
        'Only a rejected transfer can be started again',
        { state: dispatchFeeState(fee) },
      );
    }
    const fresh = await this.deps.prisma.$transaction(async (tx) => {
      const created = await createOwedDispatchFee(tx, userId);
      const { count } = await tx.emergencyRequest.updateMany({
        where: { id: request.id, dispatchFeeSubmissionId: fee.id },
        data: { dispatchFeeSubmissionId: created.id },
      });
      if (count !== 1) {
        throw new BusinessRuleError(
          'DISPATCH_FEE_NOT_REJECTED',
          'This fee has already been started again',
        );
      }
      return created;
    });
    return {
      id: fresh.id,
      requestId: request.id,
      amountLaari: fresh.amountLaari,
      referenceCode: fresh.referenceCode,
      state: dispatchFeeState(fresh),
      submittedAt: null,
      rejectionReason: null,
      proofUploaded: false,
      createdAt: fresh.createdAt.toISOString(),
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
