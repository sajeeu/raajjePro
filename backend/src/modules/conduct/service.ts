import type { Clock } from '../../core/clock.js';
import { ConflictError, NotFoundError } from '../../core/errors.js';
import type {
  Prisma,
  PrismaClient,
  ProviderConductSnapshot,
} from '../../generated/prisma/client.js';
import type { AuditService } from '../audit/service.js';
import type { ProviderConductRecord, ProviderConductSource } from '../providers/conduct.js';
import { computeConduct, type ConductEvidence } from './compute.js';
import type { ConductEvidenceDto } from './types.js';

type Db = PrismaClient | Prisma.TransactionClient;

export interface ConductServiceDeps {
  prisma: PrismaClient;
  clock: Clock;
  audit: AuditService;
}

/** How long a snapshot may go unrecomputed before the window has moved enough to matter. */
const ROLL_AFTER_MS = 24 * 60 * 60_000;

/**
 * §Phase 11's conduct metrics: "recomputed on booking terminal transitions
 * rather than on read".
 *
 * ## How a transition reaches the numbers
 *
 * `BookingRepository.recordStatusEvent` is the one writer of every status
 * event in the booking machine. On a terminal one it calls `markStale`
 * **inside the booking's own transaction**, which upserts this provider's
 * snapshot row with `staleSince` — so the mark commits with the transition or
 * not at all, and no terminal transition can be missed.
 *
 * The `conduct-recompute` job then recomputes every stale snapshot. It does
 * so under the snapshot's row lock, which the marking transaction also took:
 * a booking transaction still in flight makes the recompute wait for its
 * commit, and one that starts afterwards re-marks the row. The computation
 * therefore always reads every transition that marked it.
 *
 * Why a job and not inline: the marking point is the status event, and some
 * transitions write their other evidence *after* it in the same transaction —
 * `markNotArrived` closes the offer as `no_show` after the event. Computing
 * at the event would read the booking half-written. The job also does the
 * other half of a rolling window: once a day every snapshot is recomputed
 * whether or not anything happened, because a booking ageing out of 90 days
 * is a change with no transition at all.
 *
 * ## The public read
 *
 * `metricsFor` is §Phase 5's `ProviderConductSource`, the seam ledger row
 * P5-2 was opened for. It reads snapshots and nothing else; the display rules
 * — numbers only, the ten-booking floor, the provider first — are Phase 5's
 * and unchanged.
 */
export class ConductService implements ProviderConductSource {
  private readonly prisma: PrismaClient;
  private readonly clock: Clock;
  private readonly audit: AuditService;

  constructor(deps: ConductServiceDeps) {
    this.prisma = deps.prisma;
    this.clock = deps.clock;
    this.audit = deps.audit;
  }

  /** Called by the booking repository on every terminal status event, inside its transaction. */
  async markStale(db: Db, bookingId: string, at: Date): Promise<void> {
    const booking = await db.booking.findUnique({
      where: { id: bookingId },
      select: { providerProfileId: true },
    });
    if (booking === null) return;
    await db.providerConductSnapshot.upsert({
      where: { providerProfileId: booking.providerProfileId },
      create: { providerProfileId: booking.providerProfileId, staleSince: at },
      update: { staleSince: at },
    });
  }

  /**
   * The job's body: every stale snapshot, then every snapshot the window has
   * moved under. Each provider is its own transaction, so one failure costs
   * one provider and is retried on the next run.
   */
  async recomputeDue(now: Date): Promise<{ recomputed: number }> {
    const due = await this.prisma.providerConductSnapshot.findMany({
      where: {
        OR: [
          { staleSince: { not: null } },
          { computedAt: null },
          { computedAt: { lt: new Date(now.getTime() - ROLL_AFTER_MS) } },
        ],
      },
      select: { providerProfileId: true },
    });
    for (const { providerProfileId } of due) {
      await this.recompute(providerProfileId, now);
    }
    return { recomputed: due.length };
  }

  async recompute(providerProfileId: string, now: Date): Promise<void> {
    await this.prisma.$transaction((tx) => this.recomputeIn(tx, providerProfileId, now));
  }

  /** Lock first, then read: see the class comment for why the order is the guarantee. */
  private async recomputeIn(
    tx: Prisma.TransactionClient,
    providerProfileId: string,
    now: Date,
  ): Promise<void> {
    await tx.providerConductSnapshot.upsert({
      where: { providerProfileId },
      create: { providerProfileId },
      update: { updatedAt: now },
    });
    const { record } = await computeConduct(tx, providerProfileId, now);
    await tx.providerConductSnapshot.update({
      where: { providerProfileId },
      data: {
        jobsCompletedCount: record.jobsCompletedCount,
        completedInWindow: record.completedInWindow,
        completionRateBp: toBp(record.completionRate),
        cancellationRateBp: toBp(record.cancellationRate),
        noShowRateBp: toBp(record.noShowRate),
        onTimeRateBp: toBp(record.onTimeRate),
        priceAdherenceRateBp: toBp(record.priceAdherenceRate),
        acceptanceRateBp: toBp(record.acceptanceRate),
        medianResponseSeconds: record.medianResponseSeconds,
        computedAt: now,
        staleSince: null,
      },
    });
  }

  // -- ProviderConductSource (§Phase 5's seam) -----------------------------

  async metricsFor(providerIds: string[]): Promise<Map<string, ProviderConductRecord>> {
    if (providerIds.length === 0) return new Map();
    const rows = await this.prisma.providerConductSnapshot.findMany({
      where: { providerProfileId: { in: providerIds }, computedAt: { not: null } },
    });
    return new Map(rows.map((row) => [row.providerProfileId, toRecord(row)]));
  }

  // -- The provider's own evidence -----------------------------------------

  /**
   * `GET /v1/providers/me/conduct/bookings` — §1f: "Every metric is visible
   * to the provider on their own dashboard before it is visible to anyone
   * else, **with the underlying bookings listed**."
   *
   * Computed against the snapshot's own `computedAt`, so the list is exactly
   * the bookings behind the numbers `GET /v1/providers/me` shows — not a
   * fresher set that would disagree with them. Before the first computation
   * there are no numbers and the list is empty.
   *
   * This reads booking records, it does not compute a displayed number, so it
   * is not the check-on-read §Phase 11 rules out.
   */
  async evidenceFor(
    userId: string,
    paging: { limit: number; cursor?: string | undefined },
  ): Promise<{
    items: ConductEvidenceDto[];
    nextCursor: string | null;
    computedAt: string | null;
  }> {
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true, conductSnapshot: { select: { computedAt: true } } },
    });
    if (profile === null)
      throw new NotFoundError('No provider profile', 'PROVIDER_PROFILE_NOT_FOUND');
    const asOf = profile.conductSnapshot?.computedAt ?? null;
    if (asOf === null) return { items: [], nextCursor: null, computedAt: null };

    const { evidence } = await this.prisma.$transaction((tx) =>
      computeConduct(tx, profile.id, asOf),
    );
    const offset = paging.cursor === undefined ? 0 : decodeOffset(paging.cursor);
    const page = evidence.slice(offset, offset + paging.limit);
    const next = offset + paging.limit;
    return {
      items: page.map(toEvidenceDto),
      nextCursor: next < evidence.length ? encodeOffset(next) : null,
      computedAt: asOf.toISOString(),
    };
  }

  // -- §1f's appeal outcome --------------------------------------------------

  /**
   * §1f: "a booking excluded on appeal is excluded from the aggregate and
   * audit-logged." §Phase 22 builds the appeal queue; this is the outcome it
   * reaches. Reversible (invariant 1d), and the snapshot is recomputed in the
   * same transaction so the provider sees the change immediately.
   */
  async setExcluded(
    bookingId: string,
    adminId: string,
    reason: string,
    exclude: boolean,
    meta: { requestId?: string | null; ipAddress?: string | null } = {},
  ): Promise<{ bookingId: string; excluded: boolean }> {
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      const booking = await tx.booking.findUnique({
        where: { id: bookingId },
        select: { providerProfileId: true },
      });
      if (booking === null) throw new NotFoundError('No such booking');
      const { count } = await tx.booking.updateMany({
        where: { id: bookingId, conductExcludedAt: exclude ? null : { not: null } },
        data: exclude
          ? { conductExcludedAt: now, conductExcludedByAdminId: adminId }
          : { conductExcludedAt: null, conductExcludedByAdminId: null },
      });
      if (count === 0) {
        throw new ConflictError(
          exclude ? 'BOOKING_ALREADY_EXCLUDED' : 'BOOKING_NOT_EXCLUDED',
          exclude
            ? 'This booking is already excluded from conduct'
            : 'This booking is not excluded from conduct',
        );
      }
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: exclude ? 'booking.conduct_excluded' : 'booking.conduct_included',
        targetType: 'booking',
        targetId: bookingId,
        reason,
        metadata: { providerProfileId: booking.providerProfileId },
        requestId: meta.requestId ?? null,
        ipAddress: meta.ipAddress ?? null,
      });
      await this.recomputeIn(tx, booking.providerProfileId, now);
    });
    return { bookingId, excluded: exclude };
  }
}

function toBp(rate: number | null): number | null {
  return rate === null ? null : Math.round(rate * 10_000);
}

function fromBp(bp: number | null): number | null {
  return bp === null ? null : bp / 10_000;
}

function toRecord(row: ProviderConductSnapshot): ProviderConductRecord {
  return {
    jobsCompletedCount: row.jobsCompletedCount,
    completedInWindow: row.completedInWindow,
    completionRate: fromBp(row.completionRateBp),
    cancellationRate: fromBp(row.cancellationRateBp),
    noShowRate: fromBp(row.noShowRateBp),
    onTimeRate: fromBp(row.onTimeRateBp),
    priceAdherenceRate: fromBp(row.priceAdherenceRateBp),
    acceptanceRate: fromBp(row.acceptanceRateBp),
    medianResponseSeconds: row.medianResponseSeconds,
  };
}

function toEvidenceDto(e: ConductEvidence): ConductEvidenceDto {
  return {
    bookingId: e.bookingId,
    reference: e.reference,
    listingId: e.listingId,
    listingName: e.listingName,
    bookingMode: e.bookingMode,
    completed: e.completed,
    acceptedInWindow: e.acceptedInWindow,
    providerCancelled: e.providerCancelled,
    noShow: e.noShow,
    priceAdherent: e.priceAdherent,
    response: e.response,
    responseSeconds: e.responseSeconds,
    countedAt: e.countedAt.toISOString(),
  };
}

function encodeOffset(offset: number): string {
  return Buffer.from(String(offset)).toString('base64url');
}

function decodeOffset(cursor: string): number {
  const n = Number(Buffer.from(cursor, 'base64url').toString('utf8'));
  return Number.isInteger(n) && n >= 0 ? n : 0;
}
