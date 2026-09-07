import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { BusinessRuleError } from '../../core/errors.js';
import { requestMeta } from '../admin-auth/routes.js';
import { sessionDto, userDto } from './dto.js';
import { requireAuth, userOf } from './guards.js';
import { otpCodeBody, refreshBody, sessionIdParams } from './schema.js';
import type { TokenPair } from './service.js';

export function tokensDto(t: TokenPair) {
  return {
    accessToken: t.accessToken,
    accessTokenExpiresAt: t.accessTokenExpiresAt.toISOString(),
    refreshToken: t.refreshToken,
    refreshTokenExpiresAt: t.refreshTokenExpiresAt.toISOString(),
  };
}

export function registerAuthRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/auth';

  // Who may call: anyone holding a refresh token. Own tier: 30/min per IP.
  r.post(
    `${prefix}/refresh`,
    {
      schema: { body: refreshBody },
      config: {
        rateLimit: { max: 30, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const tokens = await app.auth.refresh(request.body.refreshToken, requestMeta(request));
      return reply.send(ok({ tokens: tokensDto(tokens) }));
    },
  );

  // Who may call: the signed-in user, for their own current session.
  r.post(`${prefix}/logout`, { preHandler: requireAuth }, async (request, reply) => {
    await app.auth.logout(userOf(request), requestMeta(request));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: the signed-in user, about themselves. Verified or not — browsing is free.
  r.get(`${prefix}/me`, { preHandler: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const user = await app.auth.repo.findById(p.id);
    if (user === null) throw new Error('principal without a user row');
    return reply.send(ok(userDto(user)));
  });

  // Who may call: the signed-in user; their own live sessions only.
  r.get(`${prefix}/sessions`, { preHandler: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const sessions = await app.auth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the signed-in user, for one of their own sessions.
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams }, preHandler: requireAuth },
    async (request, reply) => {
      await app.auth.revokeSession(userOf(request), request.params.id, requestMeta(request));
      return reply.send(ok({ revoked: request.params.id }));
    },
  );

  // Who may call: the signed-in user whose email is not yet verified. Domain
  // limits are the rule (3/address/15 min, 5/account/hour); this tier only
  // stops a misbehaving client turning them into a flood of 429s.
  r.post(
    `${prefix}/verify-email/send`,
    {
      preHandler: requireAuth,
      config: {
        rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const p = userOf(request);
      const user = await app.auth.repo.findById(p.id);
      if (user === null) throw new Error('principal without a user row');
      if (user.emailVerifiedAt !== null) {
        throw new BusinessRuleError(
          'EMAIL_ALREADY_VERIFIED',
          'This email address is already verified',
        );
      }
      const result = await app.otp.send({
        userId: p.id,
        purpose: 'verify_email',
        targetEmail: user.email,
        meta: requestMeta(request),
      });
      return reply.send(
        ok({
          status: result.status,
          expiresAt: result.expiresAt.toISOString(),
          resendAvailableAt: result.resendAvailableAt.toISOString(),
        }),
      );
    },
  );

  // Who may call: the signed-in user. Tier 10/5 min per principal — above the
  // 5-attempt rule so the fifth failure is answered by invalidation, not 429.
  r.post(
    `${prefix}/verify-email/confirm`,
    {
      schema: { body: otpCodeBody },
      preHandler: requireAuth,
      config: { rateLimit: { max: 10, timeWindow: '5 minutes' } },
    },
    async (request, reply) => {
      const p = userOf(request);
      await app.auth.markEmailVerified(p, request.body.code, requestMeta(request));
      return reply.send(ok({ emailVerified: true }));
    },
  );
}
