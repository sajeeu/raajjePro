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

/**
 * Stores the event (dedup on the SNS message id — SNS retries), moves the
 * message's status forward, and suppresses recipients of a permanent bounce or
 * a complaint. Transient bounces change status only. A terminal status never
 * moves backwards on a late `Send`.
 *
 * The status transition and the suppression insert are each a single
 * conditional/upsert SQL statement rather than a JS-side read-then-write:
 * two events for the same provider message id (or two events suppressing the
 * same address) can arrive concurrently, and a snapshot read taken before the
 * transaction — or a check-then-insert inside it — races. Postgres serialises
 * concurrent statements against the same row/index entry, so folding the
 * check into the statement's WHERE/ON CONFLICT clause is what actually
 * prevents the regression, not the surrounding `$transaction`.
 */
export async function applySesEvent(
  prisma: PrismaClient,
  clock: Clock,
  snsMessageId: string,
  event: SesEvent,
  rawPayload: unknown,
): Promise<'applied' | 'duplicate'> {
  const now = clock();
  // Read only to learn the message's id (to link the event row) and whether
  // one exists at all — its `status` is never used for the regression
  // decision below, which is made atomically inside the transaction instead.
  const message = await prisma.emailMessage.findUnique({
    where: { providerMessageId: event.mail.messageId },
  });
  const occurredAt =
    parseDate(event.bounce?.timestamp ?? event.complaint?.timestamp ?? event.mail.timestamp) ?? now;

  return prisma.$transaction(async (tx) => {
    // Prisma's query API has no atomic "insert, or skip and tell me which"
    // operation — SNS retries the same message, so the dedup check and the
    // insert have to be one statement, not a find-then-create that a
    // concurrent retry can slip between.
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
      // Conditional UPDATE, not a JS read-then-write: the WHERE clause re-checks
      // the row's *current* status at statement time, so two concurrent events
      // for the same message serialise on Postgres's row lock instead of both
      // having read the same stale non-terminal status and racing to write.
      const updated = await tx.$executeRaw`
        UPDATE email_message
        SET status = ${next}::email_message_status, last_event_at = ${occurredAt}
        WHERE id = ${message.id}::uuid
          AND NOT (
            status = ANY (ARRAY['delivered', 'bounced', 'complained', 'rejected']::email_message_status[])
            AND ${next}::email_message_status <> ALL (ARRAY['delivered', 'bounced', 'complained', 'rejected']::email_message_status[])
          )`;
      if (updated === 0) {
        // The guard above was a no-op (a terminal status held against a later
        // non-terminal event) — the event was still seen, so record that.
        await tx.$executeRaw`
          UPDATE email_message SET last_event_at = ${occurredAt} WHERE id = ${message.id}::uuid`;
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
      // Atomic insert-or-skip against the partial unique index on the active
      // address — a JS check-then-insert races when two different SNS
      // messages suppress the same address concurrently: both can see "no
      // active row" and both attempt to insert, and the loser's unique
      // violation would abort this whole transaction, losing the
      // email_event row it was meant to commit alongside.
      await tx.$executeRaw`
        INSERT INTO email_suppression (id, address, reason, source_event_id, created_at)
        VALUES (gen_random_uuid(), ${s.address}, ${s.reason}::suppression_reason, ${eventRow.id}::uuid, ${now})
        ON CONFLICT (address) WHERE lifted_at IS NULL DO NOTHING`;
    }
    return 'applied';
  });
}

function parseDate(value: string | undefined): Date | null {
  if (value === undefined) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}
