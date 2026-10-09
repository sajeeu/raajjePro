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
  /** §Phase 17.2: the provider proposed a time and a price. To the customer. */
  | 'quote_offered'
  /** §Phase 17.2: the customer approved it, and the job is on. To the provider. */
  | 'quote_approved'
  /** §Phase 17.2: the customer turned the quote down. To the provider. */
  | 'quote_declined'
  /**
   * §Phase 17.2, §1c step 4: the provider never quoted, on the category's
   * `quoteExpiryMinutes`. To the customer — `Request a Time.dc.html` promised
   * them "if he doesn't, the request expires and you owe nothing".
   */
  | 'quote_request_timed_out'
  /**
   * §Phase 17.2, §1c step 4: the approval window closed unanswered, on the
   * category's `quoteApprovalMinutes`. **To both parties** — the customer lost
   * the quote and the provider got their time back.
   */
  | 'quote_expired'
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
  | 'amendment_answered'
  // -- §Phase 17.3. The broadcast itself is not here: it goes through §Phase
  // 3c's dispatcher as `emergency_dispatch`, the kind that phase built for it.
  /** The customer chose this provider's offer. To that provider. */
  | 'emergency_offer_selected'
  /** §1c: "releases the unselected providers immediately". To each of them. */
  | 'emergency_offer_not_selected'
  /** Reject-all: "told the customer went elsewhere, without a reason". To each provider. */
  | 'emergency_offer_rejected'
  /** The customer's five minutes ran out. To each provider who offered. */
  | 'emergency_offer_expired'
  /** The overall window closed with no match. To the customer — "No one accepted in time". */
  | 'emergency_window_expired'
  /** The same close, to each provider whose open offer lapsed with it. */
  | 'emergency_request_closed'
  /** The customer marked "provider has not arrived". To that provider. */
  | 'emergency_provider_released'
  /** §1h: the chosen provider cancelled and the request went out again. To the customer. */
  | 'emergency_redispatched'
  /** §Phase 17 item 21's auto-cancel. **To both parties.** */
  | 'cancelled_verification_revoked'
  /**
   * §1c's fifth reveal condition: "the counterparty is notified at the
   * moment of reveal, in-app and by push". To the provider.
   */
  | 'contact_revealed'
  // -- §Phase 17.4 -----------------------------------------------------------
  /** §Phase 17 item 16: the customer moved an unanswered booking. To the provider. */
  | 'rescheduled'
  /** §1h: a callback was claimed against a completed job. To the provider. */
  | 'callback_claimed'
  /**
   * §1c: "that week is skipped, **both parties are notified explicitly**
   * ('this week was not confirmed; your series continues next week')". To
   * both. 🔧 The subject id is the **series**, as an emergency's is its
   * request — a week with no open slot has no booking to name.
   */
  | 'recurring_week_missed'
  /** The customer freed a week. To the provider. Subject: the series. */
  | 'recurring_week_skipped'
  /** §1c: three misses "pause the series and notify the customer to reconfirm". Subject: the series. */
  | 'recurring_series_paused'
  /** The customer ended the series; unanswered weeks are withdrawn. To the provider. Subject: the series. */
  | 'recurring_series_ended';

export interface BookingNotificationEvent {
  event: BookingNotification;
  /**
   * The subject: a booking id for booking events, the emergency request's id
   * for §Phase 17.3's pre-selection events, and the recurring series' id for
   * §Phase 17.4's series events. The event name says which.
   */
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
