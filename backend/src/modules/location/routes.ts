import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import { listIslandsQuery, serviceAreaBody, serviceAreaParams } from './schema.js';

/**
 * Islands and provider service areas (§Phase 7).
 *
 * One public read and three provider-scoped routes. The service-area routes
 * live under `/v1/providers/me/` because the resource is the provider's, and
 * are registered from this module because the join table and its rules are —
 * the same split as any other module that owns a table another module's URL
 * space refers to.
 *
 * No response here carries a phone number, and none can: `IslandDto` has no
 * field for one and the provider shapes are not reachable from this file.
 */
export function registerLocationRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Who may call: anyone, including a signed-out guest. The island picker sits
  // in the header of Explore, which renders before anyone signs in, and §0.2's
  // "guests browse freely" rule means choosing where to browse cannot need an
  // account.
  //
  // Not paged, and deliberately so — §0.0 item 12 requires every match with no
  // cap and no "show more". See `LocationService.searchIslands` for why that
  // does not breach the pagination rule: the register is closed and this phase
  // adds no way to grow it.
  r.get(
    '/v1/islands',
    {
      schema: { querystring: listIslandsQuery },
      // Declared per endpoint, as backend/CLAUDE.md requires. Generous,
      // because this is search-as-you-type: a customer spelling out
      // "Kulhudhuffushi" sends a request per keystroke.
      config: {
        rateLimit: { max: 240, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const islands = await app.location.searchIslands(request.query.search);
      return reply.send(ok(islands));
    },
  );

  const serviceAreas = '/v1/providers/me/service-areas';

  // 🔧 **There is no GET on this collection, on purpose.** §Phase 7 names two
  // routes here — the POST and the DELETE — and a picker still has to read the
  // current set from somewhere, so the read went to the endpoint that already
  // exists: `GET /v1/providers/me` carries `serviceAreas`, additively. That is
  // one new field rather than one new URL, and both writes below return the
  // resulting list in full, so a client's view is exact after every change
  // without a second request.

  // Who may call: the signed-in user, for their own provider profile.
  // `requireActiveAccount` as well as `requireAuth`, matching
  // `PATCH /v1/providers/me`: an account with a deletion request pending is
  // frozen and starts nothing new (§Phase 3).
  //
  // No idempotency key — the unique `(providerProfileId, islandId)` pair makes
  // a retry converge on one row at the database, which is stronger than
  // replaying a stored response. See the service for the full note.
  r.post(
    serviceAreas,
    {
      schema: { body: serviceAreaBody },
      preValidation: [requireAuth, requireActiveAccount],
      config: {
        rateLimit: {
          max: 60,
          timeWindow: '1 minute',
          keyGenerator: (req) => `user:${req.principal?.id ?? req.ip}`,
        },
      },
    },
    async (request, reply) => {
      const areas = await app.location.addOwnServiceArea(userOf(request).id, request.body.islandId);
      return reply.send(ok(areas));
    },
  );

  // Who may call: the signed-in user, for their own provider profile. The
  // island is in the path rather than a body: a DELETE names the resource it
  // removes, and a multi-select toggling one chip off has exactly one to name.
  //
  // Invariant 8: this stamps `removedAt` on the join row. Nothing is deleted.
  r.delete(
    `${serviceAreas}/:islandId`,
    {
      schema: { params: serviceAreaParams },
      preValidation: [requireAuth, requireActiveAccount],
      config: {
        rateLimit: {
          max: 60,
          timeWindow: '1 minute',
          keyGenerator: (req) => `user:${req.principal?.id ?? req.ip}`,
        },
      },
    },
    async (request, reply) => {
      const areas = await app.location.removeOwnServiceArea(
        userOf(request).id,
        request.params.islandId,
      );
      return reply.send(ok(areas));
    },
  );
}
