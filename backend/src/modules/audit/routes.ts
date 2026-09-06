import type { FastifyInstance } from 'fastify';

import { ok } from '../../core/envelope.js';
import { requireAdmin } from '../admin-auth/guards.js';

/**
 * Placeholder: GET /v1/admin/audit-log exists so the guard chain has a real
 * route to protect. Task 11 fills in the actual query against AuditService.
 */
export function registerAuditRoutes(app: FastifyInstance): void {
  // Who may call: the enrolled, MFA-verified admin.
  app.get('/v1/admin/audit-log', { preHandler: requireAdmin }, async (_request, reply) =>
    reply.send(ok([], { nextCursor: null })),
  );
}
