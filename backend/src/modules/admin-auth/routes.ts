import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import type { AdminSession } from '../../generated/prisma/client.js';
import { ADMIN_COOKIE, cookieOptions } from '../../plugins/admin-session.js';
import {
  principalOf,
  requireAdmin,
  requirePasswordSession,
  requireRecentReauth,
} from './guards.js';
import {
  loginBody,
  mfaCodeBody,
  reauthBody,
  revokeSessionBody,
  sessionIdParams,
} from './schema.js';
import type { RequestMeta } from './service.js';

export function requestMeta(request: FastifyRequest): RequestMeta {
  return { ip: request.ip, userAgent: request.headers['user-agent'] ?? '', requestId: request.id };
}

/** DTO: never the token hash, never the admin's password hash. */
function sessionDto(session: AdminSession, current: string) {
  return {
    id: session.id,
    createdAt: session.createdAt.toISOString(),
    lastSeenAt: session.lastSeenAt.toISOString(),
    expiresAt: session.expiresAt.toISOString(),
    ipAddress: session.ipAddress,
    userAgent: session.userAgent,
    current: session.id === current,
  };
}

export function registerAdminAuthRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/admin/auth';

  // Who may call: anyone — this is how a session begins. Stricter tier: 10 per
  // 15 min per IP. keyGenerator is explicit rather than relying on the global
  // tier's per-principal-else-IP default: login is unauthenticated so that
  // default already falls back to the IP, but the plan states "per IP" as the
  // rule itself, and an explicit key generator keeps it true even if a future
  // change makes a principal available on this route.
  r.post(
    `${prefix}/login`,
    {
      schema: { body: loginBody },
      config: {
        rateLimit: {
          max: 10,
          timeWindow: '15 minutes',
          keyGenerator: (request) => `ip:${request.ip}`,
        },
      },
    },
    async (request, reply) => {
      const result = await app.adminAuth.login(
        request.body.email,
        request.body.password,
        requestMeta(request),
      );
      void reply.setCookie(ADMIN_COOKIE, result.token, cookieOptions(app.config));
      return reply.send(ok({ state: result.state, adminId: result.session.adminId }));
    },
  );

  // Who may call: the enrolled, MFA-verified admin, about themselves.
  r.get(`${prefix}/me`, { preValidation: requireAdmin }, async (request, reply) => {
    const p = principalOf(request);
    const admin = await app.deps.prisma.adminUser.findUniqueOrThrow({ where: { id: p.id } });
    return reply.send(
      ok({
        id: admin.id,
        email: admin.email,
        role: admin.role,
        totpEnrolled: admin.totpEnrolledAt !== null,
        reauthenticatedAt: p.reauthenticatedAt?.toISOString() ?? null,
      }),
    );
  });

  // Who may call: the enrolled, MFA-verified admin, for their own session.
  r.post(`${prefix}/logout`, { preValidation: requireAdmin }, async (request, reply) => {
    const p = principalOf(request);
    await app.adminAuth.logout(p.sessionId, p.id, requestMeta(request));
    void reply.clearCookie(ADMIN_COOKIE, cookieOptions(app.config));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: a password-verified session that has not enrolled yet.
  r.post(
    `${prefix}/mfa/enrol`,
    { preValidation: requirePasswordSession },
    async (request, reply) => {
      const p = principalOf(request);
      return reply.send(
        ok(await app.adminAuth.beginEnrolment(p.id, p.sessionId, requestMeta(request))),
      );
    },
  );

  // Who may call: same. Recovery codes come back once, here, and never again.
  // Own tier: 6 per 5 min per principal — a code-guessing surface exactly like
  // mfa/verify, with the same 5-failure session revocation (see
  // registerMfaFailure); max is one above the limit for the same reason as
  // mfa/verify's tier below.
  r.post(
    `${prefix}/mfa/enrol/confirm`,
    {
      schema: { body: mfaCodeBody },
      preValidation: requirePasswordSession,
      config: { rateLimit: { max: 6, timeWindow: '5 minutes' } },
    },
    async (request, reply) => {
      const p = principalOf(request);
      return reply.send(
        ok(
          await app.adminAuth.confirmEnrolment(
            p.id,
            p.sessionId,
            request.body.code,
            requestMeta(request),
          ),
        ),
      );
    },
  );

  // Who may call: any live password-verified session of an enrolled admin;
  // requirePasswordSession also admits an already-MFA-verified session, which
  // is harmless here — re-verifying a code just re-confirms mfaVerifiedAt.
  // Own tier: 6 per 5 min per principal — one above the 5-failure limit, so
  // the sixth request (the one after five counted failures) still reaches
  // the service and is answered by the session-revocation rule (401) rather
  // than by the rate limiter (429). Both limits are defensible; the
  // failure-count revocation is the rule the plan states, so the tier is set
  // to not pre-empt it.
  r.post(
    `${prefix}/mfa/verify`,
    {
      schema: { body: mfaCodeBody },
      preValidation: requirePasswordSession,
      config: { rateLimit: { max: 6, timeWindow: '5 minutes' } },
    },
    async (request, reply) => {
      const p = principalOf(request);
      return reply.send(
        ok(
          await app.adminAuth.verifyMfa(p.id, p.sessionId, request.body.code, requestMeta(request)),
        ),
      );
    },
  );

  // Who may call: the enrolled, MFA-verified admin, for their own session.
  // Own tier: 10 per 15 min per principal — a password-guessing surface,
  // stricter than the global authenticated tier.
  r.post(
    `${prefix}/reauth`,
    {
      schema: { body: reauthBody },
      preValidation: requireAdmin,
      config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
    },
    async (request, reply) => {
      const p = principalOf(request);
      await app.adminAuth.reauthenticate(
        p.id,
        p.sessionId,
        request.body.password,
        request.body.code,
        requestMeta(request),
      );
      return reply.send(ok({ reauthenticatedAt: app.deps.clock().toISOString() }));
    },
  );

  // Who may call: the enrolled, MFA-verified admin who re-authenticated within ADMIN_REAUTH_MINUTES.
  r.post(
    `${prefix}/mfa/recovery-codes/regenerate`,
    { preValidation: requireRecentReauth },
    async (request, reply) => {
      const p = principalOf(request);
      return reply.send(
        ok(await app.adminAuth.regenerateRecoveryCodes(p.id, requestMeta(request))),
      );
    },
  );

  // Who may call: the enrolled, MFA-verified admin; lists their own sessions only.
  r.get(`${prefix}/sessions`, { preValidation: requireAdmin }, async (request, reply) => {
    const p = principalOf(request);
    const sessions = await app.adminAuth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the enrolled, MFA-verified admin, for one of their own sessions. Reason required (audit).
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams, body: revokeSessionBody }, preValidation: requireAdmin },
    async (request, reply) => {
      const p = principalOf(request);
      await app.adminAuth.revokeSession(
        p.id,
        request.params.id,
        request.body.reason,
        requestMeta(request),
      );
      return reply.send(ok({ revoked: request.params.id }));
    },
  );
}
