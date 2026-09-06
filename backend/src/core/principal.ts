/**
 * Who is making the request. Phase 2 knows one kind — an admin session. Phase 3
 * adds `user`. Set by an onRequest plugin; read by guards, the rate limiter and
 * the idempotency middleware. A principal existing does not mean it may act:
 * the guards decide that.
 */
export interface AdminPrincipal {
  kind: 'admin';
  id: string;
  sessionId: string;
  mfaVerified: boolean;
  totpEnrolled: boolean;
  reauthenticatedAt: Date | null;
}

export type Principal = AdminPrincipal;

declare module 'fastify' {
  interface FastifyRequest {
    principal?: Principal;
    /** Why a presented session was rejected — the guard turns this into the error code. */
    sessionRejection?: 'SESSION_EXPIRED' | 'UNAUTHENTICATED';
  }
}
