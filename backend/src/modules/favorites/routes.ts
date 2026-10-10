import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import {
  favoriteStatusQuery,
  listFavoritesQuery,
  listingParams,
  providerParams,
} from './schema.js';

/**
 * §Phase 14 — saved services and saved providers, under the caller's own path.
 *
 * §1c's access table puts "Save/favourite" at **Registered**, enforced by
 * `requireAuth`: saving needs an account and nothing more — not a verified
 * email, which is the bar for booking and messaging. Writes add
 * `requireActiveAccount`, as Saved Preferences' do: an account with a
 * deletion pending starts nothing new.
 *
 * Save is `PUT` and unsave is `DELETE`, each idempotent by its verb: the
 * client's heart is optimistic, and a retry after a lost response must land
 * on the same state rather than toggle it back.
 */
export function registerFavoriteRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/users/me/favorites';
  const writes = [requireAuth, requireActiveAccount];
  // Declared per endpoint (backend/CLAUDE.md), keyed on the principal. A heart
  // is tapped far more often than a form is sent; this bounds a script, not a
  // person.
  const heart = { rateLimit: { max: 60, timeWindow: '1 minute' } };

  // Who may call: the signed-in, non-frozen user, saving for themselves.
  r.put(
    `${base}/listings/:listingId`,
    { schema: { params: listingParams }, preValidation: writes, config: heart },
    async (request, reply) =>
      reply.send(ok(await app.favorites.saveListing(userOf(request).id, request.params.listingId))),
  );

  // Who may call: the signed-in, non-frozen user, for their own favourite.
  r.delete(
    `${base}/listings/:listingId`,
    { schema: { params: listingParams }, preValidation: writes, config: heart },
    async (request, reply) =>
      reply.send(
        ok(await app.favorites.unsaveListing(userOf(request).id, request.params.listingId)),
      ),
  );

  // Who may call: the signed-in, non-frozen user, saving for themselves.
  r.put(
    `${base}/providers/:providerId`,
    { schema: { params: providerParams }, preValidation: writes, config: heart },
    async (request, reply) =>
      reply.send(
        ok(await app.favorites.saveProvider(userOf(request).id, request.params.providerId)),
      ),
  );

  // Who may call: the signed-in, non-frozen user, for their own favourite.
  r.delete(
    `${base}/providers/:providerId`,
    { schema: { params: providerParams }, preValidation: writes, config: heart },
    async (request, reply) =>
      reply.send(
        ok(await app.favorites.unsaveProvider(userOf(request).id, request.params.providerId)),
      ),
  );

  // Who may call: the signed-in user, about their own favourites only.
  r.get(
    `${base}/status`,
    { schema: { querystring: favoriteStatusQuery }, preValidation: requireAuth },
    async (request, reply) =>
      reply.send(ok(await app.favorites.status(userOf(request).id, request.query))),
  );

  // Who may call: the signed-in user, for their own saved services.
  r.get(
    `${base}/listings`,
    { schema: { querystring: listFavoritesQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const { items, nextCursor } = await app.favorites.listListings(userOf(request).id, {
        limit: request.query.limit,
        cursor: request.query.cursor ?? null,
      });
      return reply.send(ok(items, { nextCursor }));
    },
  );

  // Who may call: the signed-in user, for their own saved providers.
  r.get(
    `${base}/providers`,
    { schema: { querystring: listFavoritesQuery }, preValidation: requireAuth },
    async (request, reply) => {
      const { items, nextCursor } = await app.favorites.listProviders(userOf(request).id, {
        limit: request.query.limit,
        cursor: request.query.cursor ?? null,
      });
      return reply.send(ok(items, { nextCursor }));
    },
  );
}
