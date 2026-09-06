import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { Prisma, PrismaClient } from '../src/generated/prisma/client.js';
import type { EmailServiceLogger } from '../src/modules/email/service.js';
import { EmailService } from '../src/modules/email/service.js';
import type { EmailTransport, OutboundEmail } from '../src/modules/email/types.js';
import { databaseUrl } from './helpers/app.js';

class RecordingTransport implements EmailTransport {
  calls: { email: OutboundEmail; configurationSet: string | null }[] = [];
  fail = false;
  deliver(email: OutboundEmail, _from: string, configurationSet: string | null) {
    if (this.fail) return Promise.reject(new Error(`SES said no to ${email.to}`));
    this.calls.push({ email, configurationSet });
    return Promise.resolve({ providerMessageId: `ses-${randomUUID()}` });
  }
}

class RecordingLogger implements EmailServiceLogger {
  calls: { obj: Record<string, unknown>; msg: string }[] = [];
  warn(obj: Record<string, unknown>, msg: string): void {
    this.calls.push({ obj, msg });
  }
}

/**
 * A real `PrismaClient` whose `emailMessage.update` throws whenever `shouldThrow`
 * says so of the write it was about to make, and otherwise behaves exactly
 * like the wrapped client — used to simulate the delivery-log write itself
 * failing, independent of whatever the transport did.
 */
function withThrowingEmailMessageUpdate(
  prisma: PrismaClient,
  shouldThrow: (args: Prisma.EmailMessageUpdateArgs) => boolean,
): PrismaClient {
  const emailMessage = new Proxy(prisma.emailMessage, {
    get(target, prop, receiver) {
      if (prop === 'update') {
        return (args: Prisma.EmailMessageUpdateArgs) => {
          if (shouldThrow(args)) return Promise.reject(new Error('db unavailable'));
          return target.update(args);
        };
      }
      return Reflect.get(target, prop, receiver) as unknown;
    },
  });
  return new Proxy(prisma, {
    get(target, prop, receiver) {
      if (prop === 'emailMessage') return emailMessage;
      return Reflect.get(target, prop, receiver) as unknown;
    },
  });
}

const sesConfig = {
  transport: 'ses' as const,
  fromAddress: 'no-reply@raajjepro.test',
  region: 'ap-south-1',
  configurationSets: { otp: 'cs-otp', notification: 'cs-notif', marketing: 'cs-mkt' },
  eventsTopicArn: 'arn:aws:sns:ap-south-1:1:t',
};

describe.skipIf(databaseUrl === undefined)('EmailService', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('sends through the transport with the channel configuration set and logs the message', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `User-${randomUUID()}@Example.test`;
    const outcome = await service.send({
      channel: 'otp',
      to,
      subject: 'Your code',
      text: '123456',
    });
    expect(outcome.status).toBe('sent');
    expect(transport.calls[0]?.configurationSet).toBe('cs-otp');
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('sent');
    expect(row.toAddress).toBe(to.toLowerCase());
    expect(row.providerMessageId).toMatch(/^ses-/);
    expect(row.configurationSet).toBe('cs-otp');
  });

  it('honours the suppression list BEFORE calling the transport', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `bounced-${randomUUID()}@example.test`;
    await prisma.emailSuppression.create({ data: { address: to, reason: 'hard_bounce' } });
    const outcome = await service.send({
      channel: 'notification',
      to: to.toUpperCase(),
      subject: 's',
      text: 't',
    });
    expect(outcome.status).toBe('suppressed');
    expect(transport.calls).toHaveLength(0);
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('suppressed');
    expect(row.providerMessageId).toBeNull();
  });

  it('a lifted suppression no longer blocks', async () => {
    const transport = new RecordingTransport();
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `lifted-${randomUUID()}@example.test`;
    await prisma.emailSuppression.create({
      data: { address: to, reason: 'complaint', liftedAt: new Date(), liftReason: 'user asked' },
    });
    expect((await service.send({ channel: 'marketing', to, subject: 's', text: 't' })).status).toBe(
      'sent',
    );
    expect(transport.calls[0]?.configurationSet).toBe('cs-mkt');
  });

  it('records a transport failure without the recipient address in the reason', async () => {
    const transport = new RecordingTransport();
    transport.fail = true;
    const service = new EmailService(prisma, transport, sesConfig, () => new Date());
    const to = `fail-${randomUUID()}@example.test`;
    const outcome = await service.send({ channel: 'otp', to, subject: 's', text: 't' });
    expect(outcome.status).toBe('failed');
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('failed');
    expect(row.failureReason).toBe('Error');
    expect(row.failureReason).not.toContain(to);
  });

  it('still reports sent when the vendor accepted but the delivery-log update afterwards fails', async () => {
    const transport = new RecordingTransport();
    const logger = new RecordingLogger();
    const flakyPrisma = withThrowingEmailMessageUpdate(
      prisma,
      (args) => args.data.status === 'sent',
    );
    const service = new EmailService(flakyPrisma, transport, sesConfig, () => new Date(), logger);
    const to = `sent-log-fails-${randomUUID()}@example.test`;

    const outcome = await service.send({ channel: 'otp', to, subject: 's', text: 't' });

    expect(outcome.status).toBe('sent');
    expect(transport.calls).toHaveLength(1);
    expect(logger.calls).toHaveLength(1);
    expect(logger.calls[0]?.msg).toContain('delivery log update failed');
    // The known gap: the log write failed, so the row is stuck at `queued`
    // even though the vendor sent the message — send() still told the truth.
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('queued');
  });

  it('still resolves failed when the failure-log update also fails', async () => {
    const transport = new RecordingTransport();
    transport.fail = true;
    const logger = new RecordingLogger();
    const flakyPrisma = withThrowingEmailMessageUpdate(
      prisma,
      (args) => args.data.status === 'failed',
    );
    const service = new EmailService(flakyPrisma, transport, sesConfig, () => new Date(), logger);
    const to = `fail-log-fails-${randomUUID()}@example.test`;

    const outcome = await service.send({ channel: 'otp', to, subject: 's', text: 't' });

    expect(outcome.status).toBe('failed');
    expect(logger.calls).toHaveLength(1);
    expect(logger.calls[0]?.msg).toContain('recording the failure also failed');
    const row = await prisma.emailMessage.findUniqueOrThrow({ where: { id: outcome.messageId } });
    expect(row.status).toBe('queued');
  });
});
