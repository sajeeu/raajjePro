import { z } from 'zod';

import type { Clock } from '../../../core/clock.js';
import type { EmailMessageStatus, PrismaClient } from '../../../generated/prisma/client.js';
import { normaliseAddress } from '../service.js';

const recipient = z.object({ emailAddress: z.string() });

/** The SES event-publishing JSON, the parts we act on. Unknown fields pass through into `payload`. */
export const sesEventSchema = z.object({
  eventType: z.string(),
  mail: z.object({
    messageId: z.string(),
    timestamp: z.string().optional(),
    destination: z.array(z.string()).optional(),
  }),
  bounce: z
    .object({
      bounceType: z.string(),
      bounceSubType: z.string().optional(),
      bouncedRecipients: z.array(recipient),
      timestamp: z.string().optional(),
    })
    .optional(),
  complaint: z
    .object({ complainedRecipients: z.array(recipient), timestamp: z.string().optional() })
    .optional(),
});
export type SesEvent = z.infer<typeof sesEventSchema>;

const STATUS_FOR_EVENT: Record<string, EmailMessageStatus | undefined> = {
  Send: 'sent',
  Delivery: 'delivered',
  Bounce: 'bounced',
  Complaint: 'complained',
  Reject: 'rejected',
  DeliveryDelay: 'delivery_delayed',
  'Rendering Failure': 'failed',
  RenderingFailure: 'failed',
};

const TERMINAL: ReadonlySet<EmailMessageStatus> = new Set([
  'delivered',
  'bounced',
  'complained',
  'rejected',
]);

/**
 * Stores the event (dedup on the SNS message id — SNS retries), moves the
 * message's status forward, and suppresses recipients of a permanent bounce or
 * a complaint. Transient bounces change status only. A terminal status never
 * moves backwards on a late `Send`.
 */
export async function applySesEvent(
  prisma: PrismaClient,
  clock: Clock,
  snsMessageId: string,
  event: SesEvent,
  rawPayload: unknown,
): Promise<'applied' | 'duplicate'> {
  const now = clock();
  const message = await prisma.emailMessage.findUnique({
    where: { providerMessageId: event.mail.messageId },
  });
  const occurredAt =
    parseDate(event.bounce?.timestamp ?? event.complaint?.timestamp ?? event.mail.timestamp) ?? now;

  return prisma.$transaction(async (tx) => {
    const inserted = message?.id
      ? await tx.$queryRaw<{ id: string }[]>`
          INSERT INTO email_event (id, sns_message_id, message_id, provider_message_id, event_type, occurred_at, payload, received_at)
          VALUES (gen_random_uuid(), ${snsMessageId}, ${message.id}::uuid, ${event.mail.messageId}, ${event.eventType}, ${occurredAt}, ${JSON.stringify(rawPayload)}::jsonb, ${now})
          ON CONFLICT (sns_message_id) DO NOTHING
          RETURNING id`
      : await tx.$queryRaw<{ id: string }[]>`
          INSERT INTO email_event (id, sns_message_id, message_id, provider_message_id, event_type, occurred_at, payload, received_at)
          VALUES (gen_random_uuid(), ${snsMessageId}, NULL::uuid, ${event.mail.messageId}, ${event.eventType}, ${occurredAt}, ${JSON.stringify(rawPayload)}::jsonb, ${now})
          ON CONFLICT (sns_message_id) DO NOTHING
          RETURNING id`;
    const eventRow = inserted[0];
    if (eventRow === undefined) return 'duplicate';

    const next = STATUS_FOR_EVENT[event.eventType];
    if (message !== null && next !== undefined) {
      const regress = TERMINAL.has(message.status) && !TERMINAL.has(next);
      if (!regress) {
        await tx.emailMessage.update({
          where: { id: message.id },
          data: { status: next, lastEventAt: occurredAt },
        });
      } else {
        await tx.emailMessage.update({
          where: { id: message.id },
          data: { lastEventAt: occurredAt },
        });
      }
    }

    const toSuppress: { address: string; reason: 'hard_bounce' | 'complaint' }[] = [];
    if (event.eventType === 'Bounce' && event.bounce?.bounceType === 'Permanent') {
      for (const r of event.bounce.bouncedRecipients) {
        toSuppress.push({ address: normaliseAddress(r.emailAddress), reason: 'hard_bounce' });
      }
    }
    if (event.eventType === 'Complaint' && event.complaint !== undefined) {
      for (const r of event.complaint.complainedRecipients) {
        toSuppress.push({ address: normaliseAddress(r.emailAddress), reason: 'complaint' });
      }
    }
    for (const s of toSuppress) {
      const active = await tx.emailSuppression.findFirst({
        where: { address: s.address, liftedAt: null },
      });
      if (active === null) {
        await tx.emailSuppression.create({
          data: {
            address: s.address,
            reason: s.reason,
            sourceEventId: eventRow.id,
            createdAt: now,
          },
        });
      }
    }
    return 'applied';
  });
}

function parseDate(value: string | undefined): Date | null {
  if (value === undefined) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}
