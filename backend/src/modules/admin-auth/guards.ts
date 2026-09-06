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

// Every guard below is declared `async` even though its body is synchronous
// logic that only ever throws or returns. Fastify's hook runner requires a
// two-argument (request, reply) hook to come back as a Promise; a plain sync
// function that returns `undefined` on its non-throwing path is not a
// recognised hook shape and the request hangs forever waiting for a
// done()/Promise that never arrives. Every route that reached one of these
// guards until Task 10 always hit the throwing path (no account had ever
// enrolled MFA), so the hang was latent — the first passing call is Task 10's
// own "guard lets a genuinely authorised request through" case, and it is
// what surfaced this. Keep these `async`; do not simplify back to plain
// functions.

/** A live session whose password was verified. Enough for the MFA routes only. */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requirePasswordSession(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  principalOf(request);
}

/**
 * Who may pass: an active admin, TOTP enrolled, MFA verified on this session.
 * Nothing else in /v1/admin is reachable without this (plan §Phase 2: enrolment
 * required before the account can take any action).
 */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireAdmin(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
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
export async function requireRecentReauth(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  await requireAdmin(request, reply);
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
