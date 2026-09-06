import type { Clock } from '../../core/clock.js';
import { ValidationError } from '../../core/errors.js';
import type { AuditLogEntry, PrismaClient } from '../../generated/prisma/client.js';
import type { AuditEntryInput, AuditQuery, Db } from './types.js';

/**
 * The audit log (plan §Phase 2): append-only, every admin action with actor,
 * time, action, target and reason; queryable by date, admin and action.
 * `record` takes the caller's transaction so the entry commits with the action.
 */
export class AuditService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  async record(db: Db, entry: AuditEntryInput): Promise<AuditLogEntry> {
    if (entry.reason.trim().length === 0) {
      throw new ValidationError(
        [{ path: 'reason', message: 'A reason is required' }],
        'A reason is required',
      );
    }
    return db.auditLogEntry.create({
      data: {
        actorType: entry.actorType,
        actorId: entry.actorId ?? null,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        reason: entry.reason.trim(),
        // Omit the key entirely rather than set it to `undefined` — Prisma's
        // generated input types disallow an explicit `undefined` value under
        // `exactOptionalPropertyTypes`, so a present-but-undefined key does
        // not type-check even though it would behave the same at runtime.
        ...(entry.metadata === undefined ? {} : { metadata: entry.metadata }),
        requestId: entry.requestId ?? null,
        ipAddress: entry.ipAddress ?? null,
        createdAt: this.clock(),
      },
    });
  }

  async query(q: AuditQuery): Promise<{ items: AuditLogEntry[]; nextCursor: string | null }> {
    const cursor = q.cursor === undefined ? null : decodeCursor(q.cursor);
    const items = await this.prisma.auditLogEntry.findMany({
      where: {
        AND: [
          q.actorId === undefined ? {} : { actorId: q.actorId },
          q.action === undefined ? {} : { action: q.action },
          q.from === undefined ? {} : { createdAt: { gte: q.from } },
          q.to === undefined ? {} : { createdAt: { lte: q.to } },
          cursor === null
            ? {}
            : {
                OR: [
                  { createdAt: { lt: cursor.createdAt } },
                  { createdAt: cursor.createdAt, id: { lt: cursor.id } },
                ],
              },
        ],
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: q.limit + 1,
    });
    const page = items.slice(0, q.limit);
    const last = page[page.length - 1];
    const nextCursor = items.length > q.limit && last !== undefined ? encodeCursor(last) : null;
    return { items: page, nextCursor };
  }
}

function encodeCursor(entry: { createdAt: Date; id: string }): string {
  return Buffer.from(`${entry.createdAt.toISOString()}|${entry.id}`).toString('base64url');
}

function decodeCursor(cursor: string): { createdAt: Date; id: string } {
  const [iso, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  const createdAt = new Date(iso ?? '');
  if (id === undefined || Number.isNaN(createdAt.getTime())) {
    throw new ValidationError([{ path: 'cursor', message: 'Malformed cursor' }]);
  }
  return { createdAt, id };
}
