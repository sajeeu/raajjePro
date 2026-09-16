/**
 * The booking events §1c requires somebody to be told about — as a seam,
 * because **§Phase 19 owns notification content and this phase does not**.
 *
 * This is the same shape §Phase 8a's `BillingNotifier` took, for the same
 * reason and with the same honesty: this phase **fires** the events at the
 * moments §1c specifies, and the default logs and drops. Nothing pretends a
 * customer was told.
 *
 * ## The one event that does not go through here
 *
 * The provider's **accept prompt** is dispatched through §Phase 3c's
 * `NotificationDispatcher` directly, because it already has a
 * `NotificationKind` of its own (`booking_accept_prompt`) and a
 * `NotificationContext` that is literally booking-shaped — booking type,
 * customer first name, island. §Phase 3c built that kind for this prompt.
 * Routing it through a seam instead would leave the one notification the
 * plan calls "load-bearing on real-time delivery" undelivered.
 *
 * Everything else below has no `NotificationKind` yet. Adding kinds here
 * would write §Phase 19's content in §Phase 17, which is the mistake §Phase
 * 8a's note already names.
 */

export type BookingNotification =
  /** §1c step 4: the 24-hour auto-decline. To the customer. */
  | 'accept_timed_out'
  /** The provider said no. To the customer. */
  | 'declined'
  /** §1c step 3: accepted, amount set, pay now. To the customer. */
  | 'accepted'
  /** §1c step 7: "I've Paid". To the provider. */
  | 'payment_claimed'
  /** Round 24: the customer took an unanswered claim back. To the provider. */
  | 'payment_claim_withdrawn'
  /** §1c step 8: "Provider confirmed receipt." To the customer. */
  | 'payment_confirmed'
  /** §1c step 9: seven days of silence. **To both parties.** */
  | 'payment_unresolved'
  /** Either party disputed. To the other one. */
  | 'disputed'
  /** An admin resolved a dispute or an unresolved claim. To both. */
  | 'dispute_resolved'
  /** The job is done. To the customer. */
  | 'completed'
  /** §1c step 10: "Did [Provider] complete this job?" To the customer. */
  | 'completion_prompt'
  /** The 3-day grace ran out and it auto-completed. To both. */
  | 'completed_unconfirmed'
  /** Somebody cancelled. To the other party. */
  | 'cancelled'
  /** §1h: an amendment was proposed. To the counterparty. */
  | 'amendment_proposed'
  /** §1h: the counterparty answered it. To the proposer. */
  | 'amendment_answered';

export interface BookingNotificationEvent {
  event: BookingNotification;
  bookingId: string;
  /** Who should be told. One call per recipient — "both parties" is two events. */
  userId: string;
}

export interface BookingNotifier {
  notify(event: BookingNotificationEvent): Promise<void>;
}

export interface BookingNotifierLogger {
  info(obj: Record<string, unknown>, msg: string): void;
}

/**
 * What ships until §Phase 19 registers a real one. It logs that the event
 * fired and that nothing delivered it — ids only, never a name or an address
 * (invariant: no PII in structured logs).
 *
 * `docs/deferred-verification.md` carries the row.
 */
export function loggingBookingNotifier(log: BookingNotifierLogger): BookingNotifier {
  return {
    notify(event: BookingNotificationEvent): Promise<void> {
      log.info(
        { event: event.event, bookingId: event.bookingId, userId: event.userId, delivered: false },
        'booking notification fired with no notifier registered (Phase 19)',
      );
      return Promise.resolve();
    },
  };
}
