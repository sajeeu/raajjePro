import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { EmailService } from '../src/modules/email/service.js';
import type { SnsMessage, SnsMessageValidator } from '../src/modules/email/sns/validator.js';
import type { EmailTransport } from '../src/modules/email/types.js';
import { buildTestApp, databaseUrl, TrustingValidator } from './helpers/app.js';

const TOPIC = 'arn:aws:sns:ap-south-1:123456789012:raajjepro-ses-events';

class RefusingValidator implements SnsMessageValidator {
  validate(): Promise<SnsMessage> {
    return Promise.reject(new Error('The message signature is invalid.'));
  }
}

const transport: EmailTransport = {
  deliver() {
    return Promise.resolve({ providerMessageId: `ses-${randomUUID()}` });
  },
};

function sns(
  type: SnsMessage['Type'],
  message: unknown,
  overrides: Partial<SnsMessage> = {},
): string {
  return JSON.stringify({
    Type: type,
    MessageId: randomUUID(),
    TopicArn: TOPIC,
    Message: typeof message === 'string' ? message : JSON.stringify(message),
    Timestamp: new Date().toISOString(),
    ...overrides,
  });
}

function sesEvent(
  eventType: string,
  providerMessageId: string,
  to: string,
  extra: Record<string, unknown> = {},
) {
  return {
    eventType,
    mail: {
      messageId: providerMessageId,
      timestamp: new Date().toISOString(),
      destination: [to],
      source: 'no-reply@raajjepro.test',
    },
    ...extra,
  };
}

describe.skipIf(databaseUrl === undefined)('POST /v1/webhooks/ses-events', () => {
  let ctx: Awaited<ReturnType<typeof buildTestApp>>;
  let email: EmailService;

  beforeAll(async () => {
    ctx = await buildTestApp({
      deps: { emailTransport: transport, snsValidator: new TrustingValidator() },
    });
    email = new EmailService(
      ctx.prisma,
      transport,
      {
        transport: 'ses',
        fromAddress: 'no-reply@raajjepro.test',
        region: 'ap-south-1',
        configurationSets: { otp: 'a', notification: 'b', marketing: 'c' },
        eventsTopicArn: TOPIC,
      },
      () => new Date(),
    );
  });
  afterAll(async () => {
    await ctx.app.close();
    await ctx.prisma.$disconnect();
  });

  const post = (body: string, headers: Record<string, string> = {}) =>
    ctx.app.inject({
      method: 'POST',
      url: '/v1/webhooks/ses-events',
      payload: body,
      headers: { 'content-type': 'text/plain; charset=UTF-8', ...headers },
    });

  async function sent(to: string) {
    const outcome = await email.send({ channel: 'notification', to, subject: 's', text: 't' });
    const row = await ctx.prisma.emailMessage.findUniqueOrThrow({
      where: { id: outcome.messageId },
    });
    return { id: row.id, providerMessageId: row.providerMessageId ?? '' };
  }

  it('rejects a message from an unexpected topic', async () => {
    const res = await post(
      sns('Notification', sesEvent('Delivery', 'x', 'a@b.test'), {
        TopicArn: 'arn:aws:sns:ap-south-1:1:other',
      }),
    );
    expect(res.statusCode).toBe(403);
    expect(res.json<{ error: { code: string } }>().error.code).toBe('UNEXPECTED_SNS_TOPIC');
  });

  it('rejects an invalid signature with 400 and stores nothing', async () => {
    const refusing = await buildTestApp({
      deps: { emailTransport: transport, snsValidator: new RefusingValidator() },
    });
    try {
      const before = await ctx.prisma.emailEvent.count();
      const res = await refusing.app.inject({
        method: 'POST',
        url: '/v1/webhooks/ses-events',
        payload: sns('Notification', {}),
        headers: { 'content-type': 'text/plain' },
      });
      expect(res.statusCode).toBe(400);
      expect(res.json<{ error: { code: string } }>().error.code).toBe('INVALID_SNS_SIGNATURE');
      expect(await ctx.prisma.emailEvent.count()).toBe(before);
    } finally {
      await refusing.app.close();
      await refusing.prisma.$disconnect();
    }
  });

  it('Delivery marks the message delivered; a duplicate SNS id is a no-op', async () => {
    const to = `d-${randomUUID()}@example.test`;
    const m = await sent(to);
    const body = sns(
      'Notification',
      sesEvent('Delivery', m.providerMessageId, to, {
        delivery: { timestamp: new Date().toISOString(), recipients: [to] },
      }),
    );
    expect((await post(body)).statusCode).toBe(200);
    expect((await post(body)).statusCode).toBe(200);
    const row = await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } });
    expect(row.status).toBe('delivered');
    expect(await ctx.prisma.emailEvent.count({ where: { messageId: m.id } })).toBe(1);
  });

  it('a permanent bounce suppresses every bounced recipient; a transient one does not', async () => {
    const to = `hb-${randomUUID()}@example.test`;
    const m = await sent(to);
    await post(
      sns(
        'Notification',
        sesEvent('Bounce', m.providerMessageId, to, {
          bounce: {
            bounceType: 'Permanent',
            bounceSubType: 'General',
            bouncedRecipients: [{ emailAddress: to.toUpperCase() }],
            timestamp: new Date().toISOString(),
          },
        }),
      ),
    );
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe(
      'bounced',
    );
    const suppression = await ctx.prisma.emailSuppression.findFirst({
      where: { address: to, liftedAt: null },
    });
    expect(suppression?.reason).toBe('hard_bounce');
    expect(suppression?.sourceEventId).not.toBeNull();

    const soft = `sb-${randomUUID()}@example.test`;
    const m2 = await sent(soft);
    await post(
      sns(
        'Notification',
        sesEvent('Bounce', m2.providerMessageId, soft, {
          bounce: {
            bounceType: 'Transient',
            bounceSubType: 'MailboxFull',
            bouncedRecipients: [{ emailAddress: soft }],
            timestamp: new Date().toISOString(),
          },
        }),
      ),
    );
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m2.id } })).status).toBe(
      'bounced',
    );
    expect(await ctx.prisma.emailSuppression.count({ where: { address: soft } })).toBe(0);

    // And the suppression is honoured by the sender.
    expect((await email.send({ channel: 'otp', to, subject: 's', text: 't' })).status).toBe(
      'suppressed',
    );
  });

  it('a complaint suppresses and a second complaint does not duplicate the row', async () => {
    const to = `c-${randomUUID()}@example.test`;
    const m = await sent(to);
    const body = () =>
      sns(
        'Notification',
        sesEvent('Complaint', m.providerMessageId, to, {
          complaint: {
            complainedRecipients: [{ emailAddress: to }],
            timestamp: new Date().toISOString(),
          },
        }),
      );
    await post(body());
    await post(body());
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe(
      'complained',
    );
    expect(
      await ctx.prisma.emailSuppression.count({ where: { address: to, liftedAt: null } }),
    ).toBe(1);
  });

  it('an out-of-order Send never moves a terminal status back', async () => {
    const to = `o-${randomUUID()}@example.test`;
    const m = await sent(to);
    await post(
      sns(
        'Notification',
        sesEvent('Delivery', m.providerMessageId, to, { delivery: { recipients: [to] } }),
      ),
    );
    await post(sns('Notification', sesEvent('Send', m.providerMessageId, to)));
    expect((await ctx.prisma.emailMessage.findUniqueOrThrow({ where: { id: m.id } })).status).toBe(
      'delivered',
    );
  });

  it('an event for an unknown provider id is stored with no message link', async () => {
    const body = sns(
      'Notification',
      sesEvent('Reject', `unknown-${randomUUID()}`, 'nobody@example.test', {
        reject: { reason: 'Bad content' },
      }),
    );
    expect((await post(body)).statusCode).toBe(200);
    const parsed = JSON.parse(body) as { MessageId: string };
    const event = await ctx.prisma.emailEvent.findUniqueOrThrow({
      where: { snsMessageId: parsed.MessageId },
    });
    expect(event.messageId).toBeNull();
  });

  it('confirms a subscription only for the expected topic, via the SNS host', async () => {
    const calls: string[] = [];
    const confirming = await buildTestApp({
      deps: {
        emailTransport: transport,
        snsValidator: new TrustingValidator(),
        confirmSubscription: (url: string) => {
          calls.push(url);
          return Promise.resolve();
        },
      },
    });
    try {
      const good = sns('SubscriptionConfirmation', 'You have chosen to subscribe', {
        SubscribeURL: 'https://sns.ap-south-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc',
      });
      expect(
        (
          await confirming.app.inject({
            method: 'POST',
            url: '/v1/webhooks/ses-events',
            payload: good,
            headers: { 'content-type': 'text/plain' },
          })
        ).statusCode,
      ).toBe(200);
      const evil = sns('SubscriptionConfirmation', 'x', {
        SubscribeURL: 'https://attacker.example/confirm',
      });
      expect(
        (
          await confirming.app.inject({
            method: 'POST',
            url: '/v1/webhooks/ses-events',
            payload: evil,
            headers: { 'content-type': 'text/plain' },
          })
        ).statusCode,
      ).toBe(400);
      expect(calls).toEqual([
        'https://sns.ap-south-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc',
      ]);
    } finally {
      await confirming.app.close();
      await confirming.prisma.$disconnect();
    }
  });
});
