import type { FastifyReply, FastifyRequest } from 'fastify';

import { AuthenticationError, AuthorizationError } from '../../core/errors.js';
import type { AdminPrincipal } from '../../core/principal.js';

/**
 * The resolved principal, narrowed past `undefined`. Centralised here (rather
 * than an `as AdminPrincipal` at each call site) so every route reads it the
 * same way, and so the narrowing is a real runtime check, not a bare cast.
 */
export function principalOf(request: FastifyRequest): AdminPrincipal {
  if (request.principal === undefined) {
    throw new AuthenticationError(
      request.sessionRejection ?? 'UNAUTHENTICATED',
      'Sign in to continue',
    );
  }
  return request.principal;
}

/** A live session whose password was verified. Enough for the MFA routes only. */
export function requirePasswordSession(request: FastifyRequest, _reply: FastifyReply): void {
  principalOf(request);
}

/**
 * Who may pass: an active admin, TOTP enrolled, MFA verified on this session.
 * Nothing else in /v1/admin is reachable without this (plan §Phase 2: enrolment
 * required before the account can take any action).
 */
export function requireAdmin(request: FastifyRequest, _reply: FastifyReply): void {
  const p = principalOf(request);
  if (!p.totpEnrolled)
    throw new AuthorizationError(
      'MFA_ENROLMENT_REQUIRED',
      'Enrol an authenticator app to continue',
    );
  if (!p.mfaVerified)
    throw new AuthenticationError('MFA_REQUIRED', 'Enter your authenticator code to continue');
}

/** requireAdmin plus a re-authentication within ADMIN_REAUTH_MINUTES. Phase 10a puts this before identity documents. */
export function requireRecentReauth(request: FastifyRequest, reply: FastifyReply): void {
  requireAdmin(request, reply);
  const p = principalOf(request);
  const limitMs = request.server.config.admin.reauthMinutes * 60_000;
  const now = request.server.deps.clock().getTime();
  if (p.reauthenticatedAt === null || now - p.reauthenticatedAt.getTime() > limitMs) {
    throw new AuthorizationError(
      'REAUTHENTICATION_REQUIRED',
      'Confirm your password and authenticator code to continue',
    );
  }
}
