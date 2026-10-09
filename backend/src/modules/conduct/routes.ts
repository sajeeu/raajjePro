import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requestMeta } from '../admin-auth/routes.js';
import { requireAuth, userOf } from '../auth/guards.js';
import { bookingParams, conductExclusionBody, evidenceQuery } from './schema.js';

/**
 * §1f's provider-facing evidence and the appeal outcome. The metrics
 * themselves reach clients through §Phase 5's existing shapes —
 * `GET /v1/providers/me` for the provider, the public provider read for
 * everyone else — which is where the display rules live.
 */
export function registerConductRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Who may call: a signed-in provider, for their own bookings only — the
  // profile is resolved from the principal, never from the request.
  r.get(
    '/v1/providers/me/conduct/bookings',
    { schema: { querystring: evidenceQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const page = await app.conduct.evidenceFor(userOf(request).id, request.query);
      return reply.send(
        ok({ computedAt: page.computedAt, bookings: page.items }, { nextCursor: page.nextCursor }),
      );
    },
  );

  // Who may call: an enrolled, MFA-verified admin — the outcome of a §Phase 22
  // appeal. Audit-logged with the reason, and reversible below.
  r.post(
    '/v1/admin/bookings/:id/exclude-from-conduct',
    {
      schema: { params: bookingParams, body: conductExclusionBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'booking.conduct-exclude' } },
    },
    async (request, reply) => {
      const meta = requestMeta(request);
      return reply.send(
        ok(
          await app.conduct.setExcluded(
            request.params.id,
            principalOf(request).id,
            request.body.reason,
            true,
            { requestId: meta.requestId, ipAddress: meta.ip },
          ),
        ),
      );
    },
  );

  // Who may call: an enrolled, MFA-verified admin.
  r.post(
    '/v1/admin/bookings/:id/include-in-conduct',
    {
      schema: { params: bookingParams, body: conductExclusionBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'booking.conduct-include' } },
    },
    async (request, reply) => {
      const meta = requestMeta(request);
      return reply.send(
        ok(
          await app.conduct.setExcluded(
            request.params.id,
            principalOf(request).id,
            request.body.reason,
            false,
            { requestId: meta.requestId, ipAddress: meta.ip },
          ),
        ),
      );
    },
  );
}
