import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { userDto } from '../auth/dto.js';
import { requireAuth, userOf } from '../auth/guards.js';
import {
  changeEmailConfirmBody,
  changeEmailRequestBody,
  changePasswordBody,
  changePhoneBody,
} from './schema.js';

export function registerAccountRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/users/me';
  const perPrincipal = (max: number, timeWindow: string) => ({ rateLimit: { max, timeWindow } });

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
}
