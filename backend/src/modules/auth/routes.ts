import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requestMeta } from '../admin-auth/routes.js';
import { sessionDto, userDto } from './dto.js';
import { requireAuth, userOf } from './guards.js';
import {
  loginBody,
  otpCodeBody,
  refreshBody,
  registerBody,
  sessionIdParams,
  socialBody,
  socialParams,
} from './schema.js';
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

  // Who may call: anyone — an account begins here. Creation POST, so
  // Idempotency-Key is required (subject anon:<ip> — the Phase 2 proposal,
  // confirmed in the Phase 3 spec). Tier 5/hour per IP.
  r.post(
    `${prefix}/register`,
    {
      schema: { body: registerBody },
      config: {
        idempotency: { operation: 'auth.register' },
        rateLimit: { max: 5, timeWindow: '1 hour', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const result = await app.auth.register(request.body, requestMeta(request));
      return reply.code(201).send(
        ok({
          user: userDto(result.user),
          tokens: tokensDto(result.tokens),
          verification: {
            status: result.verification.status,
            expiresAt: result.verification.expiresAt.toISOString(),
            resendAvailableAt: result.verification.resendAvailableAt.toISOString(),
          },
        }),
      );
    },
  );

  // Who may call: anyone with credentials. Tier 10 per 15 min per IP, keyed explicitly.
  r.post(
    `${prefix}/login`,
    {
      schema: { body: loginBody },
      config: {
        rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const { email, password, deviceName: device } = request.body;
      const result = await app.auth.login(email, password, device, requestMeta(request));
      return reply.send(ok({ user: userDto(result.user), tokens: tokensDto(result.tokens) }));
    },
  );

  // Who may call: anyone with a third-party id token. Every provider is a stub in v1.
  r.post(
    `${prefix}/social/:provider`,
    {
      schema: { params: socialParams, body: socialBody },
      config: {
        rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const identity = await app.social.get(request.params.provider).verify(request.body.idToken);
      // Unreachable while every provider is a stub; when one becomes real, this
      // is where identity → user lookup/creation is added.
      return reply.send(ok({ identity }));
    },
  );

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
  r.post(`${prefix}/logout`, { preValidation: requireAuth }, async (request, reply) => {
    await app.auth.logout(userOf(request), requestMeta(request));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: the signed-in user, about themselves. Verified or not — browsing is free.
  r.get(`${prefix}/me`, { preValidation: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const user = await app.auth.repo.findById(p.id);
    if (user === null) throw new Error('principal without a user row');
    return reply.send(ok(userDto(user)));
  });

  // Who may call: the signed-in user; their own live sessions only.
  r.get(`${prefix}/sessions`, { preValidation: requireAuth }, async (request, reply) => {
    const p = userOf(request);
    const sessions = await app.auth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the signed-in user, for one of their own sessions.
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams }, preValidation: requireAuth },
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
      preValidation: requireAuth,
      config: {
        rateLimit: { max: 10, timeWindow: '15 minutes', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const p = userOf(request);
      const user = await app.auth.repo.findById(p.id);
      if (user === null) throw new Error('principal without a user row');
      // Already-verified is checked inside OtpService.send itself, in the
      // same locked section as the two rate-limit counts (plan §4) — not
      // here, so it cannot race a concurrent confirm.
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
      preValidation: requireAuth,
      config: { rateLimit: { max: 10, timeWindow: '5 minutes' } },
    },
    async (request, reply) => {
      const p = userOf(request);
      await app.auth.markEmailVerified(p, request.body.code, requestMeta(request));
      return reply.send(ok({ emailVerified: true }));
    },
  );
}
