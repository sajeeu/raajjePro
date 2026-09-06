import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import type { PrismaClient } from '../../generated/prisma/client.js';
import type { EmailSender, EmailTransport, OutboundEmail, SendOutcome } from './types.js';

export function normaliseAddress(address: string): string {
  return address.trim().toLowerCase();
}

/**
 * The one sender (plan §0.0 item 8, §4): looks the address up in the
 * suppression list FIRST — a suppressed address is logged as such and the
 * transport is never contacted — then logs the message, delivers through the
 * channel's configuration set, and records the provider id or the failure.
 */
export class EmailService implements EmailSender {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly transport: EmailTransport,
    private readonly config: Config['email'],
    private readonly clock: Clock,
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
    try {
      const { providerMessageId } = await this.transport.deliver(
        { ...email, to },
        this.config.fromAddress,
        configurationSet,
      );
      await this.prisma.emailMessage.update({
        where: { id: row.id },
        data: { status: 'sent', providerMessageId, sentAt: this.clock() },
      });
      return { messageId: row.id, status: 'sent' };
    } catch (error) {
      // The class name only: a vendor message can echo the recipient address.
      const failureReason = error instanceof Error ? error.name : 'UnknownError';
      await this.prisma.emailMessage.update({
        where: { id: row.id },
        data: { status: 'failed', failureReason },
      });
      return { messageId: row.id, status: 'failed' };
    }
  }
}
