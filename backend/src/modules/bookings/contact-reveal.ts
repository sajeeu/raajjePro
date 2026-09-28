import type { Clock } from '../../core/clock.js';
import { BusinessRuleError, NotFoundError } from '../../core/errors.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { BookingStatus, KillSwitchKey } from '../../generated/prisma/enums.js';
import type { BookingNotifier } from './notifications.js';
import type { BookingRepository, BookingRow } from './repository.js';
import { isTerminal } from './transitions.js';
import type { ContactRevealDto, ContactRevealState } from './types.js';
import { CONTACT_REVEAL_AFTER_TERMINAL_HOURS } from './windows.js';

/**
 * `POST /v1/bookings/:id/reveal-contact` — **the single place in RaajjePro
 * where a phone number reaches another user** (§1c, Round 9).
 *
 * ## The seven conditions, and the eighth that is not one of them
 *
 * §1c: "Conditions — **all seven must hold**, and are validated on every
 * request", each below by its number and each refused with its own code so a
 * test can see it fail for the right reason:
 *
 *  1. the booking's mode is `emergency`                 → `CONTACT_REVEAL_EMERGENCY_ONLY`
 *  2. it is at `accepted` or later                       → `CONTACT_REVEAL_NOT_ACCEPTED`
 *  3. the customer initiates it                          → `CONTACT_REVEAL_CUSTOMER_INITIATES`
 *  4. mutual and simultaneous — both numbers or neither  → `CONTACT_REVEAL_UNAVAILABLE`
 *  5. the counterparty is notified                       (the notifier, on the first reveal)
 *  6. it expires 24 hours after a terminal state         → `CONTACT_REVEAL_EXPIRED`
 *  7. every reveal is logged                             (`ContactRevealEvent`, IDs only)
 *
 * "**Separately, and not one of the seven:** the reveal is killable at
 * runtime via the Phase 10b kill switch, without a deploy. This is a runtime
 * feature flag checked **before** the seven" → `CONTACT_REVEAL_PAUSED`.
 * §Phase 10b builds the screen that flips it and is deferred by the owner
 * (§0.0 item 20, ledger **P10-DEFER**); this is the check, and a check
 * against a flag with no admin surface is the intended state.
 *
 * ## Condition 2 — "accepted or later"
 *
 * §0.3 once said emergency contact unlocks at `payment_claimed`; §0.0's
 * precedence rule gives it to §Phase 17 item 19 and §1c, which both say
 * **`accepted` or later**. Read as: the booking was accepted (`amountSetAt`
 * is stamped at `accepted` and cleared by a re-dispatch) and is not back at a
 * pre-acceptance status. A booking cancelled while still a broadcast was
 * never accepted and never reveals.
 *
 * ## Condition 3 and condition 4 together
 *
 * "There is no automatic reveal and **no provider-initiated reveal**" — and
 * "Both parties see each other's number, or neither does." So the customer's
 * call *is* the reveal, and the provider's call is how they see the
 * customer's number afterwards: refused while no customer reveal exists
 * (that would be provider-initiated), answered once one does. Both calls
 * return both numbers.
 *
 * ## What never crosses
 *
 * WhatsApp and Viber handles are not collected anywhere (§Phase 5) and there
 * is no field for either. Nothing about either party beyond a name and a
 * number is returned. The log stores IDs, never the numbers.
 */

/** §Phase 10b's switches, as the one read this slice needs. */
export interface KillSwitches {
  isEngaged(key: KillSwitchKey): Promise<boolean>;
}

/** The runtime check against the `KillSwitch` table. No row means not engaged. */
export function databaseKillSwitches(prisma: PrismaClient): KillSwitches {
  return {
    async isEngaged(key) {
      const row = await prisma.killSwitch.findUnique({ where: { key }, select: { engaged: true } });
      return row?.engaged === true;
    },
  };
}

/** Statuses before acceptance. A booking back at one of these after a re-dispatch has no reveal. */
const PRE_ACCEPTANCE: readonly BookingStatus[] = [
  'requested',
  'emergency_offered',
  'awaiting_quote',
  'quote_offered',
];

const PRE_SELECTION: readonly BookingStatus[] = ['requested', 'emergency_offered'];

/** When the booking reached its terminal state — the stamp for whichever ending it had. */
function terminalAt(booking: BookingRow): Date | null {
  if (!isTerminal(booking.status)) return null;
  return (
    booking.completedAt ??
    booking.cancelledAt ??
    booking.declinedAt ??
    booking.disputeResolvedAt ??
    booking.updatedAt
  );
}

function revealExpiresAt(booking: BookingRow): Date | null {
  const at = terminalAt(booking);
  return at === null
    ? null
    : new Date(at.getTime() + CONTACT_REVEAL_AFTER_TERMINAL_HOURS * 60 * 60_000);
}

/**
 * Conditions 1, 2 and 6 — the three that depend on the booking alone. Returns
 * the refusal rather than throwing so the detail read can report the same
 * answer as a state without revealing anything.
 */
function bookingRefusal(booking: BookingRow, now: Date): BusinessRuleError | null {
  if (booking.bookingMode !== 'emergency') {
    return new BusinessRuleError(
      'CONTACT_REVEAL_EMERGENCY_ONLY',
      'Numbers are only ever shared on an emergency booking — use the chat',
    );
  }
  if (booking.amountSetAt === null || PRE_ACCEPTANCE.includes(booking.status)) {
    return new BusinessRuleError(
      'CONTACT_REVEAL_NOT_ACCEPTED',
      'Numbers can be shared once a provider has accepted this emergency',
    );
  }
  const expires = revealExpiresAt(booking);
  if (expires !== null && now >= expires) {
    return new BusinessRuleError(
      'CONTACT_REVEAL_EXPIRED',
      'Access to the numbers ended 24 hours after this booking closed',
      { expiredAt: expires.toISOString() },
    );
  }
  return null;
}

/** The `contactReveal` field of the emergency detail block — the same rules, no numbers. */
export async function contactRevealState(
  prisma: PrismaClient,
  killSwitches: KillSwitches,
  booking: BookingRow,
  now: Date,
): Promise<ContactRevealState> {
  if (booking.bookingMode !== 'emergency') return 'not_available';
  if (await killSwitches.isEngaged('emergency_contact_reveal')) return 'paused';
  const refusal = bookingRefusal(booking, now);
  if (refusal?.code === 'CONTACT_REVEAL_EXPIRED') return 'expired';
  if (refusal !== null) return 'not_available';
  const started = await prisma.contactRevealEvent.findFirst({
    where: { bookingId: booking.id, actorRole: 'customer' },
    select: { id: true },
  });
  return started === null ? 'available' : 'revealed';
}

export class ContactRevealService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      clock: Clock;
      repo: BookingRepository;
      notifier: BookingNotifier;
      killSwitches: KillSwitches;
      log: { warn(obj: Record<string, unknown>, msg: string): void };
    },
  ) {}

  /**
   * Who may call: the customer on an emergency booking, to start the reveal;
   * the provider on it, only once the customer has. Anyone else — including a
   * provider who offered on the broadcast and was not chosen — gets 404.
   */
  async reveal(userId: string, bookingId: string): Promise<ContactRevealDto> {
    const { prisma, clock, repo } = this.deps;
    const now = clock();

    // The eighth line, first: "a runtime feature flag checked before the seven".
    if (await this.deps.killSwitches.isEngaged('emergency_contact_reveal')) {
      throw new BusinessRuleError(
        'CONTACT_REVEAL_PAUSED',
        'Number sharing is paused right now — chat is unaffected',
      );
    }

    const booking = await repo.findById(bookingId);
    const role =
      booking === null
        ? null
        : booking.customerId === userId
          ? ('customer' as const)
          : booking.providerProfile.user.id === userId &&
              // An emergency still being broadcast has no provider side yet —
              // its provider columns only name the listing it came from.
              !(booking.bookingMode === 'emergency' && PRE_SELECTION.includes(booking.status))
            ? ('provider' as const)
            : null;
    if (booking === null || role === null) {
      throw new NotFoundError('No such booking', 'BOOKING_NOT_FOUND');
    }

    // Conditions 1, 2 and 6.
    const refusal = bookingRefusal(booking, now);
    if (refusal !== null) throw refusal;

    // Condition 3: the customer starts it; the provider can only follow.
    const started = await prisma.contactRevealEvent.findFirst({
      where: { bookingId: booking.id, actorRole: 'customer' },
      orderBy: { createdAt: 'asc' },
    });
    if (role === 'provider' && started === null) {
      throw new BusinessRuleError(
        'CONTACT_REVEAL_CUSTOMER_INITIATES',
        'Only the customer can start sharing numbers — use the chat',
      );
    }

    // Condition 4: both numbers, or neither. The **only** read of
    // `phoneE164` in this module, and it happens after every other condition
    // has already held.
    const [customer, provider] = await Promise.all([
      prisma.user.findUniqueOrThrow({
        where: { id: booking.customerId },
        select: { fullName: true, phoneE164: true },
      }),
      prisma.user.findUniqueOrThrow({
        where: { id: booking.providerProfile.user.id },
        select: { fullName: true, phoneE164: true },
      }),
    ]);
    if (customer.phoneE164 === null || provider.phoneE164 === null) {
      throw new BusinessRuleError(
        'CONTACT_REVEAL_UNAVAILABLE',
        'Numbers cannot be shared on this booking — keep using the chat',
      );
    }

    // Condition 7: every call that returns numbers is on the record.
    const logged = await prisma.contactRevealEvent.create({
      data: { bookingId: booking.id, userId, actorRole: role, createdAt: now },
    });

    // Condition 5: the counterparty is told at the moment of reveal — the
    // first customer call is that moment. The provider reading afterwards is
    // not a new reveal and tells nobody anything new.
    if (role === 'customer' && started === null) {
      try {
        await this.deps.notifier.notify({
          event: 'contact_revealed',
          bookingId: booking.id,
          userId: booking.providerProfile.user.id,
        });
      } catch (error) {
        this.deps.log.warn({ err: error, bookingId: booking.id }, 'reveal notification failed');
      }
    }

    return {
      bookingId: booking.id,
      customer: { name: customer.fullName, phone: customer.phoneE164 },
      provider: {
        name: booking.providerProfile.businessName ?? provider.fullName,
        phone: provider.phoneE164,
        verificationTier: booking.providerProfile.verificationTier,
      },
      revealedAt: (started ?? logged).createdAt.toISOString(),
      expiresAt: revealExpiresAt(booking)?.toISOString() ?? null,
    };
  }
}
