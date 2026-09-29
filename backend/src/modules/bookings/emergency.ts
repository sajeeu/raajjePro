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
import { islandDisplayName } from './mapper.js';
import type { BookingNotification, BookingNotifier } from './notifications.js';
import { generateBookingReference } from './reference.js';
import type { BookingRepository, BookingRow, Db } from './repository.js';
import { assertTransition } from './transitions.js';
import type {
  EmergencyBroadcastDto,
  EmergencyDetailsDto,
  EmergencyDispatchFeeDto,
  EmergencyOfferDto,
  EmergencyPhase,
  EmergencyRequestDto,
} from './types.js';
import {
  daysBefore,
  EMERGENCY_REQUESTS_PER_DAY,
  EMERGENCY_REQUESTS_PER_WEEK,
  MAX_OFFERS_SHOWN,
  minutesFrom,
  OFFER_CHOICE_MINUTES,
  OFFER_COLLECTION_SECONDS,
  secondsFrom,
} from './windows.js';

export interface EmergencyLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

/** `Emergency Flow.dc.html`'s form: which trade, what's wrong, and where. No slot, no window, no listing. */
export interface CreateEmergencyInput {
  categoryId: string;
  islandId: string;
  jobNotes: string;
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

/** Statuses at which the request is still a broadcast. */
const OPEN = ['requested', 'emergency_offered'] as const;

function isOpen(status: string): boolean {
  return (OPEN as readonly string[]).includes(status);
}

/** The statuses at which a chosen emergency provider owes a visit that has not happened. */
const IN_FLIGHT: readonly BookingStatus[] = [
  'accepted',
  'awaiting_payment',
  'payment_claimed',
  'confirmed',
  'payment_unresolved',
  'disputed',
];

const REQUEST_INCLUDE = {
  category: {
    select: {
      id: true,
      name: true,
      emergencyCapable: true,
      emergencyMinimumTier: true,
      emergencyAcceptWindowMinutes: true,
      emergencyEtaPresetsMinutes: true,
    },
  },
  customer: { select: { id: true, fullName: true } },
  island: { select: { id: true, name: true, atollAbbr: true, nameAmbiguous: true } },
} as const satisfies Prisma.EmergencyRequestInclude;

type RequestRow = Prisma.EmergencyRequestGetPayload<{ include: typeof REQUEST_INCLUDE }>;

/**
 * §Phase 17.3 — emergency dispatch and offer collection.
 *
 * ## The shape, in the plan's own words
 *
 * §1c, Round 15: "**Acceptances no longer race** — they create offers that
 * coexist, and the customer chooses." A request **broadcasts** to every
 * eligible provider at once; the first answer opens a **90-second collection
 * window** "during which every other eligible provider may also accept"; at
 * its close the customer is shown **up to three offers** side by side and has
 * **five minutes** to pick one or reject them all; picking one incurs the
 * **MVR 200 dispatch fee** and the job proceeds without waiting for it; the
 * whole request lives inside the category's `emergencyAcceptWindowMinutes`,
 * which no rejection or expiry resets.
 *
 * ## A request, then a booking
 *
 * 🔧 **Owner's decision, 2026-09-28.** An emergency is raised by **category
 * and island** (`POST /v1/emergency-requests`), never against a listing:
 * Round 23 moved the entry to Home and Explore and deleted the card marker
 * because "dispatch never targets a provider", and §1c computes the broadcast
 * from "all providers whose listing is emergency-capable in that category, who
 * serve that island". §Phase 17 item 2's listing-scoped emergency clause is
 * pre-Round-23 residue.
 *
 * So the pre-selection half of §1c's machine (`requested`,
 * `emergency_offered`) lives on the `EmergencyRequest`, and a `Booking` is
 * created — at `accepted`, against the chosen provider's own emergency
 * listing — when the customer selects an offer. `Booking.listingId` and
 * `providerProfileId` stay NOT NULL and nothing in §Phase 17.1 or 17.2
 * changes. When the chosen provider does not arrive or cancels, that booking
 * closes on **their** record and the request goes out again; the next
 * selection is a new booking under the same request and the same fee.
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
   * `POST /v1/emergency-requests` — the ASAP request, by category and island.
   *
   * Refused, in order: an unsettled dispatch fee (it blocks every new
   * booking, §1c); a category that is not emergency-capable, or capable but
   * with no bar or window configured (refused rather than defaulted — a
   * default would be a hardcoded tier or a hardcoded 30); an unknown island;
   * and last the rate limit, so a customer is never told they are over a
   * limit for a request that could not have been made anyway.
   *
   * Provider verification is checked where a provider acts — the offer (the
   * owner's reading of Done-when clause 3, 2026-09-28) — because a request
   * names no provider.
   */
  async create(userId: string, input: CreateEmergencyInput): Promise<EmergencyRequestDto> {
    const now = this.clock();
    await assertNoOutstandingDispatchFee(this.prisma, userId);

    const category = await this.prisma.category.findFirst({
      where: { id: input.categoryId, isActive: true },
      select: {
        name: true,
        emergencyCapable: true,
        emergencyMinimumTier: true,
        emergencyAcceptWindowMinutes: true,
      },
    });
    if (category === null) throw new NotFoundError('No such category', 'CATEGORY_NOT_FOUND');
    const windowMinutes = category.emergencyAcceptWindowMinutes;
    if (
      !category.emergencyCapable ||
      category.emergencyMinimumTier === null ||
      windowMinutes === null
    ) {
      throw new BusinessRuleError(
        'EMERGENCY_CATEGORY_NOT_CAPABLE',
        `${category.name} does not offer emergency callouts — send a normal request instead`,
      );
    }

    const island = await this.prisma.island.findFirst({
      where: { id: input.islandId, isActive: true },
      select: { id: true },
    });
    if (island === null) throw new NotFoundError('No such island', 'ISLAND_NOT_FOUND');

    await this.assertWithinRateLimit(userId, now);

    const created = await this.prisma.emergencyRequest.create({
      data: {
        customerId: userId,
        categoryId: input.categoryId,
        islandId: island.id,
        jobNotes: input.jobNotes,
        addressDetail: input.addressDetail ?? null,
        status: 'requested',
        // Stored, never recomputed: the customer is already watching it.
        windowEndsAt: minutesFrom(now, windowMinutes),
        createdAt: now,
      },
      include: REQUEST_INCLUDE,
    });

    const recipients = await this.broadcast(created);
    return this.requestDto(created, now, recipients);
  }

  /**
   * §1c: "Rate limit: 3 emergency requests per customer per 24 hours, 10 per 7
   * days." Counted over **requests** — a re-broadcast, a rejection or an
   * expiry happens inside one request and creates no new one, so none of them
   * can consume it ("Rejections do not consume the customer's rate limit").
   *
   * The refusal carries what `Emergency Flow.dc.html`'s limit screen prints:
   * "3 of 3 used", "7 of 10 used", and when the next request is possible.
   */
  private async assertWithinRateLimit(customerId: string, now: Date): Promise<void> {
    const recent = await this.prisma.emergencyRequest.findMany({
      where: { customerId, createdAt: { gt: daysBefore(now, 7) } },
      select: { createdAt: true },
      orderBy: { createdAt: 'asc' },
    });
    const dayAgo = daysBefore(now, 1);
    const inDay = recent.filter((r) => r.createdAt > dayAgo);
    const overDay = inDay.length >= EMERGENCY_REQUESTS_PER_DAY;
    const overWeek = recent.length >= EMERGENCY_REQUESTS_PER_WEEK;
    if (!overDay && !overWeek) return;

    // The next request is possible when the oldest request holding each
    // binding limit ages out — whichever of the two frees last.
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
   * Two halves, each somebody else's rule reused rather than restated:
   *  - **by listing** — a published, active, undeleted listing in this
   *    category with `isEmergency` set and a live service area on the job's
   *    island; the listing half of §1c's composed rule, and the per-listing
   *    areas are what discovery matches on (§Phase 8);
   *  - **by provider** — `findVisibleProviders`, §1a's one shared helper,
   *    with the category's tier as the minimum. Suspension is an input to that
   *    helper, so a suspended provider drops out here without a second copy of
   *    the filter.
   *
   * Excluded: `rejectedProviderIds`, every provider who passed on this request,
   * and the customer themselves where they are also a provider.
   */
  private async recipients(request: RequestRow, onlyProviderId?: string): Promise<Recipient[]> {
    const { category } = request;
    const minimum = category.emergencyMinimumTier;
    if (!category.emergencyCapable || minimum === null) return [];

    const passed = await this.prisma.emergencyPass.findMany({
      where: { requestId: request.id },
      select: { providerProfileId: true },
    });
    const excluded = [...request.rejectedProviderIds, ...passed.map((p) => p.providerProfileId)];

    const listings = await this.prisma.listing.findMany({
      where: {
        categoryId: category.id,
        isEmergency: true,
        status: 'published',
        visibility: 'active',
        deletedAt: null,
        serviceAreas: { some: { islandId: request.islandId, removedAt: null } },
        providerProfileId:
          onlyProviderId === undefined
            ? { notIn: excluded }
            : { equals: onlyProviderId, notIn: excluded },
        providerProfile: {
          userId: { not: request.customerId },
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
   * together with no ladder. Every send is a `PushDispatch` row whose
   * `subjectId` is the request, which is how "did this provider get the
   * emergency alert?" is answered in one lookup.
   *
   * After any transaction, never inside one: a notification that did not go
   * out must never roll back a request that did.
   */
  private async broadcast(request: RequestRow): Promise<number> {
    const recipients = await this.recipients(request);
    if (this.dispatcher !== undefined) {
      for (const r of recipients) {
        try {
          await this.dispatcher.dispatch({
            userId: r.userId,
            urgency: 'emergency',
            subjectId: request.id,
            context: {
              kind: 'emergency_dispatch',
              bookingType: request.category.name,
              customerFirstName: firstName(request.customer.fullName),
              islandName: islandDisplayName(request.island),
            },
          });
        } catch (error) {
          this.log.warn({ err: error, requestId: request.id }, 'emergency broadcast failed');
        }
      }
    }
    this.log.info(
      { requestId: request.id, recipients: recipients.length },
      'emergency request broadcast',
    );
    return recipients.length;
  }

  // =========================================================================
  // The provider's side — the inbox, the offer and the pass
  // =========================================================================

  /**
   * `GET /v1/providers/me/emergency-requests` — every open emergency this
   * provider may answer right now, newest first.
   *
   * Computed from the provider's side rather than stored per recipient: the
   * rule is live (§1c: "a provider whose verification is later revoked stops
   * receiving emergency requests immediately"), and a stored fan-out list
   * would be a second copy of it that could disagree.
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
    const scopes = mine.flatMap((l) =>
      l.categoryId === null || l.serviceAreas.length === 0
        ? []
        : [{ categoryId: l.categoryId, islandId: { in: l.serviceAreas.map((a) => a.islandId) } }],
    );
    if (scopes.length === 0) return [];

    const candidates = await this.prisma.emergencyRequest.findMany({
      where: {
        status: { in: [...OPEN] },
        windowEndsAt: { gt: now },
        customerId: { not: userId },
        NOT: { rejectedProviderIds: { has: profile.id } },
        passes: { none: { providerProfileId: profile.id } },
        OR: scopes,
      },
      include: REQUEST_INCLUDE,
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    const out: EmergencyBroadcastDto[] = [];
    for (const request of candidates) {
      // The whole rule, per request — tier, visibility, opt-in — so the inbox
      // never shows a request the offer endpoint would then refuse.
      const [me] = await this.recipients(request, profile.id);
      if (me === undefined) continue;
      out.push(await this.broadcastDto(request, profile.id, true, now));
    }
    return out;
  }

  /**
   * `GET /v1/providers/me/emergency-requests/:id` — one request, as the push
   * deep-links to it. Readable by a provider who may answer it now **or** who
   * already did, so the one who was not chosen sees that they were released.
   */
  async readForProvider(userId: string, requestId: string): Promise<EmergencyBroadcastDto> {
    const now = this.clock();
    const view = await this.providerView(userId, requestId);
    return this.broadcastDto(view.request, view.providerProfileId, view.recipient !== null, now);
  }

  /**
   * `PATCH /v1/emergency-requests/:id/emergency-accept` — §Phase 17 item 4:
   * the provider "**creates an `EmergencyOffer`** and supplies `calloutFee`
   * and `etaMinutes` in the same call. This no longer claims the booking."
   *
   * ## Every eligible provider may offer
   *
   * 🔧 **No admission cap — owner's decision, 2026-09-28.** §1c: the first
   * acceptance opens a window "during which **every other eligible provider
   * may also accept** with their own fee. At the end of it the customer is
   * shown up to three offers." "Up to three" caps what the customer is
   * *shown*, not who may bid; capping admission would bring back the race
   * Round 15 removed, with the fastest three winning rather than the nearest
   * or cheapest. The three are chosen at read time — see `shownOffers`.
   *
   * ## Why two simultaneous offers both land
   *
   * The request row is written by a conditional update whose `WHERE` carries
   * the open statuses and both windows. Postgres takes the row lock on the
   * first writer and re-evaluates the second writer's `WHERE` against the
   * committed row, so two answers in the same instant are serialised rather
   * than raced: both are admitted, and the status moves once, for whichever
   * was first. There is no `ALREADY_CLAIMED` — "atomicity applies only to the
   * offer the customer selects".
   */
  async offer(
    userId: string,
    requestId: string,
    input: EmergencyOfferInput,
  ): Promise<EmergencyBroadcastDto> {
    const now = this.clock();
    const { request, providerProfileId, recipient, tierBlock } = await this.providerView(
      userId,
      requestId,
    );

    // The tier half of the rule gets its own code, because the Done-when
    // names the case: "an emergency on Electrical is refused to a silver
    // provider and accepted from a gold one, while AC Repair accepts silver".
    // The bar is the category's, read from the row.
    if (tierBlock !== null) throw tierBlock;
    if (recipient === null) {
      throw new BusinessRuleError(
        'EMERGENCY_NOT_ELIGIBLE',
        'You can no longer answer this request',
      );
    }
    if (!isOpen(request.status) || now >= request.windowEndsAt) {
      throw new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }
    if (request.offerCollectionClosesAt !== null && now >= request.offerCollectionClosesAt) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFERS_CLOSED',
        'Offers for this request have closed — the customer is choosing',
      );
    }

    await this.prisma.$transaction(async (tx) => {
      const { count: admitted } = await tx.emergencyRequest.updateMany({
        where: {
          id: request.id,
          status: { in: [...OPEN] },
          windowEndsAt: { gt: now },
          OR: [{ offerCollectionClosesAt: null }, { offerCollectionClosesAt: { gt: now } }],
        },
        // A write, so that the row lock is what orders two simultaneous offers.
        data: { updatedAt: now },
      });
      if (admitted !== 1) {
        throw new BusinessRuleError(
          'EMERGENCY_OFFERS_CLOSED',
          'Offers for this request have closed — the customer is choosing',
        );
      }

      try {
        await tx.emergencyOffer.create({
          data: {
            requestId: request.id,
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
        if (isUniqueViolation(error)) {
          throw new ConflictError(
            'EMERGENCY_OFFER_ALREADY_MADE',
            'You have already made an offer on this request',
          );
        }
        throw error;
      }

      // The first offer of a round opens the collection window. A later one
      // matches nothing here — which is how "both produce offers" and "the
      // status moved once" are both true.
      await tx.emergencyRequest.updateMany({
        where: { id: request.id, status: 'requested' },
        data: {
          status: 'emergency_offered',
          offerCollectionClosesAt: secondsFrom(now, OFFER_COLLECTION_SECONDS),
        },
      });
    });

    return this.readForProvider(userId, requestId);
  }

  /**
   * `PATCH /v1/emergency-requests/:id/pass` — `Provider Emergency`'s "Decline
   * this request".
   *
   * 🔧 **Recorded, and not counted — owner's decision, 2026-09-28.** It takes
   * the request off this provider's list and out of any re-broadcast of it,
   * and tells nobody. §1f's acceptance rate does not read it: that rule was
   * written for bookings a provider was targeted with, and a broadcast reaches
   * everyone eligible whether they wanted it or not.
   */
  async pass(userId: string, requestId: string): Promise<EmergencyBroadcastDto> {
    const { providerProfileId, recipient } = await this.providerView(userId, requestId);
    if (recipient === null) {
      throw new BusinessRuleError('EMERGENCY_NOT_ELIGIBLE', 'This request is not on your list');
    }
    await this.prisma.emergencyPass.upsert({
      where: { requestId_providerProfileId: { requestId, providerProfileId } },
      create: { requestId, providerProfileId, createdAt: this.clock() },
      update: {},
    });
    return this.readForProvider(userId, requestId);
  }

  // =========================================================================
  // The customer's side — reading, choosing, cancelling
  // =========================================================================

  /** `GET /v1/emergency-requests/:id` — the customer's live view. */
  async readForCustomer(userId: string, requestId: string): Promise<EmergencyRequestDto> {
    const request = await this.customerRequest(userId, requestId);
    const recipients = isOpen(request.status) ? (await this.recipients(request)).length : 0;
    return this.requestDto(request, this.clock(), recipients);
  }

  /** `GET /v1/users/me/emergency-requests` — the customer's own, newest first. */
  async listForCustomer(userId: string): Promise<EmergencyRequestDto[]> {
    const now = this.clock();
    const rows = await this.prisma.emergencyRequest.findMany({
      where: { customerId: userId },
      include: REQUEST_INCLUDE,
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    const out: EmergencyRequestDto[] = [];
    for (const row of rows) out.push(await this.requestDto(row, now, 0));
    return out;
  }

  /**
   * `PATCH /v1/emergency-requests/:id/emergency-offer-response` — §Phase 17
   * item 4.
   *
   * **Select** — one of the offers the customer was shown — creates the
   * booking at `accepted` against the chosen provider's listing, with the
   * offer's callout fee as `agreedAmount` (`amountKind: callout_fee`), moves it
   * on to `awaiting_payment`, releases every other offer immediately, and
   * incurs the dispatch fee, recorded as owed and never blocking dispatch.
   * All of that is **one transaction**.
   *
   * **Reject all** returns the request to `requested`, adds **every** provider
   * who offered to `rejectedProviderIds`, and re-broadcasts. The overall
   * window is not reset.
   *
   * Refused before the collection window closes ("at the end of it the
   * customer is shown up to three offers") and after the five minutes to
   * choose, which the sweep is about to act on.
   */
  async respond(
    userId: string,
    requestId: string,
    response: EmergencyOfferResponse,
  ): Promise<EmergencyRequestDto> {
    const now = this.clock();
    const request = await this.customerRequest(userId, requestId);
    if (request.status !== 'emergency_offered') {
      throw new BusinessRuleError(
        'EMERGENCY_NO_OFFERS_TO_ANSWER',
        'There are no offers on this request to answer',
        { status: request.status },
      );
    }
    const closes = request.offerCollectionClosesAt;
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
    if (now >= request.windowEndsAt) {
      throw new BusinessRuleError('EMERGENCY_REQUEST_CLOSED', 'This request has closed');
    }

    if ('offerId' in response) return this.select(request, userId, response.offerId, now);
    return this.rejectAll(request, now);
  }

  private async select(
    request: RequestRow,
    userId: string,
    offerId: string,
    now: Date,
  ): Promise<EmergencyRequestDto> {
    const shown = await this.shownOffers(request.id);
    const offer = shown.find((o) => o.id === offerId);
    if (offer === undefined) {
      throw new NotFoundError('That offer is no longer available', 'EMERGENCY_OFFER_NOT_FOUND');
    }
    // §1c, Round 17: "a booking dispatches to it only when both still hold at
    // booking time". A provider demoted, suspended or opted out in the minutes
    // since they offered is not dispatched.
    const [still] = await this.recipients(request, offer.providerProfileId);
    if (still === undefined) {
      throw new BusinessRuleError(
        'EMERGENCY_OFFER_NO_LONGER_AVAILABLE',
        'That provider can no longer take this job — choose another offer',
      );
    }

    const outcome = await this.prisma.$transaction(async (tx) => {
      // The one atomic claim left in the flow: this offer, once.
      const { count } = await tx.emergencyOffer.updateMany({
        where: { id: offer.id, state: 'open' },
        data: { state: 'selected', closedAt: now },
      });
      if (count !== 1) throw stale();

      const others = await tx.emergencyOffer.findMany({
        where: { requestId: request.id, state: 'open' },
        select: { providerProfile: { select: { userId: true } } },
      });
      await tx.emergencyOffer.updateMany({
        where: { requestId: request.id, state: 'open' },
        data: { state: 'not_selected', closedAt: now },
      });

      // One emergency, one fee — a re-dispatch after a no-show finds this set.
      const feeId =
        request.dispatchFeeSubmissionId ?? (await createOwedDispatchFee(tx, request.customerId)).id;

      const { count: matched } = await tx.emergencyRequest.updateMany({
        where: { id: request.id, status: 'emergency_offered' },
        data: { status: 'matched', offerCollectionClosesAt: null, dispatchFeeSubmissionId: feeId },
      });
      if (matched !== 1) throw stale();

      const booking = await this.insertWithReference(tx, {
        listingId: offer.listingId,
        customerId: request.customerId,
        providerProfileId: offer.providerProfileId,
        bookingMode: 'emergency',
        status: 'accepted',
        agreedAmountLaari: offer.calloutFeeLaari,
        amountKind: 'callout_fee',
        amountSetAt: now,
        // §1c: "`scheduledFor` is set to the acceptance timestamp, so the
        // 7-day completion timeout fires normally."
        scheduledFor: now,
        jobNotes: request.jobNotes,
        islandId: request.islandId,
        addressDetail: request.addressDetail,
        emergencyRequestId: request.id,
        createdAt: now,
      });
      await tx.emergencyOffer.update({ where: { id: offer.id }, data: { bookingId: booking.id } });

      // `select-offer` is the booking's creation edge (`from: []`), recorded as
      // the first status event exactly as `create` is for a slot booking.
      await this.event(tx, booking.id, null, 'accepted', 'select-offer', 'customer', userId, now);

      // §1c step 3: no booking reaches `awaiting_payment` without an amount.
      // It has one, in the same transaction.
      assertTransition('amount-set', 'accepted', 'customer');
      const paid = await this.repo.transition(
        booking.id,
        'accepted',
        { status: 'awaiting_payment' },
        tx,
      );
      if (!paid) throw stale();
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

      return { bookingId: booking.id, released: others.map((o) => o.providerProfile.userId) };
    });

    const chosen = await this.prisma.providerProfile.findUniqueOrThrow({
      where: { id: offer.providerProfileId },
      select: { userId: true },
    });
    await this.notify('emergency_offer_selected', outcome.bookingId, chosen.userId);
    for (const u of outcome.released) {
      await this.notify('emergency_offer_not_selected', request.id, u);
    }

    return this.readForCustomer(userId, request.id);
  }

  private async rejectAll(request: RequestRow, now: Date): Promise<EmergencyRequestDto> {
    const rejected = await this.prisma.$transaction(async (tx) => {
      const open = await tx.emergencyOffer.findMany({
        where: { requestId: request.id, state: 'open' },
        select: { providerProfileId: true, providerProfile: { select: { userId: true } } },
      });
      await tx.emergencyOffer.updateMany({
        where: { requestId: request.id, state: 'open' },
        data: { state: 'rejected', closedAt: now },
      });
      const { count } = await tx.emergencyRequest.updateMany({
        where: { id: request.id, status: 'emergency_offered' },
        data: {
          status: 'requested',
          // "**every** provider who offered is added to `rejectedProviderIds`"
          rejectedProviderIds: {
            set: unique([...request.rejectedProviderIds, ...open.map((o) => o.providerProfileId)]),
          },
          offerCollectionClosesAt: null,
          // `windowEndsAt` is deliberately untouched: "Offer rejections and
          // expiries do not reset this clock."
        },
      });
      if (count !== 1) throw stale();
      return open.map((o) => o.providerProfile.userId);
    });

    // §1c: "The rejected provider is told the customer went elsewhere, without a reason."
    for (const u of rejected) await this.notify('emergency_offer_rejected', request.id, u);
    await this.broadcast(await this.mustFindRequest(request.id));
    return this.readForCustomer(request.customerId, request.id);
  }

  /**
   * `PATCH /v1/emergency-requests/:id/cancel` — `Emergency Flow`'s "Cancel
   * request", before anyone is chosen. "Providers will be told the request is
   * closed. Nothing has been charged" — true, because the fee is incurred only
   * by selecting.
   */
  async cancel(userId: string, requestId: string): Promise<EmergencyRequestDto> {
    const now = this.clock();
    const request = await this.customerRequest(userId, requestId);
    const released = await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.emergencyRequest.updateMany({
        where: { id: request.id, status: { in: [...OPEN] } },
        data: { status: 'cancelled', closedAt: now, offerCollectionClosesAt: null },
      });
      if (count !== 1) {
        throw new BusinessRuleError(
          'EMERGENCY_REQUEST_CLOSED',
          'This request has already been answered or closed',
        );
      }
      return this.lapseOpenOffers(tx, request.id, now);
    });
    for (const u of released) await this.notify('emergency_request_closed', request.id, u);
    return this.readForCustomer(userId, requestId);
  }

  // =========================================================================
  // After selection — the provider who does not come
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/provider-not-arrived` — Round 15: the customer may
   * mark "provider has not arrived" "at any point after the category's accept
   * window elapses. This releases the provider, records a **no-show** against
   * their conduct record, and **re-broadcasts immediately** excluding them. No
   * admin is involved." And from the fee rule: "a re-dispatch under the
   * no-show rule does **not** incur a second fee."
   *
   * The booking closes — on the no-show provider's own record, as
   * `provider-not-arrived` caused by the customer — and the offer it came from
   * becomes `no_show`, which is where §1f reads it. The request goes out again.
   */
  async markNotArrived(userId: string, bookingId: string): Promise<EmergencyRequestDto> {
    const now = this.clock();
    const booking = await this.repo.findById(bookingId);
    if (booking?.customerId !== userId || booking.emergencyRequestId === null) {
      throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    }
    assertTransition('provider-not-arrived', booking.status, 'customer');

    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    if (booking.amountSetAt === null || window === null) throw stale();
    const availableAt = minutesFrom(booking.amountSetAt, window);
    if (now < availableAt) {
      throw new BusinessRuleError(
        'EMERGENCY_NOT_ARRIVED_TOO_EARLY',
        'You can report this once the response window has passed',
        { availableAt: availableAt.toISOString() },
      );
    }

    const requestId = booking.emergencyRequestId;
    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        { status: 'cancelled', cancelledAt: now },
        tx,
      );
      if (!moved) throw stale();
      await this.event(
        tx,
        booking.id,
        booking.status,
        'cancelled',
        'provider-not-arrived',
        'customer',
        userId,
        now,
      );
      await tx.emergencyOffer.updateMany({
        where: { bookingId: booking.id },
        data: { state: 'no_show', closedAt: now },
      });
      await this.reopen(tx, requestId, booking, now);
    });

    await this.notify('emergency_provider_released', booking.id, booking.providerProfile.user.id);
    await this.broadcast(await this.mustFindRequest(requestId));
    return this.readForCustomer(userId, requestId);
  }

  /**
   * §1h, for emergency: "**Emergency bookings re-broadcast** through the normal
   * §1c dispatch, excluding the cancelling provider. No new dispatch fee is
   * incurred. The cancelling provider takes the conduct hit." Reached from
   * `BookingService.cancel` when the provider on an emergency booking cancels.
   *
   * The booking takes §Phase 17.1's own `provider-cancel` edge — `cancelled`,
   * `cancelledByRole: provider`, the row §1f's cancellation rate counts — and
   * in the same transaction the request goes out again.
   */
  async providerCancelled(booking: BookingRow, userId: string, reason?: string): Promise<void> {
    const now = this.clock();
    const requestId = booking.emergencyRequestId;
    if (requestId === null) throw stale();
    assertTransition('provider-cancel', booking.status, 'provider');
    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'cancelled',
          cancelledAt: now,
          cancelledByRole: 'provider',
          cancellationReason: reason ?? null,
        },
        tx,
      );
      if (!moved) throw stale();
      await this.event(
        tx,
        booking.id,
        booking.status,
        'cancelled',
        'provider-cancel',
        'provider',
        userId,
        now,
      );
      await tx.emergencyOffer.updateMany({
        where: { bookingId: booking.id },
        data: { state: 'cancelled', closedAt: now },
      });
      await this.reopen(tx, requestId, booking, now);
    });
    await this.notify('emergency_redispatched', booking.id, booking.customer.id);
    await this.broadcast(await this.mustFindRequest(requestId));
  }

  /**
   * The request goes out again after a chosen provider fell through, with that
   * provider excluded and the fee kept.
   *
   * 🔧 **A fresh answer window — agreed with the owner 2026-09-28.** The
   * Done-when says an unanswered set of offers re-broadcasts "without
   * resetting the overall window", and that stands for the two pre-selection
   * re-broadcasts. After selection the original window has long run out — a
   * no-show is only reportable once it has — so re-broadcasting into it would
   * decline the request on arrival and dead-end exactly the customer §1h says
   * must never be. The category's window is read again, never a literal.
   */
  private async reopen(
    tx: Prisma.TransactionClient,
    requestId: string,
    booking: BookingRow,
    now: Date,
  ): Promise<void> {
    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    if (window === null) throw stale();
    const request = await tx.emergencyRequest.findUniqueOrThrow({
      where: { id: requestId },
      select: { rejectedProviderIds: true },
    });
    const { count } = await tx.emergencyRequest.updateMany({
      where: { id: requestId, status: 'matched' },
      data: {
        status: 'requested',
        rejectedProviderIds: {
          set: unique([...request.rejectedProviderIds, booking.providerProfileId]),
        },
        offerCollectionClosesAt: null,
        windowEndsAt: minutesFrom(now, window),
      },
    });
    if (count !== 1) throw stale();
  }

  // =========================================================================
  // §Phase 17 item 21 — the verification revocation cascade
  // =========================================================================

  /**
   * Called when a provider's `verificationTier` changes. §Phase 17 item 21:
   * "their in-flight emergency bookings are handled by payment state, not
   * uniformly: at `accepted` or `awaiting_payment` the booking **auto-cancels**
   * with both parties notified; at `payment_claimed`, `confirmed`, or later it
   * is **routed to the admin queue as a dispute** and left otherwise untouched.
   * Auto-cancelling a booking the customer has already paid for off-platform
   * would strand real money with no platform recourse."
   *
   * 🔧 **The bar is the booking's category, not a flat `silver`.** Item 21 is
   * Round 9's wording ("drops below `silver`"); Round 15 made the gate
   * per-category, and a gold electrician demoted to silver no longer meets
   * Electrical's bar while still meeting AC Repair's (invariant 1c). Evaluated
   * through `emergencyEligibility`, the one place the composed rule is written.
   *
   * **Who calls it:** whatever changes a tier — §Phase 10a part 2's
   * verification queue, deferred by the owner (ledger **P10-DEFER**). Nothing
   * in this codebase changes a tier yet, so it is reached from tests alone,
   * the position `ListingService.reevaluateEmergencyEligibility` is in (ledger
   * **P8-3**). Ledger **P17-5** carries the wiring.
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
            where: { bookingId: booking.id },
            data: { state: 'lapsed', closedAt: now },
          });
          // 🔧 §0.0 item 24 (owner, 2026-09-29): "a booking the platform
          // itself cancels waives the fee". The customer chose an offer in
          // good faith and RaajjePro removed the provider — nothing happens,
          // so nothing is owed. Only an unsettled fee is waived: one an admin
          // has already confirmed is money received, and returning it is a
          // manual matter outside this system. The request closes with the
          // booking; it is not re-broadcast (§Phase 17 item 21 auto-cancels).
          if (booking.emergencyRequestId !== null) {
            const request = await tx.emergencyRequest.findUniqueOrThrow({
              where: { id: booking.emergencyRequestId },
              select: { dispatchFeeSubmissionId: true },
            });
            if (request.dispatchFeeSubmissionId !== null) {
              await tx.paymentSubmission.updateMany({
                where: {
                  id: request.dispatchFeeSubmissionId,
                  status: { not: 'confirmed' },
                  waivedAt: null,
                },
                data: { waivedAt: now, waivedReason: 'provider_verification_revoked' },
              });
            }
            await tx.emergencyRequest.updateMany({
              where: { id: booking.emergencyRequestId, status: 'matched' },
              data: { status: 'cancelled', closedAt: now },
            });
          }
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
   * sweep, which declines it; re-broadcasting a request about to be declined
   * would page every provider for nothing.
   */
  async runOfferChoiceTimeouts(now: Date, limit = 200): Promise<{ expired: number }> {
    const due = await this.prisma.emergencyRequest.findMany({
      where: {
        status: 'emergency_offered',
        offerCollectionClosesAt: { not: null, lte: minutesFrom(now, -OFFER_CHOICE_MINUTES) },
        windowEndsAt: { gt: now },
      },
      select: { id: true },
      orderBy: { offerCollectionClosesAt: 'asc' },
      take: limit,
    });
    let expired = 0;
    for (const { id } of due) {
      const released = await this.prisma.$transaction(async (tx) => {
        const { count } = await tx.emergencyRequest.updateMany({
          where: { id, status: 'emergency_offered' },
          data: { status: 'requested', offerCollectionClosesAt: null },
        });
        if (count !== 1) return null;
        const open = await tx.emergencyOffer.findMany({
          where: { requestId: id, state: 'open' },
          select: { providerProfile: { select: { userId: true } } },
        });
        await tx.emergencyOffer.updateMany({
          where: { requestId: id, state: 'open' },
          data: { state: 'expired', closedAt: now },
        });
        return open.map((o) => o.providerProfile.userId);
      });
      if (released === null) continue;
      expired += 1;
      for (const u of released) await this.notify('emergency_offer_expired', id, u);
      await this.broadcast(await this.mustFindRequest(id));
    }
    return { expired };
  }

  /**
   * §Phase 17 item 4: "**Scheduled job — request expiry:** a `requested`
   * emergency booking older than its category's `emergencyAcceptWindowMinutes`
   * (30 for all four emergency categories — Round 22) → auto-decline, notify,
   * offer re-broadcast or conversion to a request-based booking."
   *
   * The deadline is the stored `windowEndsAt`, stamped from the category at
   * creation, so Moving expires at exactly the moment Plumbing does and
   * neither is a literal. From `emergency_offered` too: "the window governs
   * the whole request, so a customer who rejects three offers has spent that
   * time." The "re-broadcast or conversion" offer is the screen's — "Try
   * again now" and "Turn into a scheduled request" — and both are ordinary
   * creation calls; nothing is charged, because nothing was selected.
   */
  async runWindowTimeouts(now: Date, limit = 200): Promise<{ declined: number }> {
    const due = await this.prisma.emergencyRequest.findMany({
      where: { status: { in: [...OPEN] }, windowEndsAt: { lte: now } },
      select: { id: true, customerId: true },
      orderBy: { windowEndsAt: 'asc' },
      take: limit,
    });
    let declined = 0;
    for (const { id, customerId } of due) {
      const released = await this.prisma.$transaction(async (tx) => {
        const { count } = await tx.emergencyRequest.updateMany({
          where: { id, status: { in: [...OPEN] } },
          data: { status: 'declined', closedAt: now, offerCollectionClosesAt: null },
        });
        if (count !== 1) return null;
        return this.lapseOpenOffers(tx, id, now);
      });
      if (released === null) continue;
      declined += 1;
      await this.notify('emergency_window_expired', id, customerId);
      for (const u of released) await this.notify('emergency_request_closed', id, u);
    }
    return { declined };
  }

  // =========================================================================
  // The booking detail's emergency block
  // =========================================================================

  /**
   * The `emergency` block of an emergency booking's detail read, for either
   * party. Called by `BookingService.read`.
   */
  async detailsFor(
    booking: BookingRow,
    role: 'customer' | 'provider',
  ): Promise<EmergencyDetailsDto> {
    const now = this.clock();
    const request =
      booking.emergencyRequestId === null
        ? null
        : await this.prisma.emergencyRequest.findUnique({
            where: { id: booking.emergencyRequestId },
            select: { id: true, dispatchFeeSubmission: true },
          });
    const offer = await this.prisma.emergencyOffer.findUnique({
      where: { bookingId: booking.id },
      select: { etaMinutes: true },
    });
    const window = booking.listing.category?.emergencyAcceptWindowMinutes ?? null;
    const reportable =
      booking.status === 'awaiting_payment' ||
      booking.status === 'payment_claimed' ||
      booking.status === 'confirmed';
    const fee = request?.dispatchFeeSubmission ?? null;

    return {
      requestId: request?.id ?? null,
      etaMinutes: offer?.etaMinutes ?? null,
      // The fee is the customer's to settle; the provider has no business with
      // RaajjePro's own money.
      dispatchFee: role === 'customer' && fee !== null ? toFeeDto(fee) : null,
      notArrivedAvailableAt:
        role === 'customer' && reportable && booking.amountSetAt !== null && window !== null
          ? minutesFrom(booking.amountSetAt, window).toISOString()
          : null,
      contactReveal: await contactRevealState(this.prisma, this.killSwitches, booking, now),
    };
  }

  // =========================================================================
  // Internals
  // =========================================================================

  /**
   * Up to three of this round's open offers, as the customer is shown them.
   *
   * 🔧 **The ranking is ours to state — the plan says "up to three" and not
   * which.** §1c names what the collection window is for: the winner should be
   * "whoever was **nearest or cheapest**" rather than whoever tapped fastest.
   * Nearest cannot be computed — the system knows islands and nothing finer,
   * and every recipient already serves the job's island (owner's decision on
   * distance, 2026-09-28) — so the order is **callout fee, lowest first**;
   * then the **provider's own arrival estimate**, soonest first, as the
   * nearest thing to "nearest" that exists; then the earlier offer, so a tie
   * is broken by something both parties can see rather than by row order.
   * An offer outside the three is released as `not_selected` when the
   * customer chooses, exactly like an unchosen one inside it.
   */
  private async shownOffers(requestId: string) {
    return this.prisma.emergencyOffer.findMany({
      where: { requestId, state: 'open' },
      orderBy: [{ calloutFeeLaari: 'asc' }, { etaMinutes: 'asc' }, { createdAt: 'asc' }],
      take: MAX_OFFERS_SHOWN,
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
  }

  private async requestDto(
    request: RequestRow,
    now: Date,
    recipients: number,
  ): Promise<EmergencyRequestDto> {
    const phase = requestPhase(request, now);
    const offersReceived =
      phase === 'collecting' || phase === 'choosing'
        ? await this.prisma.emergencyOffer.count({
            where: { requestId: request.id, state: 'open' },
          })
        : 0;
    const shown = phase === 'choosing' ? await this.shownOffers(request.id) : [];
    const booking =
      request.status === 'matched'
        ? await this.prisma.booking.findFirst({
            where: { emergencyRequestId: request.id },
            orderBy: { createdAt: 'desc' },
            select: { id: true },
          })
        : null;
    const fee =
      request.dispatchFeeSubmissionId === null
        ? null
        : await this.prisma.paymentSubmission.findUnique({
            where: { id: request.dispatchFeeSubmissionId },
          });
    const closes = request.offerCollectionClosesAt;

    return {
      id: request.id,
      status: request.status,
      phase,
      categoryId: request.category.id,
      categoryName: request.category.name,
      minimumTier: request.category.emergencyMinimumTier,
      windowMinutes: request.category.emergencyAcceptWindowMinutes,
      islandId: request.islandId,
      islandDisplayName: islandDisplayName(request.island),
      jobNotes: request.jobNotes,
      addressDetail: request.addressDetail,
      windowEndsAt: request.windowEndsAt.toISOString(),
      collectionClosesAt: iso(closes),
      choiceEndsAt:
        closes === null ? null : minutesFrom(closes, OFFER_CHOICE_MINUTES).toISOString(),
      broadcastCount: recipients,
      offersReceived,
      offers: shown.map(toOfferDto),
      bookingId: booking?.id ?? null,
      dispatchFee: fee === null ? null : toFeeDto(fee),
      createdAt: request.createdAt.toISOString(),
    };
  }

  /** The customer's own request, or 404 — a stranger learns nothing. */
  private async customerRequest(userId: string, requestId: string): Promise<RequestRow> {
    const request = await this.prisma.emergencyRequest.findUnique({
      where: { id: requestId },
      include: REQUEST_INCLUDE,
    });
    if (request?.customerId !== userId) {
      throw new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    }
    return request;
  }

  /**
   * A provider's standing on one broadcast. Not found unless they could answer
   * it, already have, or have a listing here the tier bar now refuses — the
   * existence of a request they were never sent is not theirs to learn.
   */
  private async providerView(
    userId: string,
    requestId: string,
  ): Promise<{
    request: RequestRow;
    providerProfileId: string;
    recipient: Recipient | null;
    tierBlock: BusinessRuleError | null;
  }> {
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true, verificationTier: true },
    });
    const request = await this.prisma.emergencyRequest.findUnique({
      where: { id: requestId },
      include: REQUEST_INCLUDE,
    });
    if (profile === null || request === null) {
      throw new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    }

    const [recipient] = await this.recipients(request, profile.id);
    const offered = await this.prisma.emergencyOffer.findFirst({
      where: { requestId: request.id, providerProfileId: profile.id },
      select: { id: true },
    });

    // The tier half of the rule, by name: a provider with an emergency listing
    // here whose tier no longer meets this category's bar is told so.
    let tierBlock: BusinessRuleError | null = null;
    if (recipient === undefined) {
      const hasListingHere = await this.prisma.listing.findFirst({
        where: {
          providerProfileId: profile.id,
          categoryId: request.categoryId,
          isEmergency: true,
          status: 'published',
          deletedAt: null,
          serviceAreas: { some: { islandId: request.islandId, removedAt: null } },
        },
        select: { id: true },
      });
      const verdict = emergencyEligibility({
        category: request.category,
        providerTier: profile.verificationTier,
      });
      if (hasListingHere !== null && !verdict.eligible) {
        tierBlock = new BusinessRuleError(verdict.code, verdict.message);
      }
    }

    // A provider who passed still reads it — as passed — rather than being told
    // a request they were shown does not exist.
    const passed =
      recipient === undefined
        ? await this.prisma.emergencyPass.findUnique({
            where: {
              requestId_providerProfileId: { requestId: request.id, providerProfileId: profile.id },
            },
            select: { id: true },
          })
        : null;

    if (recipient === undefined && offered === null && tierBlock === null && passed === null) {
      throw new NotFoundError('No such request', 'EMERGENCY_REQUEST_NOT_FOUND');
    }
    return { request, providerProfileId: profile.id, recipient: recipient ?? null, tierBlock };
  }

  private async broadcastDto(
    request: RequestRow,
    providerProfileId: string,
    eligible: boolean,
    now: Date,
  ): Promise<EmergencyBroadcastDto> {
    const mine = await this.prisma.emergencyOffer.findFirst({
      where: { requestId: request.id, providerProfileId },
      orderBy: { createdAt: 'desc' },
    });
    const passed = await this.prisma.emergencyPass.findUnique({
      where: { requestId_providerProfileId: { requestId: request.id, providerProfileId } },
      select: { id: true },
    });
    const closes = request.offerCollectionClosesAt;
    const open =
      isOpen(request.status) && now < request.windowEndsAt && (closes === null || now < closes);
    return {
      requestId: request.id,
      categoryName: request.category.name,
      customerFirstName: firstName(request.customer.fullName),
      jobNotes: request.jobNotes,
      islandDisplayName: islandDisplayName(request.island),
      createdAt: request.createdAt.toISOString(),
      windowEndsAt: request.windowEndsAt.toISOString(),
      collectionClosesAt: iso(closes),
      choiceEndsAt:
        closes === null ? null : minutesFrom(closes, OFFER_CHOICE_MINUTES).toISOString(),
      etaPresetsMinutes: request.category.emergencyEtaPresetsMinutes,
      myOffer:
        mine === null
          ? null
          : {
              id: mine.id,
              state: mine.state,
              calloutFeeLaari: mine.calloutFeeLaari,
              etaMinutes: mine.etaMinutes,
              bookingId: mine.bookingId,
              createdAt: mine.createdAt.toISOString(),
            },
      passed: passed !== null,
      canOffer: eligible && open && passed === null && mine?.state !== 'open',
    };
  }

  private async lapseOpenOffers(tx: Db, requestId: string, now: Date): Promise<string[]> {
    const open = await tx.emergencyOffer.findMany({
      where: { requestId, state: 'open' },
      select: { providerProfile: { select: { userId: true } } },
    });
    await tx.emergencyOffer.updateMany({
      where: { requestId, state: 'open' },
      data: { state: 'lapsed', closedAt: now },
    });
    return open.map((o) => o.providerProfile.userId);
  }

  private async mustFindRequest(id: string): Promise<RequestRow> {
    return this.prisma.emergencyRequest.findUniqueOrThrow({
      where: { id },
      include: REQUEST_INCLUDE,
    });
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
    from: BookingStatus | null,
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

  /**
   * `bookingId` on the seam is the event's subject: before selection that is
   * the request's id, which is what a push would deep-link to.
   */
  private async notify(
    event: BookingNotification,
    subjectId: string,
    userId: string,
  ): Promise<void> {
    try {
      await this.notifier.notify({ event, bookingId: subjectId, userId });
    } catch (error) {
      this.log.warn({ err: error, event, subjectId }, 'emergency notification failed');
    }
  }
}

/** Derived, never stored — the same posture `chat.ts` takes. */
export function requestPhase(
  request: { status: string; offerCollectionClosesAt: Date | null },
  now: Date,
): EmergencyPhase {
  switch (request.status) {
    case 'requested':
      return 'waiting';
    case 'emergency_offered': {
      const closes = request.offerCollectionClosesAt;
      return closes !== null && now < closes ? 'collecting' : 'choosing';
    }
    case 'matched':
      return 'matched';
    default:
      return 'closed';
  }
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

function toFeeDto(fee: {
  id: string;
  amountLaari: number;
  referenceCode: string;
  status: 'pending' | 'confirmed' | 'rejected';
  submittedAt: Date | null;
  waivedAt: Date | null;
}): EmergencyDispatchFeeDto {
  return {
    submissionId: fee.id,
    amountLaari: fee.amountLaari,
    referenceCode: fee.referenceCode,
    state: dispatchFeeState(fee),
  };
}

function stale(): ConflictError {
  return new ConflictError(
    'BOOKING_CHANGED',
    'This request changed while you were looking at it — open it again',
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
