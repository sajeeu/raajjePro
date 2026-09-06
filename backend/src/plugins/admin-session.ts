import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import type { CookieSerializeOptions } from '@fastify/cookie';
import type { FastifyInstance } from 'fastify';

import type { Config } from '../config/env.js';
import { AuthorizationError } from '../core/errors.js';

export const ADMIN_COOKIE = 'rp_admin_session';
export const CSRF_HEADER = 'x-requested-with';
export const CSRF_VALUE = 'RaajjePro-Admin';
const ADMIN_PREFIX = '/v1/admin';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function cookieOptions(config: Config): CookieSerializeOptions {
  return {
    httpOnly: true,
    secure: config.admin.cookieSecure,
    sameSite: 'strict',
    path: ADMIN_PREFIX,
    maxAge: config.admin.sessionAbsoluteHours * 3600,
  };
}

/**
 * Admin session resolution. Runs onRequest, before rate limiting, so counters
 * key on the admin. Two jobs: (1) CSRF — every non-safe request under
 * /v1/admin must carry the custom header, which a cross-origin form cannot
 * send without a preflight that CORS refuses; (2) cookie → principal, with
 * the rejection reason kept for the guard to report.
 */
export async function registerAdminSession(app: FastifyInstance): Promise<void> {
  await app.register(cookie);
  // `@fastify/cors` is registered without an encapsulating prefix, so the
  // ADMIN_ORIGIN policy applies app-wide, not just under /v1/admin. That is
  // intended: the mobile app is a native client and is never subject to CORS,
  // and the admin panel is the only browser client this API serves.
  await app.register(cors, {
    origin: app.config.admin.origin,
    credentials: true,
    allowedHeaders: ['content-type', 'x-requested-with', 'idempotency-key', 'x-request-id'],
    exposedHeaders: ['x-request-id', 'retry-after', 'idempotent-replayed'],
  });

  app.addHook('onRequest', async (request) => {
    // Match on the resolved route pattern, not the raw incoming `request.url`.
    // Routing runs before onRequest, so this is already known — and unlike the
    // raw path, it cannot be fooled by encoded slashes, a trailing-slash
    // variant, or any other request whose path merely starts with the prefix
    // string yet resolved to a route outside it. `undefined` means no route
    // matched (the 404 handler answers), so there is nothing to guard here.
    const routeUrl = request.routeOptions.url;
    if (!routeUrl?.startsWith(ADMIN_PREFIX)) return;

    if (!SAFE_METHODS.has(request.method) && request.headers[CSRF_HEADER] !== CSRF_VALUE) {
      throw new AuthorizationError(
        'CSRF_HEADER_MISSING',
        `${CSRF_HEADER}: ${CSRF_VALUE} header required`,
      );
    }

    const token = request.cookies[ADMIN_COOKIE];
    if (token === undefined) {
      request.sessionRejection = 'UNAUTHENTICATED';
      return;
    }
    const resolution = await app.adminAuth.resolveSession(token);
    if ('principal' in resolution) {
      request.principal = resolution.principal;
    } else {
      request.sessionRejection = resolution.rejection;
    }
  });
}
