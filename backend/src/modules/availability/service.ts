import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import {
  addMaldivesDays,
  dateColumnOf,
  maldivesDateOf,
  maldivesDateOfColumn,
  minutesOfDay,
  startOfMaldivesDay,
  type MaldivesDate,
} from '../../core/maldives-time.js';
import type {
  AvailabilityException,
  AvailabilityRule,
  PrismaClient,
  ProviderProfile,
  ProviderTimeOff,
  Reservation,
  TimeSlot,
} from '../../generated/prisma/client.js';
import type { ProviderProfileService } from '../providers/service.js';
import { overlaps, overlapsAny } from './conflicts.js';
import { SLOT_WINDOW_DAYS } from './generator.js';
import type { SlotGenerator } from './generation.js';
import { AvailabilityRepository } from './repository.js';
import type {
  AvailabilityExceptionDto,
  AvailabilityRuleDto,
  ListingAvailabilityDto,
  OpenSlotsDto,
  ProviderSlotDto,
  TimeOffDto,
} from './types.js';

/** What a first rule's editor opens with, when the listing's wizard window says nothing. */
const DEFAULT_SLOT_MINUTES = 120;

/**
 * §Phase 9a's provider and customer surface.
 *
 * ## Authorization, once, so every method below can be read quickly
 *
 * Every provider method resolves the caller's own profile and then loads the
 * listing **with the owner in the WHERE**, so somebody else's listing is *not
 * found* rather than found and refused — the posture §Phase 8 established, and
 * it means an id cannot be used to discover which listings are real.
 *
 * The one public method, `listOpenSlots`, is deliberately open to everyone
 * including guests: browsing is public (§0.2), and it composes
 * `PUBLICLY_VISIBLE_LISTING` and §1a's single `isVisible` helper rather than
 * restating either.
 *
 * ## No response shape here carries a phone number
 *
 * Structurally — see `types.ts`. Nothing in this module reads a `User` row.
 */
export class AvailabilityService {
  readonly repo: AvailabilityRepository;

  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      clock: Clock;
      providers: ProviderProfileService;
      generator: SlotGenerator;
    },
  ) {
    this.repo = new AvailabilityRepository(deps.prisma);
  }

  // -- Rules ---------------------------------------------------------------

  async readListingAvailability(
    userId: string,
    listingId: string,
  ): Promise<ListingAvailabilityDto> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const [rules, exceptions, state] = await Promise.all([
      this.repo.findRules(listing.id),
      this.repo.findExceptions(listing.id),
      this.repo.findState(listing.id),
    ]);
    return {
      listingId: listing.id,
      rules: rules.map(toRuleDto),
      exceptions: exceptions.map(toExceptionDto),
      horizonDate:
        state?.generatedThrough == null
          ? null
          : // `generatedThrough` is the exclusive end — midnight opening the
            // day *after* the last bookable one — so the date a provider is
            // told about is the day before it.
            addMaldivesDays(maldivesDateOf(state.generatedThrough), -1),
      lastGeneratedAt: state?.lastGeneratedAt?.toISOString() ?? null,
    };
  }

  /**
   * What the rule editor opens with for a listing that has none yet.
   *
   * §Phase 9's step 5 collects `workingDays` / `workingHoursFrom` /
   * `workingHoursTo` — a simple window that its own helper says is not the
   * pattern. It is not read anywhere else in this module and it does not
   * generate anything. Offering it here is the one honest use: the provider
   * already stated when they work, so the editor should not open empty and
   * make them state it again, and confirming it is what turns a summary into
   * a rule.
   */
  async ruleDefaults(userId: string, listingId: string) {
    const listing = await this.ownedSlotListing(userId, listingId);
    return {
      weekdays: listing.workingDays.length > 0 ? listing.workingDays : [1, 2, 3, 4, 5],
      startTime: listing.workingHoursFrom ?? '09:00',
      endTime: listing.workingHoursTo ?? '17:00',
      slotDurationMinutes: DEFAULT_SLOT_MINUTES,
    };
  }

  async addRule(
    userId: string,
    listingId: string,
    body: { weekdays: number[]; startTime: string; endTime: string; slotDurationMinutes: number },
  ): Promise<AvailabilityRuleDto> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    checkWindow(body);

    const existing = await this.repo.findRules(listing.id);
    checkNoRuleClash(existing, body, null);

    return this.deps.prisma.$transaction(async (tx) => {
      const rule = await this.repo.createRule(
        { listingId: listing.id, providerProfileId: listing.providerProfileId, ...body },
        tx,
      );
      await this.regenerateInline(listing, now, tx);
      return toRuleDto(rule);
    });
  }

  async updateRule(
    userId: string,
    listingId: string,
    ruleId: string,
    body: { weekdays: number[]; startTime: string; endTime: string; slotDurationMinutes: number },
  ): Promise<AvailabilityRuleDto> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    checkWindow(body);

    const existing = await this.repo.findRules(listing.id);
    if (!existing.some((r) => r.id === ruleId)) throw notFoundRule();
    checkNoRuleClash(existing, body, ruleId);

    return this.deps.prisma.$transaction(async (tx) => {
      const rule = await this.repo.updateRule(ruleId, body, tx);
      await this.regenerateInline(listing, now, tx);
      return toRuleDto(rule);
    });
  }

  async removeRule(userId: string, listingId: string, ruleId: string): Promise<void> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    const rule = await this.repo.findRule(ruleId, listing.id);
    if (rule === null) throw notFoundRule();

    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.softDeleteRule(ruleId, now, tx);
      await this.regenerateInline(listing, now, tx);
    });
  }

  // -- Exceptions ("modified hours") ---------------------------------------

  async addException(
    userId: string,
    listingId: string,
    body: {
      name: string;
      startDate: MaldivesDate;
      endDate: MaldivesDate;
      startTime: string;
      endTime: string;
      slotDurationMinutes?: number | null | undefined;
    },
  ): Promise<AvailabilityExceptionDto> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    checkWindow(body, body.slotDurationMinutes ?? null);
    checkDateRange(body);

    // Two exceptions covering one day would leave "which hours apply today?"
    // answered by insertion order, which is not an answer. Refusing the
    // second one keeps the model one-exception-per-day by construction and
    // lets `expandSlots` use a plain `find`.
    const existing = await this.repo.findExceptions(listing.id);
    const clash = existing.find(
      (e) =>
        maldivesDateOfColumn(e.startDate) <= body.endDate &&
        body.startDate <= maldivesDateOfColumn(e.endDate),
    );
    if (clash !== undefined) {
      throw new BusinessRuleError(
        'EXCEPTION_DATES_OVERLAP',
        `Those dates overlap "${clash.name}". Remove it first, or choose dates outside it.`,
      );
    }

    return this.deps.prisma.$transaction(async (tx) => {
      const row = await this.repo.createException(
        {
          listingId: listing.id,
          providerProfileId: listing.providerProfileId,
          name: body.name,
          startDate: dateColumnOf(body.startDate),
          endDate: dateColumnOf(body.endDate),
          startTime: body.startTime,
          endTime: body.endTime,
          slotDurationMinutes: body.slotDurationMinutes ?? null,
        },
        tx,
      );
      await this.regenerateInline(listing, now, tx);
      return toExceptionDto(row);
    });
  }

  async removeException(userId: string, listingId: string, exceptionId: string): Promise<void> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    const row = await this.repo.findException(exceptionId, listing.id);
    if (row === null) throw new NotFoundError('No such exception', 'EXCEPTION_NOT_FOUND');

    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.softDeleteException(exceptionId, now, tx);
      await this.regenerateInline(listing, now, tx);
    });
  }

  // -- Time away (provider-wide) -------------------------------------------

  async listTimeOff(userId: string): Promise<TimeOffDto[]> {
    const profile = await this.ownProfile(userId);
    const rows = await this.repo.findTimeOff(profile.id);
    return rows.map(toTimeOffDto);
  }

  async addTimeOff(
    userId: string,
    body: { name: string; startDate: MaldivesDate; endDate: MaldivesDate },
  ): Promise<TimeOffDto> {
    const profile = await this.ownProfile(userId);
    const now = this.deps.clock();
    checkDateRange(body);

    return this.deps.prisma.$transaction(async (tx) => {
      const row = await this.repo.createTimeOff(
        {
          providerProfileId: profile.id,
          name: body.name,
          startDate: dateColumnOf(body.startDate),
          endDate: dateColumnOf(body.endDate),
        },
        tx,
      );
      await this.regenerateProvider(profile.id, now, tx);
      return toTimeOffDto(row);
    });
  }

  async removeTimeOff(userId: string, timeOffId: string): Promise<void> {
    const profile = await this.ownProfile(userId);
    const now = this.deps.clock();
    const row = await this.repo.findOneTimeOff(timeOffId, profile.id);
    if (row === null) throw new NotFoundError('No such time away', 'TIME_OFF_NOT_FOUND');

    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.softDeleteTimeOff(timeOffId, now, tx);
      await this.regenerateProvider(profile.id, now, tx);
    });
  }

  // -- The provider's own grid ---------------------------------------------

  /**
   * Every time on one listing in a window, with its **effective** status.
   *
   * A slot reads `reserved` when the provider's time is held by a booking on
   * another listing, even though its own row still says `open`. That is what
   * `Availability.dc.html`'s reserved sheet already says out loud: "A booking
   * on any of your listings holds your time, so you can never be
   * double-booked."
   */
  async listOwnSlots(
    userId: string,
    listingId: string,
    range: { from?: MaldivesDate | undefined; to?: MaldivesDate | undefined },
  ): Promise<ProviderSlotDto[]> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    const { from, to } = this.clampRange(range, now);

    const [slots, held] = await Promise.all([
      this.repo.findSlotsInRange(listing.id, from, to),
      this.repo.findHeldReservations(listing.providerProfileId, from, to),
    ]);
    return slots.map((slot) => toProviderSlotDto(slot, held));
  }

  /**
   * `My Calendar.dc.html`'s "Upcoming commitments" — every time this provider
   * is committed to, across every listing and both booking modes.
   *
   * §Phase 9a owns the *commitment*; §Phase 17.1 owns the **booking** behind
   * it. So what comes back here is the reservation — when, which listing, firm
   * or provisional — and the customer, reference and mode the screen also
   * shows arrive with the booking table. Ledger row **P9A-1** carries that.
   */
  async readCalendar(
    userId: string,
    range: { from?: MaldivesDate | undefined; to?: MaldivesDate | undefined },
  ): Promise<{
    commitments: {
      id: string;
      listingId: string;
      startsAt: string;
      endsAt: string;
      kind: string;
      /// 🔧 §Phase 17.1 (ledger P9A-1). Null on a hold with no booking yet.
      bookingId: string | null;
      bookingReference: string | null;
      bookingMode: string | null;
      customerName: string | null;
    }[];
    timeOff: TimeOffDto[];
  }> {
    const profile = await this.ownProfile(userId);
    const now = this.deps.clock();
    const { from, to } = this.clampRange(range, now);
    const [held, timeOff] = await Promise.all([
      this.repo.findHeldReservations(profile.id, from, to),
      this.repo.findTimeOff(profile.id),
    ]);
    return {
      commitments: held.map((r) => ({
        id: r.id,
        listingId: r.listingId,
        startsAt: r.startsAt.toISOString(),
        endsAt: r.endsAt.toISOString(),
        kind: r.kind,
        bookingId: r.booking?.id ?? null,
        bookingReference: r.booking?.reference ?? null,
        bookingMode: r.booking?.bookingMode ?? null,
        customerName: r.booking?.customer.fullName ?? null,
      })),
      timeOff: timeOff.map(toTimeOffDto),
    };
  }

  /** The plan's "individual override": the provider taps one open time and takes it off the market. */
  async blockSlot(userId: string, slotId: string): Promise<ProviderSlotDto> {
    return this.setBlock(userId, slotId, 'open', 'blocked');
  }

  async unblockSlot(userId: string, slotId: string): Promise<ProviderSlotDto> {
    return this.setBlock(userId, slotId, 'blocked', 'open');
  }

  /** The explicit regenerate endpoint. Idempotent — re-running changes nothing (§Phase 9a). */
  async regenerate(
    userId: string,
    listingId: string,
  ): Promise<{ created: number; removed: number }> {
    const listing = await this.ownedSlotListing(userId, listingId);
    const now = this.deps.clock();
    await this.repo.markForGeneration(listing.id, listing.providerProfileId, now);
    const outcome = await this.deps.generator.generateForListing(listing.id, now);
    return { created: outcome.created, removed: outcome.removed };
  }

  // -- The customer's picker -----------------------------------------------

  /**
   * §Phase 9a: "customer slot picker showing **only currently open,
   * not-yet-passed slots**, never an unavailable or already-elapsed time."
   *
   * Four filters, and each is here for a reason the plan states:
   *
   * 1. `status = 'open'` — the stored state.
   * 2. `startsAt > now + lead time` — **at query time**, never relying on the
   *    regeneration job having run. §0.2 item 6 and §1c both single this out:
   *    "a slot that was open five minutes ago and simply wasn't cleaned up
   *    must not appear as a live option."
   * 3. The category's `minimumLeadTimeMinutes`, read per category and never
   *    hardcoded (§Phase 4 seeds Cleaning 180, Beauty 120, Fitness 120, and
   *    §Phase 10b keeps them editable).
   * 4. Not overlapping anything the **provider** is already holding — the one
   *    filter a single listing's rows cannot express, and the reason §1c can
   *    promise "no picker ever shows an unavailable time".
   */
  async listOpenSlots(
    listingId: string,
    range: { from?: MaldivesDate | undefined; to?: MaldivesDate | undefined },
  ): Promise<OpenSlotsDto> {
    // The three public clauses are `PUBLICLY_VISIBLE_LISTING`, composed in the
    // repository rather than restated here — a consumer that writes
    // `status: 'published'` on its own has already lost the deleted case.
    const listing = await this.repo.findPublicListingWithCategory(listingId);
    if (listing === null) throw notFoundListing();
    // §1a's one shared helper, not a second copy of the rule: a suspended
    // provider, or one whose account is gone, has no bookable time.
    if (!(await this.deps.providers.visibility.isVisible(listing.providerProfileId))) {
      throw notFoundListing();
    }
    if (listing.bookingMode !== 'slot') {
      throw new BusinessRuleError(
        'LISTING_NOT_SLOT_BASED',
        'This service takes requests rather than published times',
      );
    }

    const now = this.deps.clock();
    const leadMinutes = listing.category?.minimumLeadTimeMinutes ?? 0;
    const bookableFrom = new Date(now.getTime() + leadMinutes * 60_000);
    const { to } = this.clampRange(range, now);

    const [slots, held] = await Promise.all([
      this.repo.findOpenSlots(listing.id, bookableFrom, to),
      this.repo.findHeldReservations(listing.providerProfileId, bookableFrom, to),
    ]);

    return {
      listingId: listing.id,
      minimumLeadTimeMinutes: leadMinutes,
      bookableFrom: bookableFrom.toISOString(),
      slots: slots
        .filter((slot) => !overlapsAny(slot, held))
        .map((slot) => ({
          id: slot.id,
          startsAt: slot.startsAt.toISOString(),
          endsAt: slot.endsAt.toISOString(),
        })),
    };
  }

  // -- Internals -----------------------------------------------------------

  private async setBlock(
    userId: string,
    slotId: string,
    from: 'open' | 'blocked',
    to: 'open' | 'blocked',
  ): Promise<ProviderSlotDto> {
    const profile = await this.ownProfile(userId);
    const slot = await this.repo.findSlot(slotId);
    // Ownership by the provider rather than the listing: the grid is theirs
    // and a slot id is not guessable, but a mismatched one must still read as
    // absent rather than forbidden.
    if (slot === null) throw notFoundSlot();
    if (slot.providerProfileId !== profile.id) throw notFoundSlot();
    if (slot.status === 'reserved') throw reservedSlot();

    const held = await this.repo.findHeldReservations(profile.id, slot.startsAt, slot.endsAt);
    // Held from another listing: its own row says `open`, but the time is
    // not the provider's to give away or to block — the booking is.
    if (held.some((reservation) => overlaps(slot, reservation))) throw reservedSlot();

    const changed = await this.repo.setSlotStatus(slot.id, from, to);
    if (!changed) {
      throw new BusinessRuleError(
        'SLOT_ALREADY_IN_STATE',
        to === 'blocked' ? 'That time is already blocked' : 'That time is already open',
      );
    }
    return toProviderSlotDto({ ...slot, status: to }, held);
  }

  /** Regenerates inside the caller's transaction, so a rule edit and its grid land together. */
  private async regenerateInline(
    listing: { id: string; providerProfileId: string },
    now: Date,
    tx: Parameters<SlotGenerator['generateForListing']>[2],
  ): Promise<void> {
    await this.repo.markForGeneration(listing.id, listing.providerProfileId, now, tx);
    await this.deps.generator.generateForListing(listing.id, now, tx);
  }

  /**
   * Time away is provider-wide, so it reaches every listing that publishes
   * slots — which is exactly the set `ListingSlotState` holds. §Phase 9a's
   * "incremental and **per-provider**" is this: one provider's listings, not
   * everybody's.
   */
  private async regenerateProvider(
    providerProfileId: string,
    now: Date,
    tx: Parameters<SlotGenerator['generateForListing']>[2],
  ): Promise<void> {
    const states = await this.repo.findProviderStates(providerProfileId, tx);
    for (const state of states) {
      await this.repo.markForGeneration(state.listingId, providerProfileId, now, tx);
      await this.deps.generator.generateForListing(state.listingId, now, tx);
    }
  }

  private async ownProfile(userId: string): Promise<ProviderProfile> {
    const profile = await this.deps.providers.repo.findByUserId(userId);
    if (profile === null) {
      throw new NotFoundError('No provider profile yet', 'PROVIDER_PROFILE_NOT_FOUND');
    }
    return profile;
  }

  /** The caller's own listing, and one that takes published times at all. */
  private async ownedSlotListing(userId: string, listingId: string) {
    const profile = await this.ownProfile(userId);
    const listing = await this.repo.findListingWithCategory(listingId);
    if (listing === null) throw notFoundListing();
    if (listing.deletedAt !== null || listing.providerProfileId !== profile.id) {
      throw notFoundListing();
    }
    if (listing.bookingMode !== 'slot') {
      throw new BusinessRuleError(
        'LISTING_NOT_SLOT_BASED',
        'Only a service that takes time slots publishes availability. This one takes requests.',
      );
    }
    return listing;
  }

  /**
   * A window, clamped to the horizon.
   *
   * Bounded rather than paged, and that is sufficient: the set can never
   * exceed one listing's slots inside 60 days, because `to` cannot reach past
   * the horizon however far ahead a client asks.
   */
  private clampRange(
    range: { from?: MaldivesDate | undefined; to?: MaldivesDate | undefined },
    now: Date,
  ): { from: Date; to: Date } {
    const today = maldivesDateOf(now);
    const horizon = addMaldivesDays(today, SLOT_WINDOW_DAYS);
    const fromDate = range.from !== undefined && range.from > today ? range.from : today;
    const toDate =
      range.to !== undefined && range.to < horizon ? addMaldivesDays(range.to, 1) : horizon;
    const from = startOfMaldivesDay(fromDate);
    const to = startOfMaldivesDay(toDate);
    return { from, to: to > from ? to : startOfMaldivesDay(addMaldivesDays(fromDate, 1)) };
  }
}

// ---------------------------------------------------------------------------
// Rule checks
// ---------------------------------------------------------------------------

function checkWindow(
  body: { startTime: string; endTime: string; slotDurationMinutes?: number | null | undefined },
  duration: number | null = body.slotDurationMinutes ?? null,
): void {
  const start = minutesOfDay(body.startTime);
  const end = minutesOfDay(body.endTime);
  if (end <= start) {
    // Overnight availability is specified nowhere in the plan, and a window
    // that silently wrapped would put slots on a day the provider never
    // picked. Refusing says so.
    throw new BusinessRuleError(
      'WINDOW_ENDS_BEFORE_IT_STARTS',
      'The finish time has to be later than the start time on the same day.',
    );
  }
  if (duration !== null && duration > end - start) {
    // Otherwise the rule saves and generates nothing, and the provider is
    // left looking at an empty grid with no reason given.
    throw new BusinessRuleError(
      'VISIT_LONGER_THAN_WINDOW',
      'Each visit is longer than the hours you set, so no times could be published.',
    );
  }
}

function checkDateRange(body: { startDate: MaldivesDate; endDate: MaldivesDate }): void {
  if (body.endDate < body.startDate) {
    throw new BusinessRuleError('DATES_OUT_OF_ORDER', 'The last day cannot be before the first.');
  }
}

/**
 * Two rules on one listing may not cover the same weekday at overlapping
 * hours.
 *
 * Not a correctness requirement — the exclusion constraint would still keep
 * the provider from being double-booked — but a clarity one. Overlapping
 * rules publish overlapping times, so a customer picks 10:00, and the 09:30
 * beside it silently stops being bookable for everyone else. Refusing the
 * second rule keeps the published grid something a provider can read.
 */
function checkNoRuleClash(
  existing: AvailabilityRule[],
  candidate: { weekdays: number[]; startTime: string; endTime: string },
  ignoreId: string | null,
): void {
  const start = minutesOfDay(candidate.startTime);
  const end = minutesOfDay(candidate.endTime);
  for (const rule of existing) {
    if (rule.id === ignoreId) continue;
    if (!rule.weekdays.some((day) => candidate.weekdays.includes(day))) continue;
    if (minutesOfDay(rule.startTime) < end && start < minutesOfDay(rule.endTime)) {
      throw new BusinessRuleError(
        'RULE_HOURS_OVERLAP',
        `Those hours overlap another rule on the same day (${rule.startTime}–${rule.endTime}). Edit that one instead.`,
      );
    }
  }
}

function reservedSlot(): BusinessRuleError {
  return new BusinessRuleError(
    'SLOT_RESERVED',
    'A booking holds this time. To free it, manage the booking itself.',
  );
}

function notFoundListing(): NotFoundError {
  return new NotFoundError('No such service', 'LISTING_NOT_FOUND');
}

function notFoundSlot(): NotFoundError {
  return new NotFoundError('No such time', 'SLOT_NOT_FOUND');
}

function notFoundRule(): NotFoundError {
  return new NotFoundError('No such rule', 'AVAILABILITY_RULE_NOT_FOUND');
}

// ---------------------------------------------------------------------------
// DTO mapping
// ---------------------------------------------------------------------------

function toRuleDto(rule: AvailabilityRule): AvailabilityRuleDto {
  return {
    id: rule.id,
    weekdays: rule.weekdays,
    startTime: rule.startTime,
    endTime: rule.endTime,
    slotDurationMinutes: rule.slotDurationMinutes,
  };
}

function toExceptionDto(row: AvailabilityException): AvailabilityExceptionDto {
  return {
    id: row.id,
    name: row.name,
    startDate: maldivesDateOfColumn(row.startDate),
    endDate: maldivesDateOfColumn(row.endDate),
    startTime: row.startTime,
    endTime: row.endTime,
    slotDurationMinutes: row.slotDurationMinutes,
  };
}

function toTimeOffDto(row: ProviderTimeOff): TimeOffDto {
  return {
    id: row.id,
    name: row.name,
    startDate: maldivesDateOfColumn(row.startDate),
    endDate: maldivesDateOfColumn(row.endDate),
  };
}

function toProviderSlotDto(slot: TimeSlot, held: readonly Reservation[]): ProviderSlotDto {
  const heldElsewhere = slot.status === 'open' && overlapsAny(slot, held);
  return {
    id: slot.id,
    startsAt: slot.startsAt.toISOString(),
    endsAt: slot.endsAt.toISOString(),
    status: heldElsewhere ? 'reserved' : slot.status,
    heldByAnotherListing: heldElsewhere,
  };
}
