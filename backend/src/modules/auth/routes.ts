import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { sessionDto, userDto } from './dto.js';
import { requireAuth, userOf } from './guards.js';
import { refreshBody, sessionIdParams } from './schema.js';
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
}
