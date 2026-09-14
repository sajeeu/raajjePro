import type { Clock } from '../../core/clock.js';
import { ConflictError, NotFoundError } from '../../core/errors.js';
import type {
  PrismaClient,
  Reservation,
  ReservationReleaseReason,
} from '../../generated/prisma/client.js';
import type { AvailabilityRepository, Db } from './repository.js';

/** SQLSTATE for an exclusion-constraint violation. What `reservation_provider_no_overlap` raises. */
const EXCLUSION_VIOLATION = '23P01';

/** The constraint's name, as the migration declares it. A second, shape-independent signal. */
export const OVERLAP_CONSTRAINT = 'reservation_provider_no_overlap';

/**
 * Raised when a published slot was taken between the picker rendering it and
 * the customer tapping. `Pick a Time.dc.html` has the copy: "{time} is no
 * longer available — Someone else took it while you were deciding. Nothing
 * was sent."
 */
export class SlotNoLongerAvailableError extends ConflictError {
  constructor() {
    super('SLOT_NO_LONGER_AVAILABLE', 'That time is no longer available');
  }
}

/**
 * Raised when the provider's time is held by something else — a booking on
 * another listing, or an outstanding quote. Distinct from the above because
 * the customer sees a different truth: the slot they picked was never taken,
 * the *person* is busy, and nothing on this listing's grid could have shown
 * it.
 */
export class TimeNoLongerAvailableError extends ConflictError {
  constructor() {
    super('PROVIDER_TIME_UNAVAILABLE', 'The provider is no longer free at that time');
  }
}

export interface SlotReservationRequest {
  slotId: string;
  kind: 'firm' | 'provisional';
  /**
   * Provisional only. §1c: a quote's hold expires with the category's
   * `quoteApprovalMinutes` — 240 for the household trades, 4320 for
   * Photography, Moving and Boat Charter (invariant 13). **The caller
   * computes it from the category**; nothing here knows a number, and
   * §Phase 9a's own "72-hour expiry" line is a pre-Round-15 residue.
   */
  expiresAt?: Date;
}

export interface WindowReservationRequest {
  providerProfileId: string;
  listingId: string;
  startsAt: Date;
  endsAt: Date;
  kind: 'firm' | 'provisional';
  expiresAt?: Date;
}

/**
 * §Phase 9a's reservation primitive — **the seam §Phase 17 builds its booking
 * machine on**.
 *
 * Every method takes a `Db`, because §Phase 9a requires reservations to be
 * "created inside the booking transaction": the booking row, the state
 * transition and the hold either all land or none do. A reservation taken in
 * its own transaction and a booking that then failed would leave a provider
 * blocked for an appointment nobody made.
 *
 * ## The two guards, and why there are two
 *
 * `reserveSlot` first **claims the slot row** with a conditional update, then
 * inserts the reservation. The claim resolves *two customers racing the same
 * published slot*, and does it with a clean answer rather than a caught
 * constraint error — it also re-checks `startsAt > now`, so a slot whose time
 * passed in the seconds since the picker rendered it cannot be taken.
 *
 * The **exclusion constraint** resolves everything the claim cannot see: the
 * same provider's time being taken from another listing, or by a request-based
 * quote that never had a slot at all. It is the database's guarantee, not the
 * application's, and no code path here can opt out of it.
 *
 * ## What takes no reservation
 *
 * Emergency bookings (§1c): "an emergency is understood as an interruption to
 * the published calendar, not a block on it." Nothing in this file is called
 * on the emergency path.
 */
export class ReservationService {
  constructor(
    private readonly deps: { prisma: PrismaClient; clock: Clock; repo: AvailabilityRepository },
  ) {}

  /**
   * Takes a published slot. Call inside the booking transaction.
   *
   * @throws {SlotNoLongerAvailableError} the slot is gone, blocked, already
   *   taken, or its time has passed.
   * @throws {TimeNoLongerAvailableError} the provider's time is held elsewhere.
   */
  async reserveSlot(
    tx: Db,
    request: SlotReservationRequest,
    now: Date = this.deps.clock(),
  ): Promise<Reservation> {
    const slot = await this.deps.repo.findSlot(request.slotId, tx);
    if (slot === null) throw new SlotNoLongerAvailableError();

    const claimed = await this.deps.repo.claimSlot(slot.id, now, tx);
    if (!claimed) throw new SlotNoLongerAvailableError();

    return this.insert(tx, {
      providerProfileId: slot.providerProfileId,
      listingId: slot.listingId,
      timeSlotId: slot.id,
      startsAt: slot.startsAt,
      endsAt: slot.endsAt,
      kind: request.kind,
      expiresAt: request.expiresAt ?? null,
    });
  }

  /**
   * Takes a concrete time that was never a published slot — §1c's
   * request-based path, where the provider proposes a time and a price.
   *
   * §1c: "Offering a quote creates a provisional reservation on the proposed
   * time... Without this, the provider could sell that time to someone else in
   * the interim and the customer's approval would fail on a constraint
   * violation after they had already agreed a price."
   *
   * @throws {TimeNoLongerAvailableError} the provider's time is already held.
   */
  reserveWindow(
    tx: Db,
    request: WindowReservationRequest,
    _now: Date = this.deps.clock(),
  ): Promise<Reservation> {
    return this.insert(tx, {
      providerProfileId: request.providerProfileId,
      listingId: request.listingId,
      timeSlotId: null,
      startsAt: request.startsAt,
      endsAt: request.endsAt,
      kind: request.kind,
      expiresAt: request.expiresAt ?? null,
    });
  }

  /**
   * Converts an approved quote's hold into a firm one (§1c: "Approval converts
   * the provisional reservation to a firm one").
   *
   * The hold is not re-taken, so there is no window in which the time is free
   * and somebody else could win it.
   */
  async makeFirm(tx: Db, reservationId: string): Promise<Reservation> {
    const existing = await this.deps.repo.findReservation(reservationId, tx);
    if (existing === null) throw noActiveReservation();
    if (existing.releasedAt !== null) throw noActiveReservation();
    return this.deps.repo.updateReservation(reservationId, { kind: 'firm', expiresAt: null }, tx);
  }

  /**
   * Releases a hold and returns its slot to `open` — §Phase 9a: "Cancellation,
   * decline, or timeout releases the reservation", and "a cancelled booking's
   * slot reappears".
   *
   * Returns whether *this* call was the one that released it, so a replayed
   * cancellation is a no-op rather than a second release. The slot is freed
   * only on that winning call, and only if it is still `reserved` — a slot
   * somebody has since re-taken is never yanked back to `open`.
   */
  async release(
    tx: Db,
    reservationId: string,
    reason: ReservationReleaseReason,
    now: Date = this.deps.clock(),
  ): Promise<boolean> {
    const reservation = await this.deps.repo.findReservation(reservationId, tx);
    if (reservation === null) return false;

    const released = await this.deps.repo.releaseReservation(reservationId, reason, now, tx);
    if (!released) return false;
    if (reservation.timeSlotId !== null) await this.deps.repo.freeSlot(reservation.timeSlotId, tx);
    return true;
  }

  /**
   * Frees one time and takes another atomically — §Phase 17.4's reschedule.
   *
   * In one transaction on purpose: releasing first and taking second in two
   * transactions leaves a window where the provider is free and a stranger can
   * win the time they were rescheduling into, and taking first would collide
   * with the reservation being moved.
   */
  async reschedule(
    tx: Db,
    reservationId: string,
    to: { startsAt: Date; endsAt: Date; slotId?: string },
    now: Date = this.deps.clock(),
  ): Promise<Reservation> {
    const existing = await this.deps.repo.findReservation(reservationId, tx);
    if (existing === null) throw noActiveReservation();
    if (existing.releasedAt !== null) throw noActiveReservation();
    await this.release(tx, reservationId, 'superseded', now);
    return to.slotId === undefined
      ? this.reserveWindow(
          tx,
          {
            providerProfileId: existing.providerProfileId,
            listingId: existing.listingId,
            startsAt: to.startsAt,
            endsAt: to.endsAt,
            kind: existing.kind,
          },
          now,
        )
      : this.reserveSlot(tx, { slotId: to.slotId, kind: existing.kind }, now);
  }

  /**
   * §Phase 9a's provisional-hold sweep: "Provisional reservations for offered
   * quotes, with expiry swept by a scheduled job."
   *
   * On the job runner rather than checked on read (backend/CLAUDE.md), so an
   * expired hold stops blocking the provider's calendar even if nobody opens
   * the booking. Each release is its own transaction: one hold whose slot has
   * gone strange must not stop the rest of the sweep.
   */
  async sweepExpiredHolds(now: Date, limit = 200): Promise<{ released: number }> {
    const expired = await this.deps.repo.findExpiredProvisionalHolds(now, limit);
    let released = 0;
    for (const hold of expired) {
      const done = await this.deps.prisma.$transaction((tx) =>
        this.release(tx, hold.id, 'expired', now),
      );
      if (done) released += 1;
    }
    return { released };
  }

  private async insert(
    tx: Db,
    data: {
      providerProfileId: string;
      listingId: string;
      timeSlotId: string | null;
      startsAt: Date;
      endsAt: Date;
      kind: 'firm' | 'provisional';
      expiresAt: Date | null;
    },
  ): Promise<Reservation> {
    try {
      return await this.deps.repo.createReservation(data, tx);
    } catch (error) {
      // The database refused an overlap. Translate it into the API's own
      // vocabulary rather than letting a raw driver error out — invariant:
      // no internal error detail ever reaches a response.
      if (isExclusionViolation(error)) throw new TimeNoLongerAvailableError();
      throw error;
    }
  }
}

function noActiveReservation(): NotFoundError {
  return new NotFoundError('No active reservation', 'RESERVATION_NOT_FOUND');
}

/**
 * Whether the database refused this write because of the overlap constraint.
 *
 * **Prisma does not model exclusion constraints**, so it has no error class
 * for one and the SQLSTATE arrives nested inside whatever the driver adapter
 * hands up. On Prisma 7 with `@prisma/adapter-pg` that is `P2039` carrying
 * `meta.driverAdapterError.cause.code`; older shapes put it at `meta.code` or
 * on the error itself. All three are checked rather than one, because the
 * nesting is an implementation detail of a dependency and getting it wrong
 * fails *open* — the raw driver error would reach the global handler and turn
 * a "that time just went" into a 500 with an internal message in it.
 *
 * `test/phase9a-done-when.test.ts` exercises this against a real violation, so
 * a future Prisma release that moves the field again fails a test rather than
 * a customer's booking.
 */
function isExclusionViolation(error: unknown): boolean {
  if (codeOf(error) === EXCLUSION_VIOLATION) return true;

  const meta = propertyOf(error, 'meta');
  if (codeOf(meta) === EXCLUSION_VIOLATION) return true;

  const cause = propertyOf(propertyOf(meta, 'driverAdapterError'), 'cause');
  if (codeOf(cause) === EXCLUSION_VIOLATION) return true;
  if (propertyOf(cause, 'originalCode') === EXCLUSION_VIOLATION) return true;

  // Last resort, and shape-independent: the constraint names itself in the
  // message the driver passes through.
  const message = propertyOf(cause, 'message') ?? propertyOf(error, 'message');
  return typeof message === 'string' && message.includes(OVERLAP_CONSTRAINT);
}

function propertyOf(value: unknown, key: string): unknown {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)[key]
    : undefined;
}

function codeOf(value: unknown): unknown {
  return propertyOf(value, 'code');
}
