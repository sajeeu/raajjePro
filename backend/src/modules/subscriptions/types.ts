import type { BillingBankDetails } from '../../config/env.js';
import type {
  Invoice,
  PaymentSubmission,
  ProviderProfile,
  ProviderSubscription,
  User,
} from '../../generated/prisma/client.js';
import type { ProviderEntitlements } from './entitlements.js';
import { daysUntil } from './period.js';
import { forcedResumeDueAt, pauseDays } from './pause.js';

/**
 * The DTOs for §Phase 8a's surfaces, and the mapping layer that keeps the
 * sensitive fields structurally out of them (backend/CLAUDE.md: "excluded
 * structurally in the DTO mapping layer, not by remembering to omit them per
 * handler").
 *
 * ## No response here carries a phone number
 *
 * Structurally: nothing below has a field for one, and the only `User` this
 * module reads is mapped by `toPayerDto`, which takes three columns by name.
 * §1c gives exactly one endpoint in the system permission to return a phone
 * number to another user and it is `POST /v1/bookings/:id/reveal-contact`.
 *
 * ## Nor a provider's own bank details
 *
 * `ProviderProfile.bankName` and its three siblings are the *provider's*
 * account — §Phase 5 allows them in exactly one place, a booking's payment
 * step, through `paymentDetailsForBooking`. Nothing in this module reads
 * them. The bank details that *do* appear here are RaajjePro's own, from
 * configuration (§Phase 8a), which is a different set of facts entirely.
 */

/** Money is integer laari end to end (invariant 7) — in the database, in the DTO and in the JSON. */
export interface SubscriptionStatusDto {
  tier: ProviderEntitlements['tier'];
  status: ProviderEntitlements['status'];
  entitlements: {
    /**
     * 🔧 **`null` means "no limit", never "unknown"** (decided 2026-09-10).
     * §1b says premium "unlocks multiple active listings" and names no
     * number, so premium has no cap — and `Infinity` has no JSON
     * representation, which is the only reason this is not a number.
     */
    activeListingCap: number | null;
    analytics: boolean;
    priorityPlacement: boolean;
  };
  trial: {
    startedAt: string | null;
    endsAt: string | null;
    daysRemaining: number | null;
    /** False once a trial has ever run — §1b's "one trial per user account". */
    available: boolean;
  };
  billing: {
    /** §1b's 30-day anchor, explicitly not a calendar month. */
    anchorAt: string | null;
    currentPeriodEnd: string | null;
    daysRemaining: number | null;
    /** What this provider's next period costs — their own price, or §1b's cohort rule before it is set. */
    nextPaymentAmountLaari: number;
    /** Their settled price, once a payment has been confirmed. Null before that. */
    priceLaari: number | null;
    /** True while they are on §1b's introductory rate. */
    introductory: boolean;
    /** When §1b's 12-month introductory honouring ends and the standard rate applies. */
    introductoryConvertsAt: string | null;
  };
  pause: {
    paused: boolean;
    pausedAt: string | null;
    cumulativePausedDays: number;
    remainingPauseAllowanceDays: number;
    /** When the 10-day cap forces the clock to resume, if paused now. */
    forcedResumeDueAt: string | null;
  };
  /**
   * §1b: "pause keys off the provider-level `acceptingNewCustomers` toggle".
   * Returned here because the two are one state and a billing screen that
   * showed a pause without showing what it keys off would be describing half
   * of it.
   */
  acceptingNewCustomers: boolean;
  /** When §1b's grace period ended and the over-cap listings were hidden. */
  downgradedAt: string | null;
  /** The provider's most recent payment submission — what §Phase 10a's pending and rejected states render. */
  latestSubmission: PaymentSubmissionDto | null;
}

export interface PaymentSubmissionDto {
  id: string;
  purpose: PaymentSubmission['purpose'];
  amountLaari: number;
  referenceCode: string;
  status: PaymentSubmission['status'];
  submittedAt: string | null;
  /** §1b step 5: the provider sees the reason and may resubmit immediately. */
  rejectionReason: string | null;
  reviewedAt: string | null;
  reversedAt: string | null;
  /** Whether any bytes have actually arrived — a target issued and abandoned reads false. */
  proofUploaded: boolean;
  /** Short-lived and re-issued on every read; never the stored object key. */
  proofUrl: string | null;
  createdAt: string;
}

/** The admin queue's extra columns (§Phase 10a: "proof image, submitter, amount, reference code"). */
export interface AdminPaymentSubmissionDto extends PaymentSubmissionDto {
  /**
   * Admin-only. §Phase 10b forbids a name or an email address in a **CSV
   * export**; the queue itself has to say who is asking to be confirmed.
   * There is no phone number here (§1c) and no branch that could add one.
   */
  payer: { id: string; fullName: string; email: string };
  providerProfileId: string | null;
  providerBusinessName: string | null;
  /**
   * §Phase 10a's receipt analysis checks the amount against "the period's
   * price for *this provider* (`subscriptionPriceLaari`, §1b — never a global
   * constant)". This is that number, so the check reads the provider's own
   * rate rather than re-deriving it.
   */
  providerPriceLaari: number | null;
}

export interface UpgradeRequestDto {
  submission: PaymentSubmissionDto;
  /**
   * RaajjePro's own account (§1b step 2), from typed configuration.
   *
   * **Null when unconfigured**, which only development can be — production
   * refuses to boot without it. Null rather than an example account: a
   * provider who transfers to a made-up number has lost the money.
   */
  bankTransfer: BillingBankDetails | null;
}

export interface InvoiceDto {
  id: string;
  invoiceNumber: string;
  amountLaari: number;
  periodStart: string;
  periodEnd: string;
  issuedAt: string;
  /** Short-lived signed URL for the stored PDF. Re-issued per read. */
  pdfUrl: string;
  /** Set when the payment behind it was reversed — voided, never deleted (invariant 8). */
  voidedAt: string | null;
  voidedReason: string | null;
}

type ReadUrl = (objectKey: string) => string;

export function toPaymentSubmissionDto(
  row: PaymentSubmission,
  readUrl: ReadUrl,
): PaymentSubmissionDto {
  return {
    id: row.id,
    purpose: row.purpose,
    amountLaari: row.amountLaari,
    referenceCode: row.referenceCode,
    status: row.status,
    submittedAt: iso(row.submittedAt),
    rejectionReason: row.rejectionReason,
    reviewedAt: iso(row.reviewedAt),
    reversedAt: iso(row.reversedAt),
    proofUploaded: row.proofByteSize !== null,
    proofUrl: row.proofObjectKey === null ? null : readUrl(row.proofObjectKey),
    createdAt: row.createdAt.toISOString(),
  };
}

export function toAdminPaymentSubmissionDto(
  row: PaymentSubmission & {
    payer: Pick<User, 'id' | 'fullName' | 'email'> & {
      providerProfile: Pick<
        ProviderProfile,
        'id' | 'businessName' | 'subscriptionPriceLaari'
      > | null;
    };
  },
  readUrl: ReadUrl,
): AdminPaymentSubmissionDto {
  const profile = row.payer.providerProfile;
  return {
    ...toPaymentSubmissionDto(row, readUrl),
    payer: { id: row.payer.id, fullName: row.payer.fullName, email: row.payer.email },
    providerProfileId: profile?.id ?? null,
    providerBusinessName: profile?.businessName ?? null,
    providerPriceLaari: profile?.subscriptionPriceLaari ?? null,
  };
}

export function toInvoiceDto(row: Invoice, readUrl: ReadUrl): InvoiceDto {
  return {
    id: row.id,
    invoiceNumber: row.invoiceNumber,
    amountLaari: row.amountLaari,
    periodStart: row.periodStart.toISOString(),
    periodEnd: row.periodEnd.toISOString(),
    issuedAt: row.issuedAt.toISOString(),
    pdfUrl: readUrl(row.objectKey),
    voidedAt: iso(row.voidedAt),
    voidedReason: row.voidedReason,
  };
}

export interface StatusInput {
  entitlements: ProviderEntitlements;
  subscription: ProviderSubscription | null;
  profile: Pick<ProviderProfile, 'acceptingNewCustomers' | 'subscriptionPriceLaari'>;
  /** What the next period costs, from `priceForProvider` — the provider's own rate, or §1b's cohort rule. */
  nextPayment: { amountLaari: number; introductory: boolean };
  introductoryConvertsAt: Date | null;
  latestSubmission: PaymentSubmission | null;
  now: Date;
}

export function toSubscriptionStatusDto(
  input: StatusInput,
  readUrl: ReadUrl,
): SubscriptionStatusDto {
  const { entitlements, subscription, profile, now } = input;
  const pauseCounters = pauseDays({
    cumulativePausedMinutes: subscription?.cumulativePausedMinutes ?? 0,
  });
  return {
    tier: entitlements.tier,
    status: entitlements.status,
    entitlements: {
      activeListingCap: Number.isFinite(entitlements.activeListingCap)
        ? entitlements.activeListingCap
        : null,
      analytics: entitlements.analytics,
      priorityPlacement: entitlements.priorityPlacement,
    },
    trial: {
      startedAt: iso(subscription?.trialStartedAt ?? null),
      endsAt: iso(subscription?.trialEndsAt ?? null),
      daysRemaining:
        subscription?.trialEndsAt == null ? null : daysUntil(subscription.trialEndsAt, now),
      available: (subscription?.trialStartedAt ?? null) === null,
    },
    billing: {
      anchorAt: iso(subscription?.billingAnchorAt ?? null),
      currentPeriodEnd: iso(subscription?.currentPeriodEnd ?? null),
      daysRemaining:
        subscription?.currentPeriodEnd == null
          ? null
          : daysUntil(subscription.currentPeriodEnd, now),
      nextPaymentAmountLaari: input.nextPayment.amountLaari,
      priceLaari: profile.subscriptionPriceLaari,
      introductory: input.nextPayment.introductory,
      introductoryConvertsAt: iso(input.introductoryConvertsAt),
    },
    pause: {
      paused: subscription?.status === 'paused',
      pausedAt: iso(subscription?.pausedAt ?? null),
      ...pauseCounters,
      forcedResumeDueAt: subscription === null ? null : iso(forcedResumeDueAt(subscription)),
    },
    acceptingNewCustomers: profile.acceptingNewCustomers,
    downgradedAt: iso(subscription?.downgradedAt ?? null),
    latestSubmission:
      input.latestSubmission === null
        ? null
        : toPaymentSubmissionDto(input.latestSubmission, readUrl),
  };
}

function iso(date: Date | null | undefined): string | null {
  return date == null ? null : date.toISOString();
}
