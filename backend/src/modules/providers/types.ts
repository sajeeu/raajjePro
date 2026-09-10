import type {
  ProviderProfile,
  ProviderType,
  VerificationTier,
  VerificationStatus,
} from '../../generated/prisma/client.js';
import type { IslandDto } from '../location/types.js';
import { meetsConductFloor, NO_CONDUCT, type ProviderConductRecord } from './conduct.js';
import { isOnboardingComplete } from './onboarding.js';

/**
 * What a provider profile looks like on the wire.
 *
 * This file is the **structural gate** for the two exclusions §Phase 5's
 * Done-when asserts (backend/CLAUDE.md: excluded in the mapping layer, not by
 * remembering per handler):
 *
 *   - **No phone number, in any shape here, at any depth.** §Phase 5 stores
 *     exactly one, on the `User` row, and §1c allows exactly one endpoint in
 *     the entire system to return it to another user —
 *     `POST /v1/bookings/:id/reveal-contact`, under its seven conditions.
 *     `GET /v1/bookings/:id/contact-info` does not exist and must not be
 *     created. The provider's own read of their own account phone stays where
 *     Phase 3 put it, on `userDto`.
 *   - **No payment details except through `paymentDetailsForBooking`.** They
 *     are the one piece of provider information shown to a *customer*, and
 *     only at a booking's payment step (§1c) — a bank account number is not a
 *     way to reach a person, and the off-platform transfer cannot happen
 *     without it. Every other mapper here is structurally incapable of
 *     carrying them.
 *
 * A conduct field is a **number or null**, never a label. §1f rejected
 * "Prone to cancel", "Price hiking" and every euphemism for them in Round 15
 * as automated public accusations; there is deliberately no field on any of
 * these shapes that could hold one.
 */

/**
 * §1f's metrics as a client renders them. Every rate is a fraction in
 * `[0, 1]`, or null where the metric is not computable. `medianResponseSeconds`
 * is seconds; the "usually responds in 12 minutes" phrasing is the client's.
 */
export interface ConductMetricsDto {
  completionRate: number | null;
  cancellationRate: number | null;
  noShowRate: number | null;
  onTimeRate: number | null;
  priceAdherenceRate: number | null;
  acceptanceRate: number | null;
  medianResponseSeconds: number | null;
}

/** The public conduct block: either the numbers, or the job count alone. */
export interface PublicConductDto {
  /** Lifetime completed jobs — the one figure that still shows below the floor. */
  jobsCompletedCount: number;
  /**
   * §1f's ten-completed-booking floor, decided by the server (invariant 4).
   * True means the rates are suppressed because there are too few completed
   * bookings *in the window* to mean anything.
   *
   * **Not called `newProvider`.** It was, and that was wrong: the floor is
   * measured against the 90-day window (see `conduct.ts`), so a business with
   * 47 lifetime jobs and 9 this quarter would have rendered as "New provider ·
   * 47 jobs completed" — a flag name asserting something the count beside it
   * contradicts. §1f's "show 'New provider' and the job count" copy is a
   * display decision for Phases 12 and 13, which have both numbers here to
   * make it from.
   */
  metricsBelowFloor: boolean;
  /** Null when `metricsBelowFloor`: below the floor there is nothing to show. */
  metrics: ConductMetricsDto | null;
}

/**
 * The provider's own conduct block. §1f: "Every metric is visible to the
 * provider on their own dashboard before it is visible to anyone else" —
 * so the numbers are here even below the floor, with `publiclyVisible: false`
 * telling the provider what a customer currently sees instead. Nobody should
 * learn their on-time rate from a customer.
 */
export interface OwnConductDto {
  jobsCompletedCount: number;
  completedInWindow: number;
  /** False below the floor: these numbers are the provider's own for now. */
  publiclyVisible: boolean;
  metrics: ConductMetricsDto;
}

/**
 * The public provider shape. Phase 12's listing page and Phase 13's public
 * profile both map through this, so what a customer can see is defined once.
 */
export interface PublicProviderDto {
  id: string;
  businessName: string | null;
  bio: string | null;
  yearsOfExperience: number | null;
  /** §1e: what the badge renders. Never a bare boolean, never "verified". */
  verificationTier: VerificationTier;
  /**
   * §1g. `true` only where Gold review evidenced it; **null below Gold**,
   * because the attribute is absent there rather than false — an unregistered
   * tradesperson has not been found to be foreign-owned, they have not been
   * asked.
   */
  maldivianOwned: boolean | null;
  /** §Phase 5's provider-level toggle. A customer sees it because it gates every listing at once. */
  acceptingNewCustomers: boolean;
  conduct: PublicConductDto;
  createdAt: string;
}

/**
 * The provider's own profile. Adds what only they may see: the review state of
 * a pending verification submission, their own renewal price, their payment
 * details, their suspension state, and their conduct numbers ahead of the
 * floor.
 *
 * Still no phone number: their account phone is `userDto`'s, from Phase 3.
 */
export interface OwnProviderDto {
  id: string;
  userId: string;
  businessName: string | null;
  /**
   * §Phase 6a's required "How will you offer services?" choice. Null means
   * *not yet asked* — §1a's implicit path creates a profile without one — and
   * `onboardingComplete` below is what turns on it.
   *
   * Deliberately **not** on `PublicProviderDto`. §Phase 6a gives it two jobs,
   * and neither is a customer-facing one: it decides what §1e's Gold review
   * asks for, and it is what §1g's Maldivian-owned *business* attribute hangs
   * from. §Phase 13 owns the public profile and can add it there additively if
   * that screen turns out to want it.
   */
  providerType: ProviderType | null;
  bio: string | null;
  yearsOfExperience: number | null;
  verificationTier: VerificationTier;
  /** §1e: the *review state* of a pending submission, never the badge and never visibility. */
  verificationStatus: VerificationStatus;
  maldivianOwned: boolean | null;
  acceptingNewCustomers: boolean;
  /** §1b: this provider's own renewal price in integer laari. Null until their first confirmed payment. */
  subscriptionPriceLaari: number | null;
  /** Own-read only. Never in `PublicProviderDto`, which has no field for it. */
  paymentDetails: PaymentDetailsDto;
  /**
   * §Phase 7: the islands this provider works on, account-level. Here rather
   * than behind a second URL — §Phase 7 names a POST and a DELETE on
   * `/v1/providers/me/service-areas` and no GET, so the read went to the
   * endpoint that already existed, additively.
   *
   * Deliberately **not** on `PublicProviderDto`. §Phase 8 gives a listing its
   * own service areas and those are what discovery matches on; this is the
   * provider's own default, and a customer reading it would be reading a
   * coverage claim no listing has to honour.
   */
  serviceAreas: IslandDto[];
  /** §1a: an input to visibility, and Phase 10b's action. A suspended provider is told, never silently delisted. */
  suspended: boolean;
  suspendedReason: string | null;
  conduct: OwnConductDto;
  /**
   * §Phase 6a, derived and never stored — see `onboarding.ts` for the full
   * rule and for why the verified-email requirement is expressed here rather
   * than as a guard on `PATCH /v1/providers/me`.
   *
   * The onboarding screen reads it to decide whether the flow is finished;
   * §Phase 6's role switcher reads the same fact from `profile-summary`, so
   * that one screen does not pay for a second request. There is exactly one
   * definition behind both.
   */
  onboardingComplete: boolean;
  createdAt: string;
}

/**
 * The provider's bank transfer details. Reachable from exactly two places:
 * the provider's own profile read, and `paymentDetailsForBooking` at a
 * booking's payment step (§1c). Never logged — `AuditService.record` takes
 * IDs and enums only (root CLAUDE.md 1d), so no call site here passes one of
 * these values as audit metadata.
 */
export interface PaymentDetailsDto {
  bankName: string | null;
  bankAccountName: string | null;
  bankAccountNumber: string | null;
  transferInstructions: string | null;
}

function conductMetrics(record: ProviderConductRecord): ConductMetricsDto {
  return {
    completionRate: record.completionRate,
    cancellationRate: record.cancellationRate,
    noShowRate: record.noShowRate,
    onTimeRate: record.onTimeRate,
    priceAdherenceRate: record.priceAdherenceRate,
    acceptanceRate: record.acceptanceRate,
    medianResponseSeconds: record.medianResponseSeconds,
  };
}

export function toPublicProviderDto(
  row: ProviderProfile,
  conduct: ProviderConductRecord = NO_CONDUCT,
): PublicProviderDto {
  const aboveFloor = meetsConductFloor(conduct);
  return {
    id: row.id,
    businessName: row.businessName,
    bio: row.bio,
    yearsOfExperience: row.yearsOfExperience,
    verificationTier: row.verificationTier,
    // §1g's "absent below Gold", enforced here rather than by a database
    // constraint so that an admin demoting a tier is never blocked by one.
    maldivianOwned: row.verificationTier === 'gold' ? row.maldivianOwned : null,
    acceptingNewCustomers: row.acceptingNewCustomers,
    conduct: {
      jobsCompletedCount: conduct.jobsCompletedCount,
      metricsBelowFloor: !aboveFloor,
      metrics: aboveFloor ? conductMetrics(conduct) : null,
    },
    createdAt: row.createdAt.toISOString(),
  };
}

/**
 * The last two parameters are **required, with no defaults**, and that is
 * deliberate: both feed `onboardingComplete`, and a default would let a
 * forgetful caller return `false` for a provider who has finished — routing
 * them back into onboarding (§Phase 6a). A missing argument should be a
 * compile error, not a wrong answer.
 */
export function toOwnProviderDto(
  row: ProviderProfile,
  conduct: ProviderConductRecord,
  serviceAreas: IslandDto[],
  emailVerified: boolean,
): OwnProviderDto {
  return {
    id: row.id,
    userId: row.userId,
    businessName: row.businessName,
    providerType: row.providerType,
    bio: row.bio,
    yearsOfExperience: row.yearsOfExperience,
    verificationTier: row.verificationTier,
    verificationStatus: row.verificationStatus,
    maldivianOwned: row.verificationTier === 'gold' ? row.maldivianOwned : null,
    acceptingNewCustomers: row.acceptingNewCustomers,
    subscriptionPriceLaari: row.subscriptionPriceLaari,
    paymentDetails: toPaymentDetailsDto(row),
    serviceAreas,
    suspended: row.suspendedAt !== null,
    suspendedReason: row.suspendedReason,
    conduct: {
      jobsCompletedCount: conduct.jobsCompletedCount,
      completedInWindow: conduct.completedInWindow,
      publiclyVisible: meetsConductFloor(conduct),
      metrics: conductMetrics(conduct),
    },
    onboardingComplete: isOnboardingComplete({
      profile: row,
      serviceAreaCount: serviceAreas.length,
      emailVerified,
    }),
    createdAt: row.createdAt.toISOString(),
  };
}

export function toPaymentDetailsDto(row: ProviderProfile): PaymentDetailsDto {
  return {
    bankName: row.bankName,
    bankAccountName: row.bankAccountName,
    bankAccountNumber: row.bankAccountNumber,
    transferInstructions: row.transferInstructions,
  };
}

/**
 * The provider's own data for `GET /v1/users/me/data-export` (§Phase 3's
 * export, extended additively here). Own data only — the same reason
 * `AccountService.exportData` already carries the account phone — so the
 * payment details a provider typed in are returned to that provider.
 */
export function providerOwnExport(row: ProviderProfile): Record<string, unknown> {
  return {
    businessName: row.businessName,
    providerType: row.providerType,
    bio: row.bio,
    yearsOfExperience: row.yearsOfExperience,
    verificationTier: row.verificationTier,
    verificationStatus: row.verificationStatus,
    // The stored value, NOT the display-gated one. §1g's "absent below Gold"
    // governs what a customer is shown; an export is what the platform holds
    // about the subject, and masking a fact out of it would be the wrong
    // answer to the question the export exists to answer.
    maldivianOwned: row.maldivianOwned,
    acceptingNewCustomers: row.acceptingNewCustomers,
    subscriptionPriceLaari: row.subscriptionPriceLaari,
    paymentDetails: toPaymentDetailsDto(row),
    // Same reasoning: a suspended provider's own export must say so.
    suspended: row.suspendedAt !== null,
    suspendedAt: row.suspendedAt?.toISOString() ?? null,
    suspendedReason: row.suspendedReason,
    createdAt: row.createdAt.toISOString(),
  };
}
