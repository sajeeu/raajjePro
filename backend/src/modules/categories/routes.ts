import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requestMeta } from '../admin-auth/routes.js';
import {
  categoryIdParams,
  createCategoryBody,
  deleteCategoryBody,
  listCategoriesQuery,
  updateCategoryBody,
} from './schema.js';

/**
 * The category catalogue (§Phase 4).
 *
 * One public read and three admin writes. The read is deliberately
 * unauthenticated: Explore is the first screen a guest sees and §0.2's "guests
 * browse freely" rule means the grid must render before anyone signs in.
 *
 * The writes sit behind Phase 2's real admin auth — `requireAdmin`, so an
 * enrolled, MFA-verified admin only — and each carries a reason that lands in
 * the audit log with the row it changed.
 */
export function registerCategoryRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Who may call: anyone, including a signed-out guest. Active categories in
  // sortOrder, carrying the whole seeded configuration — bookingMode and
  // emergencyCapable as §Phase 4 requires, and the lead time, quote windows,
  // callback flag, tier bar and preset lists the later phases read from here
  // rather than hardcoding.
  //
  // Paged: the catalogue is explicitly unlimited (§Phase 4), and
  // `backend/CLAUDE.md` makes pagination mandatory on anything unbounded. The
  // twelve fit in one page, so `meta.nextCursor` is null in practice — it is
  // there so a hundredth category cannot make this response unbounded.
  r.get(
    '/v1/categories',
    {
      schema: { querystring: listCategoriesQuery },
      config: {
        rateLimit: { max: 120, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const { items, nextCursor } = await app.categories.listPublic({
        ...(request.query.limit === undefined ? {} : { limit: request.query.limit }),
        ...(request.query.cursor === undefined ? {} : { cursor: request.query.cursor }),
      });
      return reply.send(ok(items, { nextCursor }));
    },
  );

  const adminPrefix = '/v1/admin/categories';

  // Who may call: an enrolled, MFA-verified admin. Includes deactivated rows,
  // which the public list by definition cannot show — without this a soft
  // delete would be unreachable and so irreversible (invariant 1d).
  r.get(adminPrefix, { preValidation: requireAdmin }, async (_request, reply) => {
    return reply.send(ok(await app.categories.listForAdmin()));
  });

  // Who may call: an enrolled, MFA-verified admin. Idempotency-keyed: this is
  // a creation POST, and a retried request must not leave two catalogues.
  r.post(
    adminPrefix,
    {
      schema: { body: createCategoryBody },
      preValidation: requireAdmin,
      config: { idempotency: { operation: 'category.create' } },
    },
    async (request, reply) => {
      const created = await app.categories.create(request.body, {
        adminId: principalOf(request).id,
        meta: requestMeta(request),
      });
      return reply.status(201).send(ok(created));
    },
  );

  // Who may call: an enrolled, MFA-verified admin. Partial; the coherence
  // rules are checked against the resulting row, in the service.
  r.patch(
    `${adminPrefix}/:id`,
    {
      schema: { params: categoryIdParams, body: updateCategoryBody },
      preValidation: requireAdmin,
    },
    async (request, reply) => {
      const updated = await app.categories.update(request.params.id, request.body, {
        adminId: principalOf(request).id,
        meta: requestMeta(request),
      });
      return reply.send(ok(updated));
    },
  );

  // Who may call: an enrolled, MFA-verified admin. Soft delete only — clears
  // `isActive` (invariant 8). Reason required, as on every admin write.
  r.delete(
    `${adminPrefix}/:id`,
    {
      schema: { params: categoryIdParams, body: deleteCategoryBody },
      preValidation: requireAdmin,
    },
    async (request, reply) => {
      const deactivated = await app.categories.deactivate(request.params.id, request.body.reason, {
        adminId: principalOf(request).id,
        meta: requestMeta(request),
      });
      return reply.send(ok(deactivated));
    },
  );
}
