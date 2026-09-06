import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { ok } from '../../core/envelope.js';
import type { AuditLogEntry } from '../../generated/prisma/client.js';
import { requireAdmin } from '../admin-auth/guards.js';

const query = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  actorId: z.uuid().optional(),
  action: z.string().trim().min(1).max(100).optional(),
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

/** DTO: everything the viewer needs; the IP stays in the table. */
function dto(e: AuditLogEntry) {
  return {
    id: e.id,
    actorType: e.actorType,
    actorId: e.actorId,
    action: e.action,
    targetType: e.targetType,
    targetId: e.targetId,
    reason: e.reason,
    metadata: e.metadata,
    requestId: e.requestId,
    createdAt: e.createdAt.toISOString(),
  };
}

export function registerAuditRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  // Who may call: the enrolled, MFA-verified admin. Read access is guarded too — the log names targets.
  r.get(
    '/v1/admin/audit-log',
    { schema: { querystring: query }, preHandler: requireAdmin },
    async (request, reply) => {
      const q = request.query;
      const { items, nextCursor } = await app.audit.query({
        ...(q.from === undefined ? {} : { from: q.from }),
        ...(q.to === undefined ? {} : { to: q.to }),
        ...(q.actorId === undefined ? {} : { actorId: q.actorId }),
        ...(q.action === undefined ? {} : { action: q.action }),
        ...(q.cursor === undefined ? {} : { cursor: q.cursor }),
        limit: q.limit,
      });
      return reply.send(ok(items.map(dto), { nextCursor }));
    },
  );
}
