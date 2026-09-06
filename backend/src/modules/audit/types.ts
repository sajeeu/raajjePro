import type { Prisma, PrismaClient } from '../../generated/prisma/client.js';

export type Db = PrismaClient | Prisma.TransactionClient;

export interface AuditEntryInput {
  actorType: 'admin' | 'system';
  actorId?: string | null;
  /** Dotted, stable, e.g. `admin.session.revoked`. */
  action: string;
  targetType: string;
  targetId: string;
  /** Required by the plan: every admin action records why. */
  reason: string;
  /** IDs, enums and counts only — never an email, phone, or document content. */
  metadata?: Record<string, string | number | boolean | null>;
  requestId?: string | null;
  ipAddress?: string | null;
}

export interface AuditQuery {
  from?: Date;
  to?: Date;
  actorId?: string;
  action?: string;
  cursor?: string | undefined;
  limit: number;
}
