import type { Prisma } from '../../generated/prisma/client.js';
import type { ProviderConductRecord } from '../providers/conduct.js';

/**
 * §1f's seven conduct metrics, computed from booking outcomes and nothing
 * else — never from a review, never from anything a provider says about
 * themselves.
 *
 * This file is the **one** place each definition is written. The snapshot
 * the public reads and the evidence list the provider reads both come from
 * `computeConduct`, against the same instant, so the numbers and the
 * bookings behind them cannot disagree.
 *
 * ## The definitions, and where the plan left a choice (decision 32)
 *
 * The window is a rolling 90 days ending at `asOf`. A booking an admin
 * excluded on appeal (§1f) counts towards nothing, the job count included.
 *
 * - **Completion** — completed ÷ (completed + provider-cancelled + no-show),
 *   each counted when it happened inside the window.
 * - **Cancellation** — of the bookings that reached `accepted` inside the
 *   window, those the **provider** cancelled. A customer's cancellation never
 *   counts (§1f); neither does the system cancelling on a verification
 *   revocation, which nobody chose.
 * - **No-show** — of the same accepted cohort: an emergency offer the
 *   customer marked "provider has not arrived" (§1c, `no_show`), and a
 *   completion-prompt "No" (§1c step 10) **once an admin has resolved that
 *   dispute for the customer** — a "possible no-show" becomes a confirmed one
 *   only when somebody has looked (§1f says "confirmed no-shows").
 * - **On-time** — 🔧 **always null.** §1f's denominator is "completed with an
 *   arrival mark", and nothing in the booking machine records an arrival or
 *   says who would. Ledger row P11-1. Null is "no denominator", which is
 *   exactly true; a zero would be a lie.
 * - **Price adherence** — of the bookings completed in the window that carry
 *   an agreed amount (a callback, at zero by definition, excluded): those
 *   where the final amount did not exceed the agreed amount **and** the
 *   provider never proposed raising the price. §1h: "every amendment attempt
 *   is recorded, accepted or not, and feeds price adherence … a provider who
 *   routinely revises upward on site has a number that says so." A null
 *   `finalAmount` outside emergency means the agreed amount stood (§Phase 17.1).
 * - **Acceptance** — accepted ÷ (accepted + declined), **explicit responses
 *   only**, on bookings that targeted this provider: a slot booking's
 *   `accept`/`decline`, a request's `offer-quote`/`decline` (a callback
 *   included — declining one is how §1h's "counts against conduct" lands
 *   here, ledger P17-11). Timeouts are excluded (§1f). An emergency broadcast
 *   is excluded on both sides: §0.0 rules that a pass "does not touch the
 *   acceptance rate", and counting the offers but not the passes would only
 *   ever inflate it.
 * - **Median response time** — over those same explicit responses, seconds
 *   from the prompt (creation, or the customer's pre-accept reschedule, which
 *   restarts the accept clock) to the answer.
 *
 * Payment-claim outcomes feed nothing (§1f, Round 24): no definition above
 * reads an attestation, a withdrawal or `payment_unresolved`.
 */

export const CONDUCT_WINDOW_DAYS = 90;
const WINDOW_MS = CONDUCT_WINDOW_DAYS * 24 * 60 * 60_000;

/** The explicit responses §1f's acceptance rate and median response time read. */
const ACCEPTING_RESPONSES = new Set(['accept', 'offer-quote']);
const DECLINING_RESPONSES = new Set(['decline']);

/** What one booking contributed — the provider's evidence list, one row per booking. */
export interface ConductEvidence {
  bookingId: string;
  reference: string;
  listingId: string;
  listingName: string;
  bookingMode: 'slot' | 'request' | 'emergency';
  completed: boolean;
  /** Reached `accepted` inside the window — the cohort cancellation and no-show are rates of. */
  acceptedInWindow: boolean;
  providerCancelled: boolean;
  noShow: boolean;
  /** Null when the booking is not in price adherence's denominator. */
  priceAdherent: boolean | null;
  /** Null when there was no explicit response in the window. */
  response: 'accepted' | 'declined' | null;
  responseSeconds: number | null;
  /** When the booking last did something that counted — the order the list is shown in. */
  countedAt: Date;
}

export interface ConductComputation {
  record: ProviderConductRecord;
  evidence: ConductEvidence[];
}

const BOOKING_FIELDS = {
  id: true,
  reference: true,
  listingId: true,
  listing: { select: { name: true } },
  bookingMode: true,
  createdAt: true,
  rescheduledAt: true,
  completedAt: true,
  cancelledAt: true,
  cancelledByRole: true,
  completionPromptedAt: true,
  disputeOutcome: true,
  disputeResolvedAt: true,
  agreedAmountLaari: true,
  finalAmountLaari: true,
  amountKind: true,
  statusHistory: {
    select: { toStatus: true, transition: true, actorRole: true, createdAt: true },
    orderBy: { createdAt: 'asc' },
  },
  amendments: {
    select: { proposedByRole: true, previousAmountLaari: true, proposedAmountLaari: true },
  },
  emergencyOffer: { select: { state: true, closedAt: true } },
  reports: { select: { reason: true, reporterId: true } },
} as const satisfies Prisma.BookingSelect;

type Row = Prisma.BookingGetPayload<{ select: typeof BOOKING_FIELDS }>;

export async function computeConduct(
  db: Prisma.TransactionClient,
  providerProfileId: string,
  asOf: Date,
): Promise<ConductComputation> {
  const start = new Date(asOf.getTime() - WINDOW_MS);
  const counted = { providerProfileId, conductExcludedAt: null } as const;

  const [jobsCompletedCount, rows] = await Promise.all([
    db.booking.count({ where: { ...counted, completedAt: { not: null, lte: asOf } } }),
    // Every booking that did anything inside the window. Each outcome below
    // is a status event, so "has an event in the window" is a superset of
    // "contributed to something", and the per-metric checks narrow it.
    db.booking.findMany({
      where: {
        ...counted,
        statusHistory: { some: { createdAt: { gte: start, lte: asOf } } },
      },
      select: BOOKING_FIELDS,
    }),
  ]);

  const inWindow = (at: Date | null | undefined): at is Date =>
    at !== null && at !== undefined && at >= start && at <= asOf;

  const evidence: ConductEvidence[] = [];
  for (const row of rows) {
    const e = contribution(row, inWindow);
    if (e !== null) evidence.push(e);
  }

  const completed = evidence.filter((e) => e.completed).length;
  const cancelledInWindow = evidence.filter((e) => e.providerCancelled).length;
  const noShowsInWindow = evidence.filter((e) => e.noShow).length;
  const cohort = rows.filter((r) => inWindow(acceptedAt(r)));
  const cohortCancelled = cohort.filter((r) => isProviderCancelled(r)).length;
  const cohortNoShows = cohort.filter((r) => noShowAt(r) !== null).length;
  const priced = evidence.filter((e) => e.priceAdherent !== null);
  const responses = evidence.filter((e) => e.response !== null);
  const responseSeconds = evidence
    .map((e) => e.responseSeconds)
    .filter((s): s is number => s !== null);

  return {
    record: {
      jobsCompletedCount,
      completedInWindow: completed,
      completionRate: ratio(completed, completed + cancelledInWindow + noShowsInWindow),
      cancellationRate: ratio(cohortCancelled, cohort.length),
      noShowRate: ratio(cohortNoShows, cohort.length),
      onTimeRate: null,
      priceAdherenceRate: ratio(priced.filter((e) => e.priceAdherent).length, priced.length),
      acceptanceRate: ratio(
        responses.filter((e) => e.response === 'accepted').length,
        responses.length,
      ),
      medianResponseSeconds: median(responseSeconds),
    },
    evidence: evidence.sort(
      (a, b) =>
        b.countedAt.getTime() - a.countedAt.getTime() || b.bookingId.localeCompare(a.bookingId),
    ),
  };
}

function contribution(
  row: Row,
  inWindow: (at: Date | null | undefined) => at is Date,
): ConductEvidence | null {
  const moments: Date[] = [];

  const completed = inWindow(row.completedAt);
  if (inWindow(row.completedAt)) moments.push(row.completedAt);

  const providerCancelled = isProviderCancelled(row) && inWindow(row.cancelledAt);
  if (providerCancelled && inWindow(row.cancelledAt)) moments.push(row.cancelledAt);

  const noShowMoment = noShowAt(row);
  const noShow = inWindow(noShowMoment);
  if (inWindow(noShowMoment)) moments.push(noShowMoment);

  const accepted = acceptedAt(row);
  const acceptedInWindow = inWindow(accepted);
  if (inWindow(accepted)) moments.push(accepted);

  let priceAdherent: boolean | null = null;
  if (completed && row.agreedAmountLaari !== null && row.amountKind !== 'callback') {
    const agreed = row.agreedAmountLaari;
    const final = row.finalAmountLaari ?? agreed;
    const raised = row.amendments.some(
      (a) =>
        a.proposedByRole === 'provider' &&
        a.proposedAmountLaari !== null &&
        a.previousAmountLaari !== null &&
        a.proposedAmountLaari > a.previousAmountLaari,
    );
    priceAdherent = final <= agreed && !raised;
  }

  let response: 'accepted' | 'declined' | null = null;
  let responseSeconds: number | null = null;
  if (row.bookingMode !== 'emergency') {
    const answer = row.statusHistory.find(
      (ev) =>
        ev.actorRole === 'provider' &&
        (ACCEPTING_RESPONSES.has(ev.transition) || DECLINING_RESPONSES.has(ev.transition)),
    );
    if (answer !== undefined && inWindow(answer.createdAt)) {
      response = ACCEPTING_RESPONSES.has(answer.transition) ? 'accepted' : 'declined';
      const prompt =
        row.rescheduledAt !== null && row.rescheduledAt < answer.createdAt
          ? row.rescheduledAt
          : row.createdAt;
      responseSeconds = Math.max(
        0,
        Math.round((answer.createdAt.getTime() - prompt.getTime()) / 1000),
      );
      moments.push(answer.createdAt);
    }
  }

  if (moments.length === 0) return null;
  return {
    bookingId: row.id,
    reference: row.reference,
    listingId: row.listingId,
    listingName: row.listing.name ?? '',
    bookingMode: row.bookingMode,
    completed,
    acceptedInWindow,
    providerCancelled,
    noShow,
    priceAdherent,
    response,
    responseSeconds,
    countedAt: new Date(Math.max(...moments.map((m) => m.getTime()))),
  };
}

/** When the booking first reached `accepted` — by `accept`, `approve-quote` or `select-offer` alike. */
function acceptedAt(row: Row): Date | null {
  return row.statusHistory.find((ev) => ev.toStatus === 'accepted')?.createdAt ?? null;
}

function isProviderCancelled(row: Row): boolean {
  return row.cancelledAt !== null && row.cancelledByRole === 'provider';
}

/**
 * When a no-show was confirmed, or null if this booking is not one. The two
 * sources are disjoint: an emergency no-show cancels the booking, and a
 * completion-prompt "No" disputes it — neither completes.
 */
function noShowAt(row: Row): Date | null {
  if (row.emergencyOffer?.state === 'no_show') return row.emergencyOffer.closedAt;
  const promptedNo =
    row.completionPromptedAt !== null &&
    row.completedAt === null &&
    row.reports.some((r) => r.reason === 'work_not_done' && r.reporterId !== null);
  if (promptedNo && row.disputeOutcome === 'resolved_for_customer') return row.disputeResolvedAt;
  return null;
}

function ratio(numerator: number, denominator: number): number | null {
  return denominator === 0 ? null : numerator / denominator;
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  const upper = sorted[mid] ?? 0;
  return sorted.length % 2 === 1 ? upper : Math.round(((sorted[mid - 1] ?? 0) + upper) / 2);
}
