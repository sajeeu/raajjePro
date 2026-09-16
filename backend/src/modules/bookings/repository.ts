import type {
  Booking,
  BookingAmendment,
  Prisma,
  PrismaClient,
} from '../../generated/prisma/client.js';
import type {
  BookingActorRole,
  BookingAmendmentStatus,
  BookingStatus,
} from '../../generated/prisma/enums.js';

/** A transaction or the client. Every write takes one so the service composes them. */
export type Db = PrismaClient | Prisma.TransactionClient;

/**
 * One projection for every read of a booking, so the list, the detail and the
 * jobs cannot drift into seeing different things.
 *
 * **The user selects are the load-bearing part.** They name `id` and `fullName`
 * and nothing else — `phoneE164` is not selected anywhere in this module, so
 * there is no path by which a phone number reaches a mapper that might forget
 * to drop it (§1c, §Phase 17's Done-when). The provider's bank details are a
 * *separate* read — §Phase 5's `paymentDetailsForBooking`, which is where
 * that projection already lives — rather than a field here, because they
 * belong to exactly one screen.
 */
const BOOKING_FIELDS = {
  include: {
    listing: {
      select: {
        id: true,
        name: true,
        providerProfileId: true,
        pricingModel: true,
        priceLaari: true,
        bookingMode: true,
        category: { select: { id: true, name: true, callbackEligible: true } },
      },
    },
    customer: { select: { id: true, fullName: true } },
    providerProfile: {
      select: {
        id: true,
        businessName: true,
        suspendedAt: true,
        user: { select: { id: true, fullName: true } },
      },
    },
    timeSlot: { select: { id: true, startsAt: true, endsAt: true } },
    /// Selected for its **name**, which §Phase 3c's notification context needs
    /// and which §0.0 item 12 says the server renders rather than the client.
    island: {
      select: { id: true, name: true, atollAbbr: true, nameAmbiguous: true },
    },
    amendments: { orderBy: { createdAt: 'desc' } },
  },
} as const satisfies { include: Prisma.BookingInclude };

export type BookingRow = Prisma.BookingGetPayload<typeof BOOKING_FIELDS>;

export interface StatusEventInput {
  bookingId: string;
  fromStatus: BookingStatus | null;
  toStatus: BookingStatus;
  actorRole: BookingActorRole;
  actorUserId: string | null;
  transition: string;
  at: Date;
}

/**
 * §Phase 17.1's data access. Nothing here decides anything: the machine is
 * `transitions.ts`, the money is `pricing.ts`, and the rules are `service.ts`.
 */
export class BookingRepository {
  constructor(private readonly prisma: PrismaClient) {}

  // -- Reads ----------------------------------------------------------------

  findById(id: string, db: Db = this.prisma): Promise<BookingRow | null> {
    return db.booking.findUnique({ where: { id }, ...BOOKING_FIELDS });
  }

  /**
   * The detail read's own extra query. Kept separate from [BOOKING_FIELDS] so
   * a list of fifty bookings never drags fifty timelines with it.
   */
  findStatusHistory(bookingId: string, db: Db = this.prisma) {
    return db.bookingStatusEvent.findMany({
      where: { bookingId },
      orderBy: { createdAt: 'asc' },
    });
  }

  /**
   * `GET /v1/users/me/bookings?role=&status=` (§Phase 17 item 18).
   *
   * Keyset by `createdAt` + `id`, the shape every paged read in this codebase
   * uses, so a booking created while the customer is scrolling cannot make a
   * row appear twice.
   */
  async findForUser(
    query: {
      role: 'customer' | 'provider';
      customerId: string;
      providerProfileId: string | null;
      statuses: BookingStatus[] | null;
      limit: number;
      cursor: { createdAt: Date; id: string } | null;
    },
    db: Db = this.prisma,
  ): Promise<BookingRow[]> {
    const scope: Prisma.BookingWhereInput =
      query.role === 'customer'
        ? { customerId: query.customerId }
        : // A user with no provider profile has no provider-side bookings, and
          // an impossible filter is the honest way to say so — it returns an
          // empty page rather than everybody's bookings.
          { providerProfileId: query.providerProfileId ?? '00000000-0000-0000-0000-000000000000' };

    return db.booking.findMany({
      where: {
        ...scope,
        ...(query.statuses === null ? {} : { status: { in: query.statuses } }),
        ...(query.cursor === null
          ? {}
          : {
              OR: [
                { createdAt: { lt: query.cursor.createdAt } },
                { createdAt: query.cursor.createdAt, id: { lt: query.cursor.id } },
              ],
            }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: query.limit,
      ...BOOKING_FIELDS,
    });
  }

  // -- Scheduled-job candidate queries --------------------------------------
  //
  // Each is one indexed range scan over `(status, …)` and returns ids only:
  // the job then acts on one booking per transaction, so one strange row never
  // stops the sweep.

  findAcceptTimeouts(before: Date, limit: number): Promise<{ id: string }[]> {
    return this.prisma.booking.findMany({
      where: {
        status: 'requested',
        createdAt: { lte: before },
        // §Phase 17.3 owns the emergency window and reads it from the
        // category; this job must never answer for one.
        bookingMode: { in: ['slot', 'request'] },
      },
      select: { id: true },
      orderBy: { createdAt: 'asc' },
      take: limit,
    });
  }

  findPaymentSilenceTimeouts(before: Date, limit: number): Promise<{ id: string }[]> {
    return this.prisma.booking.findMany({
      where: { status: 'payment_claimed', paymentClaimedAt: { lte: before } },
      select: { id: true },
      orderBy: { paymentClaimedAt: 'asc' },
      take: limit,
    });
  }

  findCompletionPromptDue(before: Date, limit: number): Promise<{ id: string }[]> {
    return this.prisma.booking.findMany({
      where: {
        status: 'confirmed',
        completionPromptedAt: null,
        scheduledFor: { not: null, lte: before },
      },
      select: { id: true },
      orderBy: { scheduledFor: 'asc' },
      take: limit,
    });
  }

  findCompletionGraceExpired(before: Date, limit: number): Promise<{ id: string }[]> {
    return this.prisma.booking.findMany({
      where: { status: 'confirmed', completionPromptedAt: { not: null, lte: before } },
      select: { id: true },
      orderBy: { completionPromptedAt: 'asc' },
      take: limit,
    });
  }

  // -- Writes ---------------------------------------------------------------

  create(data: Prisma.BookingUncheckedCreateInput, db: Db): Promise<Booking> {
    return db.booking.create({ data });
  }

  /**
   * Moves a booking, **conditionally on the status it was read at**.
   *
   * The `where` carries `status` as well as `id`, so two concurrent taps on
   * the same action cannot both apply: the second updates zero rows and the
   * service turns that into the same refusal a stale screen gets. This is the
   * booking-level equivalent of `claimSlot`, and it is why the service never
   * needs a row lock.
   */
  async transition(
    id: string,
    from: BookingStatus,
    data: Prisma.BookingUncheckedUpdateInput,
    db: Db,
  ): Promise<boolean> {
    const { count } = await db.booking.updateMany({ where: { id, status: from }, data });
    return count === 1;
  }

  /** A write that changes no status — the completion prompt's own stamp. */
  async stamp(
    id: string,
    from: BookingStatus,
    data: Prisma.BookingUncheckedUpdateInput,
    db: Db,
  ): Promise<boolean> {
    const { count } = await db.booking.updateMany({ where: { id, status: from }, data });
    return count === 1;
  }

  recordStatusEvent(input: StatusEventInput, db: Db) {
    return db.bookingStatusEvent.create({
      data: {
        bookingId: input.bookingId,
        fromStatus: input.fromStatus,
        toStatus: input.toStatus,
        actorRole: input.actorRole,
        actorUserId: input.actorUserId,
        transition: input.transition,
        createdAt: input.at,
      },
    });
  }

  // -- Amendments (§1h) -----------------------------------------------------

  createAmendment(data: Prisma.BookingAmendmentUncheckedCreateInput, db: Db) {
    return db.bookingAmendment.create({ data });
  }

  findAmendment(id: string, db: Db = this.prisma): Promise<BookingAmendment | null> {
    return db.bookingAmendment.findUnique({ where: { id } });
  }

  findOpenAmendment(bookingId: string, db: Db = this.prisma): Promise<BookingAmendment | null> {
    return db.bookingAmendment.findFirst({
      where: { bookingId, status: 'proposed' },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * Answers an amendment, conditionally on it still being open — the same
   * shape as [transition], and for the same reason: both parties may be
   * looking at it.
   */
  async respondToAmendment(
    id: string,
    status: Exclude<BookingAmendmentStatus, 'proposed'>,
    respondedByUserId: string,
    at: Date,
    db: Db,
  ): Promise<boolean> {
    const { count } = await db.bookingAmendment.updateMany({
      where: { id, status: 'proposed' },
      data: { status, respondedByUserId, respondedAt: at },
    });
    return count === 1;
  }

  // -- The two seams §Phases 3 and 8a built against -------------------------

  /**
   * §Phase 3's `DeletionBlocker`: has this user anything still running?
   *
   * Both sides of the relationship count. A provider with an accepted job owes
   * somebody a visit, and a customer with one is owed it.
   */
  async hasOpenBookings(userId: string, nonTerminal: BookingStatus[]): Promise<boolean> {
    const found = await this.prisma.booking.findFirst({
      where: {
        status: { in: nonTerminal },
        OR: [{ customerId: userId }, { providerProfile: { userId } }],
      },
      select: { id: true },
    });
    return found !== null;
  }

  async hasAnyBookingForProvider(providerProfileId: string): Promise<boolean> {
    const found = await this.prisma.booking.findFirst({
      where: { providerProfileId },
      select: { id: true },
    });
    return found !== null;
  }

  /** §1b's protected listings: committed status **and** a future `scheduledFor`. */
  async listingIdsWithCommittedBooking(
    listingIds: string[],
    committed: BookingStatus[],
    now: Date,
  ): Promise<string[]> {
    if (listingIds.length === 0) return [];
    const rows = await this.prisma.booking.findMany({
      where: {
        listingId: { in: listingIds },
        status: { in: committed },
        scheduledFor: { gt: now },
      },
      select: { listingId: true },
      distinct: ['listingId'],
    });
    return rows.map((r) => r.listingId);
  }

  // -- §Phase 22's minimal insert -------------------------------------------

  createReport(data: Prisma.ReportUncheckedCreateInput, db: Db) {
    return db.report.create({ data });
  }
}
