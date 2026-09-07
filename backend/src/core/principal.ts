/**
 * Who is making the request. Two kinds: an admin session (Phase 2) and a user
 * session (Phase 3). Set by an onRequest plugin; read by guards, the rate
 * limiter and the idempotency middleware. A principal existing does not mean
 * it may act: the guards decide that.
 */
export interface AdminPrincipal {
  kind: 'admin';
  id: string;
  sessionId: string;
  mfaVerified: boolean;
  totpEnrolled: boolean;
  reauthenticatedAt: Date | null;
}

export interface UserPrincipal {
  kind: 'user';
  id: string;
  sessionId: string;
  emailVerified: boolean;
  /** `anonymised` never reaches here — that session is rejected by the plugin. */
  status: 'active' | 'frozen';
}

export type Principal = AdminPrincipal | UserPrincipal;

declare module 'fastify' {
  interface FastifyRequest {
    principal?: Principal;
    /** Why a presented credential was rejected — the guard turns this into the error code. */
    sessionRejection?: 'SESSION_EXPIRED' | 'UNAUTHENTICATED' | 'ACCESS_TOKEN_EXPIRED';
  }
}
