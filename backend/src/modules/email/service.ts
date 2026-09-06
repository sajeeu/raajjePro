import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { EmailSender, EmailTransport, OutboundEmail, SendOutcome } from './types.js';

export function normaliseAddress(address: string): string {
  return address.trim().toLowerCase();
}

/**
 * The minimal logging surface `EmailService` needs — `app.log` (a Fastify
 * logger) satisfies this structurally, so the domain module does not need to
 * import Fastify's type just to accept it.
 */
export interface EmailServiceLogger {
  warn(obj: Record<string, unknown>, msg: string): void;
}

const noopLogger: EmailServiceLogger = { warn: () => undefined };

/**
 * The one sender (plan §0.0 item 8, §4): looks the address up in the
 * suppression list FIRST — a suppressed address is logged as such and the
 * transport is never contacted — then logs the message, delivers through the
 * channel's configuration set, and records the provider id or the failure.
 *
 * "Vendor rejected" and "our own delivery-log write failed" are kept
 * strictly apart: the transport call is the only thing that can produce a
 * genuine `failed` outcome. A `sent` outcome is final the instant the vendor
 * accepts — the bookkeeping update after it is best-effort, logged on
 * failure, and never turns an accepted send into a reported failure.
 */
export class EmailService implements EmailSender {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly transport: EmailTransport,
    private readonly config: Config['email'],
    private readonly clock: Clock,
    private readonly log: EmailServiceLogger = noopLogger,
  ) {}

  async send(email: OutboundEmail): Promise<SendOutcome> {
    const to = normaliseAddress(email.to);
    const configurationSet =
      this.config.transport === 'ses' ? this.config.configurationSets[email.channel] : null;
    const now = this.clock();

    const suppressed = await this.prisma.emailSuppression.findFirst({
      where: { address: to, liftedAt: null },
    });
    if (suppressed !== null) {
      const row = await this.prisma.emailMessage.create({
        data: {
          channel: email.channel,
          toAddress: to,
          ...(email.recipientUserId === undefined
            ? {}
            : { recipientUserId: email.recipientUserId }),
          subject: email.subject,
          status: 'suppressed',
          configurationSet,
          createdAt: now,
        },
      });
      return { messageId: row.id, status: 'suppressed' };
    }

    const row = await this.prisma.emailMessage.create({
      data: {
        channel: email.channel,
        toAddress: to,
        ...(email.recipientUserId === undefined ? {} : { recipientUserId: email.recipientUserId }),
        subject: email.subject,
        status: 'queued',
        configurationSet,
        createdAt: now,
      },
    });
    // The vendor call, isolated in its own try: a throw here — and only here
    // — means the vendor rejected the message. Nothing after this block can
    // turn into a `failed` outcome.
    let providerMessageId: string;
    try {
      ({ providerMessageId } = await this.transport.deliver(
        { ...email, to },
        this.config.fromAddress,
        configurationSet,
      ));
    } catch (error) {
      // The class name only: a vendor message can echo the recipient address.
      const failureReason = error instanceof Error ? error.name : 'UnknownError';
      try {
        await this.prisma.emailMessage.update({
          where: { id: row.id },
          data: { status: 'failed', failureReason },
        });
      } catch (updateError) {
        // send() must never reject and never leave the caller without an
        // outcome — the row is stuck at `queued`, but the caller still needs
        // to know the vendor refused it.
        this.log.warn(
          { err: updateError, messageId: row.id },
          'email failed to send, and recording the failure also failed',
        );
      }
      return { messageId: row.id, status: 'failed' };
    }

    // The vendor accepted — the message is sent, full stop. This update is
    // bookkeeping for the delivery log, not part of the outcome: if it
    // throws, the email still went out, so we log and still report `sent`
    // rather than tell the caller a send that happened did not.
    try {
      await this.prisma.emailMessage.update({
        where: { id: row.id },
        data: { status: 'sent', providerMessageId, sentAt: this.clock() },
      });
    } catch (error) {
      this.log.warn({ err: error, messageId: row.id }, 'email sent but delivery log update failed');
    }
    return { messageId: row.id, status: 'sent' };
  }
}
