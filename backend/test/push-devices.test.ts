/**
 * §Phase 3c: "device token registration, refresh, and multi-device support",
 * and the Done-when clause "multi-device registration and cleanup work".
 */
import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';

import { buildTestApp, databaseUrl, freshIp, RecordingPushTransport } from './helpers/app.js';
import { bearer, createUser, registerUser } from './helpers/users.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import type { NotificationContext } from '../src/modules/push/types.js';

const describeIfDb = databaseUrl === undefined ? describe.skip : describe;

const context: NotificationContext = {
  kind: 'booking_accept_prompt',
  bookingType: 'Plumbing',
  customerFirstName: 'Hawwa',
  islandName: 'Fuvahmulah',
};

describeIfDb('Phase 3c — device registration, refresh, multi-device and cleanup', () => {
  let app: FastifyInstance;
  let prisma: PrismaClient;
  let push: RecordingPushTransport;

  beforeAll(async () => {
    push = new RecordingPushTransport();
    ({ app, prisma } = await buildTestApp({ deps: { pushTransport: push } }));
  });
  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  function body(overrides: Record<string, unknown> = {}) {
    return {
      installationId: `inst-${randomUUID()}`,
      platform: 'android',
      token: `tok-${randomUUID()}`,
      deviceName: 'Pixel 8',
      ...overrides,
    };
  }

  async function signedIn() {
    const registered = await registerUser(app);
    return registered;
  }

  it('registers a device and reports permission granted on the user', async () => {
    const user = await signedIn();
    const payload = body();

    const res = await app.inject({
      method: 'POST',
      url: '/v1/push/devices',
      headers: { ...bearer(user.tokens.accessToken), 'x-forwarded-for': freshIp() },
      payload,
    });

    expect(res.statusCode).toBe(200);
    const row = await prisma.deviceToken.findFirstOrThrow({ where: { userId: user.userId } });
    expect(row.token).toBe(payload.token);
    expect(row.revokedAt).toBeNull();
    const account = await prisma.user.findUniqueOrThrow({ where: { id: user.userId } });
    expect(account.pushPermission).toBe('granted');
    expect(account.pushPermissionUpdatedAt).not.toBeNull();
  });

  it('a token refresh updates the SAME registration — the install is the identity, not the token', async () => {
    const user = await signedIn();
    const installationId = `inst-${randomUUID()}`;
    const first = body({ installationId });
    const second = body({ installationId, token: `tok-${randomUUID()}` });

    for (const payload of [first, second]) {
      const res = await app.inject({
        method: 'POST',
        url: '/v1/push/devices',
        headers: { ...bearer(user.tokens.accessToken), 'x-forwarded-for': freshIp() },
        payload,
      });
      expect(res.statusCode).toBe(200);
    }

    const rows = await prisma.deviceToken.findMany({ where: { userId: user.userId } });
    // One row, not two: a rotation must not leave a dead registration behind
    // that the sender would then try to deliver to on every notification.
    expect(rows).toHaveLength(1);
    expect(rows[0]?.token).toBe(second.token);
  });

  it('multi-device: one notification fans out to every live registration', async () => {
    const user = await createUser(prisma, { emailVerified: true });
    const tokens = [`tok-${randomUUID()}`, `tok-${randomUUID()}`, `tok-${randomUUID()}`];
    for (const token of tokens) {
      await prisma.deviceToken.create({
        data: {
          userId: user.id,
          installationId: `inst-${randomUUID()}`,
          platform: token === tokens[0] ? 'ios' : 'android',
          token,
          deviceName: 'A device',
          lastSeenAt: new Date(),
        },
      });
    }

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context,
    });

    expect(result.pushAttempted).toBe(3);
    expect(result.pushSent).toBe(3);
    for (const token of tokens) expect(push.tokens()).toContain(token);
    const deliveries = await prisma.pushDelivery.findMany({
      where: { dispatchId: result.dispatchId },
    });
    expect(deliveries).toHaveLength(3);
  });

  it('cleanup: a vendor reporting a dead token revokes that registration and only that one', async () => {
    const user = await createUser(prisma, { emailVerified: true });
    const dead = `tok-${randomUUID()}`;
    const alive = `tok-${randomUUID()}`;
    for (const token of [dead, alive]) {
      await prisma.deviceToken.create({
        data: {
          userId: user.id,
          installationId: `inst-${randomUUID()}`,
          platform: 'android',
          token,
          deviceName: 'A device',
          lastSeenAt: new Date(),
        },
      });
    }
    push.unregisterFor.add(dead);

    const result = await app.notifications.dispatch({
      userId: user.id,
      urgency: 'standard',
      context,
    });
    expect(result.pushAttempted).toBe(2);
    expect(result.pushSent).toBe(1);

    const rows = await prisma.deviceToken.findMany({ where: { userId: user.id } });
    const deadRow = rows.find((r) => r.token === dead);
    const aliveRow = rows.find((r) => r.token === alive);
    expect(deadRow?.revokedAt).not.toBeNull();
    expect(deadRow?.revokedReason).toBe('unregistered');
    expect(aliveRow?.revokedAt).toBeNull();

    // Soft, never hard (invariant 8): the row is still there.
    expect(rows).toHaveLength(2);
    push.unregisterFor.delete(dead);
  });

  it('a device handed to another account stops delivering to the previous owner', async () => {
    const token = `tok-${randomUUID()}`;
    const installationId = `inst-${randomUUID()}`;
    const previous = await signedIn();
    const next = await signedIn();

    for (const user of [previous, next]) {
      const res = await app.inject({
        method: 'POST',
        url: '/v1/push/devices',
        headers: { ...bearer(user.tokens.accessToken), 'x-forwarded-for': freshIp() },
        payload: body({ installationId, token }),
      });
      expect(res.statusCode).toBe(200);
    }

    const old = await prisma.deviceToken.findFirstOrThrow({ where: { userId: previous.userId } });
    expect(old.revokedAt).not.toBeNull();
    expect(old.revokedReason).toBe('claimed_by_another_account');
    const current = await prisma.deviceToken.findFirstOrThrow({ where: { userId: next.userId } });
    expect(current.revokedAt).toBeNull();

    // And the previous owner receives nothing.
    const result = await app.notifications.dispatch({
      userId: previous.userId,
      urgency: 'standard',
      context,
    });
    expect(result.pushAttempted).toBe(0);
  });

  it('unregistering soft-revokes, and only the owner may do it', async () => {
    const owner = await signedIn();
    const stranger = await signedIn();
    const payload = body();
    await app.inject({
      method: 'POST',
      url: '/v1/push/devices',
      headers: { ...bearer(owner.tokens.accessToken), 'x-forwarded-for': freshIp() },
      payload,
    });

    // The wrong user gets a 404, not someone else's device revoked.
    const wrong = await app.inject({
      method: 'DELETE',
      url: `/v1/push/devices/${payload.installationId}`,
      headers: { ...bearer(stranger.tokens.accessToken), 'x-forwarded-for': freshIp() },
    });
    expect(wrong.statusCode).toBe(404);
    const stillLive = await prisma.deviceToken.findFirstOrThrow({
      where: { userId: owner.userId },
    });
    expect(stillLive.revokedAt).toBeNull();

    const res = await app.inject({
      method: 'DELETE',
      url: `/v1/push/devices/${payload.installationId}`,
      headers: { ...bearer(owner.tokens.accessToken), 'x-forwarded-for': freshIp() },
    });
    expect(res.statusCode).toBe(200);
    const revoked = await prisma.deviceToken.findFirstOrThrow({ where: { userId: owner.userId } });
    expect(revoked.revokedReason).toBe('signed_out');
  });

  it('every device route rejects an anonymous caller', async () => {
    const calls = [
      { method: 'POST' as const, url: '/v1/push/devices', payload: body() },
      { method: 'GET' as const, url: '/v1/push/devices' },
      { method: 'DELETE' as const, url: '/v1/push/devices/inst-anything-here' },
      { method: 'POST' as const, url: '/v1/push/permission', payload: { permission: 'denied' } },
      {
        method: 'POST' as const,
        url: `/v1/push/dispatches/${randomUUID()}/ack`,
        payload: {},
      },
    ];
    for (const call of calls) {
      const res = await app.inject({ ...call, headers: { 'x-forwarded-for': freshIp() } });
      expect(res.statusCode, `${call.method} ${call.url}`).toBe(401);
    }
  });

  it('one user cannot acknowledge another user’s notification and suppress their email', async () => {
    const owner = await createUser(prisma, { emailVerified: true });
    const stranger = await signedIn();
    await prisma.deviceToken.create({
      data: {
        userId: owner.id,
        installationId: `inst-${randomUUID()}`,
        platform: 'android',
        token: `tok-${randomUUID()}`,
        deviceName: 'Pixel',
        lastSeenAt: new Date(),
      },
    });
    const dispatch = await app.notifications.dispatch({
      userId: owner.id,
      urgency: 'standard',
      context,
    });

    const res = await app.inject({
      method: 'POST',
      url: `/v1/push/dispatches/${dispatch.dispatchId}/ack`,
      headers: { ...bearer(stranger.tokens.accessToken), 'x-forwarded-for': freshIp() },
      payload: {},
    });
    expect(res.statusCode).toBe(404);
    const row = await prisma.pushDispatch.findUniqueOrThrow({
      where: { id: dispatch.dispatchId },
    });
    expect(row.confirmedAt).toBeNull();
    expect(row.fallbackDueAt).not.toBeNull();
  });

  it('no device route returns a phone number, at any depth', async () => {
    const user = await signedIn();
    const payload = body();
    const created = await app.inject({
      method: 'POST',
      url: '/v1/push/devices',
      headers: { ...bearer(user.tokens.accessToken), 'x-forwarded-for': freshIp() },
      payload,
    });
    const listed = await app.inject({
      method: 'GET',
      url: '/v1/push/devices',
      headers: { ...bearer(user.tokens.accessToken), 'x-forwarded-for': freshIp() },
    });
    for (const res of [created, listed]) {
      expect(res.body).not.toContain('+960');
      // Nor the raw vendor token, which is a device credential of its own.
      expect(res.body).not.toContain(payload.token);
    }
  });
});
