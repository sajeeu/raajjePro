import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { principalOf, requireAdmin } from '../admin-auth/guards.js';
import { requestMeta } from '../admin-auth/routes.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import {
  bookingParams,
  categoryParams,
  listingParams,
  moderateReviewBody,
  postReviewBody,
  providerParams,
  reviewListQuery,
  reviewParams,
} from './schema.js';

/**
 * §Phase 11's route table.
 *
 * No response here carries `authorId`, a phone number, an email or an
 * editorial label — the DTOs in `types.ts` have no field for any of them.
 */
export function registerReviewRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Per user: a review is one per booking, so anything faster than this is
  // not a person rating jobs. §Phase 22 owns the anti-spam rules proper.
  const reviewRate = {
    rateLimit: {
      max: 20,
      timeWindow: '1 minute',
      keyGenerator: (req: { principal?: { id: string }; ip: string }) =>
        `user:${req.principal?.id ?? req.ip}`,
    },
  };

  // Who may call: the booking's customer, signed in and not frozen — a frozen
  // account "starts nothing new" (§Phase 3), and a public review is new. The
  // booking already required a verified email to exist. Idempotency key
  // required: it is a creation POST, and a replayed tap must return the one
  // review rather than a conflict.
  r.post(
    '/v1/bookings/:id/review',
    {
      schema: { params: bookingParams, body: postReviewBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: { idempotency: { operation: 'review.create' }, ...reviewRate },
    },
    async (request, reply) =>
      reply
        .code(201)
        .send(ok(await app.reviews.post(userOf(request).id, request.params.id, request.body))),
  );

  // Who may call: either party to the booking.
  r.get(
    '/v1/bookings/:id/review',
    { schema: { params: bookingParams }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.reviews.readForBooking(userOf(request).id, request.params.id))),
  );

  // Who may call: anyone. The category's fixed tag set is reference data.
  r.get(
    '/v1/categories/:id/review-tags',
    { schema: { params: categoryParams } },
    async (request, reply) => reply.send(ok(await app.reviews.tagsForCategory(request.params.id))),
  );

  // Who may call: anyone, for a publicly visible listing.
  r.get(
    '/v1/listings/:id/reviews',
    { schema: { params: listingParams, querystring: reviewListQuery } },
    async (request, reply) => {
      const page = await app.reviews.listForListing(request.params.id, request.query);
      return reply.send(ok(page.items, { nextCursor: page.nextCursor }));
    },
  );

  // Who may call: anyone, for a publicly visible listing.
  r.get(
    '/v1/listings/:id/review-summary',
    { schema: { params: listingParams } },
    async (request, reply) => reply.send(ok(await app.reviews.listingSummary(request.params.id))),
  );

  // Who may call: anyone, for a provider §1a makes visible.
  r.get(
    '/v1/providers/:id/reviews',
    { schema: { params: providerParams, querystring: reviewListQuery } },
    async (request, reply) => {
      const page = await app.reviews.listForProvider(request.params.id, request.query);
      return reply.send(ok(page.items, { nextCursor: page.nextCursor }));
    },
  );

  // Who may call: anyone, for a provider §1a makes visible.
  r.get(
    '/v1/providers/:id/review-summary',
    { schema: { params: providerParams } },
    async (request, reply) => reply.send(ok(await app.reviews.providerSummary(request.params.id))),
  );

  // Who may call: an enrolled, MFA-verified admin. Reversible (invariant 1d)
  // and audit-logged with the reason; §Phase 22's queue is what calls it.
  r.post(
    '/v1/admin/reviews/:id/hide',
    {
      schema: { params: reviewParams, body: moderateReviewBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'review.hide' } },
    },
    async (request, reply) => {
      const meta = requestMeta(request);
      return reply.send(
        ok(
          await app.reviews.hide(request.params.id, principalOf(request).id, request.body.reason, {
            requestId: meta.requestId,
            ipAddress: meta.ip,
          }),
        ),
      );
    },
  );

  // Who may call: an enrolled, MFA-verified admin.
  r.post(
    '/v1/admin/reviews/:id/unhide',
    {
      schema: { params: reviewParams, body: moderateReviewBody },
      preHandler: requireAdmin,
      config: { idempotency: { operation: 'review.unhide' } },
    },
    async (request, reply) => {
      const meta = requestMeta(request);
      return reply.send(
        ok(
          await app.reviews.unhide(
            request.params.id,
            principalOf(request).id,
            request.body.reason,
            {
              requestId: meta.requestId,
              ipAddress: meta.ip,
            },
          ),
        ),
      );
    },
  );
}
