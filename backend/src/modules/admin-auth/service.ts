import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import {
  AuthenticationError,
  BusinessRuleError,
  ConflictError,
  NotFoundError,
} from '../../core/errors.js';
import type { AdminPrincipal } from '../../core/principal.js';
import type { AdminSession, AdminUser, PrismaClient } from '../../generated/prisma/client.js';
import type { AuditService } from '../audit/service.js';
import {
  DUMMY_PASSWORD_HASH,
  hashPassword,
  hashToken,
  MAX_PASSWORD_LENGTH,
  MIN_PASSWORD_LENGTH,
  newSessionToken,
  verifyPassword,
} from './crypto.js';
import { AdminRepository } from './repository.js';

export interface RequestMeta {
  ip: string;
  userAgent: string;
  requestId: string;
}

export type LoginState = 'mfa_required' | 'mfa_enrolment_required';

export interface LoginResult {
  token: string;
  session: AdminSession;
  state: LoginState;
}

export type SessionResolution =
  { principal: AdminPrincipal } | { rejection: 'SESSION_EXPIRED' | 'UNAUTHENTICATED' };

/**
 * Admin identity (plan §Phase 2): one `admin` role, password + mandatory TOTP,
 * server-side sessions with idle and absolute expiry, force-logout, re-auth.
 * Every action that changes state writes an audit entry in the same
 * transaction.
 */
export class AdminAuthService {
  private readonly prisma: PrismaClient;
  private readonly audit: AuditService;
  private readonly clock: Clock;
  private readonly config: Config;
  private readonly repo: AdminRepository;

  constructor(deps: { prisma: PrismaClient; audit: AuditService; clock: Clock; config: Config }) {
    this.prisma = deps.prisma;
    this.audit = deps.audit;
    this.clock = deps.clock;
    this.config = deps.config;
    this.repo = new AdminRepository(deps.prisma);
  }

  /** Who may call: the server operator via the CLI (Task 11). There is no HTTP route for this in v1. */
  async createAdmin(
    emailInput: string,
    password: string,
    meta: { requestId?: string },
  ): Promise<AdminUser> {
    const email = emailInput.trim().toLowerCase();
    assertPasswordLength(password);
    if ((await this.repo.findByEmail(email)) !== null) {
      throw new ConflictError('CONFLICT', 'An admin with this email already exists');
    }
    const passwordHash = await hashPassword(password);
    const now = this.clock();
    return this.prisma.$transaction(async (tx) => {
      const admin = await this.repo.create(tx, { email, passwordHash, createdAt: now });
      await this.audit.record(tx, {
        actorType: 'system',
        action: 'admin.created',
        targetType: 'admin_user',
        targetId: admin.id,
        reason: 'created from the server CLI',
        requestId: meta.requestId ?? null,
      });
      return admin;
    });
  }

  async login(emailInput: string, password: string, meta: RequestMeta): Promise<LoginResult> {
    const email = emailInput.trim().toLowerCase();
    const admin = await this.repo.findByEmail(email);
    // Always run one argon2 verification so an unknown email costs the same time as a wrong password.
    const passwordOk = await verifyPassword(admin?.passwordHash ?? DUMMY_PASSWORD_HASH, password);
    if (admin === null) {
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }
    if (!passwordOk || admin.status !== 'active') {
      await this.audit.record(this.prisma, {
        actorType: 'system',
        action: 'admin.login.failed',
        targetType: 'admin_user',
        targetId: admin.id,
        reason: admin.status !== 'active' ? 'account_disabled' : 'wrong_password',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      throw new AuthenticationError('INVALID_CREDENTIALS', 'Email or password is incorrect');
    }

    const now = this.clock();
    const token = newSessionToken();
    const expiresAt = new Date(now.getTime() + this.config.admin.sessionAbsoluteHours * 3_600_000);
    const session = await this.prisma.$transaction(async (tx) => {
      const created = await this.repo.createSession(tx, {
        adminId: admin.id,
        tokenHash: hashToken(token),
        now,
        expiresAt,
        ipAddress: meta.ip,
        userAgent: meta.userAgent.slice(0, 512),
      });
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: admin.id,
        action: 'admin.login.succeeded',
        targetType: 'admin_session',
        targetId: created.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      return created;
    });
    return {
      token,
      session,
      state: admin.totpEnrolledAt === null ? 'mfa_enrolment_required' : 'mfa_required',
    };
  }

  /**
   * Turns a cookie token into a principal. Idle expiry slides on every call;
   * absolute expiry never moves. An expired session is revoked here so the
   * reason is recorded once, on the request that found it.
   */
  async resolveSession(token: string): Promise<SessionResolution> {
    if (token.length === 0) return { rejection: 'UNAUTHENTICATED' };
    const session = await this.repo.findSessionByTokenHash(hashToken(token));
    if (session?.admin.status !== 'active') {
      return { rejection: 'UNAUTHENTICATED' };
    }
    if (session.revokedAt !== null) {
      // A session already revoked for running out of time keeps reporting
      // SESSION_EXPIRED on every subsequent call — the caller's distinction
      // between "your session timed out" and "you were never signed in"
      // should not flip depending on how many times they retried.
      return session.revokedReason === 'idle_timeout' || session.revokedReason === 'absolute_expiry'
        ? { rejection: 'SESSION_EXPIRED' }
        : { rejection: 'UNAUTHENTICATED' };
    }
    const now = this.clock();
    const idleLimit = session.lastSeenAt.getTime() + this.config.admin.sessionIdleMinutes * 60_000;
    if (session.expiresAt.getTime() <= now.getTime()) {
      await this.expireSession(session.id, session.adminId, now, 'absolute_expiry');
      return { rejection: 'SESSION_EXPIRED' };
    }
    if (idleLimit < now.getTime()) {
      await this.expireSession(session.id, session.adminId, now, 'idle_timeout');
      return { rejection: 'SESSION_EXPIRED' };
    }
    // Ignore the affected-row count: a concurrent revoke racing this touch
    // means the update matched zero rows, which is fine — the principal below
    // was already computed from the row we read while it was still live.
    await this.repo.touchSession(session.id, now);
    return {
      principal: {
        kind: 'admin',
        id: session.adminId,
        sessionId: session.id,
        mfaVerified: session.mfaVerifiedAt !== null,
        totpEnrolled: session.admin.totpEnrolledAt !== null,
        reauthenticatedAt: session.reauthenticatedAt,
      },
    };
  }

  /** Revokes an auto-expired session and audits it in the same transaction, so an idle or absolute timeout leaves a record like any other session state change. */
  private async expireSession(
    sessionId: string,
    adminId: string,
    now: Date,
    reason: 'absolute_expiry' | 'idle_timeout',
  ): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, sessionId, now, reason);
      await this.audit.record(tx, {
        actorType: 'system',
        action: 'admin.session.expired',
        targetType: 'admin_session',
        targetId: sessionId,
        reason,
        metadata: { adminId },
      });
    });
  }

  /** Caller must pass `sessionId`/`adminId` from its own resolved principal, never from request input — this never checks ownership itself. */
  async logout(sessionId: string, adminId: string, meta: RequestMeta): Promise<void> {
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, sessionId, now, 'logout');
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'admin.logout',
        targetType: 'admin_session',
        targetId: sessionId,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  listSessions(adminId: string): Promise<AdminSession[]> {
    return this.repo.listActiveSessions(adminId, this.clock());
  }

  /** Who may call: the admin who owns the session. Another admin's session id is reported as not found, not forbidden. */
  async revokeSession(
    adminId: string,
    sessionId: string,
    reason: string,
    meta: RequestMeta,
  ): Promise<void> {
    const session = await this.repo.findSession(adminId, sessionId);
    if (session === null) throw new NotFoundError('No such active session');
    const now = this.clock();
    await this.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, sessionId, now, 'force_logout');
      await this.audit.record(tx, {
        actorType: 'admin',
        actorId: adminId,
        action: 'admin.session.revoked',
        targetType: 'admin_session',
        targetId: sessionId,
        reason,
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }
}

export function assertPasswordLength(password: string): void {
  if (password.length < MIN_PASSWORD_LENGTH) {
    throw new BusinessRuleError(
      'PASSWORD_TOO_SHORT',
      `Password must be at least ${String(MIN_PASSWORD_LENGTH)} characters`,
    );
  }
  if (password.length > MAX_PASSWORD_LENGTH) {
    throw new BusinessRuleError(
      'PASSWORD_TOO_LONG',
      `Password must be at most ${String(MAX_PASSWORD_LENGTH)} characters`,
    );
  }
}
