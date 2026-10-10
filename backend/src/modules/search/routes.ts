import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { searchQuery } from './schema.js';

/**
 * §Phase 15. Search results and category results come from one endpoint. A
 * category screen is a search with `categoryId` set, so the two screens
 * cannot rank or filter differently.
 *
 * Open to a guest (§8: guests browse freely; §1b: discoverability is never
 * paywalled). The response is the same for every viewer.
 */
export function registerSearchRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Declared per endpoint (backend/CLAUDE.md) and keyed on the caller's
  // address. It matches the public reads it sits beside: a customer changing
  // sorts and filters sends many of these in a minute.
  const publicRead = { rateLimit: { max: 120, timeWindow: '1 minute' } };

  // Who may call: anyone, including a guest.
  r.get(
    '/v1/search/listings',
    { schema: { querystring: searchQuery }, config: publicRead },
    async (request, reply) => {
      const { page, nextCursor } = await app.listingSearch.search(request.query);
      return reply.send(ok(page, { nextCursor }));
    },
  );
}
