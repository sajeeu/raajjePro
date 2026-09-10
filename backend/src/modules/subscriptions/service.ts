import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type {
  Invoice,
  PaymentSubmission,
  Prisma,
  PrismaClient,
  ProviderProfile,
  ProviderSubscription,
} from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { MediaService } from '../media/service.js';
import type { UploadTarget } from '../media/types.js';
import type { ProviderProfileService } from '../providers/service.js';
import { NO_BOOKINGS, type SubscriptionBookingSource } from './bookings.js';
import { applyEntitlementVisibility } from './downgrade.js';
import type { ProviderEntitlementReader } from '../listings/entitlements.js';
import {
  getProviderEntitlements,
  providerEntitlementReader,
  type ProviderEntitlements,
} from './entitlements.js';
import { renderInvoicePdf } from './invoice-pdf.js';
import {
  loggingBillingNotifier,
  type BillingEvent,
  type BillingNotifier,
  type BillingNotifierLogger,
} from './notifications.js';
import { forcedResumeDueAt, pause, resume } from './pause.js';
import {
  ENDING_NOTICE_DAYS,
  GRACE_DAYS,
  PROACTIVE_TRIAL_PROMPT_DAYS,
  WINBACK_DAY_7,
  WINBACK_DAY_30,
  addDays,
  daysUntil,
  periodFor,
} from './period.js';
import {
  INTRODUCTORY_MONTHS,
  INTRODUCTORY_NOTICE_DAYS,
  INTRODUCTORY_PRICE_LAARI,
  STANDARD_PRICE_LAARI,
  generateReferenceCode,
  priceForProvider,
} from './pricing.js';
import { SubscriptionRepository } from './repository.js';
import { decideTrialStart, type TrialTrigger } from './trial.js';
import {
  toAdminPaymentSubmissionDto,
  toInvoiceDto,
  toPaymentSubmissionDto,
  toSubscriptionStatusDto,
  type AdminPaymentSubmissionDto,
  type InvoiceDto,
  type PaymentSubmissionDto,
  type SubscriptionStatusDto,
  type UpgradeRequestDto,
} from './types.js';

interface Deps {
  prisma: PrismaClient;
  providers: ProviderProfileService;
  media: MediaService;
  audit: AuditService;
  clock: Clock;
  /** RaajjePro's own account, from typed config (§Phase 8a). Null only in development. */
  bankDetails: UpgradeRequestDto['bankTransfer'];
  /** §Phase 17.1 supplies the real one; until bookings exist nobody has one (`bookings.ts`). */
  bookings?: SubscriptionBookingSource;
  /** §Phase 19 supplies delivery; until then the default logs that nothing was delivered. */
  notifier?: BillingNotifier;
  log?: BillingNotifierLogger;
}

/**
 * §1b's monetization model and §Phase 8a's surfaces.
 *
 * ## What this service is not allowed to do
 *
 * **Move money.** §1b: "payment for jobs is off-platform. RaajjePro never
 * moves money between customer and provider. Everything RaajjePro collects is
 * a provider paying RaajjePro, via manual bank transfer + admin confirmation.
 * **No payment gateway in v1.**" So there is no charge, no capture, no
 * webhook and no card anywhere below — a payment is a row saying somebody
 * claims to have made a transfer, and an admin saying they saw it arrive.
 *
 * **Touch the badge.** §1b and §1e: the verified badge is gated by
 * `verificationTier` alone and "a lapsed subscription degrades a provider to
 * the free tier; it never deletes data". Nothing here reads or writes
 * `verificationTier` or `verificationStatus`.
 *
 * **Gate a customer.** §1b: "all customer-facing features remain free". The
 * only customer-side money in the whole plan is §1c's emergency dispatch fee,
 * whose `PaymentSubmission` purpose exists in the enum and whose flow is
 * §Phase 17.3's.
 *
 * ## The two-sided attestation is somewhere else entirely
 *
 * A booking's "I've Paid" / "Payment Received" (§1c) is a self-attestation
 * between customer and provider and has nothing to do with this file. The
 * `PaymentSubmission`/admin-confirmation mechanism here is exclusively for
 * RaajjePro's own subscription fees, and conflating the two is the mistake
 * root CLAUDE.md warns about twice.
 */
export class SubscriptionService {
  readonly repo: SubscriptionRepository;
  /** 🔧 What §Phase 8 registered as `FREE_TIER_ONLY`. Wired in `app.ts`; no caller changed. */
  readonly entitlementReader: ProviderEntitlementReader;
  private readonly prisma: PrismaClient;
  private readonly providers: ProviderProfileService;
  private readonly media: MediaService;
  private readonly audit: AuditService;
  private readonly clock: Clock;
  private readonly bankDetails: UpgradeRequestDto['bankTransfer'];
  private readonly bookings: SubscriptionBookingSource;
  private readonly notifier: BillingNotifier;

  constructor(deps: Deps) {
    this.prisma = deps.prisma;
    this.repo = new SubscriptionRepository(deps.prisma);
    this.entitlementReader = providerEntitlementReader(deps.prisma);
    this.providers = deps.providers;
    this.media = deps.media;
    this.audit = deps.audit;
    this.clock = deps.clock;
    this.bankDetails = deps.bankDetails;
    this.bookings = deps.bookings ?? NO_BOOKINGS;
    this.notifier = deps.notifier ?? loggingBillingNotifier(deps.log ?? { info: () => undefined });
  }

  /** The reader §Phase 8's publish gate calls. One line, so the seam is visibly filled. */
  entitlements(providerProfileId: string): Promise<ProviderEntitlements> {
    return getProviderEntitlements(this.prisma, providerProfileId);
  }

  // -------------------------------------------------------------------------
  // Provider-facing
  // -------------------------------------------------------------------------

  /**
   * Who may call: the signed-in user, for their own subscription.
   *
   * §Phase 8a's "subscription status", and what §Phase 10a's Billing screen
   * renders: the trial countdown, the next billing date, the free-tier state,
   * whether a "Try Premium" CTA should show at all, and the most recent
   * payment attempt with its rejection reason.
   */
  async readOwnStatus(userId: string): Promise<SubscriptionStatusDto> {
    const profile = await this.ownProfileOr404(userId);
    return this.statusFor(profile, userId);
  }

  /**
   * Who may call: the signed-in user, for themselves — §Phase 8a's explicit
   * `POST /v1/providers/me/subscription/start-trial`, the "Try Premium" CTA.
   *
   * One of the **two** triggers that start a trial. Idempotent in the way
   * §1b requires: a second call reports `already_used` rather than starting a
   * second trial, and it does so whether the first trial is running or ended
   * a year ago.
   */
  async startTrialForOwner(userId: string, meta?: RequestMeta): Promise<SubscriptionStatusDto> {
    const profile = await this.ownProfileOr404(userId);
    const outcome = await this.startTrial(profile.id, 'explicit_request', meta);
    if (!outcome.started && outcome.reason === 'already_used') {
      throw new BusinessRuleError(
        'TRIAL_ALREADY_USED',
        'This account has already had its free trial — one per account',
      );
    }
    if (!outcome.started && outcome.reason === 'paid_subscription_active') {
      throw new BusinessRuleError(
        'SUBSCRIPTION_ALREADY_ACTIVE',
        'Your subscription is already active, so a trial would give you nothing',
      );
    }
    return this.statusFor(profile, userId);
  }

  /**
   * 🔧 **The trial trigger §Phase 17.1 calls** — the seam this phase opens
   * (`bookings.ts`, ledger row **P8A-2**).
   *
   * §Phase 8a: "the transition of any booking into `confirmed` where this is
   * the provider's first — **hooked on the state transition, not on one
   * endpoint**, so an admin resolving `payment_unresolved` to `confirmed`
   * also fires it". So this takes a provider id and nothing about *how* the
   * transition happened: there is deliberately no way for a caller to say
   * "this one came from the admin queue", because a hook that could tell the
   * difference is a hook that could be wired to one path and not the other —
   * which is the defect §0.5 recorded.
   *
   * `startTrial` is a no-op if a trial has ever run, so §Phase 17.1 may call
   * this on **every** transition into `confirmed` rather than having to work
   * out whether it is the provider's first.
   */
  async onBookingConfirmed(providerProfileId: string): Promise<{ started: boolean }> {
    const outcome = await this.startTrial(providerProfileId, 'first_confirmed_booking');
    return { started: outcome.started };
  }

  /**
   * Who may call: the signed-in user, for themselves.
   *
   * §Phase 8a's `pause`/`resume` — 🔧 **one of two doors onto one function**
   * (confirmed 2026-09-10). §1b's "pause keys off the provider-level
   * `acceptingNewCustomers` toggle" is literal, so this endpoint sets the
   * toggle, and setting the toggle through `PATCH /v1/providers/me` runs this
   * same code. Two independent pause states would be the same failure as a
   * stored copy of a derived rule, in state form.
   */
  async pauseForOwner(userId: string, meta?: RequestMeta): Promise<SubscriptionStatusDto> {
    const profile = await this.ownProfileOr404(userId);
    // Checked here and performed by the listener. This endpoint is the one
    // place a refusal is *reportable*: the provider asked to pause billing, so
    // "you have used all ten days" and "there is nothing running to pause"
    // are answers they need. Setting the toggle directly is a different act
    // (availability, which is always theirs) and never refused for a billing
    // reason.
    pause((await this.repo.find(profile.id)) ?? freeSnapshot(), this.clock());
    // The write goes through §Phase 5's own endpoint logic, which is what
    // fires the listener — so this method never writes the pause columns
    // itself and the two doors cannot diverge.
    await this.providers.updateOwn(userId, { acceptingNewCustomers: false }, meta);
    return this.readOwnStatus(userId);
  }

  /**
   * Resuming is deliberately tolerant where pausing is strict: it is
   * idempotent, and it works even for a provider with no subscription at all.
   * A billing endpoint must never be able to leave a provider stuck at "not
   * accepting new customers" because there was nothing to resume.
   */
  async resumeForOwner(userId: string, meta?: RequestMeta): Promise<SubscriptionStatusDto> {
    await this.ownProfileOr404(userId);
    await this.providers.updateOwn(userId, { acceptingNewCustomers: true }, meta);
    return this.readOwnStatus(userId);
  }

  /**
   * The listener §Phase 5's profile update fires when the toggle changes
   * (registered in `app.ts`).
   *
   * **This is the pause**, and the reason the endpoints above delegate to the
   * toggle rather than the other way round: whichever door a provider comes
   * through, exactly one implementation decides what happens to the clock.
   *
   * Turning the toggle off for a provider with no subscription does nothing —
   * there is no clock to stop — and that is not an error: the toggle's own
   * meaning (§Phase 5: "not taking new customers") is independent of billing.
   */
  async acceptingNewCustomersChanged(providerProfileId: string, accepting: boolean): Promise<void> {
    const row = await this.repo.find(providerProfileId);
    if (row === null) return;
    const now = this.clock();
    if (accepting) {
      const outcome = resume(row, now);
      if (outcome.changed) await this.repo.update(providerProfileId, outcome.patch);
      return;
    }
    // A pause the provider is not entitled to is not an error *here*: they
    // toggled availability, which is theirs to do, and the allowance being
    // spent does not make that refusable. The explicit pause endpoint does
    // surface the refusal, because there the provider asked to pause billing.
    if (row.status !== 'trialing' && row.status !== 'active') return;
    const outcome = pause(row, now);
    if (outcome.changed) await this.repo.update(providerProfileId, outcome.patch);
  }

  /**
   * Who may call: the signed-in, non-frozen user, for themselves.
   *
   * §1b step 1–2: "provider initiates a payment intent in-app; app shows
   * RaajjePro's bank details + a generated reference code". The row exists
   * from here so the reference code the provider writes on the transfer is
   * ours and unique — but `submittedAt` stays null, so this does **not** put
   * anything in the admin queue and grants nothing at all (§1b: "nothing is
   * granted on submission", and this is not even a submission yet).
   *
   * The amount is fixed here, from `priceForProvider`. A provider is charged
   * what they were shown.
   */
  async requestUpgrade(userId: string): Promise<UpgradeRequestDto> {
    const profile = await this.ownProfileOr404(userId);
    const price = await priceForProvider(this.prisma, profile.id);
    const submission = await this.repo.createSubmission({
      payerId: userId,
      purpose: 'subscription',
      amountLaari: price.amountLaari,
      referenceCode: generateReferenceCode(),
      status: 'pending',
      submittedAt: null,
    });
    return {
      submission: this.submissionDto(submission),
      bankTransfer: this.bankDetails,
    };
  }

  /**
   * Who may call: the owner of the submission. Step 1 of §Phase 8's three-step
   * upload, against a different purpose: the server chooses the object key
   * and hands back an expiring target (`MediaService` "knows nothing about
   * listings", which is what makes this reuse rather than a second
   * implementation).
   */
  async createProofUpload(
    userId: string,
    submissionId: string,
    contentType: string,
  ): Promise<{ submission: PaymentSubmissionDto; upload: UploadTarget }> {
    const row = await this.openSubmissionOr404(userId, submissionId);
    const issued = this.media.issueUploadTarget('payment-proof', contentType);
    const updated = await this.repo.updateSubmission(row.id, {
      proofObjectKey: issued.objectKey,
      proofContentType: contentType,
      // Cleared, because a re-upload replaces an earlier one: a row whose
      // byte size still described the previous image would read as uploaded
      // before anything arrived.
      proofByteSize: null,
    });
    return { submission: this.submissionDto(updated), upload: issued.target };
  }

  /**
   * Who may call: the owner. §1b step 3 — "provider uploads proof and
   * submits. Status `pending`."
   *
   * `finalise` is where §Phase 8's guarantee is kept for this purpose too:
   * the bytes are read back, their real type sniffed, their size checked and
   * their EXIF stripped. A payment proof is a photo of a bank-app screen
   * taken on a phone, so it carries the same location metadata a listing
   * photo does.
   */
  async submitProof(userId: string, submissionId: string): Promise<PaymentSubmissionDto> {
    const row = await this.openSubmissionOr404(userId, submissionId);
    if (row.proofObjectKey === null || row.proofContentType === null) {
      throw new BusinessRuleError(
        'PAYMENT_PROOF_REQUIRED',
        'Upload a photo of your transfer receipt before submitting',
      );
    }
    const stored = await this.media.finalise(row.proofObjectKey, row.proofContentType);
    const updated = await this.repo.updateSubmission(row.id, {
      proofContentType: stored.contentType,
      proofByteSize: stored.byteSize,
      submittedAt: this.clock(),
      // A resubmission after a rejection reuses nothing: §1b step 5 allows an
      // immediate resubmit, which creates a *new* intent. This row can only
      // be `pending`, so there is no rejection reason to clear.
    });
    return this.submissionDto(updated);
  }

  /** Who may call: the signed-in user, for their own invoices (§Phase 10a's invoice list). */
  async listOwnInvoices(
    userId: string,
    query: { limit: number; cursor?: string },
  ): Promise<{ items: InvoiceDto[]; nextCursor: string | null }> {
    const profile = await this.providers.repo.findByUserId(userId);
    if (profile === null) return { items: [], nextCursor: null };
    const cursor = query.cursor === undefined ? undefined : decodeCursor(query.cursor);
    const rows = await this.repo.invoicesFor(profile.id, query.limit, cursor);
    const page = rows.slice(0, query.limit);
    const last = page[page.length - 1];
    return {
      items: page.map((row) => toInvoiceDto(row, (key) => this.media.readUrl(key))),
      nextCursor:
        rows.length > query.limit && last !== undefined
          ? encodeCursor(last.issuedAt, last.id)
          : null,
    };
  }

  // -------------------------------------------------------------------------
  // Admin
  // -------------------------------------------------------------------------

  /** Who may call: an enrolled, MFA-verified admin. §Phase 10a's pending queue, oldest first. */
  async listSubmissionsForAdmin(query: {
    status?: PaymentSubmission['status'];
    purpose?: PaymentSubmission['purpose'];
    limit: number;
    cursor?: string;
  }): Promise<{ items: AdminPaymentSubmissionDto[]; nextCursor: string | null }> {
    const cursor = query.cursor === undefined ? undefined : decodeCursor(query.cursor);
    const rows = await this.repo.pendingSubmissions({
      ...(query.status === undefined ? {} : { status: query.status }),
      ...(query.purpose === undefined ? {} : { purpose: query.purpose }),
      limit: query.limit,
      cursor: cursor === undefined ? undefined : { submittedAt: cursor.issuedAt, id: cursor.id },
    });
    const page = rows.slice(0, query.limit);
    const last = page[page.length - 1];
    return {
      items: page.map((row) => toAdminPaymentSubmissionDto(row, (key) => this.media.readUrl(key))),
      nextCursor:
        rows.length > query.limit && last?.submittedAt != null
          ? encodeCursor(last.submittedAt, last.id)
          : null,
    };
  }

  /**
   * Who may call: an enrolled, MFA-verified admin (§1b step 4).
   *
   * **The admin confirming *is* the verification** (§0.0 item 11). Nothing
   * automated approves a payment, and §Phase 10a's receipt analysis is
   * advisory beside the image — it never gates this call.
   *
   * What one confirmation does, in order:
   *
   *  1. Reserves an invoice number and renders the PDF **before** the
   *     transaction, so a storage failure aborts the confirmation instead of
   *     committing an invoice whose document does not exist.
   *  2. Moves the submission `pending → confirmed` **conditionally**, so two
   *     admins working the queue at once produce one confirmation and one
   *     conflict rather than two invoices and sixty days of subscription.
   *  3. Writes `subscriptionPriceLaari` if this is the provider's first
   *     confirmed payment (§1b: the field is "set at their first confirmed
   *     payment and honoured on every renewal thereafter").
   *  4. Sets the billing anchor if there is none and extends the period by 30
   *     days from it (§1b, never a calendar month).
   *  5. Restores everything §1b's downgrade hid — "any confirmed payment
   *     restores everything" — which is the same function the downgrade uses,
   *     run with the new cap.
   */
  async confirmSubmission(
    submissionId: string,
    adminId: string,
    options: { note?: string; meta?: RequestMeta },
  ): Promise<AdminPaymentSubmissionDto> {
    const row = await this.submittedSubmissionOr404(submissionId);
    const profile = await this.providerOfPayerOr422(row);
    const existing = await this.repo.find(profile.id);
    const now = this.clock();

    // The period this payment covers. From the later of the current period
    // end and the trial end, so a provider who pays mid-trial keeps the days
    // they still have — §1b has no rule for that case, and the alternative
    // silently charges for time they already had.
    const from = latest([existing?.currentPeriodEnd ?? null, existing?.trialEndsAt ?? null, now]);
    const period = periodFor(from, now);

    // Reserved and rendered **before** the transaction: a storage failure must
    // abort the confirmation, not commit an invoice row whose document does
    // not exist. The cost is that an aborted transaction leaves an orphan
    // object and a gap in the number series, which is what those two are for.
    const invoiceNumber = await this.repo.nextInvoiceNumber();
    const objectKey = await this.media.putGenerated(
      'invoice',
      renderInvoicePdf({
        invoiceNumber,
        issuedAt: now,
        billedTo: profile.businessName ?? 'RaajjePro provider',
        description: 'Provider subscription — 30 days',
        periodStart: period.start,
        periodEnd: period.end,
        amountLaari: row.amountLaari,
        referenceCode: row.referenceCode,
      }),
      'application/pdf',
    );

    const invoice = await this.prisma.$transaction(async (tx) => {
      const won = await this.repo.transitionSubmission(
        row.id,
        'pending',
        { status: 'confirmed', reviewedByAdminId: adminId, reviewedAt: now },
        tx,
      );
      if (!won) {
        throw new ConflictError(
          'PAYMENT_SUBMISSION_ALREADY_REVIEWED',
          'Another admin has already decided this submission',
        );
      }

      // §1b: written once, at the first confirmed payment, and never
      // recalculated afterwards — "a provider's price never changes because of
      // someone else's signup".
      if (profile.subscriptionPriceLaari === null) {
        await tx.providerProfile.update({
          where: { id: profile.id },
          data: { subscriptionPriceLaari: row.amountLaari },
        });
      }

      await this.repo.ensure(profile.id, tx);
      await this.repo.update(
        profile.id,
        {
          tier: 'premium',
          // A paused provider who pays stays paused: the toggle is still off
          // and the clock is still stopped. Their period is extended all the
          // same — money never expires (§1b).
          status: existing?.status === 'paused' ? 'paused' : 'active',
          billingAnchorAt: existing?.billingAnchorAt ?? now,
          currentPeriodEnd: period.end,
          // A new period gets a fresh warning, and a provider who was
          // downgraded is no longer downgraded — so the win-back clock and
          // its two stamps clear with it.
          periodEndingNoticeAt: null,
          downgradedAt: null,
          winbackDay7At: null,
          winbackDay30At: null,
        },
        tx,
      );

      const created = await this.repo.createInvoice(
        {
          invoiceNumber,
          providerProfileId: profile.id,
          paymentSubmissionId: row.id,
          amountLaari: row.amountLaari,
          periodStart: period.start,
          periodEnd: period.end,
          issuedAt: now,
          objectKey,
        },
        tx,
      );

      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'payment_submission.confirmed',
        targetType: 'payment_submission',
        targetId: row.id,
        reason: options.note ?? 'payment confirmed against bank record',
        // IDs, enums and amounts only — never the proof image, the reference
        // code's payer or a bank detail (root CLAUDE.md 1d).
        metadata: {
          purpose: row.purpose,
          amountLaari: row.amountLaari,
          providerProfileId: profile.id,
          invoiceNumber,
        },
        ...(options.meta === undefined
          ? {}
          : { requestId: options.meta.requestId, ipAddress: options.meta.ip }),
      });
      return created;
    });

    // Outside the transaction because it asks the booking source a question
    // (§1b's protected listings) and touches a different table. A failure here
    // leaves listings hidden until the next lifecycle sweep, which reconciles
    // them — the wrong direction to fail in, and the recoverable one.
    await this.reconcileVisibility(profile.id, now);
    await this.notify('payment_submission_confirmed', profile, {
      amountLaari: row.amountLaari,
      invoiceNumber: invoice.invoiceNumber,
      periodEnd: period.end.toISOString(),
    });
    return this.adminSubmissionDto(row.id);
  }

  /**
   * Who may call: an enrolled, MFA-verified admin. §1b step 4: "rejects
   * (reason required)", and step 5: "on rejection the provider sees the
   * reason and may **resubmit immediately** — no cooldown".
   *
   * There is no cooldown to implement and no appeal to implement — see ledger
   * row **P8A-1**: no section of the plan says what an appeal changes, so
   * inventing a status for it would put semantics in the schema that no
   * decision backs.
   */
  async rejectSubmission(
    submissionId: string,
    adminId: string,
    reason: string,
    meta?: RequestMeta,
  ): Promise<AdminPaymentSubmissionDto> {
    const row = await this.submittedSubmissionOr404(submissionId);
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      const won = await this.repo.transitionSubmission(
        row.id,
        'pending',
        {
          status: 'rejected',
          reviewedByAdminId: adminId,
          reviewedAt: now,
          rejectionReason: reason,
        },
        tx,
      );
      if (!won) {
        throw new ConflictError(
          'PAYMENT_SUBMISSION_ALREADY_REVIEWED',
          'Another admin has already decided this submission',
        );
      }
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'payment_submission.rejected',
        targetType: 'payment_submission',
        targetId: row.id,
        reason,
        metadata: { purpose: row.purpose, amountLaari: row.amountLaari },
        ...(meta === undefined ? {} : { requestId: meta.requestId, ipAddress: meta.ip }),
      });
    });
    // Nothing about the subscription changes: a rejected payment never
    // granted anything, so there is nothing to take away (§1b).
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId: row.payerId },
    });
    if (profile !== null) {
      await this.notify('payment_submission_rejected', profile, { reason });
    }
    return this.adminSubmissionDto(row.id);
  }

  /**
   * Who may call: an enrolled, MFA-verified admin. §1b: "an admin can reverse
   * a confirmed payment (mistake, bank reversal). **Explicit endpoint with an
   * audit-log entry, never a database edit.**"
   *
   * "Restores prior state" (§Phase 8a's Done-when) means the period this
   * payment bought is taken back and the row it was recorded on is voided —
   * never deleted (invariant 8). The invoice is voided for the same reason: a
   * document that was issued cannot be made never to have existed.
   *
   * The listing reconcile at the end is what makes the reversal complete: a
   * provider reversed back to the free tier has their over-cap listings
   * hidden again, protected ones excepted.
   */
  async reverseSubmission(
    submissionId: string,
    adminId: string,
    reason: string,
    meta?: RequestMeta,
  ): Promise<AdminPaymentSubmissionDto> {
    const row = await this.repo.findSubmission(submissionId);
    if (row === null) throw new NotFoundError('No such payment submission');
    if (row.status !== 'confirmed') {
      throw new BusinessRuleError(
        'PAYMENT_SUBMISSION_NOT_CONFIRMED',
        'Only a confirmed payment can be reversed',
        { status: row.status },
      );
    }
    const profile = await this.providerOfPayerOr422(row);
    const invoice = await this.repo.findInvoiceBySubmission(row.id);
    const now = this.clock();

    await this.prisma.$transaction(async (tx) => {
      const won = await this.repo.transitionSubmission(
        row.id,
        'confirmed',
        {
          // Back to `rejected` rather than a sixth status: the enum is
          // §Phase 8a's three values, and what a reversed payment has in
          // common with a rejected one is exactly what matters downstream —
          // it granted nothing. The reversal columns are what tell them apart.
          status: 'rejected',
          reversedAt: now,
          reversedByAdminId: adminId,
          reversalReason: reason,
          rejectionReason: reason,
        },
        tx,
      );
      if (!won) {
        throw new ConflictError(
          'PAYMENT_SUBMISSION_ALREADY_REVIEWED',
          'Another admin has already reversed this payment',
        );
      }
      if (invoice !== null) await this.repo.voidInvoice(invoice.id, reason, now, tx);

      const subscription = await this.repo.find(profile.id, tx);
      if (subscription !== null) {
        await this.repo.update(profile.id, this.reversalPatch(subscription, invoice, now), tx);
      }
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'payment_submission.reversed',
        targetType: 'payment_submission',
        targetId: row.id,
        reason,
        metadata: {
          purpose: row.purpose,
          amountLaari: row.amountLaari,
          providerProfileId: profile.id,
          invoiceNumber: invoice?.invoiceNumber ?? null,
        },
        ...(meta === undefined ? {} : { requestId: meta.requestId, ipAddress: meta.ip }),
      });
    });

    await this.reconcileVisibility(profile.id, now);
    return this.adminSubmissionDto(row.id);
  }

  /**
   * What a reversal takes back.
   *
   * The period the reversed payment bought is removed — `currentPeriodEnd`
   * goes back to the invoice's `periodStart`, which is where it stood before
   * the confirmation. What the provider then holds is **re-derived** rather
   * than forced to free, because reversing one payment of three must not
   * cancel the other two: if something still covers today they stay `active`,
   * and if a trial is still running they fall back to it.
   *
   * **No grace period.** §1b's seven days "with nothing changing" exist for a
   * subscription that *lapsed* — the provider paid, the period ran out, and
   * they are given a week. A reversal says the money never arrived, so there
   * is nothing to be gracious about; the provider goes to the free tier and
   * `downgradedAt` is stamped, which puts them in the same win-back path as
   * any other downgrade (their listings are hidden, intact, and one confirmed
   * payment restores them).
   */
  private reversalPatch(
    subscription: ProviderSubscription,
    invoice: Invoice | null,
    now: Date,
  ): Prisma.ProviderSubscriptionUpdateInput {
    const periodEnd = invoice === null ? subscription.currentPeriodEnd : invoice.periodStart;
    const covered = periodEnd !== null && periodEnd > now;
    const inTrial = subscription.trialEndsAt !== null && subscription.trialEndsAt > now;
    if (subscription.status === 'paused') {
      // A paused clock stays paused; the resume derivation reads the
      // rolled-back dates when it runs.
      return { currentPeriodEnd: periodEnd };
    }
    if (covered) return { currentPeriodEnd: periodEnd, status: 'active', tier: 'premium' };
    if (inTrial) return { currentPeriodEnd: periodEnd, status: 'trialing', tier: 'premium' };
    return {
      currentPeriodEnd: periodEnd,
      status: 'free',
      tier: 'free',
      downgradedAt: subscription.downgradedAt ?? now,
    };
  }

  // -------------------------------------------------------------------------
  // Scheduled work (§Phase 8a: Phase 0's runner, never check-on-read)
  // -------------------------------------------------------------------------

  /**
   * §1b's lifecycle, in one ordered pass per subscription: the forced resume
   * at the pause cap, the 7-day warning, expiry → grace, grace → downgrade,
   * the two win-back notices, and a reconcile of the over-cap listings.
   *
   * One pass rather than five jobs because these are **sequential states of
   * the same row** — a row that expires this hour cannot also be downgraded
   * this hour — so five sweeps would read the same rows five times to do at
   * most one thing each. The introductory-rate conversion is its own job:
   * §Phase 8a names it separately, it reads a different clock (the anchor,
   * twelve months back) and its action is a price rather than a status.
   *
   * The reconcile at the end is what §Phase 8a's Done-when means by "hides it
   * the moment that booking completes": the protection is re-asked every
   * sweep, so a listing loses it as soon as its booking terminates. §Phase
   * 17.1 may call `reconcileVisibility` on that transition to make the moment
   * exact.
   */
  async runLifecycle(now: Date = this.clock()): Promise<LifecycleReport> {
    const report: LifecycleReport = {
      resumedAtCap: 0,
      warned: 0,
      expired: 0,
      downgraded: 0,
      winbacks: 0,
      listingsHidden: 0,
      listingsRestored: 0,
    };

    for (const row of await this.repo.findLifecycleCandidates()) {
      const profile = await this.prisma.providerProfile.findUnique({
        where: { id: row.providerProfileId },
      });
      if (profile === null) continue;
      let current = row;

      // 1. The pause cap. §1b: "at the cap, pause auto-ends and the clock
      // forcibly resumes" — and the toggle is deliberately left alone
      // (2026-09-10): whether a provider takes work is theirs to decide, and
      // only the billing clock is capped.
      const forcedAt = forcedResumeDueAt(current);
      if (forcedAt !== null && forcedAt <= now) {
        const outcome = resume(current, now);
        if (outcome.changed) {
          current = await this.repo.update(current.providerProfileId, outcome.patch);
          report.resumedAtCap += 1;
        }
      }

      // 2. §1b: "**Warning** 7 days before trial or subscription period end."
      // Stamped, so an hourly job sends it once.
      if (
        current.status === 'trialing' &&
        current.trialEndingNoticeAt === null &&
        current.trialEndsAt !== null &&
        daysUntil(current.trialEndsAt, now) <= ENDING_NOTICE_DAYS
      ) {
        current = await this.repo.update(current.providerProfileId, {
          trialEndingNoticeAt: now,
        });
        await this.notify('trial_ending_7d', profile, {
          endsAt: current.trialEndsAt?.toISOString() ?? '',
        });
        report.warned += 1;
      }
      if (
        current.status === 'active' &&
        current.periodEndingNoticeAt === null &&
        current.currentPeriodEnd !== null &&
        daysUntil(current.currentPeriodEnd, now) <= ENDING_NOTICE_DAYS
      ) {
        current = await this.repo.update(current.providerProfileId, {
          periodEndingNoticeAt: now,
        });
        await this.notify('subscription_ending_7d', profile, {
          endsAt: current.currentPeriodEnd?.toISOString() ?? '',
        });
        report.warned += 1;
      }

      // 3. Expiry → grace. §1b: "7 days after expiry **with nothing
      // changing**", which is why `expired` still carries the premium tier.
      const deadline =
        current.status === 'trialing' ? current.trialEndsAt : current.currentPeriodEnd;
      if ((current.status === 'trialing' || current.status === 'active') && past(deadline, now)) {
        current = await this.repo.update(current.providerProfileId, { status: 'expired' });
        report.expired += 1;
      }

      // 4. Grace → downgrade.
      if (current.status === 'expired' && past(graceEnd(current), now)) {
        current = await this.repo.update(current.providerProfileId, {
          status: 'free',
          tier: 'free',
          downgradedAt: now,
        });
        report.downgraded += 1;
        await this.notify('downgraded_to_free', profile, {});
      }

      // 5. §1b's win-back pair: "a downgraded provider receives a
      // notification at 7 and 30 days reminding them their hidden listings
      // are intact and one confirmed payment restores them."
      if (current.downgradedAt !== null) {
        const since = daysSince(current.downgradedAt, now);
        if (current.winbackDay7At === null && since >= WINBACK_DAY_7) {
          current = await this.repo.update(current.providerProfileId, { winbackDay7At: now });
          await this.notify('winback_7d', profile, {});
          report.winbacks += 1;
        }
        if (current.winbackDay30At === null && since >= WINBACK_DAY_30) {
          current = await this.repo.update(current.providerProfileId, { winbackDay30At: now });
          await this.notify('winback_30d', profile, {});
          report.winbacks += 1;
        }
      }

      // 6. Reconcile the listings against whatever the entitlement now is.
      //
      // Only for a provider actually on the free tier: a premium cap is
      // unlimited, so there is nothing to hide and nothing hidden to restore,
      // and skipping them keeps the hourly cost proportional to the providers
      // the rule applies to rather than to the whole table. This is also the
      // step that satisfies "hides it the moment that booking completes" —
      // the protection is re-asked on every sweep.
      if (current.status === 'free') {
        const result = await this.reconcileVisibility(current.providerProfileId, now);
        report.listingsHidden += result.hidden.length;
        report.listingsRestored += result.restored.length;
      }
    }
    return report;
  }

  /**
   * §Phase 8a's third trigger: "prompt 'Try Premium' automatically 7 days
   * after a provider's first published listing **if no booking has landed and
   * no trial has started**".
   *
   * 🔧 **It prompts and does not start** (2026-09-10). A trial is one per
   * account and non-renewable, and this fires precisely when no booking has
   * landed — starting it there would spend the provider's only trial when
   * premium is worth least: analytics over no data, priority placement in a
   * market with no demand. The bullet's stated problem is discovery, and a
   * prompt solves that.
   *
   * "No booking has landed" is the injected source's question, and its answer
   * today is "none has" for everyone, which is true rather than stubbed.
   */
  async runTrialPrompts(now: Date = this.clock()): Promise<{ prompted: number }> {
    let prompted = 0;
    for (const candidate of await this.repo.candidatesForTrialPrompt()) {
      if (candidate.firstPublishedAt === null) continue;
      if (daysSince(candidate.firstPublishedAt, now) < PROACTIVE_TRIAL_PROMPT_DAYS) continue;

      const row = await this.repo.find(candidate.id);
      if (row?.trialPromptedAt != null || row?.trialStartedAt != null) continue;
      if (await this.bookings.hasAnyBooking(candidate.id)) continue;

      await this.repo.ensure(candidate.id);
      await this.repo.update(candidate.id, { trialPromptedAt: now });
      await this.notifier.notify({
        event: 'trial_prompt',
        userId: candidate.userId,
        providerProfileId: candidate.id,
        detail: { firstPublishedAt: candidate.firstPublishedAt.toISOString() },
      });
      prompted += 1;
    }
    return { prompted };
  }

  /**
   * 🔧 §Phase 8a's **fifth** scheduled job (added 2026-09-10).
   *
   * §1b: the introductory rate "is **honoured for 12 months from the billing
   * anchor**, then converts to standard with **30 days' notice** delivered
   * through Phase 19. Time-boxing keeps the acquisition benefit without a
   * permanent revenue drag, and produces a clean conversion measurement."
   *
   * Two steps, 30 days apart: the notice, then the re-price. No other phase
   * owns this — §Phase 10a is the billing UI and §Phase 10c only *measures*
   * the conversion — so leaving it unnamed meant nobody built the thing being
   * measured.
   *
   * 🔧 Twelve months is **365 days**, not a calendar year: §1b is emphatic
   * that nothing in this model implies month boundaries, and a calendar +12
   * months has to answer for 29 February.
   */
  async runIntroductoryConversion(
    now: Date = this.clock(),
  ): Promise<{ noticed: number; converted: number }> {
    let noticed = 0;
    let converted = 0;
    const rows = await this.prisma.providerSubscription.findMany({
      where: {
        billingAnchorAt: { not: null },
        introductoryConvertedAt: null,
        providerProfile: { subscriptionPriceLaari: INTRODUCTORY_PRICE_LAARI },
      },
      include: { providerProfile: true },
    });

    for (const row of rows) {
      if (row.billingAnchorAt === null) continue;
      const convertsAt = introductoryEnd(row.billingAnchorAt);

      if (row.introductoryNoticeAt === null) {
        if (daysUntil(convertsAt, now) > INTRODUCTORY_NOTICE_DAYS) continue;
        await this.repo.update(row.providerProfileId, { introductoryNoticeAt: now });
        await this.notify('introductory_price_converting', row.providerProfile, {
          convertsAt: convertsAt.toISOString(),
          fromLaari: INTRODUCTORY_PRICE_LAARI,
          toLaari: STANDARD_PRICE_LAARI,
        });
        noticed += 1;
        continue;
      }

      // The notice was given; the rate converts once both the twelve months
      // and the thirty days' notice have run. Whichever is later governs, so a
      // late notice still buys the provider its full thirty days.
      const effective = latest([
        convertsAt,
        addDays(row.introductoryNoticeAt, INTRODUCTORY_NOTICE_DAYS),
      ]);
      if (effective === null || effective > now) continue;
      await this.prisma.$transaction(async (tx) => {
        await tx.providerProfile.update({
          where: { id: row.providerProfileId },
          data: { subscriptionPriceLaari: STANDARD_PRICE_LAARI },
        });
        await this.repo.update(row.providerProfileId, { introductoryConvertedAt: now }, tx);
        await this.audit.record(tx, {
          actorType: 'system',
          action: 'provider.subscription_price.converted',
          targetType: 'provider_profile',
          targetId: row.providerProfileId,
          reason: `introductory rate honoured for ${String(INTRODUCTORY_MONTHS)} months from the billing anchor`,
          metadata: { fromLaari: INTRODUCTORY_PRICE_LAARI, toLaari: STANDARD_PRICE_LAARI },
        });
      });
      converted += 1;
    }
    return { noticed, converted };
  }

  /**
   * §1b's downgrade and restore, for one provider, against their current
   * entitlement. Public because a reversal, a confirmation, the lifecycle
   * sweep and eventually §Phase 17.1's booking-termination all need it, and
   * because §1b's guarantee is that upgrade restores exactly what downgrade
   * hid — which only holds if there is one function.
   */
  async reconcileVisibility(providerProfileId: string, now: Date = this.clock()) {
    const entitlements = await this.entitlements(providerProfileId);
    return applyEntitlementVisibility(
      this.prisma,
      this.bookings,
      providerProfileId,
      entitlements.activeListingCap,
      now,
    );
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /**
   * §1b's trial start, and the only place a trial is ever created. Both
   * starting triggers land here, which is what makes "never twice" a property
   * of one function rather than an agreement between call sites.
   */
  private async startTrial(
    providerProfileId: string,
    trigger: TrialTrigger,
    meta?: RequestMeta,
  ): Promise<{ started: boolean; reason?: 'already_used' | 'paid_subscription_active' }> {
    const existing = await this.repo.find(providerProfileId);
    const now = this.clock();
    const decision = decideTrialStart(
      { trialStartedAt: existing?.trialStartedAt ?? null, status: existing?.status ?? null },
      now,
    );
    if (!decision.started || decision.trialEndsAt === undefined) {
      return {
        started: false,
        ...(decision.reason === undefined ? {} : { reason: decision.reason }),
      };
    }

    await this.prisma.$transaction(async (tx) => {
      await this.repo.ensure(providerProfileId, tx);
      await this.repo.update(
        providerProfileId,
        {
          tier: 'premium',
          status: 'trialing',
          trialStartedAt: now,
          trialEndsAt: decision.trialEndsAt ?? now,
        },
        tx,
      );
      // The trigger is recorded here rather than as a column: §Phase 10c's
      // conversion dashboard needs to know how trials start, and the audit
      // log already answers "how did this happen?" for every other state
      // change in the system.
      await this.audit.record(tx, {
        actorType: trigger === 'explicit_request' ? 'user' : 'system',
        action: 'provider.trial.started',
        targetType: 'provider_profile',
        targetId: providerProfileId,
        reason: trigger,
        metadata: { trigger, endsAt: (decision.trialEndsAt ?? now).toISOString() },
        ...(meta === undefined ? {} : { requestId: meta.requestId, ipAddress: meta.ip }),
      });
    });
    // A trial is a premium entitlement, so anything hidden over the free cap
    // comes back — the same reconcile a confirmed payment runs.
    await this.reconcileVisibility(providerProfileId, now);
    return { started: true };
  }

  private async statusFor(
    profile: ProviderProfile,
    userId: string,
  ): Promise<SubscriptionStatusDto> {
    const [entitlements, subscription, nextPayment, latestSubmission] = await Promise.all([
      this.entitlements(profile.id),
      this.repo.find(profile.id),
      priceForProvider(this.prisma, profile.id),
      this.repo.findLatestSubmission(userId, 'subscription'),
    ]);
    return toSubscriptionStatusDto(
      {
        entitlements,
        subscription,
        profile,
        nextPayment,
        introductoryConvertsAt:
          subscription?.billingAnchorAt != null &&
          profile.subscriptionPriceLaari === INTRODUCTORY_PRICE_LAARI
            ? introductoryEnd(subscription.billingAnchorAt)
            : null,
        latestSubmission,
        now: this.clock(),
      },
      (key) => this.media.readUrl(key),
    );
  }

  private async notify(
    event: BillingEvent,
    profile: Pick<ProviderProfile, 'id' | 'userId'>,
    detail: Record<string, string | number | boolean>,
  ): Promise<void> {
    await this.notifier.notify({
      event,
      userId: profile.userId,
      providerProfileId: profile.id,
      detail,
    });
  }

  private submissionDto(row: PaymentSubmission): PaymentSubmissionDto {
    return toPaymentSubmissionDto(row, (key) => this.media.readUrl(key));
  }

  private async adminSubmissionDto(id: string): Promise<AdminPaymentSubmissionDto> {
    const row = await this.prisma.paymentSubmission.findUniqueOrThrow({
      where: { id },
      include: {
        payer: {
          select: {
            id: true,
            fullName: true,
            email: true,
            providerProfile: {
              select: { id: true, businessName: true, subscriptionPriceLaari: true },
            },
          },
        },
      },
    });
    return toAdminPaymentSubmissionDto(row, (key) => this.media.readUrl(key));
  }

  /**
   * A read never creates the provider profile (§Phase 5's `readOwn` note), and
   * neither does starting a trial or a payment: §1a's creation moments are
   * onboarding, the first draft save and the profile PATCH. A trial is one
   * per account and non-renewable, so handing one to an account that has
   * never acted as a provider would spend it on somebody who cannot use it.
   */
  private async ownProfileOr404(userId: string): Promise<ProviderProfile> {
    const profile = await this.providers.repo.findByUserId(userId);
    if (profile === null) {
      throw new NotFoundError(
        'This account has no provider profile yet',
        'PROVIDER_PROFILE_NOT_FOUND',
      );
    }
    return profile;
  }

  /** Not-found covers "not yours", so ids cannot be probed. `pending` and unsubmitted is the only editable state. */
  private async openSubmissionOr404(
    userId: string,
    submissionId: string,
  ): Promise<PaymentSubmission> {
    const row = await this.repo.findOwnedSubmission(submissionId, userId);
    if (row === null) throw new NotFoundError('No such payment submission');
    if (row.status !== 'pending') {
      throw new BusinessRuleError(
        'PAYMENT_SUBMISSION_CLOSED',
        row.status === 'confirmed'
          ? 'This payment has already been confirmed'
          : 'This payment was rejected — start a new one to resubmit',
        { status: row.status },
      );
    }
    return row;
  }

  private async submittedSubmissionOr404(id: string): Promise<PaymentSubmission> {
    const row = await this.repo.findSubmission(id);
    if (row === null) throw new NotFoundError('No such payment submission');
    if (row.status !== 'pending' || row.submittedAt === null) {
      throw new BusinessRuleError(
        'PAYMENT_SUBMISSION_NOT_PENDING',
        row.submittedAt === null
          ? 'This payment has not been submitted yet'
          : 'This submission has already been decided',
        { status: row.status },
      );
    }
    return row;
  }

  /**
   * A subscription payment must belong to a provider. The dispatch fee
   * (§1c) is paid by a customer and will not come through this path, which is
   * why the check is here and not on the table.
   */
  private async providerOfPayerOr422(row: PaymentSubmission): Promise<ProviderProfile> {
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId: row.payerId },
    });
    if (profile === null) {
      throw new BusinessRuleError(
        'PAYER_IS_NOT_A_PROVIDER',
        'This payment was made by an account with no provider profile',
      );
    }
    return profile;
  }
}

export interface LifecycleReport {
  resumedAtCap: number;
  warned: number;
  expired: number;
  downgraded: number;
  winbacks: number;
  listingsHidden: number;
  listingsRestored: number;
}

/** §1b's introductory honouring window — 365 days from the anchor. */
export function introductoryEnd(billingAnchorAt: Date): Date {
  return addDays(billingAnchorAt, 365);
}

function past(deadline: Date | null, now: Date): boolean {
  return deadline !== null && deadline <= now;
}

/**
 * When §1b's seven days of grace run out.
 *
 * Measured from whichever clock expired last: a provider whose trial ended
 * and who then paid has a period end later than their trial end, and one who
 * never paid has only the trial end. Taking the later of the two means a
 * downgrade is never earlier than the last thing that entitled them.
 */
function graceEnd(row: ProviderSubscription): Date | null {
  const ended = latest([row.currentPeriodEnd, row.trialEndsAt]);
  return ended === null ? null : addDays(ended, GRACE_DAYS);
}

/** What `pause` sees for a provider with no subscription row: nothing to pause. */
function freeSnapshot() {
  return {
    status: 'free' as const,
    tier: 'free' as const,
    pausedAt: null,
    cumulativePausedMinutes: 0,
    trialEndsAt: null,
    currentPeriodEnd: null,
    billingAnchorAt: null,
  };
}

function daysSince(from: Date, now: Date): number {
  return Math.floor((now.getTime() - from.getTime()) / (24 * 60 * 60 * 1000));
}

function latest(dates: (Date | null)[]): Date | null {
  return dates.reduce<Date | null>(
    (best, date) => (date === null ? best : best === null || date > best ? date : best),
    null,
  );
}

function encodeCursor(at: Date, id: string): string {
  return Buffer.from(`${at.toISOString()}|${id}`).toString('base64url');
}

function decodeCursor(cursor: string): { issuedAt: Date; id: string } {
  const [iso, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  const issuedAt = new Date(iso ?? '');
  if (id === undefined || Number.isNaN(issuedAt.getTime())) {
    throw new BusinessRuleError('INVALID_CURSOR', 'That page cursor is not valid');
  }
  return { issuedAt, id };
}
