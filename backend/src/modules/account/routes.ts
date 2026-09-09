import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { userDto } from '../auth/dto.js';
import { requireActiveAccount, requireAuth, userOf } from '../auth/guards.js';
import {
  changeEmailConfirmBody,
  changeEmailRequestBody,
  changePasswordBody,
  changePhoneBody,
  updateOwnUserBody,
} from './schema.js';

export function registerAccountRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/users/me';
  const perPrincipal = (max: number, timeWindow: string) => ({ rateLimit: { max, timeWindow } });

  // Who may call: the signed-in user, about themselves — §Phase 6's one call
  // for the Profile screen. A read, and authorization is still explicit: the
  // subject is always `userOf(request)`, so there is no client-supplied id to
  // check ownership of and no way to ask about anyone else.
  //
  // Deliberately NOT the same shape as `GET /v1/auth/me`. That one is the
  // auth surface every screen restores from; this one is the Profile screen's,
  // and `account/dto.ts` records why each field a reader would expect is
  // absent. Phases 14 and 17 extend it with their counts.
  r.get(`${prefix}/profile-summary`, { preValidation: requireAuth }, async (request, reply) => {
    return reply.send(ok(await app.account.profileSummary(userOf(request).id)));
  });

  // Who may call: the signed-in user, for their own account. `requireAuth`
  // *and* `requireActiveAccount`: a frozen account has a queued anonymisation
  // that will replace this very field with a placeholder, and §Phase 3's
  // freeze means it starts nothing new.
  //
  // No idempotency key — a PATCH, not a creation or a money-adjacent POST,
  // and a replay converges on the same row.
  r.patch(
    prefix,
    {
      schema: { body: updateOwnUserBody },
      preValidation: [requireAuth, requireActiveAccount],
      // Declared per endpoint, as backend/CLAUDE.md requires. Nothing here is
      // credential- or money-adjacent, so it sits above the change-password
      // tier and well below a read.
      config: perPrincipal(30, '1 minute'),
    },
    async (request, reply) => {
      const user = await app.account.updateOwnUser(
        userOf(request),
        request.body,
        requestMeta(request),
      );
      return reply.send(ok(userDto(user)));
    },
  );

  // Who may call: the signed-in user, for their own account. Password-guessing surface: 10/15 min per principal.
  // preValidation, not preHandler: it must reject a missing token before body
  // validation runs, so an unauthenticated call is 401 even with a bad body.
  r.post(
    `${prefix}/change-password`,
    {
      schema: { body: changePasswordBody },
      preValidation: requireAuth,
      config: perPrincipal(10, '15 minutes'),
    },
    async (request, reply) => {
      await app.account.changePassword(
        userOf(request),
        request.body.currentPassword,
        request.body.newPassword,
        requestMeta(request),
      );
      return reply.send(ok({ changed: true }));
    },
  );

  // Who may call: the signed-in user. Same tier — it takes the current password.
  r.post(
    `${prefix}/change-email/request`,
    {
      schema: { body: changeEmailRequestBody },
      preValidation: requireAuth,
      config: perPrincipal(10, '15 minutes'),
    },
    async (request, reply) => {
      const result = await app.account.requestEmailChange(
        userOf(request),
        request.body.newEmail,
        request.body.currentPassword,
        requestMeta(request),
      );
      return reply.send(
        ok({
          status: result.status,
          expiresAt: result.expiresAt.toISOString(),
          resendAvailableAt: result.resendAvailableAt.toISOString(),
        }),
      );
    },
  );

  // Who may call: the signed-in user. 10/5 min per principal, above the 5-attempt rule.
  r.post(
    `${prefix}/change-email/confirm`,
    {
      schema: { body: changeEmailConfirmBody },
      preValidation: requireAuth,
      config: perPrincipal(10, '5 minutes'),
    },
    async (request, reply) => {
      const user = await app.account.confirmEmailChange(
        userOf(request),
        request.body.code,
        requestMeta(request),
      );
      return reply.send(ok(userDto(user)));
    },
  );

  // Who may call: the signed-in user. The number is stored as given and never marked verified.
  r.patch(
    `${prefix}/phone`,
    { schema: { body: changePhoneBody }, preValidation: requireAuth },
    async (request, reply) => {
      const user = await app.account.changePhone(
        userOf(request),
        request.body,
        requestMeta(request),
      );
      return reply.send(ok(userDto(user)));
    },
  );

  // Who may call: the signed-in user, for their own data. Synchronous JSON as plan §Phase 3 specifies.
  r.get(
    `${prefix}/data-export`,
    { preValidation: requireAuth, config: perPrincipal(10, '1 hour') },
    async (request, reply) => {
      const data = await app.account.exportData(userOf(request).id);
      const date = app.deps.clock().toISOString().slice(0, 10);
      void reply.header(
        'content-disposition',
        `attachment; filename="raajjepro-export-${date}.json"`,
      );
      return reply.send(ok(data));
    },
  );

  // Who may call: the signed-in user. 202: queued, never refused. Tier 5/hour per principal.
  r.post(
    `${prefix}/deletion-request`,
    { preValidation: requireAuth, config: perPrincipal(5, '1 hour') },
    async (request, reply) => {
      const result = await app.account.requestDeletion(userOf(request), requestMeta(request));
      return reply.code(202).send(
        ok({
          status: result.status,
          deletionRequestedAt: result.deletionRequestedAt.toISOString(),
          deletionDeadlineAt: result.deletionDeadlineAt.toISOString(),
        }),
      );
    },
  );
}
