import type { FastifyInstance } from 'fastify';

/**
 * User session resolution (plan §Phase 3). Runs onRequest, beside the admin
 * cookie plugin and before rate limiting so counters key on the user. No
 * header means an anonymous request — browsing needs nothing. A header is
 * verified as a JWT and then resolved to its session row, so a revoked
 * device or a frozen account is seen on the very next request. The rejection
 * reason is left for the guard to report; a public route ignores it.
 */
export function registerUserAuth(app: FastifyInstance): void {
  app.addHook('onRequest', async (request) => {
    const header = request.headers.authorization;
    if (header === undefined) return;
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || token === undefined || token.length === 0) {
      request.sessionRejection = 'UNAUTHENTICATED';
      return;
    }
    const resolution = await app.auth.resolveAccessToken(token);
    if ('principal' in resolution) {
      request.principal = resolution.principal;
    } else {
      request.sessionRejection = resolution.rejection;
    }
  });
}
