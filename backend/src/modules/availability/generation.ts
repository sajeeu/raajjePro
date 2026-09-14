import type { Clock } from '../../core/clock.js';
import {
  maldivesDateOf,
  maldivesDateOfColumn,
  startOfNextMaldivesDay,
} from '../../core/maldives-time.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import { expandSlots, SLOT_WINDOW_DAYS, windowEnd, type DesiredSlot } from './generator.js';
import type { AvailabilityRepository, Db } from './repository.js';

/**
 * **The wall-clock budget, stated (§Phase 9a).**
 *
 * One run may spend 5 seconds and touch at most 50 listings. Both bounds are
 * real: whichever it reaches first, the run stops, logs, and leaves the rest
 * for the next tick — nothing is lost, because `ListingSlotState` is a
 * durable work list rather than an in-memory queue.
 *
 * Why these numbers. At a 5-minute interval, 50 listings a run is 14,400 a
 * day, and the rolling horizon asks each listing for exactly one top-up a
 * day — so the steady state at a thousand providers is a few hundred
 * regenerations a day against a capacity of fourteen thousand. The budget is
 * not a throughput limit; it is a tripwire.
 *
 * And it is a tripwire because of a failure this repository has already had.
 * §Phase 8a's `runLifecycle` selected every subscription row and then did a
 * `findUnique` per candidate; it crossed five seconds on a laptop at a
 * thousand rows and was found only because a test began timing out four days
 * later. Slot generation is the bigger version of the same shape — 60 days,
 * per provider, per listing — so it was written narrow from the start
 * (`findGenerationCandidates` is the whole WHERE) and it says out loud how
 * long it is allowed to take.
 */
export const SLOT_GENERATION_BUDGET_MS = 5_000;
export const SLOT_GENERATION_BATCH = 50;

/** Logged per listing when one expansion alone is slow enough to be worth seeing. */
export const SLOW_LISTING_MS = 500;

export interface GenerationOutcome {
  listingId: string;
  created: number;
  removed: number;
  elapsedMs: number;
  /** False when the listing turned out to publish no slots at all — it is now dormant. */
  active: boolean;
}

export interface GenerationReport {
  considered: number;
  created: number;
  removed: number;
  elapsedMs: number;
  /** True when the run stopped on its budget with candidates still waiting. */
  overran: boolean;
  slowest: { listingId: string; elapsedMs: number } | null;
}

export interface GenerationLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

/**
 * Turns availability rules into `TimeSlot` rows over the 60-day rolling
 * window (§Phase 9a).
 *
 * ## What it may and may not touch
 *
 * §Phase 9a: "an availability-rule change regenerates **future unreserved
 * slots only** — reserved slots are never touched by a rule change." So every
 * read and write below is bounded by `startsAt > now` and by
 * `status !== 'reserved'`. A slot in the past is history; a reserved slot is
 * somebody's appointment. Neither is this job's business.
 *
 * ## Why it is safe to remove rows
 *
 * A future, unreserved slot is the *expansion of a rule*, not a record of
 * anything — the rule is soft-deleted and the reservation is never deleted.
 * `TimeSlot`'s schema comment and
 * `docs/decisions/24-phase-9a-availability-and-reservations.md` carry the
 * decision; it is a deliberate, bounded exception to invariant 8 and the only
 * one in this phase.
 */
export class SlotGenerator {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      clock: Clock;
      repo: AvailabilityRepository;
      log: GenerationLogger;
    },
  ) {}

  /**
   * Regenerates one listing.
   *
   * Six queries, whatever the size of the grid: the listing, its rules, its
   * exceptions, the provider's time off, the existing future slots, and one
   * delete plus one `createMany`. There is deliberately no per-slot or
   * per-day round trip — that is the shape that broke §Phase 8a's sweep.
   *
   * Takes an optional `Db` so a rule edit can run it **inside the same
   * transaction that saved the rule**. That is what makes "Save rules" atomic:
   * the provider never sees a saved rule whose grid has not caught up, and a
   * failure rolls the rule back rather than leaving the two disagreeing.
   */
  async generateForListing(listingId: string, now: Date, db?: Db): Promise<GenerationOutcome> {
    const startedAt = Date.now();
    const run = async (tx: Db): Promise<Omit<GenerationOutcome, 'elapsedMs' | 'listingId'>> => {
      const listing = await this.deps.repo.findListingForGeneration(listingId, tx);

      // A listing that has left slot mode, been deleted, or never had a rule
      // publishes nothing. Withdraw its future unreserved times and go
      // dormant, so `findGenerationCandidates` stops reading it entirely.
      if (listing === null) {
        return { ...(await this.withdrawAll(listingId, now, tx)), active: false };
      }
      if (listing.deletedAt !== null || listing.bookingMode !== 'slot') {
        return { ...(await this.withdrawAll(listingId, now, tx)), active: false };
      }

      const rules = await this.deps.repo.findRules(listingId, tx);
      if (rules.length === 0) {
        return { ...(await this.withdrawAll(listingId, now, tx)), active: false };
      }

      const exceptions = await this.deps.repo.findExceptions(listingId, tx);
      const timeOff = await this.deps.repo.findTimeOff(listing.providerProfileId, tx);

      const from = maldivesDateOf(now);
      const desired = expandSlots({
        rules,
        exceptions: exceptions.map((e) => ({
          startDate: maldivesDateOfColumn(e.startDate),
          endDate: maldivesDateOfColumn(e.endDate),
          startTime: e.startTime,
          endTime: e.endTime,
          slotDurationMinutes: e.slotDurationMinutes,
        })),
        timeOff: timeOff.map((t) => ({
          startDate: maldivesDateOfColumn(t.startDate),
          endDate: maldivesDateOfColumn(t.endDate),
        })),
        from,
        days: SLOT_WINDOW_DAYS,
        notBefore: now,
      });

      const { created, removed } = await this.reconcile(listing, desired, now, tx);

      await this.deps.repo.recordGeneration(
        listingId,
        {
          // The horizon advances a day at a time, so the next thing this
          // listing needs is one top-up at the next Maldives midnight.
          // Anything sooner is a change, and a change sets this to now.
          nextGenerationAt: startOfNextMaldivesDay(now),
          generatedThrough: windowEnd(from, SLOT_WINDOW_DAYS),
          lastGeneratedAt: now,
          lastRunMs: Date.now() - startedAt,
        },
        tx,
      );
      return { created, removed, active: true };
    };

    const result = db === undefined ? await this.deps.prisma.$transaction(run) : await run(db);
    const elapsedMs = Date.now() - startedAt;
    if (elapsedMs >= SLOW_LISTING_MS) {
      this.deps.log.warn({ listingId, elapsedMs }, 'slot generation for one listing was slow');
    }
    return { listingId, elapsedMs, ...result };
  }

  /**
   * The scheduled sweep: incremental and per-listing, never a global pass.
   *
   * The candidate query is the entire condition — one indexed range scan over
   * `next_generation_at` — so a listing with nothing to do is never read.
   */
  async run(now: Date): Promise<GenerationReport> {
    const startedAt = Date.now();
    const candidates = await this.deps.repo.findGenerationCandidates(
      now,
      SLOT_GENERATION_BATCH,
      this.deps.prisma,
    );

    const report: GenerationReport = {
      considered: 0,
      created: 0,
      removed: 0,
      elapsedMs: 0,
      overran: false,
      slowest: null,
    };

    for (const candidate of candidates) {
      if (Date.now() - startedAt >= SLOT_GENERATION_BUDGET_MS) {
        report.overran = true;
        break;
      }
      const outcome = await this.generateForListing(candidate.listingId, now);
      report.considered += 1;
      report.created += outcome.created;
      report.removed += outcome.removed;
      if (report.slowest === null || outcome.elapsedMs > report.slowest.elapsedMs) {
        report.slowest = { listingId: outcome.listingId, elapsedMs: outcome.elapsedMs };
      }
    }

    report.elapsedMs = Date.now() - startedAt;
    if (report.overran) {
      // §Phase 9a: "a stated wall-clock budget and a §Phase 21 alert on
      // overrun". This is the signal that alert reads; §Phase 21 gives it a
      // destination. It is a warning rather than an error because the work is
      // not lost — the next tick resumes from the same work list.
      this.deps.log.warn(
        {
          event: 'slot_generation_overrun',
          budgetMs: SLOT_GENERATION_BUDGET_MS,
          elapsedMs: report.elapsedMs,
          processed: report.considered,
          batch: SLOT_GENERATION_BATCH,
          slowest: report.slowest,
        },
        'slot generation exceeded its wall-clock budget',
      );
    }
    return report;
  }

  /** Everything future and unreserved goes; the listing stops being a candidate. */
  private async withdrawAll(
    listingId: string,
    now: Date,
    tx: Db,
  ): Promise<{ created: number; removed: number }> {
    const existing = await this.deps.repo.findFutureSlots(listingId, now, tx);
    const ids = existing.filter((s) => s.status !== 'reserved').map((s) => s.id);
    const { count } = ids.length === 0 ? { count: 0 } : await this.deps.repo.deleteSlots(ids, tx);
    await this.deps.repo.recordGeneration(
      listingId,
      { nextGenerationAt: null, generatedThrough: null, lastGeneratedAt: now, lastRunMs: 0 },
      tx,
    );
    return { created: 0, removed: count };
  }

  /**
   * Brings the stored grid to the desired one.
   *
   * Delete before insert, because a duration change produces a *different*
   * slot at the *same* `startsAt` and the unique index would otherwise make
   * `skipDuplicates` silently keep the old length.
   *
   * A `blocked` slot that the rules still produce survives both steps — it is
   * not in the delete set, and `skipDuplicates` leaves it alone — so an
   * individual override outlives an unrelated rule edit. One that the rules no
   * longer produce goes with everything else, which is what §Phase 9a's
   * "future unreserved slots" says and what the save sheet promises: "Only
   * future, unbooked times change."
   */
  private async reconcile(
    listing: { id: string; providerProfileId: string },
    desired: DesiredSlot[],
    now: Date,
    tx: Db,
  ): Promise<{ created: number; removed: number }> {
    const existing = await this.deps.repo.findFutureSlots(listing.id, now, tx);
    const desiredKeys = new Set(desired.map(keyOf));
    const existingKeys = new Set(existing.map(keyOf));

    const staleIds = existing
      .filter((slot) => slot.status !== 'reserved' && !desiredKeys.has(keyOf(slot)))
      .map((slot) => slot.id);
    const removed =
      staleIds.length === 0 ? 0 : (await this.deps.repo.deleteSlots(staleIds, tx)).count;

    const fresh = desired.filter((slot) => !existingKeys.has(keyOf(slot)));
    const created =
      fresh.length === 0
        ? 0
        : (
            await this.deps.repo.createSlots(
              fresh.map((slot) => ({
                providerProfileId: listing.providerProfileId,
                listingId: listing.id,
                startsAt: slot.startsAt,
                endsAt: slot.endsAt,
              })),
              tx,
            )
          ).count;

    return { created, removed };
  }
}

/** A slot's identity for reconciliation: when it starts *and* how long it runs. */
function keyOf(slot: { startsAt: Date; endsAt: Date }): string {
  return `${String(slot.startsAt.getTime())}:${String(slot.endsAt.getTime())}`;
}
