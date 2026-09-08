import type { NotificationKind, PushPlatform } from '../../generated/prisma/enums.js';

/**
 * What goes on the wire to FCM or APNs. Deliberately narrow: a title, a body,
 * and a small map of string data the app routes on. §Phase 3c's content rule
 * is written about the fallback email, but the same restraint applies here —
 * a lock-screen notification is at least as public as an inbox, so it carries
 * no amounts, no phone numbers and no links either (see `content.ts`).
 */
export interface PushMessage {
  title: string;
  body: string;
  /** Values are strings because both vendors flatten the data payload to strings. */
  data: Record<string, string>;
}

/** One device's registration, as the sender needs it. */
export interface PushTarget {
  deviceTokenId: string;
  token: string;
  platform: PushPlatform;
}

export interface PushDeliveryOutcome {
  deviceTokenId: string;
  status: 'sent' | 'failed';
  providerMessageId: string | null;
  /** The error class name only — a vendor message can echo the token. */
  failureReason: string | null;
  /** The vendor says this token is dead: the app was uninstalled or its data cleared. */
  unregistered: boolean;
}

/**
 * The vendor boundary, one call per device. FCM and APNs are two vendors
 * behind one interface — `platform` selects which, so a caller never branches
 * on it. Nothing outside this directory constructs a transport.
 */
export interface PushTransport {
  deliver(message: PushMessage, target: PushTarget): Promise<{ providerMessageId: string }>;
}

/**
 * A transport signals a dead token by throwing this rather than by returning
 * a status, so the ordinary path stays a plain value. `sender.ts` is the only
 * thing that catches it, and it revokes the registration.
 */
export class UnregisteredTokenError extends Error {
  constructor(message = 'The vendor no longer recognises this device token') {
    super(message);
    this.name = 'UnregisteredTokenError';
  }
}

/**
 * The single send interface every later module calls (§Phase 3c: "A single
 * `PushSender` abstraction — the send interface every later module (17, 19)
 * calls, not one each"). It fans out to every live device the user has and
 * reports what each one did; it does not decide whether an email should also
 * go out — that is `NotificationDispatcher`'s job.
 */
export interface PushSender {
  send(
    userId: string,
    dispatchId: string,
    message: PushMessage,
  ): Promise<{ attempted: number; sent: number; outcomes: PushDeliveryOutcome[] }>;
}

/** The context every notification's copy is built from. Kind decides the wording. */
export interface NotificationContext {
  kind: NotificationKind;
  /** Category name as the customer sees it, e.g. "AC Repair". Never an id. */
  bookingType: string;
  /**
   * First name only. The full name is not needed to recognise a job, and this
   * text goes to an inbox and a lock screen.
   */
  customerFirstName: string;
  /**
   * Already rendered by the caller under the Round 30 rule — `Dh. Meedhoo`
   * when the name is ambiguous, `Kulhudhuffushi` when it is not. This module
   * never looks an island up and never re-formats one.
   */
  islandName: string;
}
