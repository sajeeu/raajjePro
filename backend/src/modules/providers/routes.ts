import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import { updateOwnProviderBody } from './schema.js';

/**
 * The provider profile surface (§Phase 5).
 *
 * Two routes, both scoped to the caller's own profile. §Phase 5 is a backend
 * phase and the *public* provider surface belongs to its consumers — Phase 12's
 * listing page and Phase 13's public profile, both of which check §1a through
 * `app.providers.visibility` and map through `toPublicProviderDto`. This phase
 * deliberately adds no public provider route: it would be Phase 13's, and
 * Phase 13's own Done-when covers the not-found state for a drafts-only
 * provider that this phase has no listings to produce.
 *
 * Neither response carries a phone number. §Phase 5 stores exactly one, on the
 * user row, and §1c gives exactly one endpoint in the system permission to
 * return it to another user — the emergency reveal. The provider's own read of
 * their own number stays on Phase 3's `GET /v1/users/me`.
 */
export function registerProviderRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();

  // Who may call: any signed-in user, for their own provider profile.
  //
  // **A read never creates it.** An account with no provider profile gets a
  // 404 — `isProvider` on `userDto` is `providerProfile !== null` and
  // §Phase 6's role switcher routes on it, so a read that created a row would
  // turn a customer into a provider permanently (invariant 8: nothing is ever
  // hard-deleted). §1a's creation moments are Phase 6a's onboarding and the
  // first `POST /v1/listings`; the PATCH below is the third, because sending
  // business details is acting as a provider. Opening a screen is not.
  //
  // Email verification is deliberately NOT required: §1c's stricter guard
  // gates booking, enquiry and messaging, and §1a says dashboard access is
  // never gated — a provider with only drafts reaches their workspace
  // normally. Phase 6a is where an unverified email blocks Continue.
  //
  // A caller can tell "no profile yet" from a typo'd URL: this read answers
  // `PROVIDER_PROFILE_NOT_FOUND` where a bad path answers `NOT_FOUND`
  // (`NotFoundError` took an optional code on 2026-09-09).
  //
  // Phase 6 and 6a should still route on `isProvider` from the auth surface,
  // which costs no request and is reliable because a read no longer creates
  // the profile — the code is what makes a 404 legible when one is reached
  // anyway, not an invitation to probe for one.
  r.get('/v1/providers/me', { preValidation: requireAuth }, async (request, reply) => {
    return reply.send(ok(await app.providers.readOwn(userOf(request).id)));
  });

  // Who may call: the signed-in user, for their own provider profile.
  // `requireActiveAccount` as well as `requireAuth`: an account with a
  // deletion request pending is frozen and starts nothing new (§Phase 3), and
  // rewriting the bank details a queued anonymisation is about to clear is
  // exactly that.
  //
  // No idempotency key: this is a PATCH, not a creation or money-adjacent
  // POST, and a replayed partial update converges on the same row.
  r.patch(
    '/v1/providers/me',
    {
      schema: { body: updateOwnProviderBody },
      preValidation: [requireAuth, requireActiveAccount],
      // Declared per endpoint, as backend/CLAUDE.md requires. Generous enough
      // for §Phase 6a's step-by-step saves, tight enough that rewriting the
      // destination account is not something to try in a loop.
      config: {
        rateLimit: {
          max: 30,
          timeWindow: '1 minute',
          keyGenerator: (req) => `user:${req.principal?.id ?? req.ip}`,
        },
      },
    },
    async (request, reply) => {
      return reply.send(
        ok(await app.providers.updateOwn(userOf(request).id, request.body, requestMeta(request))),
      );
    },
  );
}
