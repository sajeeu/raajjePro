import type { Clock } from '../../core/clock.js';
import { NotFoundError } from '../../core/errors.js';
import type { DeviceToken, PrismaClient } from '../../generated/prisma/client.js';
import type { PushPermission } from '../../generated/prisma/enums.js';
import { cleanDeviceName } from '../auth/service.js';
import type { DeviceTokenRepository, RegisterDeviceInput } from './repository.js';

/** What a device registration looks like to its owner. The raw token never leaves the server. */
export interface DeviceDto {
  installationId: string;
  platform: string;
  deviceName: string;
  lastSeenAt: string;
  createdAt: string;
}

export function deviceDto(row: DeviceToken): DeviceDto {
  return {
    installationId: row.installationId,
    platform: row.platform,
    deviceName: row.deviceName,
    lastSeenAt: row.lastSeenAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
  };
}

/**
 * Registration, permission state and delivery acknowledgement — the app-facing
 * half of §Phase 3c. The send side is `PushService`; the rungs are
 * `NotificationDispatcher`.
 */
export class PushRegistrationService {
  constructor(
    private readonly deps: {
      prisma: PrismaClient;
      devices: DeviceTokenRepository;
      clock: Clock;
    },
  ) {}

  async register(
    input: Omit<RegisterDeviceInput, 'deviceName'> & {
      deviceName: string | undefined;
      permission?: PushPermission | undefined;
    },
  ): Promise<DeviceDto> {
    const row = await this.deps.devices.register({
      userId: input.userId,
      installationId: input.installationId,
      platform: input.platform,
      token: input.token,
      deviceName: cleanDeviceName(input.deviceName),
    });
    // A device that produced a token has permission, whatever the app said —
    // but only ever upgrade from this direction. If the app explicitly
    // reported `denied` while still holding a token (iOS provisional
    // authorisation does exactly this), that report is the truthful one and
    // the immediate-email rung is the safe reading.
    await this.setPermission(input.userId, input.permission ?? 'granted');
    return deviceDto(row);
  }

  async listDevices(userId: string): Promise<DeviceDto[]> {
    const rows = await this.deps.devices.liveFor(userId);
    return rows.map(deviceDto);
  }

  /** Sign-out or an explicit "forget this device". 404 when the caller does not own it. */
  async unregister(userId: string, installationId: string): Promise<void> {
    const count = await this.deps.devices.revoke(userId, installationId, 'signed_out');
    if (count === 0) throw new NotFoundError('No such device registration');
  }

  /**
   * The OS-level answer, stored on the user (§Phase 3c: "Detect OS-level
   * permission denial and store that state on the user").
   *
   * Note what this is NOT: a setting. There is no in-app toggle for booking
   * notifications and this endpoint is not one — it records what the operating
   * system reported, and the only thing the app can do about a `denied` is
   * show the reminder and send email instead.
   */
  async setPermission(userId: string, permission: PushPermission): Promise<PushPermission> {
    const now = this.deps.clock();
    const user = await this.deps.prisma.user.update({
      where: { id: userId },
      data: { pushPermission: permission, pushPermissionUpdatedAt: now },
      select: { pushPermission: true },
    });
    return user.pushPermission;
  }

  /**
   * A device says the push arrived. This — and nothing the vendor returns —
   * is what "delivery confirmed" means, and it is what stops the 30-minute
   * rung from firing. Clearing `fallbackDueAt` keeps the sweep's partial index
   * proportional to work outstanding.
   *
   * Idempotent: a device that acks twice, or two devices that both received
   * the push, leave the first confirmation time standing.
   */
  async acknowledge(
    userId: string,
    dispatchId: string,
    installationId: string | undefined,
  ): Promise<{ confirmedAt: string }> {
    const now = this.deps.clock();
    const dispatch = await this.deps.prisma.pushDispatch.findFirst({
      where: { id: dispatchId, userId },
      select: { id: true, confirmedAt: true },
    });
    // Scoped to the caller, so one user cannot confirm another's dispatch and
    // silently suppress their fallback email. A miss reads as 404 either way.
    if (dispatch === null) throw new NotFoundError('No such notification');

    const confirmedAt = dispatch.confirmedAt ?? now;
    if (dispatch.confirmedAt === null) {
      await this.deps.prisma.pushDispatch.update({
        where: { id: dispatch.id },
        data: { confirmedAt, fallbackDueAt: null },
      });
    }

    if (installationId !== undefined) {
      const device = await this.deps.prisma.deviceToken.findUnique({
        where: { userId_installationId: { userId, installationId } },
        select: { id: true },
      });
      if (device !== null) {
        await this.deps.prisma.pushDelivery.updateMany({
          where: { dispatchId: dispatch.id, deviceTokenId: device.id, confirmedAt: null },
          data: { status: 'confirmed', confirmedAt },
        });
      }
    }

    return { confirmedAt: confirmedAt.toISOString() };
  }
}
