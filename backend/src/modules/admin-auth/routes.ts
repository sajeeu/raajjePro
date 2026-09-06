import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import type { AdminSession } from '../../generated/prisma/client.js';
import { ADMIN_COOKIE, cookieOptions } from '../../plugins/admin-session.js';
import { principalOf, requireAdmin } from './guards.js';
import { loginBody, revokeSessionBody, sessionIdParams } from './schema.js';
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

  // Who may call: anyone — this is how a session begins. Stricter tier: 10 per 15 min per IP.
  r.post(
    `${prefix}/login`,
    { schema: { body: loginBody }, config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } },
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
  r.get(`${prefix}/me`, { preHandler: requireAdmin }, async (request, reply) => {
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
  r.post(`${prefix}/logout`, { preHandler: requireAdmin }, async (request, reply) => {
    const p = principalOf(request);
    await app.adminAuth.logout(p.sessionId, p.id, requestMeta(request));
    void reply.clearCookie(ADMIN_COOKIE, cookieOptions(app.config));
    return reply.send(ok({ loggedOut: true }));
  });

  // Who may call: the enrolled, MFA-verified admin; lists their own sessions only.
  r.get(`${prefix}/sessions`, { preHandler: requireAdmin }, async (request, reply) => {
    const p = principalOf(request);
    const sessions = await app.adminAuth.listSessions(p.id);
    return reply.send(ok(sessions.map((s) => sessionDto(s, p.sessionId))));
  });

  // Who may call: the enrolled, MFA-verified admin, for one of their own sessions. Reason required (audit).
  r.delete(
    `${prefix}/sessions/:id`,
    { schema: { params: sessionIdParams, body: revokeSessionBody }, preHandler: requireAdmin },
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
