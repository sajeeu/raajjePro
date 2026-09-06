import type {
  AdminRecoveryCode,
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

  /** `updateMany` scoped to `revokedAt: null` so a concurrent revoke can never be clobbered back to live by a racing touch; the caller does not need the row back. */
  touchSession(sessionId: string, now: Date): Promise<{ count: number }> {
    return this.prisma.adminSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { lastSeenAt: now },
    });
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

  setPendingTotpSecret(adminId: string, encrypted: string): Promise<AdminUser> {
    return this.prisma.adminUser.update({
      where: { id: adminId },
      data: { totpSecretEncrypted: encrypted },
    });
  }

  async markEnrolled(db: Db, adminId: string, sessionId: string, now: Date): Promise<void> {
    await db.adminUser.update({ where: { id: adminId }, data: { totpEnrolledAt: now } });
    await db.adminSession.update({
      where: { id: sessionId },
      data: { mfaVerifiedAt: now, mfaFailures: 0 },
    });
  }

  markMfaVerified(db: Db, sessionId: string, now: Date): Promise<AdminSession> {
    return db.adminSession.update({
      where: { id: sessionId },
      data: { mfaVerifiedAt: now, mfaFailures: 0 },
    });
  }

  incrementMfaFailures(sessionId: string): Promise<AdminSession> {
    return this.prisma.adminSession.update({
      where: { id: sessionId },
      data: { mfaFailures: { increment: 1 } },
    });
  }

  markReauthenticated(sessionId: string, now: Date): Promise<AdminSession> {
    return this.prisma.adminSession.update({
      where: { id: sessionId },
      data: { reauthenticatedAt: now },
    });
  }

  async replaceRecoveryCodes(db: Db, adminId: string, hashes: string[], now: Date): Promise<void> {
    await db.adminRecoveryCode.updateMany({
      where: { adminId, usedAt: null, revokedAt: null },
      data: { revokedAt: now },
    });
    await db.adminRecoveryCode.createMany({
      data: hashes.map((codeHash) => ({ adminId, codeHash, createdAt: now })),
    });
  }

  findUnusedRecoveryCode(adminId: string, codeHash: string): Promise<AdminRecoveryCode | null> {
    return this.prisma.adminRecoveryCode.findFirst({
      where: { adminId, codeHash, usedAt: null, revokedAt: null },
    });
  }

  /** `updateMany` scoped to `usedAt: null` so two concurrent verifications racing on the same recovery code can never both win — returns the affected-row count so the caller can tell a lost race (0) from the normal single-use case (1) instead of trusting a prior read. */
  markRecoveryCodeUsed(db: Db, id: string, now: Date): Promise<{ count: number }> {
    return db.adminRecoveryCode.updateMany({
      where: { id, usedAt: null },
      data: { usedAt: now },
    });
  }
}
