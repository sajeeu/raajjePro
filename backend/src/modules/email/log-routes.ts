import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { ok } from '../../core/envelope.js';
import { requireAdmin } from '../admin-auth/guards.js';

const query = z.object({
  recipientUserId: z.uuid().optional(),
  address: z.string().trim().min(3).max(320).optional(),
  channel: z.enum(['otp', 'notification', 'marketing']).optional(),
  status: z
    .enum([
      'queued',
      'sent',
      'failed',
      'suppressed',
      'delivered',
      'bounced',
      'complained',
      'rejected',
      'delivery_delayed',
    ])
    .optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  cursor: z.uuid().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

/**
 * The delivery-log lookup §Phase 3c budgets and Phase 10b surfaces. Shaped
 * deliberately like `/v1/admin/audit-log`: same guard, same cursor pagination,
 * same envelope — a second admin read surface should not invent a second set
 * of conventions.
 */
export function registerEmailLogRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  // Who may call: the enrolled, MFA-verified admin, and nobody else. Rows
  // carry recipient email addresses, so the READ is the sensitive operation.
  r.get(
    '/v1/admin/message-log',
    { schema: { querystring: query }, preHandler: requireAdmin },
    async (request, reply) => {
      const q = request.query;
      const { items, nextCursor } = await app.emailLog.query({
        ...(q.recipientUserId === undefined ? {} : { recipientUserId: q.recipientUserId }),
        ...(q.address === undefined ? {} : { address: q.address }),
        ...(q.channel === undefined ? {} : { channel: q.channel }),
        ...(q.status === undefined ? {} : { status: q.status }),
        ...(q.from === undefined ? {} : { from: q.from }),
        ...(q.to === undefined ? {} : { to: q.to }),
        ...(q.cursor === undefined ? {} : { cursor: q.cursor }),
        limit: q.limit,
      });
      return reply.send(ok(items, { nextCursor }));
    },
  );
}
