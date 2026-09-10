import type { Clock } from '../../core/clock.js';
import type { ListingEventKind, PrismaClient } from '../../generated/prisma/client.js';

/**
 * The listing event log and its rollup (§Phase 8: "view and booking counts
 * come from an event log with periodic rollup, not per-request counter
 * writes").
 *
 * ## Why not just increment a counter
 *
 * `UPDATE listing SET view_count = view_count + 1` takes a row lock. On the
 * one listing everybody is looking at — the popular one, which is precisely
 * the one being viewed concurrently — every reader queues behind every other
 * reader on a write they did not ask for. An append has no such contention.
 *
 * ## Why the rows stay
 *
 * §1b's downgrade rule keeps "the highest-performing" unprotected listing,
 * "ranked by confirmed bookings over the trailing 90 days, falling back to
 * listing views". That is a **windowed** question and a counter cannot answer
 * it — a counter knows the total and nothing about when. The log is what
 * makes Phase 8a's rule computable at all, which is why the rollup adds to
 * the counters rather than replacing the rows with them.
 *
 * ## No PII
 *
 * A listing id, a kind and a time (root CLAUDE.md 1d: event metadata
 * references IDs, never raw values). There is deliberately no viewer column
 * — nothing in this phase needs one, and a viewer id on an impression log is
 * easy to add now and hard to justify to anybody later.
 */
export class ListingEvents {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  /**
   * Who may call: any module that has already decided the event happened.
   * This does not authorize and does not check visibility — it records.
   *
   * §Phase 12's Service Preview records the view and §Phase 17 records the
   * booking; neither exists yet, which is why nothing in this phase calls
   * `record('view')` from a route. The log, the rollup and the counters are
   * built and tested now because §Phase 8's bullet is where they belong.
   */
  async record(listingId: string, kind: ListingEventKind): Promise<void> {
    await this.prisma.listingEvent.create({
      data: { listingId, kind, occurredAt: this.clock() },
    });
  }

  /**
   * Folds every event since each listing's watermark into its counters.
   *
   * **The window is half-open: `[watermark, now)`.** Both ends matter and
   * getting either wrong loses events silently.
   *
   *   - **Inclusive at the watermark.** The watermark is the previous run's
   *     `now`, so an event stamped at exactly that instant belongs to *this*
   *     run. An exclusive low bound drops it forever — which is not
   *     theoretical: the first version of this method had it, and the very
   *     first test that recorded an event and rolled up twice caught two
   *     events becoming one.
   *   - **Exclusive at `now`, and `now` is captured once for the whole
   *     run.** An event written *during* the sweep is counted by the next
   *     run rather than half-counted by this one, and one `now` for every
   *     listing means there is no gap between one listing's high bound and
   *     another's low bound.
   *
   * Idempotent by construction rather than by luck: the first run moves the
   * watermark past everything it counted, and the half-open window means the
   * second run's range starts exactly where the first one stopped.
   */
  async rollUp(
    now: Date = this.clock(),
  ): Promise<{ listingsUpdated: number; eventsCounted: number }> {
    // Only listings with something waiting. `groupBy` over the unrolled
    // window is one query for the whole sweep, rather than one per listing.
    const pending = await this.prisma.$queryRaw<
      { listing_id: string; kind: ListingEventKind; count: bigint }[]
    >`
      SELECT e.listing_id, e.kind, count(*) AS count
      FROM listing_event e
      JOIN listing l ON l.id = e.listing_id
      WHERE e.occurred_at < ${now}
        AND (l.counts_rolled_up_at IS NULL OR e.occurred_at >= l.counts_rolled_up_at)
      GROUP BY e.listing_id, e.kind`;

    const byListing = new Map<string, { view: number; booking: number }>();
    for (const row of pending) {
      const entry = byListing.get(row.listing_id) ?? { view: 0, booking: 0 };
      entry[row.kind] += Number(row.count);
      byListing.set(row.listing_id, entry);
    }

    let eventsCounted = 0;
    for (const [listingId, counts] of byListing) {
      eventsCounted += counts.view + counts.booking;
      await this.prisma.listing.update({
        where: { id: listingId },
        data: {
          viewCount: { increment: counts.view },
          bookingCount: { increment: counts.booking },
          countsRolledUpAt: now,
        },
      });
    }

    // Listings whose watermark is behind but which had no events in the
    // window are left alone: moving the watermark for them costs a write and
    // changes nothing, and a null watermark on a listing that has never been
    // viewed is the truthful state.
    return { listingsUpdated: byListing.size, eventsCounted };
  }
}
