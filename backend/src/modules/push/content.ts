import type { OutboundEmail } from '../email/types.js';
import type { NotificationContext, PushMessage } from './types.js';

/**
 * Notification copy, in one place.
 *
 * §Phase 3c fixes the fallback email's contents exactly: "booking type,
 * customer first name, job location island, and an instruction to open the
 * app. **No links** — do not train providers to tap links in messages that
 * claim a job is waiting. No amounts, no phone numbers."
 *
 * Two consequences are worth stating, because both are easy to undo later:
 *
 *  - The no-links rule is anti-phishing, not minimalism. A provider who has
 *    learned to tap a link in a "you have a job" email will tap the next one
 *    too, and that one will not be from us. The mail says so in as many words.
 *  - The same restraint is applied to the push payload. The plan writes the
 *    rule about email, but a push body is rendered on a locked screen, which
 *    is no more private than an inbox.
 *
 * `assertContentRules` below is the enforcement, and it runs on every built
 * message rather than only in tests — a later phase adding a kind here gets
 * the check whether or not it remembers to write one.
 */

/** No `http://`, `https://`, bare `www.`, or a mailto:. */
const LINKISH = /\b(?:https?:\/\/|www\.|mailto:)/i;
/** MVR, laari, or a currency symbol — the amount rule. */
const AMOUNTISH = /\b(?:MVR|Rf\.?|laari)\b|[$€£]/i;
/**
 * A phone-shaped run: 6+ digits, tolerating spaces and dashes, optionally
 * with a dial code. Deliberately blunt — this guards copy WE write, so a
 * false positive is a bug in the copy, not a blocked user message. (The
 * silent-and-logged detector §1c describes is a different mechanism, in
 * Phase 18, and never touches user content.)
 */
const PHONEISH = /(?:\+\d[\d\s-]{5,}|\b\d[\d\s-]{5,}\d\b)/;

export class NotificationContentError extends Error {
  constructor(rule: string, where: string) {
    super(`Notification copy broke the §Phase 3c content rule (${rule}) in ${where}`);
    this.name = 'NotificationContentError';
  }
}

export function assertContentRules(text: string, where: string): void {
  if (LINKISH.test(text)) throw new NotificationContentError('no links', where);
  if (AMOUNTISH.test(text)) throw new NotificationContentError('no amounts', where);
  if (PHONEISH.test(text)) throw new NotificationContentError('no phone numbers', where);
}

const NO_LINK_LINE =
  'Open the RaajjePro app to see it. We never put links in these emails — always open the app yourself.';

/** The subject and body of the email that goes when push cannot be relied on. */
export function fallbackEmail(
  toAddress: string,
  recipientUserId: string,
  context: NotificationContext,
): OutboundEmail {
  const { bookingType, customerFirstName, islandName } = context;
  const emergency = context.kind === 'emergency_dispatch';

  const subject = emergency
    ? `Emergency ${bookingType} request — open the app now`
    : `New ${bookingType} booking request — open the app`;

  const opening = emergency
    ? `An emergency ${bookingType} request is open and providers are being asked now.`
    : `A ${bookingType} booking request is waiting for you.`;

  const closing = emergency ? `${NO_LINK_LINE} Emergency requests close quickly.` : NO_LINK_LINE;

  const text = [
    opening,
    '',
    `From: ${customerFirstName}`,
    `Island: ${islandName}`,
    '',
    closing,
  ].join('\n');

  assertContentRules(subject, 'fallback email subject');
  assertContentRules(text, 'fallback email body');

  // The notification configuration set, never the OTP one: a complaint spike
  // on booking mail must not degrade the reputation OTP depends on (§Phase 3c,
  // §Notifications — three independently killable channels).
  return { channel: 'notification', to: toAddress, subject, text, recipientUserId };
}

/** The push payload for the same notification. `data.dispatchId` is what the app acks with. */
export function pushMessage(dispatchId: string, context: NotificationContext): PushMessage {
  const { bookingType, customerFirstName, islandName } = context;
  const emergency = context.kind === 'emergency_dispatch';

  const title = emergency ? `Emergency ${bookingType}` : `New ${bookingType} request`;
  const body = `${customerFirstName} · ${islandName}. Open the app to respond.`;

  assertContentRules(title, 'push title');
  assertContentRules(body, 'push body');

  return { title, body, data: { dispatchId, kind: context.kind } };
}
