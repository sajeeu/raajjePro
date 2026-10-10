import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { ok } from '../../core/envelope.js';

const idParams = z.object({ id: z.uuid() });

/**
 * §Phase 12's two public reads.
 *
 * **Neither response ever contains contact or payment details.** The DTOs in
 * `types.ts` and `providers/types.ts` have no field that could hold one, so
 * this holds for every caller and every state rather than by a check per
 * handler.
 *
 * Both are open to a guest — and a signed-in caller is recognised, not
 * required: the principal hook runs on every request, so a valid session is
 * simply present, and a missing or expired one reads as a guest.
 */
export function registerPublicListingRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Declared per endpoint (backend/CLAUDE.md). Keyed on the caller's address;
  // generous because a feed of cards opens many of these in a minute.
  const publicRead = { rateLimit: { max: 120, timeWindow: '1 minute' } };

  // Who may call: anyone, including a guest.
  r.get(
    '/v1/listings/:id/public',
    { schema: { params: idParams }, config: publicRead },
    async (request, reply) => {
      const principal = request.principal;
      const viewerUserId = principal?.kind === 'user' ? principal.id : null;
      return reply.send(ok(await app.publicListings.readPublic(request.params.id, viewerUserId)));
    },
  );

  // Who may call: anyone, including a guest. Not found unless §1a shows the provider.
  r.get(
    '/v1/providers/:id/public-summary',
    { schema: { params: idParams }, config: publicRead },
    async (request, reply) =>
      reply.send(ok(await app.publicListings.readProviderSummary(request.params.id))),
  );

  // 🔧 §Phase 13 — the provider's public profile. Who may call: anyone,
  // including a guest. Not found unless §1a shows the provider, even by
  // direct id; the response is identical whoever asks.
  r.get(
    '/v1/providers/:id/public',
    { schema: { params: idParams }, config: publicRead },
    async (request, reply) =>
      reply.send(ok(await app.publicListings.readProviderProfile(request.params.id))),
  );
}
