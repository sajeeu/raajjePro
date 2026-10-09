import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import {
  addressBody,
  addressParams,
  standingInstructionsBody,
  timeWindowBody,
  timeWindowParams,
} from './schema.js';

/**
 * `Saved Preferences.dc.html`, under the signed-in user's own path.
 *
 * Every route is the caller's own preferences and nobody else's: the user id
 * comes from the principal, never from the request, and every write is scoped
 * to it in the repository's `where`. A stranger's address id answers **not
 * found**.
 *
 * Reads carry `requireAuth` alone. Writes add `requireActiveAccount`: §Phase 3
 * freezes an account with a deletion pending, and saving a new address for a
 * booking that account can no longer make is starting something new.
 */
export function registerSavedPreferencesRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const base = '/v1/users/me/saved-preferences';
  const writes = [requireAuth, requireActiveAccount];

  // Who may call: the signed-in user, for their own preferences.
  r.get(base, { preValidation: requireAuth }, async (request, reply) =>
    reply.send(ok(await app.savedPreferences.read(userOf(request).id))),
  );

  // Who may call: the signed-in, non-frozen user, for their own preferences.
  r.post(
    `${base}/addresses`,
    { schema: { body: addressBody }, preValidation: writes },
    async (request, reply) =>
      reply
        .code(201)
        .send(ok(await app.savedPreferences.addAddress(userOf(request).id, request.body))),
  );

  // Who may call: the owner of this address.
  r.patch(
    `${base}/addresses/:id`,
    { schema: { params: addressParams, body: addressBody }, preValidation: writes },
    async (request, reply) =>
      reply.send(
        ok(
          await app.savedPreferences.updateAddress(
            userOf(request).id,
            request.params.id,
            request.body,
          ),
        ),
      ),
  );

  // Who may call: the owner of this address. A soft delete (invariant 8).
  r.delete(
    `${base}/addresses/:id`,
    { schema: { params: addressParams }, preValidation: writes },
    async (request, reply) => {
      await app.savedPreferences.removeAddress(userOf(request).id, request.params.id);
      return reply.send(ok(await app.savedPreferences.read(userOf(request).id)));
    },
  );

  // Who may call: the signed-in, non-frozen user, for their own preferences.
  r.post(
    `${base}/time-windows`,
    { schema: { body: timeWindowBody }, preValidation: writes },
    async (request, reply) =>
      reply
        .code(201)
        .send(ok(await app.savedPreferences.addTimeWindow(userOf(request).id, request.body))),
  );

  // Who may call: the owner of this window. A soft delete (invariant 8).
  r.delete(
    `${base}/time-windows/:id`,
    { schema: { params: timeWindowParams }, preValidation: writes },
    async (request, reply) => {
      await app.savedPreferences.removeTimeWindow(userOf(request).id, request.params.id);
      return reply.send(ok(await app.savedPreferences.read(userOf(request).id)));
    },
  );

  // Who may call: the signed-in, non-frozen user. An empty string clears it.
  r.put(
    `${base}/standing-instructions`,
    { schema: { body: standingInstructionsBody }, preValidation: writes },
    async (request, reply) =>
      reply.send(
        ok(
          await app.savedPreferences.setStandingInstructions(userOf(request).id, request.body.text),
        ),
      ),
  );
}
