import type { FastifyReply, FastifyRequest } from 'fastify';

import { AuthenticationError, BusinessRuleError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';

/**
 * The user principal, narrowed past `undefined` and past the admin kind. A
 * real runtime check, not a cast — an admin cookie must never satisfy a user
 * route.
 */
export function userOf(request: FastifyRequest): UserPrincipal {
  if (request.principal?.kind !== 'user') {
    throw new AuthenticationError(
      request.sessionRejection ?? 'UNAUTHENTICATED',
      request.sessionRejection === 'ACCESS_TOKEN_EXPIRED'
        ? 'Your access token has expired — refresh it'
        : request.sessionRejection === 'SESSION_EXPIRED'
          ? 'Signed out for your security — sign in again'
          : 'Sign in to continue',
    );
  }
  return request.principal;
}

// Declared `async` for the same reason the admin guards are: Fastify needs a
// two-argument hook to return a Promise, and a plain function returning
// undefined on its non-throwing path hangs the request. Keep them async.

/** Any signed-in user, verified or not. Browsing needs nothing; this is for "your own stuff". */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  userOf(request);
}

/**
 * Stricter than requireAuth (plan §Phase 3, CLAUDE.md 1c): the guard booking,
 * enquiry and messaging endpoints carry. 422 with its own code so the app
 * can route straight to Verify Email.
 */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireEmailVerified(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const p = userOf(request);
  if (!p.emailVerified) {
    throw new BusinessRuleError(
      'EMAIL_NOT_VERIFIED',
      'Verify your email address to book, enquire or message',
    );
  }
}

/**
 * A deletion request freezes the account: no new bookings, no new listings
 * (plan §Phase 3). Later phases place this on those endpoints; everything in
 * Phase 3 itself stays usable while frozen.
 */
// eslint-disable-next-line @typescript-eslint/require-await -- async is load-bearing, see note above
export async function requireActiveAccount(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const p = userOf(request);
  if (p.status !== 'active') {
    throw new BusinessRuleError(
      'ACCOUNT_FROZEN',
      'This account is being deleted and cannot start anything new',
    );
  }
}
