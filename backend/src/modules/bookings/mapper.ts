import type { BookingAmendment, BookingStatusEvent } from '../../generated/prisma/client.js';
import type { PaymentDetailsDto as ProviderPaymentDetailsDto } from '../providers/types.js';
import { bookingChatState } from './chat.js';
import type { BookingRow } from './repository.js';
import type {
  BookingAmendmentDto,
  BookingDto,
  BookingStatusEventDto,
  PaymentDetailsDto,
  ReplacementPrefillDto,
} from './types.js';

/**
 * Row → DTO, in one file.
 *
 * **This is the structural half of §1c's phone-number rule.** A mapper is
 * where a field gets forgotten about; here there is nothing to forget, because
 * `BOOKING_FIELDS` never selects a phone number and no shape in `types.ts` has
 * a slot for one. The only way to add one is to add it in three files at once,
 * which is the point.
 */

const iso = (d: Date | null): string | null => (d === null ? null : d.toISOString());

/**
 * §0.0 item 12's display convention, and the same expression §Phase 7's
 * `toIslandDto` uses: an ambiguous name is qualified in the Maldivian form,
 * an unambiguous one stands alone. Written here rather than imported because
 * the projection this module selects is four columns, not an `Island` row.
 */
export function islandDisplayName(island: {
  name: string;
  atollAbbr: string;
  nameAmbiguous: boolean;
}): string {
  return island.nameAmbiguous ? `${island.atollAbbr}. ${island.name}` : island.name;
}

export function toStatusEventDto(row: BookingStatusEvent): BookingStatusEventDto {
  return {
    id: row.id,
    fromStatus: row.fromStatus,
    toStatus: row.toStatus,
    actorRole: row.actorRole,
    transition: row.transition,
    at: row.createdAt.toISOString(),
  };
}

export function toAmendmentDto(row: BookingAmendment): BookingAmendmentDto {
  return {
    id: row.id,
    status: row.status,
    proposedByRole: row.proposedByRole,
    previousAmountLaari: row.previousAmountLaari,
    previousScheduledFor: iso(row.previousScheduledFor),
    previousScopeNote: row.previousScopeNote,
    proposedAmountLaari: row.proposedAmountLaari,
    proposedScheduledFor: iso(row.proposedScheduledFor),
    proposedScopeNote: row.proposedScopeNote,
    reason: row.reason,
    createdAt: row.createdAt.toISOString(),
    respondedAt: iso(row.respondedAt),
  };
}

/** §Phase 5's shape, narrowed to the three fields the payment step renders. */
export function toPaymentDetailsDto(source: ProviderPaymentDetailsDto): PaymentDetailsDto {
  return {
    bankName: source.bankName,
    accountName: source.bankAccountName,
    accountNumber: source.bankAccountNumber,
  };
}

/**
 * §1h's prefill. Built from the booking that died, so "service, date, time"
 * come back exactly as they were and the customer confirms rather than
 * re-enters.
 */
export function toReplacementPrefillDto(row: BookingRow): ReplacementPrefillDto {
  return {
    listingId: row.listingId,
    bookingMode: row.bookingMode,
    scheduledFor: iso(row.scheduledFor),
    jobNotes: row.jobNotes,
    islandId: row.islandId,
    addressDetail: row.addressDetail,
    occasion: row.occasion,
  };
}

export interface BookingDtoExtras {
  statusHistory?: BookingStatusEvent[];
  paymentDetails?: ProviderPaymentDetailsDto;
  /** True only where §1h's rule applies — see `service.ts`'s `replacementFor`. */
  includeReplacement?: boolean;
}

/**
 * @param now the caller's clock. 🔧 **Required as of §Phase 17.2**, and
 *   required rather than defaulted because the one field it feeds — Round 27's
 *   `chatState` lock, seven days after completion — is a rule, and a mapper
 *   that reached for `new Date()` would be the one place in this codebase
 *   where a rule read a clock nobody injected.
 */
export function toBookingDto(
  row: BookingRow,
  now: Date,
  extras: BookingDtoExtras = {},
): BookingDto {
  const dto: BookingDto = {
    id: row.id,
    reference: row.reference,
    listingId: row.listingId,
    listingName: row.listing.name,
    categoryName: row.listing.category?.name ?? null,
    bookingMode: row.bookingMode,
    status: row.status,

    customer: { userId: row.customer.id, name: row.customer.fullName },
    provider: {
      userId: row.providerProfile.user.id,
      // The business name where there is one — it is what the listing card
      // shows and what a customer recognises. The person's own name is the
      // fallback, and it is a name, not a way to reach them.
      name: row.providerProfile.businessName ?? row.providerProfile.user.fullName,
    },

    agreedAmountLaari: row.agreedAmountLaari,
    amountKind: row.amountKind,
    quotedAmountLaari: row.quotedAmountLaari,
    finalAmountLaari: row.finalAmountLaari,

    scheduledFor: iso(row.scheduledFor),
    timeSlotId: row.timeSlotId,
    durationMinutes:
      row.timeSlot === null
        ? null
        : Math.round((row.timeSlot.endsAt.getTime() - row.timeSlot.startsAt.getTime()) / 60_000),

    preferredWindowText: row.preferredWindowText,
    preferredWindowFrom: iso(row.preferredWindowFrom),
    preferredWindowTo: iso(row.preferredWindowTo),
    occasion: row.occasion,

    quoteDueAt: iso(row.quoteDueAt),
    quoteOfferedAt: iso(row.quoteOfferedAt),
    quoteExpiresAt: iso(row.quoteExpiresAt),
    quoteNote: row.quoteNote,
    // Derived, and from the caller's own clock — §Phase 18 compares the same
    // rule against its own. `chat.ts` is the single place the rule is written.
    chatState: bookingChatState(row, now),
    jobNotes: row.jobNotes,
    islandId: row.islandId,
    islandDisplayName: row.island === null ? null : islandDisplayName(row.island),
    addressDetail: row.addressDetail,

    paymentClaimedAt: iso(row.paymentClaimedAt),
    paymentClaimWithdrawnAt: iso(row.paymentClaimWithdrawnAt),
    paymentAttestedAt: iso(row.paymentAttestedAt),
    completedAt: iso(row.completedAt),
    completedVia: row.completedVia,
    completionPromptedAt: iso(row.completionPromptedAt),
    cancelledAt: iso(row.cancelledAt),
    cancelledByRole: row.cancelledByRole,
    cancellationReason: row.cancellationReason,
    disputedAt: iso(row.disputedAt),
    disputeOutcome: row.disputeOutcome,

    createdAt: row.createdAt.toISOString(),

    amendments: row.amendments.map(toAmendmentDto),
  };

  if (extras.statusHistory !== undefined) {
    dto.statusHistory = extras.statusHistory.map(toStatusEventDto);
  }
  if (extras.paymentDetails !== undefined) {
    dto.paymentDetails = toPaymentDetailsDto(extras.paymentDetails);
  }
  if (extras.includeReplacement === true) {
    dto.replacement = toReplacementPrefillDto(row);
  }
  return dto;
}
