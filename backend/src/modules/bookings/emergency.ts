import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { Prisma, PrismaClient, VerificationTier } from '../../generated/prisma/client.js';
import type { BookingActorRole, BookingStatus } from '../../generated/prisma/enums.js';
import { emergencyEligibility } from '../listings/emergency.js';
import type { ProviderProfileService } from '../providers/service.js';
import { tiersAtOrAbove } from '../providers/visibility.js';
import type { NotificationDispatcher } from '../push/dispatcher.js';
import { contactRevealState, type KillSwitches } from './contact-reveal.js';
import {
  assertNoOutstandingDispatchFee,
  createOwedDispatchFee,
  dispatchFeeState,
} from './dispatch-fee.js';
import { islandDisplayName, toBookingDto } from './mapper.js';
import type { BookingNotification, BookingNotifier } from './notifications.js';
import { generateBookingReference } from './reference.js';
import type { BookingRepository, BookingRow, Db } from './repository.js';
import { assertTransition } from './transitions.js';
import type {
  BookingDto,
  EmergencyBroadcastDto,
  EmergencyDetailsDto,
  EmergencyOfferDto,
  EmergencyPhase,
} from './types.js';
import {
  daysBefore,
  EMERGENCY_REQUESTS_PER_DAY,
  EMERGENCY_REQUESTS_PER_WEEK,
  MAX_OFFERS_PER_ROUND,
  minutesFrom,
  OFFER_CHOICE_MINUTES,
  OFFER_COLLECTION_SECONDS,
  secondsFrom,
} from './windows.js';

export interface EmergencyLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

/** `Emergency Flow.dc.html`'s form: what's wrong, and where. No slot, no window. */
export interface CreateEmergencyInput {
  jobNotes: string;
  islandId: string;
  addressDetail?: string | undefined;
}

export interface EmergencyOfferInput {
  calloutFeeLaari: number;
  etaMinutes: number;
}

export type EmergencyOfferResponse = { offerId: string } | { rejectAll: true };

/** One provider a broadcast reaches, and the listing an offer from them would go through. */
interface Recipient {
  providerProfileId: string;
  userId: string;
  listingId: string;
}

/** The statuses at which an emergency has no provider yet — it is still a broadcast. */
const PRE_SELECTION: readonly BookingStatus[] = ['requested', 'emergency_offered'];

/** The statuses at which a chosen emergency provider owes a visit that has not happened. */
const IN_FLIGHT: readonly BookingStatus[] = [
  'accepted',
  'awaiting_payment',
  'payment_claimed',
  'confirmed',
  'payment_unresolved',
  'disputed',
];

export function isPreSelectionEmergency(booking: {
  bookingMode: string;
  status: BookingStatus;
}): boolean {
  return booking.bookingMode === 'emergency' && PRE_SELECTION.includes(booking.status);
}

/**
 * §Phase 17.3 — emergency dispatch and offer collection.
 *
 * ## The shape, in the plan's own words
 *
 * §1c, Round 15: "**Acceptances no longer race** — they create offers that
 * coexist, and the customer chooses." A request **broadcasts** to every
 * eligible provider at once; the first answer opens a **90-second collection
 * window**; at its close the customer sees **up to three offers** side by
 * side and has **five minutes** to pick one or reject them all; picking one
 * incurs the **MVR 200 dispatch fee** and the job proceeds without waiting
 * for it; the whole request lives inside the category's
 * `emergencyAcceptWindowMinutes`, which no rejection or expiry resets.
 *
 * ## Who the booking belongs to before anyone is chosen
 *
 * `Booking.listingId` and `providerProfileId` are NOT NULL, and an emergency
 * is raised from a listing (§Phase 17 item 2). Until a customer selects an
 * offer those columns name the listing the request came from — and **nothing
 * more**: `BookingService.authorize` gives that provider no side of the
 * booking, their bookings list does not show it, and they reach it through
 * the emergency inbox like every other eligible provider. Selection
 * re-points both columns to the chosen provider and their own emergency
 * listing, so every step after it — the payment step's bank details, the
 * provider's own list, completion — reads the provider who is actually
 * coming, through code §Phase 17.1 wrote and this slice did not touch.
 *
 * ## Where the phone-number rule stands
 *
 * No method here returns one. The broadcast view withholds even the address
 * ("Exact address is shared if the customer picks you"), and an offer card is
 * a name, a tier, a fee and an estimate. The single exception in the system is
 * `contact-reveal.ts`, and it is not reached from here.
 */
export class EmergencyService {
  private readonly prisma: PrismaClient;
  private readonly clock: Clock;
  private readonly repo: BookingRepository;
  private readonly providers: ProviderProfileService;
  private readonly notifier: BookingNotifier;
  private readonly dispatcher: NotificationDispatcher | undefined;
  private readonly killSwitches: KillSwitches;
  private readonly log: EmergencyLogger;

  constructor(deps: {
    prisma: PrismaClient;
    clock: Clock;
    repo: BookingRepository;
    providers: ProviderProfileService;
    notifier: BookingNotifier;
    dispatcher?: NotificationDispatcher;
    killSwitches: KillSwitches;
    log: EmergencyLogger;
  }) {
    this.prisma = deps.prisma;
    this.clock = deps.clock;
    this.repo = deps.repo;
    this.providers = deps.providers;
    this.notifier = deps.notifier;
    this.dispatcher = deps.dispatcher;
    this.killSwitches = deps.killSwitches;
    this.log = deps.log;
  }

  // =========================================================================
  // Creation and the broadcast
  // =========================================================================

  /**
   * `POST /v1/listings/:id/bookings` with `emergency: true` — §Phase 17 item
   * 2: "emergency captures no timing constraint but **validates category
   * eligibility, provider verification, and the customer's emergency rate
   * limit**."
   *
   * Refused, in order: an unsettled dispatch fee (it blocks every new
   * booking, §1c); a listing that is not public; the caller's own listing; the
   * composed rule — a category that is not emergency-capable, or a provider
   * below that category's `emergencyMinimumTier` (never a hardcoded tier); a
   * listing whose provider has not opted in; and last, the rate limit, so a
   * customer is never told they are over a limit for a request that could not
   * have been made anyway.
   */
  async create(
    userId: string,
    listingId: string,
    input: CreateEmergencyInput,
  ): Promise<BookingDto> {
    const now = this.clock();
    await assertNoOutstandingDispatchFee(this.prisma, userId);

    const listing = await this.prisma.listing.findFirst({
      where: { id: listingId, status: 'published', visibility: 'active', deletedAt: null },
      select: {
        id: true,
        providerProfileId: true,
        isEmergency: true,
        category: {
          select: {
            name: true,
            emergencyCapable: true,
            emergencyMinimumTier: true,
            emergencyAcceptWindowMinutes: true,
          },
        },
        providerProfile: { select: { userId: true, suspendedAt: true, verificationTier: true } },
      },
    });
    if (listing?.category == null || listing.providerProfile.suspendedAt !== null) {
      throw new NotFoundError('No such service', 'LISTING_NOT_FOUND');
    }
    if (listing.providerProfile.userId === userId) {
      throw new BusinessRuleError('CANNOT_BOOK_OWN_LISTING', 'You cannot book your own service');
    }

    // §1c, Round 17: "a booking dispatches to it only when both still hold
    // **at booking time**" — so the rule is re-run here, against today's tier,
    // not trusted from the listing's flag.
    const verdict = emergencyEligibility({
      category: listing.category,
      providerTier: listing.providerProfile.verificationTier,
    });
    if (!verdict.eligible) {
      throw new BusinessRuleError(verdict.code, verdict.message);
    }
    if (!listing.isEmergency) {
      throw new BusinessRuleError(
        'EMERGENCY_NOT_OFFERED',
        'This service does not take emergency requests — send a normal request instead',
      );
    }
    const windowMinutes = listing.category.emergencyAcceptWindowMinutes;
    if (windowMinutes === null) {
      // A capable category with no window is a misconfigured row. Refusing is
      // the safe direction; a default would be a hardcoded 30 by another name.
      throw new BusinessRuleError(
        'EMERGENCY_CATEGORY_NOT_CAPABLE',
        `${listing.category.name} does not offer emergency callouts`,
      );
    }

    const island = await this.prisma.island.findFirst({
      where: { id: input.islandId, isActive: true },
      select: { id: true },
    });
    if (island === null) throw new NotFoundError('No such island', 'ISLAND_NOT_FOUND');

    await this.assertWithinRateLimit(userId, now);

    const created = await this.prisma.$transaction(async (tx) => {
      const booking = await this.insertWithReference(tx, {
        listingId: listing.id,
        customerId: userId,
        providerProfileId: listing.providerProfileId,
        bookingMode: 'emergency',
        status: 'requested',
        // §1c: "No calendar reservation — an emergency is understood as an
        // interruption to the published calendar, not a block on it."
        timeSlotId: null,
        reservationId: null,
        scheduledFor: null,
        jobNotes: input.jobNotes,
        islandId: island.id,
        addressDetail: input.addressDetail ?? null,
        // Stored, never recomputed: the customer is already watching it.
        emergencyWindowEndsAt: minutesFrom(now, windowMinutes),
        createdAt: now,
      });
      await this.repo.recordStatusEvent(
        {
          bookingId: booking.id,
          fromStatus: null,
          toStatus: 'requested',
          actorRole: 'customer',
          actorUserId: userId,
          transition: 'create-emergency',
          at: now,
        },
        tx,
      );
      return booking;
    });

    const row = await this.mustFind(created.id);
    await this.broadcast(row);
    return this.dtoFor(row, 'customer');
  }

  /**
   * §1c: "Rate limit: 3 emergency requests per customer per 24 hours, 10 per 7
   * days." Counted over **requests** — a re-broadcast, a rejection or an
   * expiry happens inside one request and creates no new booking, so none of
   * them can consume it.
   *
   * The refusal carries what `Emergency Flow.dc.html`'s limit screen prints:
   * "3 of 3 used", "7 of 10 used", and when the next request is possible.
   */
  private async assertWithinRateLimit(customerId: string, now: Date): Promise<void> {
    const recent = await this.prisma.booking.findMany({
      where: { customerId, bookingMode: 'emergency', createdAt: { gt: daysBefore(now, 7) } },
      select: { createdAt: true },
      orderBy: { createdAt: 'asc' },
    });
    const dayAgo = daysBefore(now, 1);
    const inDay = recent.filter((r) => r.createdAt > dayAgo);
    const overDay = inDay.length >= EMERGENCY_REQUESTS_PER_DAY;
    const overWeek = recent.length >= EMERGENCY_REQUESTS_PER_WEEK;
    if (!overDay && !overWeek) return;

    // The next request is possible when the oldest request that is holding
    // each limit ages out — whichever of the two binding limits frees last.
    const dayFree = overDay ? inDay[inDay.length - EMERGENCY_REQUESTS_PER_DAY] : undefined;
    const weekFree = overWeek ? recent[recent.length - EMERGENCY_REQUESTS_PER_WEEK] : undefined;
    const candidates = [
      dayFree === undefined ? null : dayFree.createdAt.getTime() + 24 * 60 * 60_000,
      weekFree === undefined ? null : weekFree.createdAt.getTime() + 7 * 24 * 60 * 60_000,
    ].filter((t): t is number => t !== null);

    throw new BusinessRuleError(
      'EMERGENCY_RATE_LIMITED',
      "You've reached the emergency request limit — a normal booking has no limit",
      {
        usedLast24Hours: inDay.length,
        limitPer24Hours: EMERGENCY_REQUESTS_PER_DAY,
        usedLast7Days: recent.length,
        limitPer7Days: EMERGENCY_REQUESTS_PER_WEEK,
        nextAvailableAt: new Date(Math.max(...candidates)).toISOString(),
      },
    );
  }

  /**
   * Every provider this request reaches right now — §Phase 17 item 4:
   * "emergency-capable category, island match, `verificationTier` meeting the
   * category's `emergencyMinimumTier` … `acceptingNewCustomers` on."
   *
   * Two halves, and each is somebody else's rule reused rather than restated:
   *  - **by listing** — a published, active, undeleted listing in this
   *    category with `isEmergency` set and a live service area on the job's
   *    island. That is the listing half of §1c's composed rule, and the
   *    per-listing areas are what discovery matches on (§Phase 8);
   *  - **by provider** — `findVisibleProviders`, §1a's one shared helper, with
   *    the category's own tier as the minimum. Suspension is an input to that
   *    helper, so a suspended provider drops out here without a second copy of
   *    the filter.
   *
   * Excluded: everyone in `rejectedProviderIds`, and the customer themselves
   * where they also happen to be a provider.
   */
  private async recipients(booking: BookingRow, onlyProviderId?: string): Promise<Recipient[]> {
    const category = booking.listing.category;
    const minimum = category?.emergencyMinimumTier ?? null;
    if (category === null || !category.emergencyCapable || minimum === null) return [];
    if (booking.islandId === null) return [];

    const listings = await this.prisma.listing.findMany({
      where: {
        categoryId: booking.listing.categoryId,
        isEmergency: true,
        status: 'published',
        visibility: 'active',
        deletedAt: null,
        serviceAreas: { some: { islandId: booking.islandId, removedAt: null } },
        providerProfileId:
          onlyProviderId === undefined
            ? { notIn: booking.rejectedProviderIds }
            : { equals: onlyProviderId, notIn: booking.rejectedProviderIds },
        providerProfile: {
          userId: { not: booking.customerId },
          verificationTier: { in: tiersAtOrAbove(minimum) },
          acceptingNewCustomers: true,
        },
      },
      select: { id: true, providerProfileId: true, providerProfile: { select: { userId: true } } },
      // A provider with two emergency listings in one category is asked once;
      // their oldest listing is the one an offer goes through.
      orderBy: { createdAt: 'asc' },
    });
    const byProvider = new Map<string, Recipient>();
    for (const l of listings) {
      if (byProvider.has(l.providerProfileId)) continue;
      byProvider.set(l.providerProfileId, {
        providerProfileId: l.providerProfileId,
        userId: l.providerProfile.userId,
        listingId: l.id,
      });
    }
    if (byProvider.size === 0) return [];

    const visible = await this.providers.visibility.findVisibleProviders(
      { ids: [...byProvider.keys()], minimumTier: minimum, acceptingNewCustomers: true },
      { limit: byProvider.size },
    );
    return visible.items.flatMap((p) => {
      const r = byProvider.get(p.id);
      return r === undefined ? [] : [r];
    });
  }

  /**
   * §1c: "The request is broadcast to **every eligible provider at once**."
   *
   * Through §Phase 3c's dispatcher with the kind it built for this —
   * `emergency_dispatch`, urgency `emergency` — which sends push and email
   * together with no ladder, because "an emergency window is 30 minutes, which
   * leaves no room to wait for a push to go unconfirmed". Every send is a
   * `PushDispatch` row, which is how "did this provider get the emergency
   * alert?" is answered in one lookup.
   *
   * After the transaction, never inside it: a notification that did not go out
   * must never roll back a request that did.
   */
  private async broadcast(booking: BookingRow): Promise<number> {
    const recipients = await this.recipients(booking);
    if (this.dispatcher === undefined) return recipients.length;
    for (const r of recipients) {
      try {
        await this.dispatcher.dispatch({
          userId: r.userId,
          urgency: 'emergency',
          subjectId: booking.id,
          context: {
            kind: 'emergency_dispatch',
            bookingType: booking.listing.category?.name ?? 'Service',
            customerFirstName: firstName(booking.customer.fullName),
            islandName: booking.island === null ? '' : islandDisplayName(booking.island),
          },
        });
      } catch (error) {
        this.log.warn({ err: error, bookingId: booking.id }, 'emergency broadcast dispatch failed');
      }
    }
    this.log.info(
      { bookingId: booking.id, recipients: recipients.length },
      'emergency request broadcast',
    );
    return recipients.length;
  }

  // =========================================================================
  // The provider's side — the inbox and the offer
  // =========================================================================

  /**
   * `GET /v1/providers/me/emergency-requests` — every open emergency this
   * provider may answer right now, newest first.
   *
   * Computed from the provider's side rather than stored per recipient: the
   * eligibility rule is live (§1c: "a provider whose verification is later
   * revoked stops receiving emergency requests immediately"), so a stored
   * fan-out list would be a second copy of it that could disagree.
   */
  async inbox(userId: string): Promise<EmergencyBroadcastDto[]> {
    const now = this.clock();
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true },
    });
    if (profile === null) return [];

    const mine = await this.prisma.listing.findMany({
      where: {
        providerProfileId: profile.id,
        isEmergency: true,
        status: 'published',
        visibility: 'active',
        deletedAt: null,
      },
      select: {
        categoryId: true,
        serviceAreas: { where: { removedAt: null }, select: { islandId: true } },
      },
    });
    const scopes = mine
      .filter((l) => l.categoryId !== null && l.serviceAreas.length > 0)
      .map((l) => ({
        listing: { categoryId: l.categoryId },
        islandId: { in: l.serviceAreas.map((a) => a.islandId) },
      }));
    if (scopes.length === 0) return [];

    const candidates = await this.prisma.booking.findMany({
      where: {
        bookingMode: 'emergency',
        status: { in: [...PRE_SELECTION] },
        emergencyWindowEndsAt: { gt: now },
        customerId: { not: userId },
        NOT: { rejectedProviderIds: { has: profile.id } },
        OR: scopes,
      },
      select: { id: true },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    const out: EmergencyBroadcastDto[] = [];
    for (const { id } of candidates) {
      const booking = await this.repo.findById(id);
      if (booking === null) continue;
      // The full rule, per request — tier, visibility, opt-in — so the inbox
      // can never show a request the offer endpoint would then refuse.
      const [me] = await this.recipients(booking, profile.id);
      if (me === undefined) continue;
      out.push(await this.broadcastDto(booking, profile.id, true, now));
    }
    return out;
  }

  /**
   * `GET /v1/providers/me/emergency-requests/:id` — one request, as the push
   * deep-links to it. Readable by a provider who may answer it now **or** who
   * already did, so the one who was not chosen sees that they were released.
   */
  async readForProvider(userId: string, bookingId: string): Promise<EmergencyBroadcastDto> {
    const now = this.clock();
    const { booking, providerProfileId, eligible } = await this.providerView(userId, bookingId);
    return this.broadcastDto(booking, providerProfileId, eligible, now);
  }

  /**
   * `PATCH /v1/bookings/:id/emergency-accept` — §Phase 17 item 4: the
   * provider "**creates an `EmergencyOffer`** and supplies `calloutFee` and
   * `etaMinutes` in the same call. This no longer claims the booking."
   *
   * ## Why two simultaneous offers both land
   *
   * Every offer is admitted by one conditional increment of
   * `emergencyOfferCount` — `WHERE status IN (requested, emergency_offered)
   * AND count < 3 AND window still open`. Postgres takes the row lock on the
   * first writer and re-evaluates the second writer's `WHERE` against the
   * committed row, so two providers answering in the same instant are
   * serialised rather than raced: both see room, both are admitted, and the
   * status moves once, for whichever was first. A fourth is refused by the same
   * predicate. There is no `ALREADY_CLAIMED` — "atomicity applies only to the
   * offer the customer selects".
   *
   * 🔧 **A fourth offer is refused rather than hidden** —
   * `EMERGENCY_OFFERS_FULL`, so that provider is released at once instead of
   * waiting on a choice they are not part of. Raised with the verification
   * session on 2026-09-28 (the plan says "at most three" and not which three).
   */
  async offer(
    userId: string,
    bookingId: string,
    input: EmergencyOfferInput,
  ): Promise<EmergencyBroadcastDto> {
    const now = this.clock();
    const { booking, providerProfileId, recipient, tierBlock } = await this.providerView(
      userId,
      bookingId,
    );

    // The composed rule's tier half gets its own code, because §Phase 17.3's
    // Done-when names the case: "an emergency on Electrical is refused to a
    // silver provider and accepted from a gold one, while AC Repair accepts
    // silver". The bar is the category's, read from the row.
    if (tierBlock !== null) throw tierBlock;
    if (recipient === null) {
      throw new BusinessRuleError(
        'EMERGENCY_NOT_ELIGIBLE',
        'You can no longer answer this request',
      );
    }
    if (booking.emergencyWindowEndsAt === null || now >= booking.emergencyWindowEndsAt) {
      throw new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }
    if (booking.offerCollectionClosesAt !== null && now >= booking.offerCollectionClosesAt) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFERS_CLOSED',
        'Offers for this request have closed — the customer is choosing',
      );
    }
    // A later offer in the same round moves nothing, so only the first is a
    // transition; anything past selection is simply closed to new offers.
    if (booking.status !== 'emergency_offered') {
      assertTransition('emergency-offer', booking.status, 'provider');
    }

    await this.prisma.$transaction(async (tx) => {
      const { count: admitted } = await tx.booking.updateMany({
        where: {
          id: booking.id,
          status: { in: [...PRE_SELECTION] },
          emergencyOfferCount: { lt: MAX_OFFERS_PER_ROUND },
          emergencyWindowEndsAt: { gt: now },
          OR: [{ offerCollectionClosesAt: null }, { offerCollectionClosesAt: { gt: now } }],
        },
        data: { emergencyOfferCount: { increment: 1 } },
      });
      if (admitted !== 1) throw await this.whyNotAdmitted(tx, booking.id, now);

      try {
        await tx.emergencyOffer.create({
          data: {
            bookingId: booking.id,
            providerProfileId,
            listingId: recipient.listingId,
            calloutFeeLaari: input.calloutFeeLaari,
            etaMinutes: input.etaMinutes,
            state: 'open',
            createdAt: now,
          },
        });
      } catch (error) {
        // The partial unique index — one open offer per provider per request.
        // The throw rolls back the increment above with it.
        if (isUniqueViolation(error)) {
          throw new ConflictError(
            'EMERGENCY_OFFER_ALREADY_MADE',
            'You have already made an offer on this request',
          );
        }
        throw error;
      }

      // The first offer of a round opens the collection window. A later one
      // updates nothing here — which is how "both produce offers" and "the
      // status moved once" are both true.
      const { count: opened } = await tx.booking.updateMany({
        where: { id: booking.id, status: 'requested' },
        data: {
          status: 'emergency_offered',
          offerCollectionClosesAt: secondsFrom(now, OFFER_COLLECTION_SECONDS),
        },
      });
      if (opened === 1) {
        await this.event(
          tx,
          booking.id,
          'requested',
          'emergency_offered',
          'emergency-offer',
          'provider',
          userId,
          now,
        );
      }
    });

    return this.readForProvider(userId, bookingId);
  }

  // =========================================================================
  // The customer's side — choosing
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/emergency-offer-response` — §Phase 17 item 4.
   *
   * **Select** sets `agreedAmount` from the offer's callout fee with
   * `amountKind: callout_fee`, moves through `accepted` to
   * `awaiting_payment`, releases every other offer immediately, and incurs
   * the dispatch fee — recorded as owed and never blocking dispatch. All of
   * that is one transaction: the offer claim, the release, the fee, the
   * re-pointing of the booking and both status events land together or none
   * of them does.
   *
   * **Reject all** returns the booking to `requested`, adds **every** provider
   * who offered to `rejectedProviderIds`, and re-broadcasts. The overall window
   * is not reset.
   *
   * Refused before the collection window closes — "at the end of it the
   * customer is shown up to three offers" — and after the five minutes to
   * choose, which the sweep is about to act on.
   */
  async respond(
    userId: string,
    bookingId: string,
    response: EmergencyOfferResponse,
  ): Promise<BookingDto> {
    const now = this.clock();
    const booking = await this.customerBooking(userId, bookingId);
    const transition = 'offerId' in response ? 'select-offer' : 'reject-all-offers';
    assertTransition(transition, booking.status, 'customer');

    const closes = booking.offerCollectionClosesAt;
    if (closes !== null && now < closes) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFERS_STILL_COLLECTING',
        'Offers are still arriving — you can choose in a moment',
        { collectionClosesAt: closes.toISOString() },
      );
    }
    if (closes !== null && now >= minutesFrom(closes, OFFER_CHOICE_MINUTES)) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFERS_EXPIRED',
        'These offers have expired — your request is being sent out again',
      );
    }
    if (booking.emergencyWindowEndsAt !== null && now >= booking.emergencyWindowEndsAt) {
      throw new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }

    if ('offerId' in response) return this.select(booking, userId, response.offerId, now);
    return this.rejectAll(booking, userId, now);
  }

  private async select(
    booking: BookingRow,
    userId: string,
    offerId: string,
    now: Date,
  ): Promise<BookingDto> {
    const offer = await this.prisma.emergencyOffer.findFirst({
      where: { id: offerId, bookingId: booking.id, state: 'open' },
    });
    if (offer === null) {
      throw new NotFoundError('That offer is no longer available', 'EMERGENCY_OFFER_NOT_FOUND');
    }
    // §1c: "a booking dispatches to it only when both still hold at booking
    // time". A provider demoted, suspended or opted out in the minutes since
    // they offered is not dispatched.
    const [still] = await this.recipients(booking, offer.providerProfileId);
    if (still === undefined) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFER_NO_LONGER_AVAILABLE',
        'That provider can no longer take this job — choose another offer',
      );
    }

    const released = await this.prisma.$transaction(async (tx) => {
      // The one atomic claim left in the flow: this offer, once.
      const { count } = await tx.emergencyOffer.updateMany({
        where: { id: offer.id, state: 'open' },
        data: { state: 'selected', closedAt: now },
      });
      if (count !== 1) throw staleBooking();

      const others = await tx.emergencyOffer.findMany({
        where: { bookingId: booking.id, state: 'open' },
        select: { providerProfile: { select: { userId: true } } },
      });
      await tx.emergencyOffer.updateMany({
        where: { bookingId: booking.id, state: 'open' },
        data: { state: 'not_selected', closedAt: now },
      });

      // One emergency, one fee — a re-dispatch after a no-show finds this set.
      const feeId =
        booking.dispatchFeeSubmissionId ?? (await createOwedDispatchFee(tx, booking.customerId)).id;

      const moved = await this.repo.transition(
        booking.id,
        'emergency_offered',
        {
          status: 'accepted',
          listingId: offer.listingId,
          providerProfileId: offer.providerProfileId,
          agreedAmountLaari: offer.calloutFeeLaari,
          amountKind: 'callout_fee',
          amountSetAt: now,
          // §1c: "`scheduledFor` is set to the acceptance timestamp, so the
          // 7-day completion timeout fires normally."
          scheduledFor: now,
          offerCollectionClosesAt: null,
          emergencyOfferCount: 0,
          dispatchFeeSubmissionId: feeId,
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(
        tx,
        booking.id,
        'emergency_offered',
        'accepted',
        'select-offer',
        'customer',
        userId,
        now,
      );

      assertTransition('amount-set', 'accepted', 'customer');
      const paid = await this.repo.transition(
        booking.id,
        'accepted',
        { status: 'awaiting_payment' },
        tx,
      );
      if (!paid) throw staleBooking();
      await this.event(
        tx,
        booking.id,
        'accepted',
        'awaiting_payment',
        'amount-set',
        'customer',
        userId,
        now,
      );

      return others.map((o) => o.providerProfile.userId);
    });

    const chosen = await this.prisma.providerProfile.findUniqueOrThrow({
      where: { id: offer.providerProfileId },
      select: { userId: true },
    });
    await this.notify('emergency_offer_selected', booking.id, chosen.userId);
    for (const u of released) await this.notify('emergency_offer_not_selected', booking.id, u);

    return this.dtoFor(await this.mustFind(booking.id), 'customer');
  }

  private async rejectAll(booking: BookingRow, userId: string, now: Date): Promise<BookingDto> {
    const rejected = await this.prisma.$transaction(async (tx) => {
      const open = await tx.emergencyOffer.findMany({
        where: { bookingId: booking.id, state: 'open' },
        select: { providerProfileId: true, providerProfile: { select: { userId: true } } },
      });
      await tx.emergencyOffer.updateMany({
        where: { bookingId: booking.id, state: 'open' },
        data: { state: 'rejected', closedAt: now },
      });
      const moved = await this.repo.transition(
        booking.id,
        'emergency_offered',
        {
          status: 'requested',
          // "**every** provider who offered is added to `rejectedProviderIds`"
          rejectedProviderIds: {
            set: unique([...booking.rejectedProviderIds, ...open.map((o) => o.providerProfileId)]),
          },
          offerCollectionClosesAt: null,
          emergencyOfferCount: 0,
          // `emergencyWindowEndsAt` is deliberately untouched: "Offer
          // rejections and expiries do not reset this clock."
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(
        tx,
        booking.id,
        'emergency_offered',
        'requested',
        'reject-all-offers',
        'customer',
        userId,
        now,
      );
      return open.map((o) => o.providerProfile.userId);
    });

    // §1c: "The rejected provider is told the customer went elsewhere, without a reason."
    for (const u of rejected) await this.notify('emergency_offer_rejected', booking.id, u);
    const row = await this.mustFind(booking.id);
    await this.broadcast(row);
    return this.dtoFor(row, 'customer');
  }

  // =========================================================================
  // After selection — the provider who does not come
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/provider-not-arrived` — Round 15: "the customer may
   * mark 'provider has not arrived' … at any point after the category's accept
   * window elapses. This releases the provider, records a **no-show** against
   * their conduct record, and **re-broadcasts immediately** excluding them. No
   * admin is involved." And from the fee rule: "a re-dispatch under the
   * no-show rule does **not** incur a second fee."
   *
   * The no-show is recorded on the provider's own offer — `state: no_show` —
   * which is where §1f's conduct window reads it, and in the status timeline
   * as a customer-caused `provider-not-arrived`.
   */
  async markNotArrived(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const booking = await this.customerBooking(userId, bookingId);
    assertTransition('provider-not-arrived', booking.status, 'customer');

    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    if (booking.amountSetAt === null || window === null) throw staleBooking();
    const availableAt = minutesFrom(booking.amountSetAt, window);
    if (now < availableAt) {
      throw new BusinessRuleError(
        'EMERGENCY_NOT_ARRIVED_TOO_EARLY',
        'You can report this once the response window has passed',
        { availableAt: availableAt.toISOString() },
      );
    }

    const released = booking.providerProfile.user.id;
    await this.prisma.$transaction(async (tx) => {
      await tx.emergencyOffer.updateMany({
        where: {
          bookingId: booking.id,
          providerProfileId: booking.providerProfileId,
          state: 'selected',
        },
        data: { state: 'no_show', closedAt: now },
      });
      await this.redispatch(tx, booking, 'provider-not-arrived', 'customer', userId, now);
    });

    await this.notify('emergency_provider_released', booking.id, released);
    const row = await this.mustFind(booking.id);
    await this.broadcast(row);
    return this.dtoFor(row, 'customer');
  }

  /**
   * §1h, for emergency: "**Emergency bookings re-broadcast** through the normal
   * §1c dispatch, excluding the cancelling provider. No new dispatch fee is
   * incurred. The cancelling provider takes the conduct hit." Reached from
   * `BookingService.cancel` when the provider on an emergency cancels — the
   * endpoint is §Phase 17.1's, the re-broadcast was always this slice's.
   */
  async providerCancelled(booking: BookingRow, userId: string): Promise<void> {
    const now = this.clock();
    assertTransition('emergency-provider-cancel', booking.status, 'provider');
    await this.prisma.$transaction(async (tx) => {
      await tx.emergencyOffer.updateMany({
        where: {
          bookingId: booking.id,
          providerProfileId: booking.providerProfileId,
          state: 'selected',
        },
        data: { state: 'cancelled', closedAt: now },
      });
      await this.redispatch(tx, booking, 'emergency-provider-cancel', 'provider', userId, now);
    });
    await this.notify('emergency_redispatched', booking.id, booking.customer.id);
    await this.broadcast(await this.mustFind(booking.id));
  }

  /**
   * Back to `requested`, with the released provider excluded and the agreement
   * cleared — the next provider gets a fresh one, and §1h's lock applies to it
   * from its own `accepted`.
   *
   * 🔧 **A fresh answer window.** The Done-when says an unanswered set of
   * offers re-broadcasts "without resetting the overall window", and that
   * stands for the two pre-selection re-broadcasts. After selection the
   * original window has long run out — a no-show is only reportable once it
   * has — so re-broadcasting into it would decline the request on arrival and
   * dead-end exactly the customer §1h says must never be. The category's
   * window is read again, never a literal.
   *
   * The fee (`dispatchFeeSubmissionId`) is kept — one emergency, one fee.
   */
  private async redispatch(
    tx: Prisma.TransactionClient,
    booking: BookingRow,
    transition: 'provider-not-arrived' | 'emergency-provider-cancel',
    actor: BookingActorRole,
    userId: string,
    now: Date,
  ): Promise<void> {
    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    if (window === null) throw staleBooking();
    const moved = await this.repo.transition(
      booking.id,
      booking.status,
      {
        status: 'requested',
        rejectedProviderIds: {
          set: unique([...booking.rejectedProviderIds, booking.providerProfileId]),
        },
        agreedAmountLaari: null,
        amountKind: null,
        amountSetAt: null,
        scheduledFor: null,
        paymentClaimedAt: null,
        paymentAttestedAt: null,
        completionPromptedAt: null,
        offerCollectionClosesAt: null,
        emergencyOfferCount: 0,
        emergencyWindowEndsAt: minutesFrom(now, window),
      },
      tx,
    );
    if (!moved) throw staleBooking();
    await this.event(tx, booking.id, booking.status, 'requested', transition, actor, userId, now);
  }

  // =========================================================================
  // §Phase 17 item 21 — the verification revocation cascade
  // =========================================================================

  /**
   * Called when a provider's `verificationTier` changes. §Phase 17 item 21:
   * "their in-flight emergency bookings are handled by payment state, not
   * uniformly: at `accepted` or `awaiting_payment` the booking **auto-cancels**
   * with both parties notified; at `payment_claimed`, `confirmed`, or later it
   * is **routed to the admin queue as a dispute** and left otherwise
   * untouched. Auto-cancelling a booking the customer has already paid for
   * off-platform would strand real money with no platform recourse."
   *
   * 🔧 **The bar is the booking's category, not a flat `silver`.** Item 21 is
   * Round 9's wording ("drops below `silver`"); Round 15 made the gate
   * per-category, and a gold electrician demoted to silver no longer meets
   * Electrical's bar while still meeting AC Repair's. Evaluated through
   * `emergencyEligibility`, the one place the composed rule is written.
   *
   * **Who calls it:** whatever changes a tier — §Phase 10a part 2's
   * verification queue, deferred by the owner (ledger **P10-DEFER**). Nothing
   * in this codebase changes a tier yet, so this is reached from tests alone,
   * the same position `ListingService.reevaluateEmergencyEligibility` is in
   * (ledger **P8-3**). Ledger **P17-5** carries the wiring.
   */
  async onProviderTierChanged(
    providerProfileId: string,
  ): Promise<{ cancelled: string[]; routedToAdmin: string[] }> {
    const now = this.clock();
    const profile = await this.prisma.providerProfile.findUniqueOrThrow({
      where: { id: providerProfileId },
      select: { verificationTier: true },
    });
    const candidates = await this.prisma.booking.findMany({
      where: { providerProfileId, bookingMode: 'emergency', status: { in: [...IN_FLIGHT] } },
      select: { id: true },
    });

    const cancelled: string[] = [];
    const routedToAdmin: string[] = [];
    for (const { id } of candidates) {
      const booking = await this.repo.findById(id);
      const category = booking?.listing.category ?? null;
      if (booking === null || category === null) continue;
      if (emergencyEligibility({ category, providerTier: profile.verificationTier }).eligible) {
        continue;
      }

      if (booking.status === 'accepted' || booking.status === 'awaiting_payment') {
        const done = await this.prisma.$transaction(async (tx) => {
          const moved = await this.repo.transition(
            booking.id,
            booking.status,
            { status: 'cancelled', cancelledAt: now, cancelledByRole: 'system' },
            tx,
          );
          if (!moved) return false;
          await tx.emergencyOffer.updateMany({
            where: { bookingId: booking.id, providerProfileId, state: 'selected' },
            data: { state: 'lapsed', closedAt: now },
          });
          await this.event(
            tx,
            booking.id,
            booking.status,
            'cancelled',
            'verification-revoked',
            'system',
            null,
            now,
          );
          return true;
        });
        if (done) {
          cancelled.push(booking.id);
          await this.notify('cancelled_verification_revoked', booking.id, booking.customer.id);
          await this.notify(
            'cancelled_verification_revoked',
            booking.id,
            booking.providerProfile.user.id,
          );
        }
        continue;
      }

      // Paid, or past it: the admin queue, and nothing else moves. One Report
      // per booking — a second tier change must not file a second.
      const existing = await this.prisma.report.findFirst({
        where: { bookingId: booking.id, reason: 'provider_verification_revoked' },
        select: { id: true },
      });
      if (existing === null) {
        await this.repo.createReport(
          {
            // The system filed it; recording a human reporter would be a lie
            // about who complained.
            reporterId: null,
            targetType: 'booking',
            targetId: booking.id,
            bookingId: booking.id,
            reason: 'provider_verification_revoked',
            status: 'open',
            createdAt: now,
          },
          this.prisma,
        );
      }
      routedToAdmin.push(booking.id);
    }
    return { cancelled, routedToAdmin };
  }

  // =========================================================================
  // Scheduled jobs
  // =========================================================================

  /**
   * §Phase 17 item 4: "**Scheduled job — offer expiry:** a collection window
   * whose customer has not responded **5 minutes** after it closes → release
   * all offers, return to `requested`, re-broadcast." The released providers
   * are **not** excluded — a silent customer is not a verdict on anyone's
   * offer — and the overall window is not reset.
   *
   * A request whose overall window has also run out is left for the window
   * sweep, which declines it; re-broadcasting a request that is about to be
   * declined would page every provider for nothing.
   */
  async runOfferChoiceTimeouts(now: Date, limit = 200): Promise<{ expired: number }> {
    const due = await this.repo.findOfferChoiceTimeouts(
      minutesFrom(now, -OFFER_CHOICE_MINUTES),
      limit,
    );
    let expired = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'emergency_offered') continue;
      if (booking.emergencyWindowEndsAt !== null && now >= booking.emergencyWindowEndsAt) continue;
      const released = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'emergency_offered',
          { status: 'requested', offerCollectionClosesAt: null, emergencyOfferCount: 0 },
          tx,
        );
        if (!moved) return null;
        const open = await tx.emergencyOffer.findMany({
          where: { bookingId: booking.id, state: 'open' },
          select: { providerProfile: { select: { userId: true } } },
        });
        await tx.emergencyOffer.updateMany({
          where: { bookingId: booking.id, state: 'open' },
          data: { state: 'expired', closedAt: now },
        });
        await this.event(
          tx,
          booking.id,
          'emergency_offered',
          'requested',
          'offer-choice-timeout',
          'system',
          null,
          now,
        );
        return open.map((o) => o.providerProfile.userId);
      });
      if (released === null) continue;
      expired += 1;
      for (const u of released) await this.notify('emergency_offer_expired', booking.id, u);
      await this.broadcast(await this.mustFind(booking.id));
    }
    return { expired };
  }

  /**
   * §Phase 17 item 4: "**Scheduled job — request expiry:** a `requested`
   * emergency booking older than its category's
   * `emergencyAcceptWindowMinutes` (30 for all four emergency categories —
   * Round 22) → auto-decline, notify, offer re-broadcast or conversion to a
   * request-based booking."
   *
   * The deadline is the stored `emergencyWindowEndsAt`, stamped from the
   * category at creation, so Moving expires at exactly the moment Plumbing
   * does and neither is a literal. The "re-broadcast or conversion" offer is
   * the screen's (`Emergency Flow.dc.html`'s "Try again now" and "Turn into a
   * scheduled request"), and both are ordinary creation calls against the
   * same listing — nothing is charged, because nothing was selected.
   */
  async runWindowTimeouts(now: Date, limit = 200): Promise<{ declined: number }> {
    const due = await this.repo.findEmergencyWindowTimeouts(now, limit);
    let declined = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking === null || !isPreSelectionEmergency(booking)) continue;
      const released = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          booking.status,
          {
            status: 'declined',
            declinedAt: now,
            offerCollectionClosesAt: null,
            emergencyOfferCount: 0,
          },
          tx,
        );
        if (!moved) return null;
        const open = await tx.emergencyOffer.findMany({
          where: { bookingId: booking.id, state: 'open' },
          select: { providerProfile: { select: { userId: true } } },
        });
        await tx.emergencyOffer.updateMany({
          where: { bookingId: booking.id, state: 'open' },
          data: { state: 'lapsed', closedAt: now },
        });
        await this.event(
          tx,
          booking.id,
          booking.status,
          'declined',
          'emergency-window-timeout',
          'system',
          null,
          now,
        );
        return open.map((o) => o.providerProfile.userId);
      });
      if (released === null) continue;
      declined += 1;
      await this.notify('emergency_window_expired', booking.id, booking.customer.id);
      for (const u of released) await this.notify('emergency_request_closed', booking.id, u);
    }
    return { declined };
  }

  // =========================================================================
  // Reads
  // =========================================================================

  /**
   * The `emergency` block of an emergency booking's detail read, for either
   * party. Called by `BookingService.read`, so the customer's screen polls one
   * endpoint for everything.
   */
  async detailsFor(
    booking: BookingRow,
    role: 'customer' | 'provider',
  ): Promise<EmergencyDetailsDto> {
    const now = this.clock();
    const phase = emergencyPhase(booking, now);
    const offers = await this.prisma.emergencyOffer.findMany({
      where:
        phase === 'matched'
          ? {
              bookingId: booking.id,
              state: 'selected',
              providerProfileId: booking.providerProfileId,
            }
          : { bookingId: booking.id, state: 'open' },
      orderBy: { createdAt: 'asc' },
      include: {
        providerProfile: {
          select: {
            businessName: true,
            verificationTier: true,
            user: { select: { fullName: true } },
          },
        },
      },
    });

    // The customer sees the offers once the window closes (§1c), and the
    // chosen one after. A provider on the booking never sees rival bids.
    const visible = role === 'customer' && (phase === 'choosing' || phase === 'matched');
    const fee =
      role === 'customer' && booking.dispatchFeeSubmissionId !== null
        ? await this.prisma.paymentSubmission.findUnique({
            where: { id: booking.dispatchFeeSubmissionId },
          })
        : null;
    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    const closes = booking.offerCollectionClosesAt;

    return {
      phase,
      windowEndsAt: iso(booking.emergencyWindowEndsAt),
      collectionClosesAt: iso(closes),
      choiceEndsAt:
        closes === null ? null : minutesFrom(closes, OFFER_CHOICE_MINUTES).toISOString(),
      offersReceived: phase === 'matched' ? 0 : offers.length,
      offers: visible ? offers.map(toOfferDto) : [],
      etaPresetsMinutes: booking.listing.category?.emergencyEtaPresetsMinutes ?? [],
      dispatchFee:
        fee === null
          ? null
          : {
              submissionId: fee.id,
              amountLaari: fee.amountLaari,
              referenceCode: fee.referenceCode,
              state: dispatchFeeState(fee),
            },
      notArrivedAvailableAt:
        phase === 'matched' && booking.amountSetAt !== null && window !== null
          ? minutesFrom(booking.amountSetAt, window).toISOString()
          : null,
      contactReveal: await contactRevealState(this.prisma, this.killSwitches, booking, now),
    };
  }

  // =========================================================================
  // Internals
  // =========================================================================

  /** The customer on this emergency, or 404 — a stranger learns nothing. */
  private async customerBooking(userId: string, bookingId: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (booking?.customerId !== userId || booking.bookingMode !== 'emergency') {
      throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    }
    return booking;
  }

  /**
   * A provider's standing on one broadcast. Not found unless they could
   * answer it or already have — the existence of a request they were never
   * sent is not theirs to learn.
   */
  private async providerView(
    userId: string,
    bookingId: string,
  ): Promise<{
    booking: BookingRow;
    providerProfileId: string;
    recipient: Recipient | null;
    eligible: boolean;
    tierBlock: BusinessRuleError | null;
  }> {
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true, verificationTier: true },
    });
    const booking = await this.repo.findById(bookingId);
    if (profile === null || booking?.bookingMode !== 'emergency') {
      throw new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    }

    const [recipient] = await this.recipients(booking, profile.id);
    const offered = await this.prisma.emergencyOffer.findFirst({
      where: { bookingId: booking.id, providerProfileId: profile.id },
      select: { id: true },
    });

    // The tier half of the rule, reported by name: a provider who has an
    // emergency listing here but whose tier no longer meets this category's
    // bar is told that, rather than "not found".
    let tierBlock: BusinessRuleError | null = null;
    if (recipient === undefined && booking.listing.category !== null && booking.islandId !== null) {
      const hasListingHere = await this.prisma.listing.findFirst({
        where: {
          providerProfileId: profile.id,
          categoryId: booking.listing.categoryId,
          isEmergency: true,
          status: 'published',
          deletedAt: null,
          serviceAreas: { some: { islandId: booking.islandId, removedAt: null } },
        },
        select: { id: true },
      });
      const verdict = emergencyEligibility({
        category: booking.listing.category,
        providerTier: profile.verificationTier,
      });
      if (hasListingHere !== null && !verdict.eligible) {
        tierBlock = new BusinessRuleError(verdict.code, verdict.message);
      }
    }

    if (recipient === undefined && offered === null && tierBlock === null) {
      throw new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    }
    return {
      booking,
      providerProfileId: profile.id,
      recipient: recipient ?? null,
      eligible: recipient !== undefined && isPreSelectionEmergency(booking),
      tierBlock,
    };
  }

  private async broadcastDto(
    booking: BookingRow,
    providerProfileId: string,
    eligible: boolean,
    now: Date,
  ): Promise<EmergencyBroadcastDto> {
    const mine = await this.prisma.emergencyOffer.findFirst({
      where: { bookingId: booking.id, providerProfileId },
      orderBy: { createdAt: 'desc' },
    });
    const closes = booking.offerCollectionClosesAt;
    const open =
      isPreSelectionEmergency(booking) &&
      booking.emergencyWindowEndsAt !== null &&
      now < booking.emergencyWindowEndsAt &&
      (closes === null || now < closes);
    return {
      bookingId: booking.id,
      categoryName: booking.listing.category?.name ?? 'Service',
      customerFirstName: firstName(booking.customer.fullName),
      jobNotes: booking.jobNotes,
      islandDisplayName: booking.island === null ? null : islandDisplayName(booking.island),
      createdAt: booking.createdAt.toISOString(),
      windowEndsAt: iso(booking.emergencyWindowEndsAt),
      collectionClosesAt: iso(closes),
      choiceEndsAt:
        closes === null ? null : minutesFrom(closes, OFFER_CHOICE_MINUTES).toISOString(),
      etaPresetsMinutes: booking.listing.category?.emergencyEtaPresetsMinutes ?? [],
      myOffer:
        mine === null
          ? null
          : {
              id: mine.id,
              state: mine.state,
              calloutFeeLaari: mine.calloutFeeLaari,
              etaMinutes: mine.etaMinutes,
              createdAt: mine.createdAt.toISOString(),
            },
      canOffer: eligible && open && mine?.state !== 'open',
    };
  }

  /** Which refusal applies when the admission gate matched nothing. */
  private async whyNotAdmitted(tx: Db, bookingId: string, now: Date): Promise<Error> {
    const row = await tx.booking.findUnique({
      where: { id: bookingId },
      select: {
        status: true,
        emergencyOfferCount: true,
        emergencyWindowEndsAt: true,
        offerCollectionClosesAt: true,
      },
    });
    if (row === null) return new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    if (!PRE_SELECTION.includes(row.status)) {
      return new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }
    if (row.emergencyWindowEndsAt === null || now >= row.emergencyWindowEndsAt) {
      return new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }
    if (row.offerCollectionClosesAt !== null && now >= row.offerCollectionClosesAt) {
      return new BusinessRuleError(
        'EMERGENCY_OFFERS_CLOSED',
        'Offers for this request have closed — the customer is choosing',
      );
    }
    return new BusinessRuleError(
      'EMERGENCY_OFFERS_FULL',
      'This request already has three offers — the customer is choosing between them',
    );
  }

  private async dtoFor(row: BookingRow, role: 'customer' | 'provider'): Promise<BookingDto> {
    const dto = toBookingDto(row, this.clock());
    dto.emergency = await this.detailsFor(row, role);
    return dto;
  }

  private async mustFind(id: string): Promise<BookingRow> {
    const booking = await this.repo.findById(id);
    if (booking === null) throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    return booking;
  }

  private async insertWithReference(
    tx: Db,
    data: Omit<Prisma.BookingUncheckedCreateInput, 'reference'>,
  ) {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      try {
        return await this.repo.create({ ...data, reference: generateBookingReference() }, tx);
      } catch (error) {
        if (attempt === 4 || !isUniqueViolation(error)) throw error;
      }
    }
    throw new Error('could not allocate a booking reference');
  }

  private async event(
    tx: Db,
    bookingId: string,
    from: BookingStatus,
    to: BookingStatus,
    transition: string,
    actorRole: BookingActorRole,
    actorUserId: string | null,
    at: Date,
  ): Promise<void> {
    await this.repo.recordStatusEvent(
      { bookingId, fromStatus: from, toStatus: to, actorRole, actorUserId, transition, at },
      tx,
    );
  }

  private async notify(
    event: BookingNotification,
    bookingId: string,
    userId: string,
  ): Promise<void> {
    try {
      await this.notifier.notify({ event, bookingId, userId });
    } catch (error) {
      this.log.warn({ err: error, event, bookingId }, 'booking notification failed');
    }
  }
}

/** Derived, never stored — the same posture `chat.ts` takes. */
export function emergencyPhase(
  booking: Pick<BookingRow, 'status' | 'offerCollectionClosesAt' | 'emergencyOfferCount'>,
  now: Date,
): EmergencyPhase {
  if (booking.status === 'requested') return 'waiting';
  if (booking.status === 'emergency_offered') {
    const closes = booking.offerCollectionClosesAt;
    return closes !== null && now < closes ? 'collecting' : 'choosing';
  }
  if (['declined', 'cancelled'].includes(booking.status)) return 'closed';
  return 'matched';
}

function toOfferDto(row: {
  id: string;
  calloutFeeLaari: number;
  etaMinutes: number;
  state: EmergencyOfferDto['state'];
  createdAt: Date;
  providerProfile: {
    businessName: string | null;
    verificationTier: VerificationTier;
    user: { fullName: string };
  };
}): EmergencyOfferDto {
  return {
    id: row.id,
    providerName: row.providerProfile.businessName ?? row.providerProfile.user.fullName,
    verificationTier: row.providerProfile.verificationTier,
    ratingAverage: null,
    calloutFeeLaari: row.calloutFeeLaari,
    etaMinutes: row.etaMinutes,
    state: row.state,
    createdAt: row.createdAt.toISOString(),
  };
}

function staleBooking(): ConflictError {
  return new ConflictError(
    'BOOKING_CHANGED',
    'This booking changed while you were looking at it — open it again',
  );
}

function iso(d: Date | null): string | null {
  return d === null ? null : d.toISOString();
}

function unique(ids: string[]): string[] {
  return [...new Set(ids)];
}

function firstName(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? fullName;
}

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === 'object' && error !== null && (error as { code?: unknown }).code === 'P2002'
  );
}
