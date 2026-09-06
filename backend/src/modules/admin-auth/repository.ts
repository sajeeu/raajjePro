import type {
  AdminSession,
  AdminUser,
  PrismaClient,
  SessionRevokedReason,
} from '../../generated/prisma/client.js';
import type { Db } from '../audit/types.js';

/** Data access for admin identity. No rules here — the service owns them. */
export class AdminRepository {
  constructor(private readonly prisma: PrismaClient) {}

  findByEmail(email: string): Promise<AdminUser | null> {
    return this.prisma.adminUser.findUnique({ where: { email } });
  }

  findById(id: string): Promise<AdminUser | null> {
    return this.prisma.adminUser.findUnique({ where: { id } });
  }

  create(
    db: Db,
    data: { email: string; passwordHash: string; createdAt: Date },
  ): Promise<AdminUser> {
    return db.adminUser.create({ data: { ...data, passwordChangedAt: data.createdAt } });
  }

  createSession(
    db: Db,
    data: {
      adminId: string;
      tokenHash: string;
      now: Date;
      expiresAt: Date;
      ipAddress: string;
      userAgent: string;
    },
  ): Promise<AdminSession> {
    return db.adminSession.create({
      data: {
        adminId: data.adminId,
        tokenHash: data.tokenHash,
        createdAt: data.now,
        lastSeenAt: data.now,
        expiresAt: data.expiresAt,
        ipAddress: data.ipAddress,
        userAgent: data.userAgent,
      },
    });
  }

  findSessionByTokenHash(tokenHash: string): Promise<(AdminSession & { admin: AdminUser }) | null> {
    return this.prisma.adminSession.findUnique({ where: { tokenHash }, include: { admin: true } });
  }

  findSession(adminId: string, sessionId: string): Promise<AdminSession | null> {
    return this.prisma.adminSession.findFirst({
      where: { id: sessionId, adminId, revokedAt: null },
    });
  }

  listActiveSessions(adminId: string, now: Date): Promise<AdminSession[]> {
    return this.prisma.adminSession.findMany({
      where: { adminId, revokedAt: null, expiresAt: { gt: now } },
      orderBy: { lastSeenAt: 'desc' },
    });
  }

  touchSession(sessionId: string, now: Date): Promise<AdminSession> {
    return this.prisma.adminSession.update({ where: { id: sessionId }, data: { lastSeenAt: now } });
  }

  revokeSession(
    db: Db,
    sessionId: string,
    now: Date,
    reason: SessionRevokedReason,
  ): Promise<AdminSession> {
    return db.adminSession.update({
      where: { id: sessionId },
      data: { revokedAt: now, revokedReason: reason },
    });
  }
}
