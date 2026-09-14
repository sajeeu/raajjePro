import { PUBLICLY_VISIBLE_LISTING } from '../listings/visibility.js';
import type {
  AvailabilityException,
  AvailabilityRule,
  ListingSlotState,
  Prisma,
  PrismaClient,
  ProviderTimeOff,
  Reservation,
  ReservationReleaseReason,
  TimeSlot,
} from '../../generated/prisma/client.js';

/** A transaction or the client. Every write takes one so a caller can compose it into their own. */
export type Db = PrismaClient | Prisma.TransactionClient;

/** One projection, two readers — so the owner's view and the public one cannot drift apart. */
const LISTING_FIELDS = {
  id: true,
  providerProfileId: true,
  bookingMode: true,
  status: true,
  visibility: true,
  deletedAt: true,
  workingDays: true,
  workingHoursFrom: true,
  workingHoursTo: true,
  category: { select: { id: true, name: true, minimumLeadTimeMinutes: true } },
} as const satisfies Prisma.ListingSelect;

/**
 * §Phase 9a's data access. Nothing here decides anything — the rules live in
 * `service.ts` and the calendar arithmetic in `generator.ts`.
 *
 * Two queries in this file are the ones worth reading carefully:
 * `findGenerationCandidates`, which is the narrow work-list query the phase
 * brief asks for, and `findExpiredProvisionalHolds`, which is the same shape
 * for the quote sweep.
 */
export class AvailabilityRepository {
  constructor(private readonly prisma: PrismaClient) {}

  // -- The listing this availability belongs to -----------------------------

  /**
   * The four columns generation and authorization actually need.
   *
   * A narrow `select` rather than the whole row, and read here rather than
   * through `ListingService`, for the same reason §Phase 8a reads `listing`
   * directly: this module owns a listing's *availability*, the question is
   * "may this produce slots", and routing it through another service's
   * business logic would put a publish gate in the middle of a scheduled job.
   */
  findListingForGeneration(id: string, db: Db = this.prisma) {
    return db.listing.findUnique({
      where: { id },
      select: { id: true, providerProfileId: true, bookingMode: true, deletedAt: true },
    });
  }

  /** The owner's listing, plus the category numbers §1c reads per category. */
  findListingWithCategory(id: string, db: Db = this.prisma) {
    return db.listing.findUnique({
      where: { id },
      select: LISTING_FIELDS,
    });
  }

  /**
   * The same listing, but only if a customer is allowed to see it.
   *
   * `PUBLICLY_VISIBLE_LISTING` is **composed, never restated** — §Phase 8's
   * visibility module makes the point that a consumer writing
   * `status: 'published'` on its own has already lost the deleted case, and
   * the picker is exactly such a consumer. The provider half of §1a's rule
   * is not here: that is `ProviderVisibility.isVisible`, the one shared
   * helper, and the service calls it rather than adding a suspension clause
   * of its own.
   */
  findPublicListingWithCategory(id: string, db: Db = this.prisma) {
    return db.listing.findFirst({
      where: { id, ...PUBLICLY_VISIBLE_LISTING },
      select: LISTING_FIELDS,
    });
  }

  // -- Rules ---------------------------------------------------------------

  /** The generator's read, and the provider's list. Ordered so expansion is deterministic. */
  findRules(listingId: string, db: Db = this.prisma): Promise<AvailabilityRule[]> {
    return db.availabilityRule.findMany({
      where: { listingId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });
  }

  findRule(id: string, listingId: string, db: Db = this.prisma): Promise<AvailabilityRule | null> {
    // Ownership is in the WHERE, so another listing's rule is *not found*
    // rather than found and refused — the same posture as `findOwnedSubmission`.
    return db.availabilityRule.findFirst({ where: { id, listingId, deletedAt: null } });
  }

  createRule(
    data: Prisma.AvailabilityRuleUncheckedCreateInput,
    db: Db = this.prisma,
  ): Promise<AvailabilityRule> {
    return db.availabilityRule.create({ data });
  }

  updateRule(
    id: string,
    data: Prisma.AvailabilityRuleUncheckedUpdateInput,
    db: Db = this.prisma,
  ): Promise<AvailabilityRule> {
    return db.availabilityRule.update({ where: { id }, data });
  }

  // -- Exceptions ("modified hours") ---------------------------------------

  findExceptions(listingId: string, db: Db = this.prisma): Promise<AvailabilityException[]> {
    return db.availabilityException.findMany({
      where: { listingId, deletedAt: null },
      orderBy: { startDate: 'asc' },
    });
  }

  findException(
    id: string,
    listingId: string,
    db: Db = this.prisma,
  ): Promise<AvailabilityException | null> {
    return db.availabilityException.findFirst({ where: { id, listingId, deletedAt: null } });
  }

  createException(
    data: Prisma.AvailabilityExceptionUncheckedCreateInput,
    db: Db = this.prisma,
  ): Promise<AvailabilityException> {
    return db.availabilityException.create({ data });
  }

  softDeleteException(id: string, at: Date, db: Db = this.prisma): Promise<AvailabilityException> {
    return db.availabilityException.update({ where: { id }, data: { deletedAt: at } });
  }

  softDeleteRule(id: string, at: Date, db: Db = this.prisma): Promise<AvailabilityRule> {
    return db.availabilityRule.update({ where: { id }, data: { deletedAt: at } });
  }

  // -- Time away -----------------------------------------------------------

  findTimeOff(providerProfileId: string, db: Db = this.prisma): Promise<ProviderTimeOff[]> {
    return db.providerTimeOff.findMany({
      where: { providerProfileId, deletedAt: null },
      orderBy: { startDate: 'asc' },
    });
  }

  findOneTimeOff(
    id: string,
    providerProfileId: string,
    db: Db = this.prisma,
  ): Promise<ProviderTimeOff | null> {
    return db.providerTimeOff.findFirst({ where: { id, providerProfileId, deletedAt: null } });
  }

  createTimeOff(
    data: Prisma.ProviderTimeOffUncheckedCreateInput,
    db: Db = this.prisma,
  ): Promise<ProviderTimeOff> {
    return db.providerTimeOff.create({ data });
  }

  softDeleteTimeOff(id: string, at: Date, db: Db = this.prisma): Promise<ProviderTimeOff> {
    return db.providerTimeOff.update({ where: { id }, data: { deletedAt: at } });
  }

  // -- Slots ---------------------------------------------------------------

  /** Every slot the generator may replace: this listing, strictly in the future. */
  findFutureSlots(listingId: string, after: Date, db: Db = this.prisma): Promise<TimeSlot[]> {
    return db.timeSlot.findMany({
      where: { listingId, startsAt: { gt: after } },
      orderBy: { startsAt: 'asc' },
    });
  }

  findSlotsInRange(
    listingId: string,
    from: Date,
    to: Date,
    db: Db = this.prisma,
  ): Promise<TimeSlot[]> {
    return db.timeSlot.findMany({
      where: { listingId, startsAt: { gte: from, lt: to } },
      orderBy: { startsAt: 'asc' },
    });
  }

  /**
   * The customer picker's read, and the reason §Phase 9a calls the
   * already-passed rule "a query-time guarantee, not something that depends
   * on job timing": `startsAt > bookableFrom` is in the WHERE, so a slot whose
   * time went by a minute ago is gone from the answer whether or not any job
   * has run.
   */
  findOpenSlots(
    listingId: string,
    bookableFrom: Date,
    until: Date,
    db: Db = this.prisma,
  ): Promise<TimeSlot[]> {
    return db.timeSlot.findMany({
      where: { listingId, status: 'open', startsAt: { gt: bookableFrom, lt: until } },
      orderBy: { startsAt: 'asc' },
    });
  }

  findSlot(id: string, db: Db = this.prisma): Promise<TimeSlot | null> {
    return db.timeSlot.findUnique({ where: { id } });
  }

  createSlots(
    rows: Prisma.TimeSlotCreateManyInput[],
    db: Db = this.prisma,
  ): Promise<{ count: number }> {
    // `skipDuplicates` against the `(listingId, startsAt)` unique index is
    // what makes re-running generation a no-op (§Phase 9a: "re-running
    // changes nothing"). See the schema comment on that index for why it is
    // not, and must not be mistaken for, the double-booking guard.
    return db.timeSlot.createMany({ data: rows, skipDuplicates: true });
  }

  deleteSlots(ids: string[], db: Db = this.prisma): Promise<{ count: number }> {
    // The one place in this codebase that removes rows rather than stamping a
    // column, and only ever for **future, unreserved** slots the caller has
    // already filtered. `TimeSlot`'s schema comment carries the reasoning and
    // `docs/decisions/24-phase-9a-availability-and-reservations.md` records
    // the decision as an explicit, bounded exception to invariant 8.
    return db.timeSlot.deleteMany({ where: { id: { in: ids } } });
  }

  /**
   * Claims a slot for a reservation. Returns whether *this* caller got it.
   *
   * One conditional statement rather than read-then-write, because two
   * customers tapping the same 10:00 at the same moment is the sequence
   * §Phase 9a's first Done-when line is about. The second transaction blocks
   * on the row lock, wakes to find `status` no longer `open`, matches nothing
   * and is told the slot is gone — it never reaches the reservation insert.
   */
  async claimSlot(id: string, now: Date, db: Db): Promise<boolean> {
    const { count } = await db.timeSlot.updateMany({
      where: { id, status: 'open', startsAt: { gt: now } },
      data: { status: 'reserved' },
    });
    return count === 1;
  }

  /** Returns a released slot to `open`. Never touches one somebody re-took. */
  async freeSlot(id: string, db: Db): Promise<void> {
    await db.timeSlot.updateMany({ where: { id, status: 'reserved' }, data: { status: 'open' } });
  }

  async setSlotStatus(
    id: string,
    from: 'open' | 'blocked',
    to: 'open' | 'blocked',
    db: Db = this.prisma,
  ): Promise<boolean> {
    const { count } = await db.timeSlot.updateMany({
      where: { id, status: from },
      data: { status: to },
    });
    return count === 1;
  }

  // -- Reservations --------------------------------------------------------

  createReservation(data: Prisma.ReservationUncheckedCreateInput, db: Db): Promise<Reservation> {
    return db.reservation.create({ data });
  }

  findReservation(id: string, db: Db = this.prisma): Promise<Reservation | null> {
    return db.reservation.findUnique({ where: { id } });
  }

  updateReservation(
    id: string,
    data: Prisma.ReservationUncheckedUpdateInput,
    db: Db,
  ): Promise<Reservation> {
    return db.reservation.update({ where: { id }, data });
  }

  /**
   * Every hold a provider has in a window, across every listing and both
   * booking modes. What `overlapsAny` filters against, and what makes a
   * cleaning slot disappear while a plumbing quote is outstanding.
   */
  findHeldReservations(
    providerProfileId: string,
    from: Date,
    to: Date,
    db: Db = this.prisma,
  ): Promise<Reservation[]> {
    return db.reservation.findMany({
      where: {
        providerProfileId,
        releasedAt: null,
        startsAt: { lt: to },
        endsAt: { gt: from },
      },
      orderBy: { startsAt: 'asc' },
    });
  }

  /** Releases, and reports whether this caller was the one that did it — a replayed cancel releases once. */
  async releaseReservation(
    id: string,
    reason: ReservationReleaseReason,
    at: Date,
    db: Db,
  ): Promise<boolean> {
    const { count } = await db.reservation.updateMany({
      where: { id, releasedAt: null },
      data: { releasedAt: at, releaseReason: reason },
    });
    return count === 1;
  }

  /**
   * The provisional-hold sweep's entire WHERE.
   *
   * Written narrow from the start, for the reason the phase brief spells out:
   * §Phase 8a's `runLifecycle` selected every row and then looked each one up,
   * and crossed five seconds at a thousand rows. The job's conditions are all
   * here and all indexed (`kind, releasedAt, expiresAt`), so a run reads only
   * the holds that have actually expired.
   */
  findExpiredProvisionalHolds(
    now: Date,
    limit: number,
    db: Db = this.prisma,
  ): Promise<Reservation[]> {
    return db.reservation.findMany({
      where: { kind: 'provisional', releasedAt: null, expiresAt: { not: null, lte: now } },
      orderBy: { expiresAt: 'asc' },
      take: limit,
    });
  }

  // -- Generation state ----------------------------------------------------

  findState(listingId: string, db: Db = this.prisma): Promise<ListingSlotState | null> {
    return db.listingSlotState.findUnique({ where: { listingId } });
  }

  /**
   * Wakes a listing's generator. Called whenever a rule, an exception or a
   * time-off range changes.
   *
   * An upsert rather than a create-if-missing read, so two concurrent edits on
   * the same listing cannot both decide the row is absent.
   */
  async markForGeneration(
    listingId: string,
    providerProfileId: string,
    at: Date,
    db: Db = this.prisma,
  ): Promise<void> {
    await db.listingSlotState.upsert({
      where: { listingId },
      create: { listingId, providerProfileId, nextGenerationAt: at },
      update: { nextGenerationAt: at },
    });
  }

  /** Every slot-publishing listing this provider owns — how a time-off change reaches them all. */
  findProviderStates(providerProfileId: string, db: Db = this.prisma): Promise<ListingSlotState[]> {
    return db.listingSlotState.findMany({ where: { providerProfileId } });
  }

  /**
   * **The job's work list, and the whole reason it stays cheap.**
   *
   * One indexed range scan over `next_generation_at`, returning only listings
   * that have something to do. A dormant listing — no rules, not slot-mode,
   * deleted — carries a null here and is never read at all, rather than read
   * and skipped. There is no second query per candidate: the caller loads
   * exactly the listing it is about to regenerate.
   */
  findGenerationCandidates(
    now: Date,
    limit: number,
    db: Db = this.prisma,
  ): Promise<ListingSlotState[]> {
    return db.listingSlotState.findMany({
      where: { nextGenerationAt: { not: null, lte: now } },
      orderBy: { nextGenerationAt: 'asc' },
      take: limit,
    });
  }

  async recordGeneration(
    listingId: string,
    data: {
      nextGenerationAt: Date | null;
      generatedThrough: Date | null;
      lastGeneratedAt: Date;
      lastRunMs: number;
    },
    db: Db = this.prisma,
  ): Promise<void> {
    await db.listingSlotState.update({ where: { listingId }, data });
  }
}
