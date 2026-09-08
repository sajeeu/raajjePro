import type { EmailMessage, PrismaClient } from '../../generated/prisma/client.js';
import type { EmailChannel, EmailMessageStatus } from '../../generated/prisma/enums.js';

export interface MessageLogQuery {
  recipientUserId?: string;
  address?: string;
  channel?: EmailChannel;
  status?: EmailMessageStatus;
  from?: Date;
  to?: Date;
  cursor?: string;
  limit: number;
}

export interface MessageLogRow {
  id: string;
  channel: EmailChannel;
  toAddress: string;
  recipientUserId: string | null;
  subject: string;
  status: EmailMessageStatus;
  configurationSet: string | null;
  providerMessageId: string | null;
  failureReason: string | null;
  createdAt: string;
  sentAt: string | null;
  lastEventAt: string | null;
  /** Every SNS event seen for this message, oldest first — the "what happened to it" half. */
  events: { eventType: string; occurredAt: string }[];
}

/**
 * "SES has no searchable activity UI, so the message log is ours to build…
 * Phase 10b needs to answer 'did this provider actually receive the emergency
 * alert?' in one lookup" (§Phase 3c).
 *
 * This is that lookup. Phase 2 built the store and the SNS event destination
 * that fills it; what was missing was a way to interrogate it, which is what
 * §Phase 3c budgets here and Phase 10b puts a screen on.
 *
 * `to_address` is a raw email address, so this is admin-only at the route and
 * the DTO exists so a future caller cannot accidentally widen it.
 */
export class EmailMessageLog {
  constructor(private readonly prisma: PrismaClient) {}

  async query(q: MessageLogQuery): Promise<{ items: MessageLogRow[]; nextCursor: string | null }> {
    const createdAt =
      q.from === undefined && q.to === undefined
        ? undefined
        : {
            ...(q.from === undefined ? {} : { gte: q.from }),
            ...(q.to === undefined ? {} : { lte: q.to }),
          };
    const rows = await this.prisma.emailMessage.findMany({
      where: {
        ...(q.recipientUserId === undefined ? {} : { recipientUserId: q.recipientUserId }),
        // Normalised the same way `EmailService` normalises before storing, so
        // a search typed in mixed case finds what was sent.
        ...(q.address === undefined ? {} : { toAddress: q.address.trim().toLowerCase() }),
        ...(q.channel === undefined ? {} : { channel: q.channel }),
        ...(q.status === undefined ? {} : { status: q.status }),
        ...(createdAt === undefined ? {} : { createdAt }),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: { events: { orderBy: { occurredAt: 'asc' } } },
      take: q.limit + 1,
      ...(q.cursor === undefined ? {} : { cursor: { id: q.cursor }, skip: 1 }),
    });
    const page = rows.slice(0, q.limit);
    const nextCursor = rows.length > q.limit ? (page.at(-1)?.id ?? null) : null;
    return { items: page.map(dto), nextCursor };
  }
}

function dto(
  row: EmailMessage & { events: { eventType: string; occurredAt: Date }[] },
): MessageLogRow {
  return {
    id: row.id,
    channel: row.channel,
    toAddress: row.toAddress,
    recipientUserId: row.recipientUserId,
    subject: row.subject,
    status: row.status,
    configurationSet: row.configurationSet,
    providerMessageId: row.providerMessageId,
    failureReason: row.failureReason,
    createdAt: row.createdAt.toISOString(),
    sentAt: row.sentAt?.toISOString() ?? null,
    lastEventAt: row.lastEventAt?.toISOString() ?? null,
    events: row.events.map((e) => ({
      eventType: e.eventType,
      occurredAt: e.occurredAt.toISOString(),
    })),
  };
}
