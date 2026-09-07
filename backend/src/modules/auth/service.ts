import { randomUUID } from 'node:crypto';

import type { Config } from '../../config/env.js';
import type { Clock } from '../../core/clock.js';
import { AuthenticationError, NotFoundError } from '../../core/errors.js';
import type { UserPrincipal } from '../../core/principal.js';
import type { PrismaClient, UserSession } from '../../generated/prisma/client.js';
import type { RequestMeta } from '../admin-auth/service.js';
import type { AuditService } from '../audit/service.js';
import type { OtpService } from './otp.js';
import { UserRepository, type UserWithProfile } from './repository.js';
import { hashToken, newRefreshToken, signAccessToken, verifyAccessToken } from './tokens.js';

export type { RequestMeta };

export interface TokenPair {
  accessToken: string;
  accessTokenExpiresAt: Date;
  refreshToken: string;
  refreshTokenExpiresAt: Date;
}

export type AccessResolution =
  | { principal: UserPrincipal }
  | { rejection: 'UNAUTHENTICATED' | 'SESSION_EXPIRED' | 'ACCESS_TOKEN_EXPIRED' };

/** A rotated refresh token presented again within this window is a client retry, not a theft. */
export const REFRESH_REUSE_GRACE_MS = 30_000;

/** Device names are client-supplied text; bounded and defaulted here, never trusted for anything else. */
export function cleanDeviceName(input: string | undefined): string {
  const trimmed = (input ?? '').trim().slice(0, 80);
  return trimmed.length === 0 ? 'Unknown device' : trimmed;
}

/**
 * User identity (plan §Phase 3): JWT access + rotated per-device refresh
 * tokens, sessions listed and revoked per device. Every state change writes
 * an audit row in the same transaction.
 */
export class AuthService {
  readonly repo: UserRepository;

  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      audit: AuditService;
      clock: Clock;
      config: Config;
      otp: OtpService;
    },
  ) {
    this.repo = new UserRepository(deps.prisma);
  }

  /** Who may call: the service itself, after a password or registration has been accepted. */
  async openSession(
    user: UserWithProfile,
    meta: RequestMeta,
    now: Date,
    deviceName: string | undefined,
    action: 'user.login.succeeded' | 'user.registered' = 'user.login.succeeded',
  ): Promise<TokenPair> {
    const refreshToken = newRefreshToken();
    const refreshTokenExpiresAt = this.refreshExpiry(now);
    const session = await this.deps.prisma.$transaction(async (tx) => {
      const created = await this.repo.createSession(tx, {
        userId: user.id,
        deviceName: cleanDeviceName(deviceName),
        ipAddress: meta.ip,
        userAgent: meta.userAgent.slice(0, 512),
        now,
      });
      await this.repo.createRefreshToken(tx, {
        sessionId: created.id,
        tokenHash: hashToken(refreshToken),
        createdAt: now,
        expiresAt: refreshTokenExpiresAt,
      });
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: user.id,
        action,
        targetType: 'user_session',
        targetId: created.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
      return created;
    });
    const access = await this.signAccess(user.id, session.id, now);
    return {
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken,
      refreshTokenExpiresAt,
    };
  }

  /** Bearer token → principal. Signature first, then the row, so a revocation is honoured at once. */
  async resolveAccessToken(token: string): Promise<AccessResolution> {
    const now = this.deps.clock();
    const verified = await verifyAccessToken(token, this.deps.config.auth.jwtSecret, now);
    if (!verified.ok) {
      return {
        rejection: verified.reason === 'expired' ? 'ACCESS_TOKEN_EXPIRED' : 'UNAUTHENTICATED',
      };
    }
    const session = await this.repo.findSessionById(verified.sessionId);
    if (session?.userId !== verified.userId) return { rejection: 'UNAUTHENTICATED' };
    if (session.revokedAt !== null || session.user.status === 'anonymised') {
      return { rejection: 'SESSION_EXPIRED' };
    }
    if (now.getTime() - session.lastSeenAt.getTime() > 60_000) {
      await this.repo.touchSession(session.id, now);
    }
    return {
      principal: {
        kind: 'user',
        id: session.userId,
        sessionId: session.id,
        emailVerified: session.user.emailVerifiedAt !== null,
        status: session.user.status === 'frozen' ? 'frozen' : 'active',
      },
    };
  }

  /** Who may call: anyone holding a refresh token — the token is the credential. */
  async refresh(refreshToken: string, meta: RequestMeta): Promise<TokenPair> {
    const now = this.deps.clock();
    const presentedHash = hashToken(refreshToken);
    const existing = await this.repo.findRefreshTokenByHash(presentedHash);
    if (existing === null) throw new AuthenticationError('UNAUTHENTICATED', 'Sign in to continue');
    const session = existing.session;
    const dead = () =>
      new AuthenticationError('SESSION_EXPIRED', 'Signed out for your security — sign in again');

    if (session.revokedAt !== null || session.user.status === 'anonymised') throw dead();

    if (existing.rotatedAt !== null) {
      // Already rotated. A retry inside the grace window is a flaky-network
      // client re-sending; beyond it, someone is replaying a stolen token
      // and the whole device session is revoked (plan §2 rotation).
      if (now.getTime() - existing.rotatedAt.getTime() <= REFRESH_REUSE_GRACE_MS) {
        throw new AuthenticationError(
          'REFRESH_TOKEN_ROTATED',
          'This refresh token was already used — retry with the newest one',
        );
      }
      await this.revokeBySystem(session, now, 'refresh_reuse', meta);
      throw dead();
    }
    if (existing.expiresAt.getTime() <= now.getTime()) {
      await this.revokeBySystem(session, now, 'refresh_expired', meta);
      throw dead();
    }

    const nextToken = newRefreshToken();
    const nextExpiresAt = this.refreshExpiry(now);
    const nextId = randomUUID();
    const rotated = await this.deps.prisma.$transaction(async (tx) => {
      const won = await this.repo.rotateRefreshToken(tx, presentedHash, now, nextId);
      if (!won) return false;
      await this.repo.createRefreshToken(tx, {
        id: nextId,
        sessionId: session.id,
        tokenHash: hashToken(nextToken),
        createdAt: now,
        expiresAt: nextExpiresAt,
      });
      return true;
    });
    if (!rotated) {
      // Lost a race with a concurrent refresh of the same token — by
      // definition inside the grace window.
      throw new AuthenticationError(
        'REFRESH_TOKEN_ROTATED',
        'This refresh token was already used — retry with the newest one',
      );
    }
    await this.repo.touchSession(session.id, now);
    const access = await this.signAccess(session.userId, session.id, now);
    return {
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: nextToken,
      refreshTokenExpiresAt: nextExpiresAt,
    };
  }

  /** Who may call: the signed-in user, for their own current session. */
  async logout(principal: UserPrincipal, meta: RequestMeta): Promise<void> {
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, principal.sessionId, now, 'logout');
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.logout',
        targetType: 'user_session',
        targetId: principal.sessionId,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  /** Who may call: the signed-in user; lists their own live sessions only. */
  listSessions(userId: string): Promise<UserSession[]> {
    return this.repo.listLiveSessions(userId);
  }

  /** Who may call: the signed-in user, for one of their own sessions. A foreign id is 404, never 403. */
  async revokeSession(
    principal: UserPrincipal,
    sessionId: string,
    meta: RequestMeta,
  ): Promise<void> {
    const now = this.deps.clock();
    const target = await this.deps.prisma.userSession.findFirst({
      where: { id: sessionId, userId: principal.id, revokedAt: null },
    });
    if (target === null) throw new NotFoundError('No such session');
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(
        tx,
        target.id,
        now,
        sessionId === principal.sessionId ? 'logout' : 'revoked_by_user',
      );
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.session.revoked',
        targetType: 'user_session',
        targetId: target.id,
        reason: 'user_initiated',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  /** Who may call: the signed-in user, with a code from their inbox. */
  async markEmailVerified(
    principal: UserPrincipal,
    code: string,
    meta: RequestMeta,
  ): Promise<void> {
    const { targetEmail } = await this.deps.otp.confirm({
      userId: principal.id,
      purpose: 'verify_email',
      code,
      meta,
    });
    const now = this.deps.clock();
    await this.deps.prisma.$transaction(async (tx) => {
      await tx.user.updateMany({
        where: { id: principal.id, email: targetEmail, emailVerifiedAt: null },
        data: { emailVerifiedAt: now },
      });
      await this.deps.audit.record(tx, {
        actorType: 'user',
        actorId: principal.id,
        action: 'user.email.verified',
        targetType: 'user',
        targetId: principal.id,
        reason: 'otp_confirmed',
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  private async revokeBySystem(
    session: UserSession,
    now: Date,
    reason: 'refresh_reuse' | 'refresh_expired',
    meta: RequestMeta,
  ): Promise<void> {
    await this.deps.prisma.$transaction(async (tx) => {
      await this.repo.revokeSession(tx, session.id, now, reason);
      await this.deps.audit.record(tx, {
        actorType: 'system',
        action: 'user.session.revoked',
        targetType: 'user_session',
        targetId: session.id,
        reason,
        requestId: meta.requestId,
        ipAddress: meta.ip,
      });
    });
  }

  private signAccess(userId: string, sessionId: string, now: Date) {
    return signAccessToken({
      userId,
      sessionId,
      now,
      ttlMinutes: this.deps.config.auth.accessTokenMinutes,
      secret: this.deps.config.auth.jwtSecret,
    });
  }

  private refreshExpiry(now: Date): Date {
    return new Date(now.getTime() + this.deps.config.auth.refreshTokenDays * 86_400_000);
  }
}
