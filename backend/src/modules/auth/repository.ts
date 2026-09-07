import type {
  PrismaClient,
  ProviderProfile,
  RefreshToken,
  User,
  UserSession,
  UserSessionRevokedReason,
} from '../../generated/prisma/client.js';
import type { Db } from '../audit/types.js';

export type UserWithProfile = User & { providerProfile: ProviderProfile | null };
export type SessionWithUser = UserSession & { user: UserWithProfile };

/** Data access for user identity. No rules here — the services own them. */
export class UserRepository {
  constructor(private readonly prisma: PrismaClient) {}

  findByEmail(email: string): Promise<UserWithProfile | null> {
    return this.prisma.user.findUnique({ where: { email }, include: { providerProfile: true } });
  }

  findById(id: string): Promise<UserWithProfile | null> {
    return this.prisma.user.findUnique({ where: { id }, include: { providerProfile: true } });
  }

  createSession(
    db: Db,
    data: { userId: string; deviceName: string; ipAddress: string; userAgent: string; now: Date },
  ): Promise<UserSession> {
    return db.userSession.create({
      data: {
        userId: data.userId,
        deviceName: data.deviceName,
        ipAddress: data.ipAddress,
        userAgent: data.userAgent,
        createdAt: data.now,
        lastSeenAt: data.now,
      },
    });
  }

  createRefreshToken(
    db: Db,
    data: { id?: string; sessionId: string; tokenHash: string; createdAt: Date; expiresAt: Date },
  ): Promise<RefreshToken> {
    return db.refreshToken.create({
      data: {
        ...(data.id === undefined ? {} : { id: data.id }),
        sessionId: data.sessionId,
        tokenHash: data.tokenHash,
        createdAt: data.createdAt,
        expiresAt: data.expiresAt,
      },
    });
  }

  findSessionById(id: string): Promise<SessionWithUser | null> {
    return this.prisma.userSession.findUnique({
      where: { id },
      include: { user: { include: { providerProfile: true } } },
    });
  }

  findRefreshTokenByHash(
    tokenHash: string,
  ): Promise<(RefreshToken & { session: SessionWithUser }) | null> {
    return this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { session: { include: { user: { include: { providerProfile: true } } } } },
    });
  }

  /**
   * The rotation is one conditional UPDATE so two racing refreshes with the
   * same token cannot both win — `updateMany` returns the affected count and
   * the caller treats 0 as "lost the race or not live". The session predicate
   * closes a TOCTOU window: without it, a refresh racing a concurrent revoke
   * of the same session can still win the rotation and mint a fresh, live
   * token pair for a session that is supposed to be dead.
   */
  async rotateRefreshToken(
    db: Db,
    tokenHash: string,
    now: Date,
    replacedById: string,
  ): Promise<boolean> {
    const result = await db.refreshToken.updateMany({
      where: { tokenHash, rotatedAt: null, expiresAt: { gt: now }, session: { revokedAt: null } },
      data: { rotatedAt: now, replacedById },
    });
    return result.count === 1;
  }

  touchSession(sessionId: string, now: Date): Promise<{ count: number }> {
    return this.prisma.userSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { lastSeenAt: now },
    });
  }

  revokeSession(
    db: Db,
    sessionId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  revokeOtherSessions(
    db: Db,
    userId: string,
    keepSessionId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { userId, revokedAt: null, id: { not: keepSessionId } },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  revokeAllSessions(
    db: Db,
    userId: string,
    now: Date,
    reason: UserSessionRevokedReason,
  ): Promise<{ count: number }> {
    return db.userSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });
  }

  listLiveSessions(userId: string): Promise<UserSession[]> {
    return this.prisma.userSession.findMany({
      where: { userId, revokedAt: null },
      orderBy: { lastSeenAt: 'desc' },
    });
  }

  create(
    db: Db,
    data: {
      email: string;
      passwordHash: string;
      fullName: string;
      phoneE164: string;
      phoneDialCode: string;
      now: Date;
    },
  ): Promise<User> {
    return db.user.create({
      data: {
        email: data.email,
        passwordHash: data.passwordHash,
        fullName: data.fullName,
        phoneE164: data.phoneE164,
        phoneDialCode: data.phoneDialCode,
        termsAcceptedAt: data.now,
        passwordChangedAt: data.now,
        createdAt: data.now,
      },
    });
  }

  /**
   * The Bronze-uniqueness rule (plan §Phase 3, Round 15): a number is
   * exclusive only once an account holding it has a ProviderProfile at
   * bronze or above. Below that, several accounts may hold it.
   */
  async phoneHeldAtBronzeOrAbove(phoneE164: string, excludingUserId?: string): Promise<boolean> {
    const holder = await this.prisma.user.findFirst({
      where: {
        phoneE164,
        status: { not: 'anonymised' },
        ...(excludingUserId === undefined ? {} : { id: { not: excludingUserId } }),
        providerProfile: { is: { verificationTier: { in: ['bronze', 'silver', 'gold'] } } },
      },
      select: { id: true },
    });
    return holder !== null;
  }

  /** Idempotent (§1a). Phase 6a and Phase 8 call this too; Phase 5 extends what it sets. */
  async getOrCreateProviderProfile(
    db: Db,
    userId: string,
    businessName?: string,
  ): Promise<ProviderProfile> {
    const existing = await db.providerProfile.findUnique({ where: { userId } });
    if (existing !== null) return existing;
    return db.providerProfile.create({
      data: { userId, ...(businessName === undefined ? {} : { businessName }) },
    });
  }
}
