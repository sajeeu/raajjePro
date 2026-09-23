import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, ConflictError, NotFoundError } from '../../core/errors.js';
import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';
import type {
  BookingActorRole,
  BookingStatus,
  DisputeOutcome,
  ReportReason,
} from '../../generated/prisma/enums.js';
import type { ReservationService } from '../availability/reservations.js';
import type { NotificationDispatcher } from '../push/dispatcher.js';
import type { ProviderProfileService } from '../providers/service.js';
import { islandDisplayName, toBookingDto } from './mapper.js';
import type { BookingNotification, BookingNotifier } from './notifications.js';
import { deriveQuotedAmount, deriveSlotAmount, durationMinutes } from './pricing.js';
import {
  chipLabel,
  QuoteWindowsMissingError,
  readQuoteWindows,
  REQUEST_HOLD_MINUTES,
  resolveWindowChip,
  type WindowChip,
} from './quotes.js';
import { generateBookingReference } from './reference.js';
import { assertReasonAllowed } from './reports.js';
import type { BookingRepository, BookingRow, Db } from './repository.js';
import {
  assertTransition,
  COMMITTED_STATUSES,
  isTerminal,
  TERMINAL_STATUSES,
} from './transitions.js';
import type { BookingDto } from './types.js';
import {
  ACCEPT_WINDOW_MINUTES,
  COMPLETION_GRACE_DAYS,
  COMPLETION_PROMPT_AFTER_DAYS,
  daysBefore,
  minutesFrom,
  PAYMENT_SILENCE_DAYS,
} from './windows.js';

/** Non-terminal in §1c's sense: an admin still owes somebody an answer on these two. */
const NON_TERMINAL_STATUSES: BookingStatus[] = (
  [
    'requested',
    'awaiting_quote',
    'quote_offered',
    'emergency_offered',
    'accepted',
    'awaiting_payment',
    'payment_claimed',
    'confirmed',
    'disputed',
    'payment_unresolved',
  ] as const
).filter((s) => !isTerminal(s));

export interface ServiceLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

export interface CreateSlotBookingInput {
  timeSlotId: string;
  jobNotes?: string | undefined;
  islandId?: string | undefined;
  addressDetail?: string | undefined;
}

/**
 * §Phase 17.2's creation input — `Request a Time.dc.html`.
 *
 * The window arrives as the chip the customer tapped, the text they typed, or
 * both; `quotes.ts` resolves a chip to a Maldives-time range and the text is
 * stored verbatim. Neither is a constraint on anything — §1c: "this is a
 * preference, not a slot", and the provider answers with a concrete time.
 */
export interface CreateRequestBookingInput {
  preferredWindowChip?: WindowChip | undefined;
  preferredWindowText?: string | undefined;
  occasion?: string | undefined;
  jobNotes?: string | undefined;
  islandId?: string | undefined;
  addressDetail?: string | undefined;
}

/** `Propose Time and Price.dc.html` — a concrete time, a price, and a note. */
export interface OfferQuoteInput {
  scheduledFor: Date;
  amountLaari: number;
  note?: string | undefined;
}

export interface ProposeAmendmentInput {
  amountLaari?: number;
  scheduledFor?: Date;
  scopeNote?: string;
  reason?: string;
}

export interface ListBookingsQuery {
  role: 'customer' | 'provider';
  statuses: BookingStatus[] | null;
  limit: number;
  cursor: string | null;
}

/** How the caller relates to a booking. `none` is never returned — it is a 404. */
type CallerRole = Extract<BookingActorRole, 'customer' | 'provider'>;

interface Caller {
  userId: string;
  role: CallerRole;
}

/**
 * §Phase 17.1 — the core booking machine, payment attestation and §1h's locked
 * agreement.
 *
 * ## Three things this service deliberately does not do
 *
 * **It does not hold money.** §1h considered escrow and rejected it: "escrow
 * means a payment gateway and almost certainly MMA licensing, which is a
 * different company, not a feature." What replaces it is the agreement being
 * immovable — `proposeAmendment` and `respondToAmendment` below — and that is
 * the entire mechanism (invariant 12).
 *
 * **It does not verify a payment.** `claimPayment` and `confirmPaymentReceived`
 * are two humans each saying what they did. Nothing in this system can see a
 * bank transfer, and no field, status or piece of copy may imply otherwise.
 * This is a different mechanism from `PaymentSubmission`, which is RaajjePro's
 * own subscription money and does have an admin confirming it.
 *
 * **It does not return a phone number.** §1c allows exactly one endpoint in
 * the system to, and it is §Phase 17.3's `reveal-contact`. The exclusion here
 * is structural — see `repository.ts` and `types.ts`.
 *
 * ## Where a transition is checked
 *
 * Once, in `transitions.ts`, and then again by the database: every write goes
 * through `repo.transition`, whose `where` carries the status the booking was
 * read at. Two taps on the same button, from two devices, resolve to one
 * winner without a row lock — the loser sees the same refusal a stale screen
 * gets.
 */
export class BookingService {
  private readonly prisma: PrismaClient;
  private readonly clock: Clock;
  private readonly repo: BookingRepository;
  private readonly reservations: ReservationService;
  private readonly providers: ProviderProfileService;
  private readonly notifier: BookingNotifier;
  private readonly dispatcher: NotificationDispatcher | undefined;
  private readonly onConfirmed: ((providerProfileId: string) => Promise<unknown>) | undefined;
  private readonly log: ServiceLogger;

  constructor(deps: {
    prisma: PrismaClient;
    clock: Clock;
    repo: BookingRepository;
    reservations: ReservationService;
    providers: ProviderProfileService;
    notifier: BookingNotifier;
    /** §Phase 3c's dispatcher, for the one notification that has a kind of its own. */
    dispatcher?: NotificationDispatcher;
    /**
     * §Phase 8a's trial trigger — "fires on the state transition into
     * `confirmed`, not from one endpoint", which is why it is a callback here
     * and is invoked from `enterConfirmed` rather than from an endpoint.
     */
    onConfirmed?: (providerProfileId: string) => Promise<unknown>;
    log: ServiceLogger;
  }) {
    this.prisma = deps.prisma;
    this.clock = deps.clock;
    this.repo = deps.repo;
    this.reservations = deps.reservations;
    this.providers = deps.providers;
    this.notifier = deps.notifier;
    this.dispatcher = deps.dispatcher;
    this.onConfirmed = deps.onConfirmed;
    this.log = deps.log;
  }

  // =========================================================================
  // Reads
  // =========================================================================

  /**
   * `GET /v1/users/me/bookings?role=&status=` (§Phase 17 item 18).
   *
   * Authorization is the query itself: a caller reads their own bookings as
   * customer, or their own as provider. There is no shape of this request that
   * reaches somebody else's.
   */
  async list(
    userId: string,
    query: ListBookingsQuery,
  ): Promise<{ bookings: BookingDto[]; nextCursor: string | null }> {
    const now = this.clock();
    const providerProfileId =
      query.role === 'provider' ? await this.providerProfileIdOf(userId) : null;

    const rows = await this.repo.findForUser({
      role: query.role,
      customerId: userId,
      providerProfileId,
      statuses: query.statuses,
      limit: query.limit + 1,
      cursor: decodeCursor(query.cursor),
    });

    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      bookings: page.map((row) => toBookingDto(row, now)),
      nextCursor:
        rows.length > query.limit && last !== undefined
          ? encodeCursor(last.createdAt, last.id)
          : null,
    };
  }

  /**
   * `GET /v1/bookings/:id` — the detail view, with the status timeline
   * §Phase 17 asks for.
   *
   * Three things attach conditionally, and each has a rule:
   *  - the **status history**, always, because this is the detail read;
   *  - the provider's **bank details**, only for the customer and only while
   *    the booking is actually at `awaiting_payment` (§1c: payment details are
   *    shown "at the payment step of every booking", not on every read of one);
   *  - §1h's **replacement prefill**, only for the customer and only where the
   *    provider is the one who cancelled.
   */
  async read(userId: string, bookingId: string): Promise<BookingDto> {
    const { booking, caller } = await this.authorize(userId, bookingId);
    const statusHistory = await this.repo.findStatusHistory(bookingId);

    const showPaymentDetails = caller.role === 'customer' && booking.status === 'awaiting_payment';
    const paymentDetails = showPaymentDetails
      ? await this.providers.paymentDetailsForBooking(booking.providerProfileId)
      : undefined;

    return toBookingDto(booking, this.clock(), {
      statusHistory,
      ...(paymentDetails === undefined ? {} : { paymentDetails }),
      includeReplacement: this.offersReplacement(booking, caller.role),
    });
  }

  // =========================================================================
  // Creation
  // =========================================================================

  /**
   * `POST /v1/listings/:id/bookings` — §Phase 17.1's slot-based creation.
   *
   * ## One transaction, and ledger row P9A-2
   *
   * §Phase 9a requires reservations to be "created inside the booking
   * transaction", and its own ledger row says what could not be proved there:
   * that the booking machine, when it existed, would open *one* transaction
   * around the booking row, its first status event and the hold. It does — the
   * `$transaction` below is the whole of creation, so a booking write that
   * fails after the reservation succeeded leaves no hold behind.
   *
   * ## What refuses this, and in what order
   *
   * The listing must be publicly visible (a hidden or deleted listing is *not
   * found*, never "forbidden"); its mode must be `slot`; the provider must not
   * be the customer; and the slot claim itself is the last word — two customers
   * racing one slot resolve in `reserveSlot`, not here.
   *
   * §Phases 17.2 and 17.3 own the other two modes. A `request` or `emergency`
   * listing is refused here by name rather than silently mishandled.
   */
  async createSlotBooking(
    userId: string,
    listingId: string,
    input: CreateSlotBookingInput,
  ): Promise<BookingDto> {
    const now = this.clock();
    const listing = await this.bookableListing(listingId, userId, 'slot');

    const slot = await this.prisma.timeSlot.findUnique({
      where: { id: input.timeSlotId },
      select: { id: true, listingId: true, startsAt: true, endsAt: true },
    });
    if (slot?.listingId !== listing.id) {
      throw new NotFoundError('That time is no longer available', 'SLOT_NOT_FOUND');
    }

    // The amount is derived from the listing and the **slot's own** length —
    // never from anything the client sent (Round 17, invariant 4).
    const amount = deriveSlotAmount(listing, durationMinutes(slot.startsAt, slot.endsAt));

    const created = await this.prisma.$transaction(async (tx) => {
      const reservation = await this.reservations.reserveSlot(
        tx,
        { slotId: slot.id, kind: 'firm' },
        now,
      );

      const booking = await this.createWithReference(tx, {
        listingId: listing.id,
        customerId: userId,
        providerProfileId: listing.providerProfileId,
        bookingMode: 'slot',
        status: 'requested',
        timeSlotId: slot.id,
        reservationId: reservation.id,
        scheduledFor: slot.startsAt,
        // §1c step 3 sets the amount at `accepted`, not here. What is known now
        // is what it *will* be, and quoting it before the provider has agreed
        // would put a number on a screen nobody has committed to — so it is
        // carried as the quoted amount and becomes `agreedAmount` on accept.
        quotedAmountLaari: amount.amountLaari,
        jobNotes: input.jobNotes ?? null,
        islandId: input.islandId ?? null,
        addressDetail: input.addressDetail ?? null,
        createdAt: now,
      });

      await this.repo.recordStatusEvent(
        {
          bookingId: booking.id,
          fromStatus: null,
          toStatus: 'requested',
          actorRole: 'customer',
          actorUserId: userId,
          transition: 'create',
          at: now,
        },
        tx,
      );
      return booking;
    });

    const row = await this.mustFind(created.id);
    await this.sendAcceptPrompt(row);
    return toBookingDto(row, now);
  }

  /**
   * `POST /v1/listings/:id/bookings` on a **`request`** listing — §Phase
   * 17.2's creation, and the refusal §Phase 17.1 left by name.
   *
   * ## What opens here
   *
   * Nine of the twelve seeded categories are `request` mode (§1c), so until
   * this method existed three-quarters of the catalogue could be published,
   * found and priced but not booked. §Phase 17.1's `BOOKING_MODE_NOT_AVAILABLE`
   * was that refusal; `bookableListing` now routes by mode instead.
   *
   * ## `awaiting_quote`, not `requested`
   *
   * §1c's status machine: "Request-based / quote-priced listings insert
   * `awaiting_quote → quote_offered → accepted` before the diagram above."
   * The booking lands on the first of those three, because that is the state
   * it is actually in — the provider owes a **quote**, on the category's own
   * `quoteExpiryMinutes` clock, which is a different fact and a different
   * clock from a slot booking's wait for an accept on the flat 24 hours.
   *
   * 🔧 **This is the one place §Phase 17.2 had to choose between two sentences
   * of §1c**, and `docs/decisions/29-phase-17-2-quotes.md` records it: step 1
   * says every mode's creation lands on `requested`, and the machine section
   * says request mode inserts `awaiting_quote` first. Nothing could move
   * `requested → awaiting_quote` — no endpoint in the plan's list does it and
   * no screen offers it — so reading step 1 literally would leave a status the
   * plan puts in the machine permanently unreachable.
   *
   * ## No reservation yet
   *
   * There is no time to hold: a preferred window "is a preference, not a slot"
   * (§1c, and `Request a Time.dc.html` says it in those words). The hold is
   * taken when the provider proposes a concrete time — [offerQuote] — which is
   * exactly §1c's provisional reservation.
   */
  async createRequestBooking(
    userId: string,
    listingId: string,
    input: CreateRequestBookingInput,
  ): Promise<BookingDto> {
    const now = this.clock();
    const listing = await this.bookableListing(listingId, userId, 'request');

    // Invariant 13, read and never hardcoded: 120/240 for the household
    // trades, 1440/4320 where planning happens. A category with neither set
    // is refused rather than defaulted — a default here would be the flat
    // 24h/72h that Round 15 removed, reappearing through a fallback.
    const windows = readQuoteWindows(listing.category);

    const occasion = this.validateOccasion(listing.category, input.occasion);
    const window = this.resolvePreferredWindow(input, now);

    const created = await this.prisma.$transaction(async (tx) => {
      const booking = await this.createWithReference(tx, {
        listingId: listing.id,
        customerId: userId,
        providerProfileId: listing.providerProfileId,
        bookingMode: 'request',
        status: 'awaiting_quote',
        // Null on purpose, both of them: no slot was picked and no time is
        // held. `scheduledFor` is null too — §1h locks a date at `accepted`,
        // and there is no date to lock until the customer approves a quote.
        timeSlotId: null,
        reservationId: null,
        scheduledFor: null,
        preferredWindowText: window.text,
        preferredWindowFrom: window.from,
        preferredWindowTo: window.to,
        occasion,
        // The clock `Request a Time.dc.html` shows the customer as "until
        // 12:30 today". Stored rather than recomputed per read, so an admin
        // editing the category later cannot move a deadline somebody is
        // already counting down.
        quoteDueAt: minutesFrom(now, windows.expiryMinutes),
        jobNotes: input.jobNotes ?? null,
        islandId: input.islandId ?? null,
        addressDetail: input.addressDetail ?? null,
        createdAt: now,
      });

      await this.repo.recordStatusEvent(
        {
          bookingId: booking.id,
          fromStatus: null,
          toStatus: 'awaiting_quote',
          actorRole: 'customer',
          actorUserId: userId,
          transition: 'create-request',
          at: now,
        },
        tx,
      );
      return booking;
    });

    const row = await this.mustFind(created.id);
    // The same prompt a slot booking sends — §1c step 2's "job details and the
    // customer's name only". What the provider does with it differs (quote,
    // not accept) and the notification carries neither verb.
    await this.sendAcceptPrompt(row);
    return toBookingDto(row, now);
  }

  // =========================================================================
  // The provider answers the accept prompt
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/accept` — §Phase 17 item 3, "sets `agreedAmount`
   * for slot and request bookings".
   *
   * The booking passes through `accepted` into `awaiting_payment` in one
   * transaction, because §1c says it does: "Slot-based and request-based
   * bookings pass through `awaiting_payment` instantly — `agreedAmount` is set
   * at `accepted`, so the customer's payment prompt appears immediately."
   * **Two** status events are written, not one: the timeline is the evidence in
   * a dispute and collapsing them would lose the moment the terms locked.
   *
   * 🔧 **Emergency does not use this endpoint — Round 15, §0.0 item 15.** It has
   * `emergency-accept`, which creates an `EmergencyOffer` carrying the callout
   * fee and `etaMinutes` together (§Phase 17.3). The guard is here rather than
   * only in 17.3 so that the wrong call is refused by name today.
   */
  async accept(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'provider');

    if (booking.bookingMode === 'emergency') {
      throw new BusinessRuleError(
        'EMERGENCY_USES_ITS_OWN_ACCEPT',
        'An emergency request is accepted with your callout fee and arrival estimate',
      );
    }
    if (booking.bookingMode !== 'slot') {
      // §Phase 17.2's quote path. A request-based booking is accepted by the
      // customer approving a quote, not by the provider accepting a price
      // nobody has proposed.
      throw new BusinessRuleError(
        'REQUEST_BOOKING_NEEDS_A_QUOTE',
        'Respond to this request with a time and a price',
      );
    }

    assertTransition('accept', booking.status, 'provider');

    const amount = deriveSlotAmount(booking.listing, this.slotDuration(booking));

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'accepted',
          agreedAmountLaari: amount.amountLaari,
          amountKind: amount.amountKind,
          amountSetAt: now,
        },
        tx,
      );
      if (!moved) throw staleBooking();

      await this.event(tx, booking, 'accepted', 'accept', 'provider', userId, now);

      // §1c step 3: no booking reaches `awaiting_payment` without an amount.
      // It has one now, in the same transaction, so there is no instant in
      // which the customer could see a payment prompt with no number on it.
      assertTransition('amount-set', 'accepted', 'provider');
      const paid = await this.repo.transition(
        booking.id,
        'accepted',
        { status: 'awaiting_payment' },
        tx,
      );
      if (!paid) throw staleBooking();
      await this.event(
        tx,
        { ...booking, status: 'accepted' },
        'awaiting_payment',
        'amount-set',
        'provider',
        userId,
        now,
      );
    });

    await this.notify('accepted', booking.id, booking.customer.id);
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/decline` — §Phase 17 item 6: "provider; frees the
   * slot/reservation; **distinct from dispute**".
   */
  async decline(userId: string, bookingId: string, reason?: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'provider');
    assertTransition('decline', booking.status, 'provider');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        { status: 'declined', declinedAt: now, cancellationReason: reason ?? null },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.releaseHold(tx, booking, 'declined', now);
      await this.event(tx, booking, 'declined', 'decline', 'provider', userId, now);
    });

    await this.notify('declined', booking.id, booking.customer.id);
    return this.reread(booking.id);
  }

  // =========================================================================
  // §Phase 17.2 — the quote, at both ends
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/quote` — §Phase 17 item 5, and
   * `Propose Time and Price.dc.html`.
   *
   * §1c: "Provider reviews via the same accept prompt and **responds with a
   * proposed concrete date/time and price**. This reuses the quote mechanism
   * (`awaiting_quote` → `quote_offered`)."
   *
   * ## The provisional reservation, and why it is in this transaction
   *
   * §1c: "**Offering a quote creates a provisional reservation** on the
   * proposed time, expiring with the quote's approval window. Without this,
   * the provider could sell that time to someone else in the interim and the
   * customer's approval would fail on a constraint violation after they had
   * already agreed a price."
   *
   * So the hold and the status move together or not at all — the property
   * §Phase 17.1 proved for the firm hold (ledger row **P9A-2**), asserted here
   * for the provisional one in both directions: a time that is already taken
   * leaves the booking at `awaiting_quote`, and a failure after the hold is
   * taken leaves no hold.
   *
   * ## Two edges, one endpoint
   *
   * From `awaiting_quote` this is `offer-quote`. From `quote_offered` it is
   * `revise-quote` — the negotiation §1c describes, where "the provider
   * proposes Tuesday 2pm at a price and the customer wants Tuesday 3pm". The
   * revision releases the old hold and takes a new one in the same
   * transaction, and **restarts the customer's approval clock**, because the
   * terms they are being asked to consider are new.
   */
  async offerQuote(userId: string, bookingId: string, input: OfferQuoteInput): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'provider');

    if (booking.bookingMode !== 'request') {
      // A slot booking has a published time and a derived price; an emergency
      // one is answered with a callout fee and an arrival estimate (§Phase
      // 17.3). Neither is quoted.
      throw new BusinessRuleError(
        'BOOKING_MODE_HAS_NO_QUOTE',
        booking.bookingMode === 'emergency'
          ? 'An emergency request is answered with your callout fee, not a quote'
          : 'This booking is for a published time — accept or decline it',
        { bookingMode: booking.bookingMode },
      );
    }

    const transition = booking.status === 'quote_offered' ? 'revise-quote' : 'offer-quote';
    assertTransition(transition, booking.status, 'provider');

    const category = booking.listing.category;
    if (category === null) throw new QuoteWindowsMissingError();
    const windows = readQuoteWindows(category);

    // Round 14's lead time, read from the category exactly as the slot picker
    // reads it. A plumber quoting a time twenty minutes out is proposing
    // something the catalogue says nobody can commit to.
    const earliest = minutesFrom(now, category.minimumLeadTimeMinutes);
    if (input.scheduledFor < earliest) {
      throw new BusinessRuleError(
        'QUOTE_TIME_TOO_SOON',
        'That time is sooner than this category allows — propose a later one',
        { earliest: earliest.toISOString() },
      );
    }

    // The customer's clock, and the hold's, are the same instant written
    // twice — §1c's "expiring with the quote's approval window".
    const expiresAt = minutesFrom(now, windows.approvalMinutes);
    const endsAt = minutesFrom(input.scheduledFor, REQUEST_HOLD_MINUTES);

    await this.prisma.$transaction(async (tx) => {
      // A revision's old hold goes first: the provider may be moving the quote
      // by an hour, and the new range would otherwise collide with their own
      // outstanding one.
      if (booking.reservationId !== null) {
        await this.reservations.release(tx, booking.reservationId, 'superseded', now);
      }

      const reservation = await this.reservations.reserveWindow(
        tx,
        {
          providerProfileId: booking.providerProfileId,
          listingId: booking.listingId,
          startsAt: input.scheduledFor,
          endsAt,
          kind: 'provisional',
          expiresAt,
        },
        now,
      );

      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'quote_offered',
          reservationId: reservation.id,
          // The proposed time, which is not yet locked — §1h locks it at
          // `accepted`. Written here so the customer's screen and the
          // provider's calendar read the same time as the hold.
          scheduledFor: input.scheduledFor,
          quotedAmountLaari: input.amountLaari,
          quoteNote: input.note ?? null,
          quoteOfferedAt: now,
          quoteExpiresAt: expiresAt,
          // Cleared: the provider has answered, so their own deadline is spent.
          // A revision does not restore it.
          quoteDueAt: null,
        },
        tx,
      );
      if (!moved) throw staleBooking();

      await this.event(tx, booking, 'quote_offered', transition, 'provider', userId, now);
    });

    // §0.0 item 7 and 17.2's Done-when: the `booking` chat opens **here**, not
    // at `accepted`. `chat.ts` derives that state from `quoteOfferedAt`, which
    // the transition above has just stamped; §Phase 18 builds the thread on it.
    await this.notify('quote_offered', booking.id, booking.customer.id);
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/approve-quote` — §1c: "Customer approves or
   * rejects. **Approval converts the provisional reservation to a firm one**
   * and transitions to `accepted`."
   *
   * From here the booking is indistinguishable from a slot booking that was
   * accepted: §1c, "everything downstream is identical to the slot-based flow
   * from `accepted` onward". So the two status events §Phase 17.1 writes on
   * accept are written here too — `accepted`, where §1h's terms lock, then
   * `awaiting_payment`, because §1c step 3 lets no booking reach the payment
   * prompt without an amount and this one now has one.
   */
  async approveQuote(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'customer');
    assertTransition('approve-quote', booking.status, 'customer');

    // The sweep runs every five minutes, so a quote can be seconds past its
    // deadline and still be on screen. Refusing it here is not a substitute
    // for the job (backend/CLAUDE.md: a timed transition is made by a job) —
    // it is what stops the customer approving terms whose hold is already
    // expiring underneath them.
    if (booking.quoteExpiresAt !== null && now >= booking.quoteExpiresAt) {
      throw new BusinessRuleError('QUOTE_EXPIRED', 'This quote has expired — ask for a new one', {
        expiredAt: booking.quoteExpiresAt.toISOString(),
      });
    }
    if (booking.reservationId === null) {
      // Unreachable: `quote_offered` is only ever entered with a hold. A quote
      // whose hold has gone is not approvable, because the time it named is no
      // longer held for anyone.
      throw new ConflictError(
        'QUOTE_HOLD_GONE',
        'The time this quote held is no longer reserved — ask for a new quote',
      );
    }

    const amount = deriveQuotedAmount(booking.quotedAmountLaari ?? 0);
    const reservationId = booking.reservationId;

    await this.prisma.$transaction(async (tx) => {
      // §1c: the hold is converted, never re-taken — so there is no instant in
      // which the time is free and a stranger could win it.
      await this.reservations.makeFirm(tx, reservationId);

      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'accepted',
          agreedAmountLaari: amount.amountLaari,
          amountKind: amount.amountKind,
          amountSetAt: now,
          // The customer answered, so the approval clock is spent. The quote's
          // own numbers stay: `quotedAmountLaari` is the "original terms" half
          // of §1h's retained pair, and `quoteOfferedAt` is what `chat.ts`
          // reads to know the thread opened.
          quoteExpiresAt: null,
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(tx, booking, 'accepted', 'approve-quote', 'customer', userId, now);

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
        { ...booking, status: 'accepted' },
        'awaiting_payment',
        'amount-set',
        'customer',
        userId,
        now,
      );
    });

    await this.notify('quote_approved', booking.id, booking.providerProfile.user.id);
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/decline-quote` — the other half of §1c's
   * "customer approves or rejects", and `Quote Received.dc.html`'s "Decline
   * this quote".
   *
   * **Lands on `cancelled`, never `declined`.** §1f defines acceptance rate as
   * "accepted ÷ (accepted + declined) — explicit responses only", a measure of
   * what the provider did; a customer turning a price down must not count
   * against the provider who answered promptly. `cancelledByRole: 'customer'`
   * is then the row §1f's cancellation rate explicitly never counts.
   *
   * The screen's own way back is a **new request** ("Send a new request"),
   * not a re-quote of this one: a declined quote is a closed booking, and the
   * negotiation case is served by the chat while the quote is still live.
   */
  async declineQuote(userId: string, bookingId: string, reason?: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'customer');
    assertTransition('decline-quote', booking.status, 'customer');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'cancelled',
          cancelledAt: now,
          cancelledByRole: 'customer',
          cancellationReason: reason ?? null,
          quoteExpiresAt: null,
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.releaseHold(tx, booking, 'cancelled', now);
      await this.event(tx, booking, 'cancelled', 'decline-quote', 'customer', userId, now);
    });

    await this.notify('quote_declined', booking.id, booking.providerProfile.user.id);
    return this.reread(booking.id);
  }

  // =========================================================================
  // Payment attestation — two humans, no verification
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/claim-payment` — §1c step 7: "Customer taps 'I've
   * Paid' — self-attestation, **no proof upload**."
   *
   * Nothing is checked, because nothing can be. What this records is that the
   * customer said so, and the record of *when* they said it is what starts the
   * 7-day clock on the provider's silence.
   */
  async claimPayment(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'customer');
    assertTransition('claim-payment', booking.status, 'customer');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        { status: 'payment_claimed', paymentClaimedAt: now },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(tx, booking, 'payment_claimed', 'claim-payment', 'customer', userId, now);
    });

    await this.notify('payment_claimed', booking.id, booking.providerProfile.user.id);
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/withdraw-payment-claim` — Round 24, §Phase 17 item
   * 8a.
   *
   * Three refusals, and each is in the plan for a stated reason:
   *  - **not at `payment_claimed`** — there is no claim to withdraw;
   *  - **the provider has already answered** — "once the provider has
   *    responded, the customer's own correction is no longer the right
   *    instrument and the dispute path is". The status check covers this on
   *    its own: a confirmed or disputed booking is no longer `payment_claimed`;
   *  - **a second attempt** — "once per booking, so it cannot be used as a
   *    toggle", which is what `paymentClaimWithdrawnAt` is for. It is never
   *    cleared, so the guard survives a second claim.
   *
   * It **files no Report and touches no conduct metric** (§1f, Round 24): "a
   * customer's mis-tap is neither". So there is no `createReport` call here and
   * there must never be one.
   */
  async withdrawPaymentClaim(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'customer');

    if (booking.paymentClaimWithdrawnAt !== null) {
      throw new BusinessRuleError(
        'PAYMENT_CLAIM_ALREADY_WITHDRAWN',
        'You have already withdrawn a payment claim on this booking',
        { withdrawnAt: booking.paymentClaimWithdrawnAt.toISOString() },
      );
    }
    assertTransition('withdraw-payment-claim', booking.status, 'customer');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'awaiting_payment',
          paymentClaimedAt: null,
          paymentClaimWithdrawnAt: now,
        },
        tx,
      );
      if (!moved) throw staleBooking();
      // Both transitions stay in `statusHistory` — "a withdrawal hides
      // nothing, it corrects the record."
      await this.event(
        tx,
        booking,
        'awaiting_payment',
        'withdraw-payment-claim',
        'customer',
        userId,
        now,
      );
    });

    await this.notify('payment_claim_withdrawn', booking.id, booking.providerProfile.user.id);
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/confirm-payment-received` — §1c step 8.
   *
   * The provider saying the money arrived. **Not** a verification: the copy
   * everywhere reads "Provider confirmed receipt", never "Payment verified".
   */
  async confirmPaymentReceived(userId: string, bookingId: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'provider');
    assertTransition('confirm-payment-received', booking.status, 'provider');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        { status: 'confirmed', paymentAttestedAt: now },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(
        tx,
        booking,
        'confirmed',
        'confirm-payment-received',
        'provider',
        userId,
        now,
      );
    });

    await this.enterConfirmed(booking.id, booking.providerProfileId);
    await this.notify('payment_confirmed', booking.id, booking.customer.id);
    return this.reread(booking.id);
  }

  // =========================================================================
  // Completion
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/complete` — §Phase 17 item 13.
   *
   * 🔧 **An emergency booking is rejected without `finalAmount`** — "the real
   * settled total once parts and labour were added to the callout fee… It is
   * the number a price dispute needs, and a provider has no incentive to
   * volunteer it when it reflects badly on them." The guard lives here because
   * this endpoint is §Phase 17.1's; §Phase 17.3 creates the bookings it bites
   * on.
   *
   * On any mode a `finalAmount` may be recorded, because §1f's price adherence
   * is "completions where `finalAmount` ≤ `agreedAmount`" and a slot job that
   * came to more than the agreed price is exactly what that measures. Nothing
   * is refused for being higher — §1h makes it "a price-adherence failure…
   * visible on the profile as one", not an error.
   */
  async complete(
    userId: string,
    bookingId: string,
    finalAmountLaari?: number,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'provider');

    if (booking.bookingMode === 'emergency' && finalAmountLaari === undefined) {
      throw new BusinessRuleError(
        'FINAL_AMOUNT_REQUIRED',
        'Record what the job came to in total before marking it complete',
      );
    }
    assertTransition('complete', booking.status, 'provider');

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'completed',
          completedAt: now,
          completedVia: 'confirmed',
          ...(finalAmountLaari === undefined ? {} : { finalAmountLaari }),
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.event(tx, booking, 'completed', 'complete', 'provider', userId, now);
    });

    await this.notify('completed', booking.id, booking.customer.id);
    return this.reread(booking.id);
  }

  /**
   * §1c step 10's "Did [Provider] complete this job?", answered.
   *
   * **Yes** → `completed`, `completedVia: 'confirmed'`. It is a genuine
   * two-sided completion even though the provider never pressed anything: the
   * customer saw the job happen.
   *
   * **No** → "flagged to the moderation queue as a possible no-show, same path
   * as a dispute", so this files a `booking` Report under `work_not_done` and
   * moves the booking to `disputed`. It is not a silent flag: §1c calls it the
   * same path as a dispute, and a dispute has a status.
   */
  async answerCompletionPrompt(
    userId: string,
    bookingId: string,
    happened: boolean,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking } = await this.authorize(userId, bookingId, 'customer');

    if (happened) {
      assertTransition('complete-customer-confirmed', booking.status, 'customer');
      await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          booking.status,
          { status: 'completed', completedAt: now, completedVia: 'confirmed' },
          tx,
        );
        if (!moved) throw staleBooking();
        await this.event(
          tx,
          booking,
          'completed',
          'complete-customer-confirmed',
          'customer',
          userId,
          now,
        );
      });
      await this.notify('completed', booking.id, booking.providerProfile.user.id);
      return this.reread(booking.id);
    }

    return this.raiseDispute(booking, { userId, role: 'customer' }, 'work_not_done', null, now);
  }

  // =========================================================================
  // Cancellation, and §1h's replacement
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/cancel` — one endpoint, two edges.
   *
   * Which edge depends on who called it, and the difference is not cosmetic:
   * §1f counts "provider-initiated cancellations after `accepted`" and says
   * "customer cancellations **never** count against a provider", and §1h's
   * replacement prefill is offered only where the provider is the one who
   * walked away.
   *
   * §1h's other half — "emergency bookings re-broadcast … normal bookings do
   * not broadcast" — is honoured by there being no broadcast here at all. The
   * customer gets their booking back as a prefill (`read` attaches it) and
   * rebooks when they choose; §Phase 17.3 owns the re-broadcast.
   */
  async cancel(userId: string, bookingId: string, reason?: string): Promise<BookingDto> {
    const now = this.clock();
    const { booking, caller } = await this.authorize(userId, bookingId);
    const transition = caller.role === 'provider' ? 'provider-cancel' : 'cancel';
    assertTransition(transition, booking.status, caller.role);

    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        {
          status: 'cancelled',
          cancelledAt: now,
          cancelledByRole: caller.role,
          cancellationReason: reason ?? null,
        },
        tx,
      );
      if (!moved) throw staleBooking();
      await this.releaseHold(tx, booking, 'cancelled', now);
      await this.event(tx, booking, 'cancelled', transition, caller.role, userId, now);
    });

    await this.notify(
      'cancelled',
      booking.id,
      caller.role === 'customer' ? booking.providerProfile.user.id : booking.customer.id,
    );
    return this.reread(booking.id);
  }

  // =========================================================================
  // §1h — the locked agreement
  // =========================================================================

  /**
   * `POST /v1/bookings/:id/amendments` — §1h.
   *
   * "At `accepted`, the agreed price, date, time and scope are locked. Neither
   * party can alter them unilaterally. Any change requires an **explicit
   * in-app amendment the other party accepts**. The original terms and the
   * amendment are both retained. **Every amendment attempt is recorded,
   * accepted or not**, and feeds price adherence."
   *
   * So the row is written on *proposal*. A rejected proposal is as much of a
   * record as an accepted one, and §Phase 11 counts proposals — which is what
   * makes "a provider who routinely revises upward on site has a number that
   * says so" true.
   *
   * One open proposal at a time, because two live counter-offers on one
   * agreement have no defined resolution and the plan describes none.
   */
  async proposeAmendment(
    userId: string,
    bookingId: string,
    input: ProposeAmendmentInput,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking, caller } = await this.authorize(userId, bookingId);

    if (!AMENDABLE_STATUSES.includes(booking.status)) {
      throw new BusinessRuleError(
        'BOOKING_NOT_AMENDABLE',
        'There is no locked agreement on this booking to amend',
        { status: booking.status },
      );
    }
    if (
      input.amountLaari === undefined &&
      input.scheduledFor === undefined &&
      input.scopeNote === undefined
    ) {
      // An amendment that changes nothing is not a proposal, it is noise in a
      // metric that exists to count real ones.
      throw new BusinessRuleError(
        'AMENDMENT_CHANGES_NOTHING',
        'Propose a new price, a new time, or a change of scope',
      );
    }
    const open = await this.repo.findOpenAmendment(bookingId);
    if (open !== null) {
      throw new ConflictError(
        'AMENDMENT_ALREADY_OPEN',
        'There is already an amendment waiting for an answer',
      );
    }

    await this.repo.createAmendment(
      {
        bookingId: booking.id,
        proposedByRole: caller.role,
        proposedByUserId: userId,
        // The original terms, copied rather than joined — the booking's live
        // values move when this is accepted, and a later reader must still see
        // what was being changed from.
        previousAmountLaari: booking.agreedAmountLaari,
        previousScheduledFor: booking.scheduledFor,
        previousScopeNote: booking.jobNotes,
        proposedAmountLaari: input.amountLaari ?? null,
        proposedScheduledFor: input.scheduledFor ?? null,
        proposedScopeNote: input.scopeNote ?? null,
        reason: input.reason ?? null,
        createdAt: now,
      },
      this.prisma,
    );

    await this.notify(
      'amendment_proposed',
      booking.id,
      caller.role === 'customer' ? booking.providerProfile.user.id : booking.customer.id,
    );
    return this.reread(booking.id);
  }

  /**
   * `PATCH /v1/bookings/:id/amendments/:amendmentId` — the counterparty
   * accepts or rejects.
   *
   * **Only the counterparty may answer**, which is the whole of "neither party
   * can alter them unilaterally": a proposer who could accept their own
   * proposal would have a unilateral change with extra steps. The proposer's
   * own move is `withdraw`, below.
   *
   * On acceptance the booking's live terms move, **and the hold moves with
   * them**. A new time means releasing the old reservation and taking the new
   * one in the same transaction (§Phase 9a's `reschedule`), so the provider is
   * never both blocked at the old time and free at the new one. The
   * exclusion constraint has the last word: an accepted time the provider has
   * since sold elsewhere fails as `PROVIDER_TIME_UNAVAILABLE` rather than
   * silently double-booking them.
   */
  async respondToAmendment(
    userId: string,
    bookingId: string,
    amendmentId: string,
    accept: boolean,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking, caller } = await this.authorize(userId, bookingId);

    const amendment = await this.repo.findAmendment(amendmentId);
    if (amendment?.bookingId !== booking.id) {
      throw new NotFoundError('No such amendment', 'AMENDMENT_NOT_FOUND');
    }
    if (amendment.status !== 'proposed') {
      throw new BusinessRuleError(
        'AMENDMENT_ALREADY_ANSWERED',
        'That amendment has already been answered',
        { status: amendment.status },
      );
    }
    if (amendment.proposedByRole === caller.role) {
      throw new BusinessRuleError(
        'AMENDMENT_NEEDS_THE_OTHER_PARTY',
        'The other party has to accept this amendment',
      );
    }

    await this.prisma.$transaction(async (tx) => {
      const answered = await this.repo.respondToAmendment(
        amendment.id,
        accept ? 'accepted' : 'rejected',
        userId,
        now,
        tx,
      );
      if (!answered) throw staleBooking();
      if (!accept) return;

      const data: Prisma.BookingUncheckedUpdateInput = {};
      if (amendment.proposedAmountLaari !== null) {
        data.agreedAmountLaari = amendment.proposedAmountLaari;
        data.amountSetAt = now;
      }
      if (amendment.proposedScopeNote !== null) data.jobNotes = amendment.proposedScopeNote;

      if (amendment.proposedScheduledFor !== null) {
        data.scheduledFor = amendment.proposedScheduledFor;
        if (booking.reservationId !== null) {
          const minutes = this.slotDuration(booking);
          await this.reservations.reschedule(
            tx,
            booking.reservationId,
            {
              startsAt: amendment.proposedScheduledFor,
              endsAt: new Date(amendment.proposedScheduledFor.getTime() + minutes * 60_000),
            },
            now,
          );
          // The booking no longer sits on a published slot: the old one went
          // back to `open` when its hold was released, and the new time is a
          // window the provider agreed to rather than one they published.
          data.timeSlotId = null;
        }
      }

      const moved = await this.repo.stamp(booking.id, booking.status, data, tx);
      if (!moved) throw staleBooking();
    });

    await this.notify('amendment_answered', booking.id, amendment.proposedByUserId);
    return this.reread(booking.id);
  }

  /**
   * The proposer taking their own proposal back. Still an attempt, and the row
   * stays — §1h counts proposals, not survivors.
   */
  async withdrawAmendment(
    userId: string,
    bookingId: string,
    amendmentId: string,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking, caller } = await this.authorize(userId, bookingId);
    const amendment = await this.repo.findAmendment(amendmentId);
    if (amendment?.bookingId !== booking.id) {
      throw new NotFoundError('No such amendment', 'AMENDMENT_NOT_FOUND');
    }
    if (amendment.proposedByRole !== caller.role) {
      throw new BusinessRuleError(
        'AMENDMENT_NOT_YOURS',
        'Only the party who proposed an amendment can withdraw it',
      );
    }
    const done = await this.repo.respondToAmendment(
      amendment.id,
      'withdrawn',
      userId,
      now,
      this.prisma,
    );
    if (!done) {
      throw new BusinessRuleError(
        'AMENDMENT_ALREADY_ANSWERED',
        'That amendment has already been answered',
      );
    }
    return this.reread(booking.id);
  }

  // =========================================================================
  // Disputes
  // =========================================================================

  /**
   * `PATCH /v1/bookings/:id/dispute` — §Phase 17 item 11. Either party.
   *
   * §1c: "A **late dispute** (post-`completed`) is accepted; the booking stays
   * completed and the dispute queues separately." So a completed booking files
   * a Report and does **not** transition — which is why the status change below
   * is conditional rather than unconditional.
   *
   * Decline ≠ dispute (§1c): separate endpoints, separate statuses.
   */
  async dispute(
    userId: string,
    bookingId: string,
    reason: ReportReason,
    note: string | null,
  ): Promise<BookingDto> {
    const now = this.clock();
    const { booking, caller } = await this.authorize(userId, bookingId);
    return this.raiseDispute(booking, caller, reason, note, now);
  }

  /**
   * `PATCH /v1/bookings/:id/resolve-dispute` — §Phase 17 item 12, admin only.
   *
   * One endpoint for two jobs, because the plan gives it both: it resolves a
   * `disputed` booking "with an **enumerated outcome**", and it "also resolves
   * `payment_unresolved` to `confirmed` or `cancelled`".
   *
   * 🔧 Resolving an unresolved claim to `confirmed` reaches §Phase 8a's trial
   * hook, exactly as §Phase 17 item 20 requires: the hook fires "on the state
   * transition into `confirmed`, **not from one endpoint**".
   */
  async resolveDispute(
    adminUserId: string,
    bookingId: string,
    outcome: DisputeOutcome,
    resolution: { unresolvedTo?: 'confirmed' | 'cancelled'; note?: string },
  ): Promise<BookingDto> {
    const now = this.clock();
    const booking = await this.mustFind(bookingId);

    if (booking.status === 'payment_unresolved') {
      const to = resolution.unresolvedTo;
      if (to === undefined) {
        throw new BusinessRuleError(
          'UNRESOLVED_NEEDS_AN_OUTCOME',
          'Resolve this to confirmed or cancelled',
        );
      }
      const transition =
        to === 'confirmed' ? 'resolve-unresolved-confirmed' : 'resolve-unresolved-cancelled';
      assertTransition(transition, booking.status, 'admin');

      await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          booking.status,
          to === 'confirmed'
            ? { status: 'confirmed', disputeOutcome: outcome, disputeResolvedAt: now }
            : {
                status: 'cancelled',
                cancelledAt: now,
                cancelledByRole: 'admin',
                disputeOutcome: outcome,
                disputeResolvedAt: now,
              },
          tx,
        );
        if (!moved) throw staleBooking();
        if (to === 'cancelled') await this.releaseHold(tx, booking, 'cancelled', now);
        await this.event(tx, booking, to, transition, 'admin', adminUserId, now);
      });

      if (to === 'confirmed') await this.enterConfirmed(booking.id, booking.providerProfileId);
      await this.notifyBoth('dispute_resolved', booking);
      return this.reread(booking.id);
    }

    assertTransition('resolve-dispute', booking.status, 'admin');
    await this.prisma.$transaction(async (tx) => {
      const moved = await this.repo.transition(
        booking.id,
        booking.status,
        { status: 'dispute_resolved', disputeOutcome: outcome, disputeResolvedAt: now },
        tx,
      );
      if (!moved) throw staleBooking();
      // A resolved dispute frees whatever time the booking was still holding:
      // nobody is turning up for it now.
      await this.releaseHold(tx, booking, 'cancelled', now);
      await this.event(
        tx,
        booking,
        'dispute_resolved',
        'resolve-dispute',
        'admin',
        adminUserId,
        now,
      );
    });

    await this.markReportsResolved(bookingId, adminUserId, outcome, resolution.note ?? null, now);
    await this.notifyBoth('dispute_resolved', booking);
    return this.reread(booking.id);
  }

  // =========================================================================
  // Scheduled jobs (§Phase 17 items 7, 10 and 14)
  // =========================================================================

  /**
   * §1c step 4: "Slot and request-based: **24 hours** → auto-decline, release
   * the slot or reservation, notify the customer to look elsewhere."
   *
   * The emergency window is not this job's. §Phase 17.3 reads it from
   * `Category.emergencyAcceptWindowMinutes`, and the candidate query here
   * excludes emergency bookings outright rather than trusting a later filter.
   */
  async runAcceptTimeouts(now: Date, limit = 200): Promise<{ declined: number }> {
    const before = new Date(now.getTime() - ACCEPT_WINDOW_MINUTES * 60_000);
    const due = await this.repo.findAcceptTimeouts(before, limit);
    let declined = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'requested') continue;
      const done = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'requested',
          { status: 'declined', declinedAt: now },
          tx,
        );
        if (!moved) return false;
        await this.releaseHold(tx, booking, 'declined', now);
        await this.event(tx, booking, 'declined', 'accept-timeout', 'system', null, now);
        return true;
      });
      if (done) {
        declined += 1;
        await this.notify('accept_timed_out', booking.id, booking.customer.id);
      }
    }
    return { declined };
  }

  /**
   * §1c step 4's first clause for request mode: the provider never quoted.
   *
   * 🔧 **This runs on the category's `quoteExpiryMinutes`, not on the flat 24
   * hours** — invariant 13, Round 15: "2 hours to quote" for the household
   * trades and 24 for the long-lead ones. `Request a Time.dc.html` promises it
   * to the customer in those words: "Ibrahim has 2 hours — until 12:30 today —
   * to reply with a time and price. **If he doesn't, the request expires and
   * you owe nothing.**"
   *
   * The deadline is already on the row (`quoteDueAt`, stamped at creation), so
   * this is one indexed range scan and no join through the category — and a
   * request keeps the deadline it was created under even if an admin edits the
   * category afterwards.
   *
   * `declined` with a **`system`** actor, exactly as the slot window's
   * `accept-timeout` is: §1f reads the actor to tell a timeout from an
   * explicit refusal, so this feeds response rate and never acceptance rate.
   */
  async runQuoteRequestTimeouts(now: Date, limit = 200): Promise<{ declined: number }> {
    const due = await this.repo.findQuoteRequestTimeouts(now, limit);
    let declined = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'awaiting_quote') continue;
      const done = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'awaiting_quote',
          { status: 'declined', declinedAt: now },
          tx,
        );
        if (!moved) return false;
        // Nothing is normally held at `awaiting_quote` — the hold arrives with
        // the quote — but releasing is a no-op where there is nothing, and
        // assuming otherwise is how a provider's calendar stays blocked.
        await this.releaseHold(tx, booking, 'declined', now);
        await this.event(tx, booking, 'declined', 'quote-request-timeout', 'system', null, now);
        return true;
      });
      if (done) {
        declined += 1;
        await this.notify('quote_request_timed_out', booking.id, booking.customer.id);
      }
    }
    return { declined };
  }

  /**
   * §1c step 4's third clause: "**Customer quote-approval:** the category's
   * `quoteApprovalMinutes` from the quote being *offered* (its own clock) —
   * 240 minutes for the household trades, 4320 for the long-lead ones; the
   * flat 72 hours this line used to name is the long-lead figure and was never
   * the rule after Round 15 → **quote expires, provisional reservation
   * releases, booking closes**."
   *
   * All three effects are here, and the third is `cancelled` rather than
   * `declined` for the reason `transitions.ts` records: the party who did not
   * act is the customer, and a provider's acceptance rate must not move
   * because somebody stopped reading their phone. `cancelledByRole` is left
   * **null** — nobody cancelled, a clock ran out — so §1f counts neither.
   */
  async runQuoteApprovalTimeouts(now: Date, limit = 200): Promise<{ expired: number }> {
    const due = await this.repo.findQuoteApprovalTimeouts(now, limit);
    let expired = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'quote_offered') continue;
      const done = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'quote_offered',
          { status: 'cancelled', cancelledAt: now },
          tx,
        );
        if (!moved) return false;
        // The hold goes with it, in the same transaction — the second half of
        // 17.2's Done-when clause: created inside the quote transaction and
        // "released in one".
        await this.releaseHold(tx, booking, 'cancelled', now);
        await this.event(tx, booking, 'cancelled', 'quote-approval-timeout', 'system', null, now);
        return true;
      });
      if (done) {
        expired += 1;
        // Both parties: the customer lost the quote and the provider got their
        // time back, and each needs to know which.
        await this.notifyBoth('quote_expired', booking);
      }
    }
    return { expired };
  }

  /**
   * §1c step 9: seven days of provider silence on a payment claim →
   * `payment_unresolved`, **not** `confirmed`.
   *
   * "Both parties notified, queued in Phase 22's moderation queue. **Nothing
   * further is unlocked by this transition.**" So there is no entitlement call
   * here, no trial hook, and no access granted — the only effects are the
   * status, the Report and the two notifications.
   */
  async runPaymentSilenceTimeouts(now: Date, limit = 200): Promise<{ escalated: number }> {
    const before = daysBefore(now, PAYMENT_SILENCE_DAYS);
    const due = await this.repo.findPaymentSilenceTimeouts(before, limit);
    let escalated = 0;
    for (const { id } of due) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'payment_claimed') continue;
      const done = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'payment_claimed',
          { status: 'payment_unresolved' },
          tx,
        );
        if (!moved) return false;
        await this.event(
          tx,
          booking,
          'payment_unresolved',
          'payment-silence-timeout',
          'system',
          null,
          now,
        );
        // §4 Sequencing: "build 17 first with a minimal Report insert".
        // Reporter is null — the system filed this, and recording a human
        // reporter would be a lie about who complained.
        await this.repo.createReport(
          {
            reporterId: null,
            targetType: 'booking',
            targetId: booking.id,
            bookingId: booking.id,
            reason: 'payment_dispute',
            status: 'open',
            createdAt: now,
          },
          tx,
        );
        return true;
      });
      if (done) {
        escalated += 1;
        await this.notifyBoth('payment_unresolved', booking);
      }
    }
    return { escalated };
  }

  /**
   * §1c step 10, both halves.
   *
   * **At 7 days past `scheduledFor`** with no completion, the customer is
   * prompted — the booking does not move, and `completionPromptedAt` is what
   * starts the grace.
   *
   * **After a further 3 days** with no answer, it auto-completes as
   * `completedVia: 'unconfirmed'` — "a provider must not be able to block
   * reviews forever by staying silent", and §Phase 11 gates reviews on
   * completion precisely because this exists.
   */
  async runCompletionTimeouts(
    now: Date,
    limit = 200,
  ): Promise<{ prompted: number; autoCompleted: number }> {
    let prompted = 0;
    const promptDue = await this.repo.findCompletionPromptDue(
      daysBefore(now, COMPLETION_PROMPT_AFTER_DAYS),
      limit,
    );
    for (const { id } of promptDue) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'confirmed') continue;
      const done = await this.repo.stamp(
        booking.id,
        'confirmed',
        { completionPromptedAt: now },
        this.prisma,
      );
      if (done) {
        prompted += 1;
        await this.notify('completion_prompt', booking.id, booking.customer.id);
      }
    }

    let autoCompleted = 0;
    const graceDue = await this.repo.findCompletionGraceExpired(
      daysBefore(now, COMPLETION_GRACE_DAYS),
      limit,
    );
    for (const { id } of graceDue) {
      const booking = await this.repo.findById(id);
      if (booking?.status !== 'confirmed') continue;
      const done = await this.prisma.$transaction(async (tx) => {
        const moved = await this.repo.transition(
          booking.id,
          'confirmed',
          { status: 'completed', completedAt: now, completedVia: 'unconfirmed' },
          tx,
        );
        if (!moved) return false;
        await this.event(tx, booking, 'completed', 'complete-unconfirmed', 'system', null, now);
        return true;
      });
      if (done) {
        autoCompleted += 1;
        await this.notifyBoth('completed_unconfirmed', booking);
      }
    }

    return { prompted, autoCompleted };
  }

  // =========================================================================
  // The two seams earlier phases built against
  // =========================================================================

  /**
   * §Phase 3's `DeletionBlocker`, filled. "Anonymisation executes
   * automatically once non-terminal bookings terminate, with a hard 30-day
   * backstop" — the backstop is the anonymiser's and is unchanged.
   */
  hasOpenBookings(userId: string): Promise<boolean> {
    return this.repo.hasOpenBookings(userId, NON_TERMINAL_STATUSES);
  }

  /** §Phase 8a's `SubscriptionBookingSource`, filled. */
  hasAnyBooking(providerProfileId: string): Promise<boolean> {
    return this.repo.hasAnyBookingForProvider(providerProfileId);
  }

  /** §1b's protected listings — committed status **and** a future `scheduledFor`. */
  listingIdsWithCommittedBooking(listingIds: string[]): Promise<string[]> {
    return this.repo.listingIdsWithCommittedBooking(
      listingIds,
      [...COMMITTED_STATUSES],
      this.clock(),
    );
  }

  // =========================================================================
  // Internals
  // =========================================================================

  /**
   * Resolves the caller's side of the booking, or 404s.
   *
   * **A stranger gets `not found`, never `forbidden`** — the existence of
   * somebody else's booking is not theirs to learn. `expect` narrows it
   * further where an endpoint is one side's only: a customer calling the
   * provider's accept gets the actor error from the machine, which names the
   * action rather than the booking.
   */
  private async authorize(
    userId: string,
    bookingId: string,
    expect?: CallerRole,
  ): Promise<{ booking: BookingRow; caller: Caller }> {
    const booking = await this.mustFind(bookingId);
    const role: CallerRole | null =
      booking.customerId === userId
        ? 'customer'
        : booking.providerProfile.user.id === userId
          ? 'provider'
          : null;
    if (role === null) throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    if (expect !== undefined && role !== expect) {
      throw new BusinessRuleError(
        'BOOKING_ACTOR_NOT_ALLOWED',
        expect === 'provider' ? 'Only the provider can do that' : 'Only the customer can do that',
        { expected: expect, actual: role },
      );
    }
    return { booking, caller: { userId, role } };
  }

  /**
   * The gate every creation path passes, and the one place the mode is routed.
   *
   * Order matters and each refusal is §1c's or §1a's:
   *  - a listing that is not published, active and undeleted is **not found**,
   *    never "forbidden" — a hidden listing's existence is not a caller's to
   *    learn;
   *  - a suspended provider's listing is *also* not found (§1a: suspension is
   *    an input to visibility, so a stale screen cannot book one);
   *  - `acceptingNewCustomers` off is a refusal the customer can act on;
   *  - and the **mode** is last, so a caller reaching the wrong path is told
   *    which one this listing takes.
   *
   * 🔧 The mode refusal is what §Phase 17.1 left for this slice. It read "this
   * service is booked by request rather than by picking a time" for every
   * `request` listing; now each mode has a path and only `emergency` — §Phase
   * 17.3's, and never a *listing's* mode (§1c: emergency is a capability
   * layered on a `request` listing) — is still refused by name.
   */
  private async bookableListing(listingId: string, userId: string, expect: 'slot' | 'request') {
    const listing = await this.prisma.listing.findFirst({
      where: { id: listingId, status: 'published', visibility: 'active', deletedAt: null },
      select: {
        id: true,
        providerProfileId: true,
        bookingMode: true,
        pricingModel: true,
        priceLaari: true,
        categoryId: true,
        // §Phase 17.2 reads four of these: both quote clocks (invariant 13),
        // Round 14's lead time and Round 25's occasion presets. None of them
        // is ever a literal in this module.
        category: {
          select: {
            id: true,
            name: true,
            quoteExpiryMinutes: true,
            quoteApprovalMinutes: true,
            minimumLeadTimeMinutes: true,
            occasionPresets: true,
          },
        },
        providerProfile: {
          select: { id: true, userId: true, suspendedAt: true, acceptingNewCustomers: true },
        },
      },
    });
    if (listing === null) throw new NotFoundError('No such service', 'LISTING_NOT_FOUND');

    if (listing.providerProfile.userId === userId) {
      throw new BusinessRuleError('CANNOT_BOOK_OWN_LISTING', 'You cannot book your own service');
    }
    if (listing.providerProfile.suspendedAt !== null) {
      throw new NotFoundError('No such service', 'LISTING_NOT_FOUND');
    }
    if (!listing.providerProfile.acceptingNewCustomers) {
      throw new BusinessRuleError(
        'PROVIDER_NOT_ACCEPTING_BOOKINGS',
        'This provider is not taking new bookings right now',
      );
    }
    if (listing.bookingMode !== expect) {
      throw new BusinessRuleError(
        'BOOKING_MODE_NOT_AVAILABLE',
        listing.bookingMode === 'request'
          ? 'This service is booked by request — send a preferred time instead'
          : 'This service is booked by picking a published time',
        { bookingMode: listing.bookingMode },
      );
    }
    if (listing.category === null) {
      // Unreachable: §Phase 8 requires a category to publish. A booking is a
      // commitment and this is not the place to assume.
      throw new NotFoundError('No such service', 'LISTING_NOT_FOUND');
    }
    return { ...listing, category: listing.category };
  }

  /**
   * Round 25: the occasion is "one of the category's `occasionPresets`",
   * request mode only, never required.
   *
   * Checked against the seeded list rather than accepted as free text, because
   * the whole value of the field is that it aggregates — "Wedding — 26 Aug" as
   * a booking subtitle is only meaningful while everybody's weddings say
   * "Wedding". A category with no presets (every one but Photography and Boat
   * Charter) accepts no occasion at all.
   */
  private validateOccasion(
    category: { name: string; occasionPresets: string[] },
    occasion: string | undefined,
  ): string | null {
    if (occasion === undefined) return null;
    if (!category.occasionPresets.includes(occasion)) {
      throw new BusinessRuleError(
        'OCCASION_NOT_IN_CATEGORY',
        `"${occasion}" is not one of the occasions ${category.name} offers`,
        { allowed: category.occasionPresets },
      );
    }
    return occasion;
  }

  /**
   * §1c's preferred window, as stored.
   *
   * The text is what a human reads and the range is the machine-readable
   * restatement. Where the customer typed something, **their words win** —
   * they tapped a chip and then said "Thursday after 16:00", and the specific
   * one is the one the provider should read. The chip's range is still stored
   * in that case, because it is the only structured form either input has.
   */
  private resolvePreferredWindow(
    input: CreateRequestBookingInput,
    now: Date,
  ): { text: string | null; from: Date | null; to: Date | null } {
    const chip = input.preferredWindowChip;
    const range = chip === undefined ? null : resolveWindowChip(chip, now);
    const text = input.preferredWindowText ?? (chip === undefined ? null : chipLabel(chip));
    return { text, from: range?.from ?? null, to: range?.to ?? null };
  }

  private async mustFind(id: string): Promise<BookingRow> {
    const booking = await this.repo.findById(id);
    if (booking === null) throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    return booking;
  }

  private async reread(id: string): Promise<BookingDto> {
    return toBookingDto(await this.mustFind(id), this.clock());
  }

  /**
   * Writes the booking with a fresh reference, retrying on the unique index
   * rather than checking first — a read-then-write has a race and the index
   * does not.
   */
  private async createWithReference(
    tx: Db,
    data: Omit<Prisma.BookingUncheckedCreateInput, 'reference'>,
  ) {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      try {
        return await this.repo.create({ ...data, reference: generateBookingReference() }, tx);
      } catch (error) {
        if (attempt === 4 || !isUniqueViolation(error, 'reference')) throw error;
      }
    }
    // Unreachable: the loop either returns or throws.
    throw new Error('could not allocate a booking reference');
  }

  private async event(
    tx: Db,
    booking: { id: string; status: BookingStatus },
    to: BookingStatus,
    transition: string,
    actorRole: BookingActorRole,
    actorUserId: string | null,
    at: Date,
  ): Promise<void> {
    await this.repo.recordStatusEvent(
      {
        bookingId: booking.id,
        fromStatus: booking.status,
        toStatus: to,
        actorRole,
        actorUserId,
        transition,
        at,
      },
      tx,
    );
  }

  /**
   * Frees whatever time this booking was holding (§Phase 17 item 6: "frees the
   * slot/reservation"). A booking with no reservation — emergency, or a
   * request-based one before its quote — has nothing to free, which is why
   * this is a no-op rather than an error.
   */
  private async releaseHold(
    tx: Db,
    booking: BookingRow,
    reason: 'cancelled' | 'declined',
    now: Date,
  ): Promise<void> {
    if (booking.reservationId === null) return;
    await this.reservations.release(tx, booking.reservationId, reason, now);
  }

  /**
   * §Phase 17 item 20, and the reason it is a method rather than a line in
   * `confirmPaymentReceived`: "the trial-start hook fires on **the state
   * transition into `confirmed`**, not from one endpoint — so both
   * `confirm-payment-received` and an admin `resolve-dispute` resolution reach
   * it."
   *
   * Stamped so the two doors cannot fire it twice, and failure is logged
   * rather than thrown: a trial that did not start is not a reason to fail the
   * confirmation a provider is waiting on.
   */
  private async enterConfirmed(bookingId: string, providerProfileId: string): Promise<void> {
    if (this.onConfirmed === undefined) return;
    const now = this.clock();
    const { count } = await this.prisma.booking.updateMany({
      where: { id: bookingId, trialHookFiredAt: null },
      data: { trialHookFiredAt: now },
    });
    if (count !== 1) return;
    try {
      await this.onConfirmed(providerProfileId);
    } catch (error) {
      this.log.warn({ err: error, bookingId }, 'trial-start hook failed on booking confirmation');
    }
  }

  /** The shared body of `dispute` and the completion prompt's "No". */
  private async raiseDispute(
    booking: BookingRow,
    caller: Caller,
    reason: ReportReason,
    note: string | null,
    now: Date,
  ): Promise<BookingDto> {
    assertReasonAllowed('booking', reason);

    // §1c: "A late dispute (post-`completed`) is accepted; the booking stays
    // completed and the dispute queues separately."
    const late = isTerminal(booking.status);

    await this.prisma.$transaction(async (tx) => {
      if (!late) {
        assertTransition('dispute', booking.status, caller.role);
        const moved = await this.repo.transition(
          booking.id,
          booking.status,
          { status: 'disputed', disputedAt: now },
          tx,
        );
        if (!moved) throw staleBooking();
        await this.event(tx, booking, 'disputed', 'dispute', caller.role, caller.userId, now);
      }
      await this.repo.createReport(
        {
          reporterId: caller.userId,
          targetType: 'booking',
          targetId: booking.id,
          bookingId: booking.id,
          reason,
          note,
          status: 'open',
          createdAt: now,
        },
        tx,
      );
    });

    await this.notify(
      'disputed',
      booking.id,
      caller.role === 'customer' ? booking.providerProfile.user.id : booking.customer.id,
    );
    return this.reread(booking.id);
  }

  /**
   * Closes the open Reports a resolved dispute was about. §Phase 22 owns the
   * queue; what §Phase 17.1 owes it is that a booking it has finished with is
   * not left sitting in it.
   */
  private async markReportsResolved(
    bookingId: string,
    adminUserId: string,
    outcome: DisputeOutcome,
    note: string | null,
    now: Date,
  ): Promise<void> {
    await this.prisma.report.updateMany({
      where: { bookingId, status: { in: ['open', 'under_review'] } },
      data: {
        status: 'resolved',
        reviewedByAdminId: adminUserId,
        reviewedAt: now,
        // §Phase 22: `resolved` is unreachable without a resolution reason.
        // The dispute outcome is that reason, and the admin's note follows it.
        resolutionReason: note === null ? outcome : `${outcome}: ${note}`,
      },
    });
  }

  /**
   * §1h: "the customer is dropped back into the booking flow with service,
   * date, time and preferences pre-filled" — offered only to the **customer**,
   * and only where the **provider** is the one who cancelled.
   */
  private offersReplacement(booking: BookingRow, role: CallerRole): boolean {
    return (
      role === 'customer' &&
      booking.status === 'cancelled' &&
      booking.cancelledByRole === 'provider'
    );
  }

  private slotDuration(booking: BookingRow): number {
    if (booking.timeSlot !== null) {
      return durationMinutes(booking.timeSlot.startsAt, booking.timeSlot.endsAt);
    }
    // A booking whose slot has gone (an accepted amendment cleared it) keeps
    // its length on the reservation. 60 minutes is the last resort and is
    // reached only by a request-based booking with no hold at all, which
    // §Phase 17.2 gives a real duration.
    return 60;
  }

  private async providerProfileIdOf(userId: string): Promise<string | null> {
    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true },
    });
    return profile?.id ?? null;
  }

  private async notify(
    event: BookingNotification,
    bookingId: string,
    userId: string,
  ): Promise<void> {
    try {
      await this.notifier.notify({ event, bookingId, userId });
    } catch (error) {
      // A notification that did not go out must never roll back a transition
      // that did. §Phase 19 owns delivery and its own retries.
      this.log.warn({ err: error, event, bookingId }, 'booking notification failed');
    }
  }

  private async notifyBoth(event: BookingNotification, booking: BookingRow): Promise<void> {
    await this.notify(event, booking.id, booking.customer.id);
    await this.notify(event, booking.id, booking.providerProfile.user.id);
  }

  /**
   * §1c step 2's accept prompt — the one booking notification that has a
   * §Phase 3c `NotificationKind` of its own, because that phase built
   * `booking_accept_prompt` for exactly this.
   *
   * **Job details and the customer's first name only.** §Phase 3c's own
   * content rule keeps amounts, phone numbers and links off a lock screen, and
   * the context shape has room for nothing else.
   */
  private async sendAcceptPrompt(booking: BookingRow): Promise<void> {
    if (this.dispatcher === undefined) return;
    try {
      await this.dispatcher.dispatch({
        userId: booking.providerProfile.user.id,
        urgency: 'standard',
        subjectId: booking.id,
        context: {
          kind: 'booking_accept_prompt',
          bookingType: booking.listing.category?.name ?? 'Service',
          customerFirstName: firstName(booking.customer.fullName),
          islandName: booking.island === null ? '' : islandDisplayName(booking.island),
        },
      });
    } catch (error) {
      this.log.warn({ err: error, bookingId: booking.id }, 'accept prompt dispatch failed');
    }
  }
}

/**
 * The statuses at which §1h's agreement exists and can be amended.
 *
 * Nothing before `accepted` is locked — there is no agreement yet — and
 * nothing terminal can be. `disputed` and `payment_unresolved` are excluded
 * because an admin owns them: an amendment accepted underneath a live dispute
 * would change the terms the dispute is about.
 */
const AMENDABLE_STATUSES: BookingStatus[] = [
  'accepted',
  'awaiting_payment',
  'payment_claimed',
  'confirmed',
];

/** The two-devices case, and the stale screen. Same truth, same answer. */
function staleBooking(): ConflictError {
  return new ConflictError(
    'BOOKING_CHANGED',
    'This booking changed while you were looking at it — open it again',
  );
}

function firstName(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? fullName;
}

function isUniqueViolation(error: unknown, field: string): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const e = error as { code?: unknown; meta?: { target?: unknown } };
  if (e.code !== 'P2002') return false;
  const target = e.meta?.target;
  return Array.isArray(target) ? target.some((t) => String(t).includes(field)) : true;
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

export { TERMINAL_STATUSES };
