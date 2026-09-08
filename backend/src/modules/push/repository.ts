import type { Clock } from '../../core/clock.js';
import type { DeviceToken, PrismaClient } from '../../generated/prisma/client.js';
import type { DeviceTokenRevokedReason, PushPlatform } from '../../generated/prisma/enums.js';

export interface RegisterDeviceInput {
  userId: string;
  installationId: string;
  platform: PushPlatform;
  token: string;
  deviceName: string;
}

/**
 * Device registrations. Three rules live here and nowhere else:
 *
 *  1. The INSTALL is the identity; the token is a rotating credential. FCM and
 *     APNs both re-issue a token for the same install (reinstall, restore,
 *     Play Services housekeeping), so a refresh is an UPDATE of the existing
 *     row, not a second row. That is what makes "multi-device" mean "one row
 *     per device" rather than "one row per token this device ever held".
 *  2. One LIVE row per raw token across all accounts, enforced by a partial
 *     unique index in the migration and by `claimToken` below. A phone handed
 *     from one person to another must stop delivering the previous owner's
 *     booking notifications the moment the new owner registers.
 *  3. Nothing is deleted. Sign-out, an uninstall the vendor tells us about,
 *     and anonymisation all set `revokedAt` with a reason.
 */
export class DeviceTokenRepository {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly clock: Clock,
  ) {}

  /** Every live registration for a user, newest first. */
  liveFor(userId: string): Promise<DeviceToken[]> {
    return this.prisma.deviceToken.findMany({
      where: { userId, revokedAt: null },
      orderBy: { lastSeenAt: 'desc' },
    });
  }

  /**
   * Upsert by (user, install). Any OTHER live row holding the same raw token —
   * the previous owner of a handed-on device — is revoked first, in the same
   * transaction, so the partial unique index can never be the thing that
   * fails. Returns the live row.
   */
  async register(input: RegisterDeviceInput): Promise<DeviceToken> {
    const now = this.clock();
    return this.prisma.$transaction(async (tx) => {
      await tx.deviceToken.updateMany({
        where: {
          token: input.token,
          revokedAt: null,
          NOT: { userId: input.userId, installationId: input.installationId },
        },
        data: { revokedAt: now, revokedReason: 'claimed_by_another_account' },
      });
      return tx.deviceToken.upsert({
        where: {
          userId_installationId: {
            userId: input.userId,
            installationId: input.installationId,
          },
        },
        create: {
          userId: input.userId,
          installationId: input.installationId,
          platform: input.platform,
          token: input.token,
          deviceName: input.deviceName,
          lastSeenAt: now,
        },
        // A re-register is also how a revoked install comes back (the user
        // signs in again on the same phone), so revocation is cleared here.
        update: {
          platform: input.platform,
          token: input.token,
          deviceName: input.deviceName,
          lastSeenAt: now,
          revokedAt: null,
          revokedReason: null,
        },
      });
    });
  }

  /** Soft-revoke one install. Idempotent: revoking an already-revoked row changes nothing. */
  async revoke(
    userId: string,
    installationId: string,
    reason: DeviceTokenRevokedReason,
  ): Promise<number> {
    const { count } = await this.prisma.deviceToken.updateMany({
      where: { userId, installationId, revokedAt: null },
      data: { revokedAt: this.clock(), revokedReason: reason },
    });
    return count;
  }

  /** Soft-revoke by row id. Used when the vendor reports a token is dead. */
  async revokeById(id: string, reason: DeviceTokenRevokedReason): Promise<void> {
    await this.prisma.deviceToken.updateMany({
      where: { id, revokedAt: null },
      data: { revokedAt: this.clock(), revokedReason: reason },
    });
  }

  /** Every live registration for a user, revoked at once. Sign-out-everywhere and anonymisation. */
  async revokeAllFor(userId: string, reason: DeviceTokenRevokedReason): Promise<number> {
    const { count } = await this.prisma.deviceToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: this.clock(), revokedReason: reason },
    });
    return count;
  }
}
