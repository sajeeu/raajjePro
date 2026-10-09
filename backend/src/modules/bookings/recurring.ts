import type { Clock } from '../../core/clock.js';
import { AppError, BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import type { RecurringMissReason } from '../../generated/prisma/enums.js';
import {
  SlotNoLongerAvailableError,
  TimeNoLongerAvailableError,
} from '../availability/reservations.js';
import type { BookingNotification, BookingNotifier } from './notifications.js';
import { deriveSlotAmount, durationMinutes } from './pricing.js';
import type { BookingRepository } from './repository.js';
import type { BookingService, ServiceLogger } from './service.js';
import type { RecurringOccurrenceDto, RecurringSeriesDto } from './types.js';
import { daysFrom, RECURRING_CADENCE_DAYS, RECURRING_PAUSE_AFTER_MISSES } from './windows.js';

const SERIES_INCLUDE = {
  customer: { select: { id: true, fullName: true } },
  providerProfile: {
    select: { id: true, businessName: true, user: { select: { id: true, fullName: true } } },
  },
  listing: { select: { id: true, name: true, pricingModel: true, priceLaari: true } },
  originBooking: { select: { timeSlot: { select: { startsAt: true, endsAt: true } } } },
} as const satisfies Prisma.RecurringSeriesInclude;

type SeriesRow = Prisma.RecurringSeriesGetPayload<{ include: typeof SERIES_INCLUDE }>;

/** How many weeks the series read carries — recent history, not the whole of it. */
const OCCURRENCES_SHOWN = 12;

/**
 * §1c "Recurring bookings", and `Recurring Booking.dc.html`.
 *
 * ## What a series is, and what it is not
 *
 * "**Each occurrence still requires individual provider accept.** Recurrence
 * is a convenience, not a standing pre-authorization." So a series holds no
 * time and no agreement. Each week it makes an **ordinary slot booking**
 * through `BookingService.createSlotBooking` — the same visibility, paused
 * and dispatch-fee rules as any booking, the same 24-hour accept window, the
 * same accept prompt — and records which week it was.
 *
 * ## The cadence
 *
 * One week ahead. The ask for Tuesday the 15th goes out on Tuesday the 8th,
 * which is what the artboard tells the customer ("The ask goes out on Tue 8
 * Sep"), and gives the provider a week rather than a day to answer. The
 * first ask goes out the moment the series is made — "Ask Mariyam for next
 * Tuesday" asks now.
 *
 * ## A missed week skips; three in a row pause
 *
 * §1c: "If an occurrence auto-declines at the 24-hour timeout, that week is
 * skipped, both parties are notified explicitly, and the series continues.
 * **Three consecutive missed occurrences** pause the series and notify the
 * customer to reconfirm." Owner's decision, 2026-10-09: a decline and a week
 * with no open slot are misses too — to the customer each is "the provider
 * didn't confirm this week". A week the customer skips is neutral; an
 * accepted week resets the run.
 *
 * ## Why outcomes are reconciled by a job
 *
 * A week resolves when its booking leaves `requested` — accepted, declined,
 * timed out, cancelled. Rather than threading a hook through every one of
 * those paths in `BookingService`, the sweep reads the booking's status and
 * records the outcome. The booking machine stays the only thing that moves a
 * booking, and nothing here can disagree with it.
 */
export class RecurringSeriesService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      clock: Clock;
      repo: BookingRepository;
      bookings: BookingService;
      notifier: BookingNotifier;
      log: ServiceLogger;
    },
  ) {}

  // =========================================================================
  // Endpoints
  // =========================================================================

  /**
   * `POST /v1/recurring-series` — "Same time next week?", from a booking the
   * customer has had.
   *
   * Slot bookings only (§1c: "predictable duration is what makes 'same time
   * next week' meaningful"), and only once the provider has actually done or
   * confirmed one — `Booking Detail.dc.html` offers "Make this recurring" on
   * a confirmed booking and the offer screen leads with a completed one.
   */
  async create(userId: string, originBookingId: string): Promise<RecurringSeriesDto> {
    const now = this.deps.clock();
    const origin = await this.deps.repo.findById(originBookingId);
    if (origin?.customerId !== userId) {
      throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    }
    if (origin.bookingMode !== 'slot') {
      throw new BusinessRuleError(
        'RECURRING_SLOT_ONLY',
        'Only bookings for a published time can repeat weekly',
        { bookingMode: origin.bookingMode },
      );
    }
    if (
      (origin.status !== 'confirmed' && origin.status !== 'completed') ||
      origin.scheduledFor === null
    ) {
      throw new BusinessRuleError(
        'RECURRING_NOT_AVAILABLE',
        'A booking can repeat once the provider has confirmed it',
        { status: origin.status },
      );
    }
    const existing = await this.deps.prisma.recurringSeries.findFirst({
      where: {
        customerId: userId,
        listingId: origin.listingId,
        status: { in: ['active', 'paused'] },
      },
      select: { id: true },
    });
    if (existing !== null) {
      throw new ConflictError(
        'RECURRING_SERIES_EXISTS',
        'You already have a weekly series with this provider for this service',
        { seriesId: existing.id },
      );
    }

    const series = await this.deps.prisma.recurringSeries.create({
      data: {
        customerId: userId,
        providerProfileId: origin.providerProfileId,
        listingId: origin.listingId,
        originBookingId: origin.id,
        status: 'active',
        nextOccurrenceAt: nextWeekAfter(origin.scheduledFor, now),
        nextAskAt: now,
        jobNotes: origin.jobNotes,
        islandId: origin.islandId,
        addressDetail: origin.addressDetail,
      },
    });
    await this.askFor(series.id, now);
    return this.read(userId, series.id);
  }

  /** `GET /v1/recurring-series/:id` — either party. A stranger gets not found. */
  async read(userId: string, seriesId: string): Promise<RecurringSeriesDto> {
    const series = await this.authorize(userId, seriesId);
    return this.toDto(series);
  }

  /**
   * `GET /v1/users/me/recurring-series?role=` — the caller's own series, as
   * customer or as provider. Keyset-paged like the bookings list.
   */
  async list(
    userId: string,
    query: { role: 'customer' | 'provider'; limit: number; cursor: string | null },
  ): Promise<{ series: RecurringSeriesDto[]; nextCursor: string | null }> {
    const scope: Prisma.RecurringSeriesWhereInput =
      query.role === 'customer' ? { customerId: userId } : { providerProfile: { userId } };
    const cursor = decodeCursor(query.cursor);
    const rows = await this.deps.prisma.recurringSeries.findMany({
      where: {
        ...scope,
        ...(cursor === null
          ? {}
          : {
              OR: [
                { createdAt: { lt: cursor.createdAt } },
                { createdAt: cursor.createdAt, id: { lt: cursor.id } },
              ],
            }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: query.limit + 1,
      include: SERIES_INCLUDE,
    });
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      series: await Promise.all(page.map((row) => this.toDto(row))),
      nextCursor:
        rows.length > query.limit && last !== undefined
          ? encodeCursor(last.createdAt, last.id)
          : null,
    };
  }

  /**
   * `PATCH /v1/recurring-series/:id/skip` — "Skipping frees one week and
   * tells Mariyam — the series continues."
   *
   * Two weeks are skippable: the one that has been asked for and not yet
   * answered (its booking is cancelled as the customer's own, which §1f never
   * counts against the provider), and the next one, not yet asked, which is
   * recorded now so the ask never goes out. A week the provider has already
   * accepted is a booking: the customer cancels that like any other.
   */
  async skip(userId: string, seriesId: string, occursAt: Date): Promise<RecurringSeriesDto> {
    const now = this.deps.clock();
    const series = await this.authorize(userId, seriesId, 'customer');
    if (series.status !== 'active') {
      throw new BusinessRuleError('RECURRING_SERIES_NOT_ACTIVE', 'This series is not running', {
        status: series.status,
      });
    }

    const occurrence = await this.deps.prisma.recurringOccurrence.findUnique({
      where: { seriesId_occursAt: { seriesId, occursAt } },
      include: { booking: { select: { id: true, status: true } } },
    });

    if (occurrence === null) {
      if (occursAt.getTime() !== series.nextOccurrenceAt.getTime()) throw notSkippable();
      await this.deps.prisma.recurringOccurrence.create({
        data: { seriesId, occursAt, state: 'skipped', resolvedAt: now },
      });
    } else if (occurrence.state === 'asked' && occurrence.booking?.status === 'requested') {
      await this.deps.bookings.cancel(userId, occurrence.booking.id, 'Skipped this week');
      await this.deps.prisma.recurringOccurrence.updateMany({
        where: { id: occurrence.id, state: 'asked' },
        data: { state: 'skipped', resolvedAt: now },
      });
    } else if (occurrence.state === 'accepted' || occurrence.state === 'asked') {
      throw new BusinessRuleError(
        'OCCURRENCE_ALREADY_ACCEPTED',
        'The provider already accepted that week — cancel the booking instead',
        { bookingId: occurrence.bookingId },
      );
    } else {
      throw notSkippable();
    }

    await this.notify('recurring_week_skipped', series.id, series.providerProfile.user.id);
    return this.read(userId, seriesId);
  }

  /**
   * `PATCH /v1/recurring-series/:id/end` — §1c: "cancelling the series stops
   * future occurrences." The artboard: "The weekly ask stops and any week
   * Mariyam hasn't accepted yet is withdrawn. Confirmed and past weeks are
   * untouched."
   */
  async end(userId: string, seriesId: string): Promise<RecurringSeriesDto> {
    const now = this.deps.clock();
    const series = await this.authorize(userId, seriesId, 'customer');
    if (series.status === 'ended') {
      throw new BusinessRuleError('RECURRING_SERIES_ENDED', 'This series has already ended');
    }
    const { count } = await this.deps.prisma.recurringSeries.updateMany({
      where: { id: seriesId, status: { not: 'ended' } },
      data: { status: 'ended', endedAt: now, nextAskAt: null },
    });
    if (count !== 1)
      throw new ConflictError('BOOKING_CHANGED', 'This series changed — open it again');

    const pending = await this.deps.prisma.recurringOccurrence.findMany({
      where: { seriesId, state: 'asked' },
      include: { booking: { select: { id: true, status: true } } },
    });
    for (const occurrence of pending) {
      if (occurrence.booking?.status === 'requested') {
        await this.deps.bookings.cancel(userId, occurrence.booking.id, 'Weekly series ended');
        await this.deps.prisma.recurringOccurrence.updateMany({
          where: { id: occurrence.id, state: 'asked' },
          data: { state: 'withdrawn', resolvedAt: now },
        });
      }
    }

    await this.notify('recurring_series_ended', series.id, series.providerProfile.user.id);
    return this.read(userId, seriesId);
  }

  /**
   * `PATCH /v1/recurring-series/:id/resume` — the paused state's "Keep asking
   * weekly", which is §1c's "reconfirm". The run of misses starts again at
   * zero, and the next future week is asked for now.
   */
  async resume(userId: string, seriesId: string): Promise<RecurringSeriesDto> {
    const now = this.deps.clock();
    const series = await this.authorize(userId, seriesId, 'customer');
    if (series.status !== 'paused') {
      throw new BusinessRuleError('RECURRING_SERIES_NOT_PAUSED', 'This series is not paused', {
        status: series.status,
      });
    }
    const { count } = await this.deps.prisma.recurringSeries.updateMany({
      where: { id: seriesId, status: 'paused' },
      data: {
        status: 'active',
        pausedAt: null,
        consecutiveMisses: 0,
        nextOccurrenceAt: nextWeekAfter(
          daysFrom(series.nextOccurrenceAt, -RECURRING_CADENCE_DAYS),
          now,
        ),
        nextAskAt: now,
      },
    });
    if (count !== 1)
      throw new ConflictError('BOOKING_CHANGED', 'This series changed — open it again');
    await this.askFor(seriesId, now);
    return this.read(userId, seriesId);
  }

  // =========================================================================
  // The sweep
  // =========================================================================

  /**
   * One tick of the series job: first record how every unanswered week
   * turned out, then send every ask that has come due. In that order, so a
   * third miss pauses the series before its next ask could go out.
   */
  async runSweep(now: Date, limit = 200): Promise<{ resolved: number; asked: number }> {
    const resolved = await this.reconcile(now, limit);
    const due = await this.deps.prisma.recurringSeries.findMany({
      where: { status: 'active', nextAskAt: { not: null, lte: now } },
      select: { id: true },
      orderBy: { nextAskAt: 'asc' },
      take: limit,
    });
    let asked = 0;
    for (const { id } of due) {
      try {
        if (await this.askFor(id, now)) asked += 1;
      } catch (error) {
        // One series must never stop the sweep.
        this.deps.log.warn({ err: error, seriesId: id }, 'recurring ask failed');
      }
    }
    return { resolved, asked };
  }

  /**
   * Records the outcome of every asked week whose booking has left
   * `requested`. The booking's own status and the edge that moved it are the
   * whole of the evidence.
   */
  async reconcile(now: Date, limit = 200): Promise<number> {
    const open = await this.deps.prisma.recurringOccurrence.findMany({
      where: { state: 'asked', booking: { status: { not: 'requested' } } },
      include: {
        booking: {
          select: {
            id: true,
            status: true,
            cancelledByRole: true,
            statusHistory: {
              orderBy: { createdAt: 'desc' },
              take: 1,
              select: { transition: true },
            },
          },
        },
      },
      orderBy: { occursAt: 'asc' },
      take: limit,
    });

    let resolved = 0;
    for (const occurrence of open) {
      const booking = occurrence.booking;
      if (booking === null) continue;
      const outcome = outcomeOf(
        booking.status,
        booking.cancelledByRole,
        booking.statusHistory[0]?.transition,
      );
      if (outcome === 'accepted') {
        const done = await this.deps.prisma.$transaction(async (tx) => {
          const { count } = await tx.recurringOccurrence.updateMany({
            where: { id: occurrence.id, state: 'asked' },
            data: { state: 'accepted', resolvedAt: now },
          });
          if (count !== 1) return false;
          await tx.recurringSeries.update({
            where: { id: occurrence.seriesId },
            data: { consecutiveMisses: 0 },
          });
          return true;
        });
        if (done) resolved += 1;
      } else if (outcome === 'skipped') {
        const { count } = await this.deps.prisma.recurringOccurrence.updateMany({
          where: { id: occurrence.id, state: 'asked' },
          data: { state: 'skipped', resolvedAt: now },
        });
        if (count === 1) resolved += 1;
      } else {
        if (await this.recordMiss(occurrence.seriesId, occurrence.id, null, outcome, now)) {
          resolved += 1;
        }
      }
    }
    return resolved;
  }

  // =========================================================================
  // Internals
  // =========================================================================

  /**
   * Asks for the series' next week, if its ask is due, and moves the series
   * on by one week. Idempotent: the `(series, week)` unique key means a
   * second tick racing this one finds the week already written and only
   * advances.
   *
   * @returns whether a booking was created.
   */
  private async askFor(seriesId: string, now: Date): Promise<boolean> {
    const series = await this.deps.prisma.recurringSeries.findUnique({ where: { id: seriesId } });
    if (series?.status !== 'active' || series.nextAskAt === null || series.nextAskAt > now) {
      return false;
    }
    const occursAt = series.nextOccurrenceAt;
    let created = false;

    const already = await this.deps.prisma.recurringOccurrence.findUnique({
      where: { seriesId_occursAt: { seriesId, occursAt } },
      select: { id: true },
    });
    if (already === null) {
      const slot = await this.deps.prisma.timeSlot.findFirst({
        where: {
          listingId: series.listingId,
          startsAt: occursAt,
          status: 'open',
        },
        select: { id: true },
      });
      if (slot === null) {
        await this.recordMiss(seriesId, null, occursAt, 'no_open_slot', now);
      } else {
        try {
          await this.deps.bookings.createSlotBooking(
            series.customerId,
            series.listingId,
            {
              timeSlotId: slot.id,
              jobNotes: series.jobNotes ?? undefined,
              islandId: series.islandId ?? undefined,
              addressDetail: series.addressDetail ?? undefined,
            },
            {
              inTransaction: async (tx, bookingId) => {
                await tx.recurringOccurrence.create({
                  data: { seriesId, occursAt, bookingId, state: 'asked' },
                });
              },
            },
          );
          created = true;
        } catch (error) {
          if (isUniqueViolation(error)) {
            // Another tick asked for this week first. Its booking stands.
          } else if (
            error instanceof SlotNoLongerAvailableError ||
            error instanceof TimeNoLongerAvailableError
          ) {
            await this.recordMiss(seriesId, null, occursAt, 'no_open_slot', now);
          } else if (error instanceof AppError) {
            // The listing is gone or paused, or the customer is blocked —
            // creation's own refusals, each a reason this week cannot be asked.
            await this.recordMiss(seriesId, null, occursAt, 'could_not_ask', now);
          } else {
            throw error;
          }
        }
      }
    }

    // Move on one week. Conditional on the week this call read, so two ticks
    // cannot advance twice; a series a third miss just paused keeps its
    // `nextAskAt` null.
    await this.deps.prisma.recurringSeries.updateMany({
      where: { id: seriesId, nextOccurrenceAt: occursAt },
      data: { nextOccurrenceAt: daysFrom(occursAt, RECURRING_CADENCE_DAYS) },
    });
    await this.deps.prisma.recurringSeries.updateMany({
      where: { id: seriesId, status: 'active' },
      data: { nextAskAt: occursAt },
    });
    return created;
  }

  /**
   * §1c: "that week is skipped, both parties are notified explicitly ('this
   * week was not confirmed; your series continues next week'), and the series
   * continues. Three consecutive missed occurrences pause the series and
   * notify the customer to reconfirm."
   */
  private async recordMiss(
    seriesId: string,
    occurrenceId: string | null,
    occursAt: Date | null,
    reason: RecurringMissReason,
    now: Date,
  ): Promise<boolean> {
    const result = await this.deps.prisma.$transaction(async (tx) => {
      if (occurrenceId !== null) {
        const { count } = await tx.recurringOccurrence.updateMany({
          where: { id: occurrenceId, state: 'asked' },
          data: { state: 'missed', missReason: reason, resolvedAt: now },
        });
        if (count !== 1) return null;
      } else if (occursAt !== null) {
        const inserted = await tx.recurringOccurrence.createMany({
          data: [{ seriesId, occursAt, state: 'missed', missReason: reason, resolvedAt: now }],
          skipDuplicates: true,
        });
        if (inserted.count !== 1) return null;
      }
      const series = await tx.recurringSeries.update({
        where: { id: seriesId },
        data: { consecutiveMisses: { increment: 1 } },
        include: SERIES_INCLUDE,
      });
      const pause =
        series.status === 'active' && series.consecutiveMisses >= RECURRING_PAUSE_AFTER_MISSES;
      if (pause) {
        await tx.recurringSeries.update({
          where: { id: seriesId },
          data: { status: 'paused', pausedAt: now, nextAskAt: null },
        });
      }
      return { series, pause };
    });
    if (result === null) return false;

    const { series, pause } = result;
    await this.notify('recurring_week_missed', seriesId, series.customer.id);
    await this.notify('recurring_week_missed', seriesId, series.providerProfile.user.id);
    if (pause) await this.notify('recurring_series_paused', seriesId, series.customer.id);
    return true;
  }

  private async authorize(
    userId: string,
    seriesId: string,
    expect?: 'customer',
  ): Promise<SeriesRow> {
    const series = await this.deps.prisma.recurringSeries.findUnique({
      where: { id: seriesId },
      include: SERIES_INCLUDE,
    });
    const isCustomer = series?.customerId === userId;
    const isProvider = series?.providerProfile.user.id === userId;
    if (series === null || (!isCustomer && !isProvider)) {
      throw new NotFoundError('No such series', 'RECURRING_SERIES_NOT_FOUND');
    }
    if (expect === 'customer' && !isCustomer) {
      throw new BusinessRuleError(
        'RECURRING_CUSTOMER_ONLY',
        'Only the customer can change a series',
      );
    }
    return series;
  }

  private async toDto(series: SeriesRow): Promise<RecurringSeriesDto> {
    const rows = await this.deps.prisma.recurringOccurrence.findMany({
      where: { seriesId: series.id },
      orderBy: { occursAt: 'desc' },
      take: OCCURRENCES_SHOWN,
      include: { booking: { select: { status: true } } },
    });
    const occurrences: RecurringOccurrenceDto[] = rows.reverse().map((o) => ({
      id: o.id,
      occursAt: o.occursAt.toISOString(),
      state: o.state,
      missReason: o.missReason,
      bookingId: o.bookingId,
      bookingStatus: o.booking?.status ?? null,
    }));
    const nextSkipped = occurrences.some(
      (o) => o.occursAt === series.nextOccurrenceAt.toISOString() && o.state === 'skipped',
    );
    const slot = series.originBooking.timeSlot;
    const minutes = slot === null ? null : durationMinutes(slot.startsAt, slot.endsAt);
    const running = series.status !== 'ended';

    return {
      id: series.id,
      status: series.status,
      listingId: series.listingId,
      listingName: series.listing.name,
      customer: { userId: series.customer.id, name: series.customer.fullName },
      provider: {
        userId: series.providerProfile.user.id,
        name: series.providerProfile.businessName ?? series.providerProfile.user.fullName,
      },
      durationMinutes: minutes,
      pricePerVisitLaari: minutes === null ? null : pricePerVisit(series.listing, minutes),
      nextOccurrenceAt: running ? series.nextOccurrenceAt.toISOString() : null,
      nextAskAt: series.nextAskAt === null ? null : series.nextAskAt.toISOString(),
      nextOccurrenceSkipped: running && nextSkipped,
      consecutiveMisses: series.consecutiveMisses,
      pausedAt: series.pausedAt === null ? null : series.pausedAt.toISOString(),
      endedAt: series.endedAt === null ? null : series.endedAt.toISOString(),
      createdAt: series.createdAt.toISOString(),
      occurrences,
    };
  }

  private async notify(event: BookingNotification, seriesId: string, userId: string) {
    try {
      await this.deps.notifier.notify({ event, bookingId: seriesId, userId });
    } catch (error) {
      this.deps.log.warn({ err: error, event, seriesId }, 'recurring notification failed');
    }
  }
}

/**
 * How a week's booking turned out, from the booking alone.
 *
 * Anything at or past `accepted` is an accepted week — what happens to that
 * booking afterwards is the booking's business, not the series'. A decline
 * is a decline unless the machine says the 24-hour clock made it; a booking
 * the customer cancelled while it waited is a week they skipped.
 */
function outcomeOf(
  status: string,
  cancelledByRole: string | null,
  lastTransition: string | undefined,
): 'accepted' | 'skipped' | RecurringMissReason {
  if (status === 'declined') return lastTransition === 'accept-timeout' ? 'timed_out' : 'declined';
  if (status === 'cancelled') return cancelledByRole === 'customer' ? 'skipped' : 'declined';
  return 'accepted';
}

/**
 * What one visit costs at the listing's price **now** — the provider may have
 * changed it since the first week, and each week's booking prices itself
 * afresh at creation. Null where the listing has since moved to a pricing
 * model a slot cannot derive (a range or a quote, §Phase 8).
 */
function pricePerVisit(
  listing: Parameters<typeof deriveSlotAmount>[0],
  minutes: number,
): number | null {
  try {
    return deriveSlotAmount(listing, minutes).amountLaari;
  } catch {
    return null;
  }
}

/** The first weekly repeat of `from` that is still in the future. */
function nextWeekAfter(from: Date, now: Date): Date {
  let next = daysFrom(from, RECURRING_CADENCE_DAYS);
  while (next <= now) next = daysFrom(next, RECURRING_CADENCE_DAYS);
  return next;
}

function notSkippable(): BusinessRuleError {
  return new BusinessRuleError(
    'OCCURRENCE_NOT_SKIPPABLE',
    'Only the next week, or one still waiting for an answer, can be skipped',
  );
}

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === 'object' && error !== null && (error as { code?: unknown }).code === 'P2002'
  );
}

function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}

function decodeCursor(cursor: string | null): { createdAt: Date; id: string } | null {
  if (cursor === null) return null;
  const [at, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  if (at === undefined || id === undefined) return null;
  const createdAt = new Date(at);
  return Number.isNaN(createdAt.getTime()) ? null : { createdAt, id };
}
