import { z } from 'zod';

import { deviceName } from '../auth/schema.js';

/**
 * A stable per-installation identifier the app generates once and keeps. It is
 * NOT the device token: the token rotates and this does not, which is what
 * lets a refresh update the existing registration instead of accumulating a
 * dead row per rotation.
 */
const installationId = z.string().trim().min(8).max(128);

/**
 * The vendor token. Both FCM and APNs tokens are long opaque strings; the
 * bound is a sanity limit, not a format claim — pinning a shape here would
 * break the day a vendor lengthens theirs.
 */
const deviceToken = z.string().trim().min(16).max(4096);

export const permissionField = z.enum(['unknown', 'granted', 'denied']);

export const registerDeviceBody = z.object({
  installationId,
  platform: z.enum(['android', 'ios']),
  token: deviceToken,
  deviceName,
  /**
   * Optional: the app reports the OS answer alongside the registration it
   * just managed to make. A registration existing at all implies permission
   * was granted, but sending it explicitly keeps the two facts independent.
   */
  permission: permissionField.optional(),
});

export const permissionBody = z.object({ permission: permissionField });

export const installationParams = z.object({ installationId });

export const dispatchParams = z.object({ dispatchId: z.uuid() });

export const ackBody = z.object({
  /** Which device received it, when the app knows. Optional so an ack is never lost to a missing field. */
  installationId: installationId.optional(),
});
