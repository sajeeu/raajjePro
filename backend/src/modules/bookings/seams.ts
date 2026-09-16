import type { Clock } from '../../core/clock.js';
import type { DeletionBlocker } from '../account/anonymise.js';
import type { SubscriptionBookingSource } from '../subscriptions/bookings.js';
import type { BookingStatus } from '../../generated/prisma/enums.js';
import type { BookingRepository } from './repository.js';
import { COMMITTED_STATUSES, isTerminal } from './transitions.js';
import { BOOKING_STATUSES } from './transitions.js';

/**
 * The two interfaces earlier phases built against, implemented.
 *
 * ## Why these live on the repository rather than on `BookingService`
 *
 * Because of the order things are constructed in. `SubscriptionService` needs
 * a booking source, and `BookingService` needs `subscriptions.onBookingConfirmed`
 * for §Phase 8a's trial trigger — wiring both through the service would be a
 * cycle. Both questions are pure reads with no rules in them, so they are
 * answered from the repository, `SubscriptionService` is constructed with one
 * of them, and `BookingService` is constructed after it. The dependency runs
 * one way and nothing is lazily assigned.
 *
 * ## Why neither interface changed
 *
 * This is the fifth time this codebase has built a rule one phase before its
 * data source and had the interface survive intact — `DeletionBlocker`
 * (§Phase 3), `PublishedListingSource` (§Phase 5, closed by §Phase 8),
 * `ProviderEntitlementReader` (§Phase 8, closed by §Phase 8a) and
 * `SubscriptionBookingSource` (§Phase 8a, closed here). No caller in
 * `modules/account/` or `modules/subscriptions/` changed.
 */

/**
 * Non-terminal in §1c's sense.
 *
 * **`payment_unresolved` and `disputed` are in here**, and that is the whole
 * point of the list: both read like endings and §1c says an admin still owes
 * somebody an answer on each. A deletion that completed while a dispute was
 * open would anonymise one side of the evidence.
 */
export const NON_TERMINAL_STATUSES: BookingStatus[] = BOOKING_STATUSES.filter(
  (s) => !isTerminal(s),
);

/**
 * §Phase 3's blocker, filled. "A request is accepted immediately, the account
 * frozen, and anonymisation executes automatically **once non-terminal
 * bookings terminate**, with a hard 30-day backstop."
 *
 * Both sides of the relationship count: a provider with an accepted job owes
 * somebody a visit, and a customer with one is owed it.
 */
export function bookingDeletionBlocker(repo: BookingRepository): DeletionBlocker {
  return {
    hasOpenBookings: (userId) => repo.hasOpenBookings(userId, NON_TERMINAL_STATUSES),
  };
}

/** §Phase 8a's source, filled. Both questions are one indexed query each. */
export function bookingSubscriptionSource(
  repo: BookingRepository,
  clock: Clock,
): SubscriptionBookingSource {
  return {
    hasAnyBooking: (providerProfileId) => repo.hasAnyBookingForProvider(providerProfileId),
    listingIdsWithCommittedBooking: (listingIds) =>
      repo.listingIdsWithCommittedBooking(listingIds, [...COMMITTED_STATUSES], clock()),
  };
}
