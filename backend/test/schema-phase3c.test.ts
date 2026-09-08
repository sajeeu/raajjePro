import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 3c schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  const newUser = () =>
    prisma.user.create({
      data: {
        email: `u-${randomUUID()}@example.test`,
        passwordHash: 'x',
        fullName: 'Test',
        termsAcceptedAt: new Date(),
      },
    });

  const device = (userId: string, token: string) => ({
    userId,
    installationId: `inst-${randomUUID()}`,
    platform: 'android' as const,
    token,
    deviceName: 'Test device',
    lastSeenAt: new Date(),
  });

  it('push permission defaults to unknown — never asked is not the same as refused', async () => {
    const user = await newUser();
    expect(user.pushPermission).toBe('unknown');
    expect(user.pushPermissionUpdatedAt).toBeNull();
  });

  it('the partial unique index allows one LIVE row per raw token and any number of revoked ones', async () => {
    // Hand-written in the migration; Prisma does not model partial uniques, so
    // a regenerated migration would silently drop it. This is the guard.
    const a = await newUser();
    const b = await newUser();
    const token = `tok-${randomUUID()}`;

    const first = await prisma.deviceToken.create({ data: device(a.id, token) });
    await expect(prisma.deviceToken.create({ data: device(b.id, token) })).rejects.toThrow();

    await prisma.deviceToken.update({
      where: { id: first.id },
      data: { revokedAt: new Date(), revokedReason: 'signed_out' },
    });
    // Once the first is revoked the token is claimable again, and the revoked
    // row stays as history (invariant 8).
    await expect(prisma.deviceToken.create({ data: device(b.id, token) })).resolves.toBeDefined();
    expect(await prisma.deviceToken.count({ where: { token } })).toBe(2);
  });

  it('one registration per (user, install), so a token refresh cannot fork into two rows', async () => {
    const user = await newUser();
    const installationId = `inst-${randomUUID()}`;
    await prisma.deviceToken.create({
      data: { ...device(user.id, `tok-${randomUUID()}`), installationId },
    });
    await expect(
      prisma.deviceToken.create({
        data: { ...device(user.id, `tok-${randomUUID()}`), installationId },
      }),
    ).rejects.toThrow();
  });

  it('the sweep’s partial index exists and is scoped to work outstanding', async () => {
    const rows = await prisma.$queryRaw<{ indexdef: string }[]>`
      SELECT indexdef FROM pg_indexes
      WHERE tablename = 'push_dispatch' AND indexname = 'push_dispatch_fallback_pending_idx'
    `;
    expect(rows).toHaveLength(1);
    expect(rows[0]?.indexdef).toContain('email_sent_at IS NULL');
  });

  it('a dispatch subject is not a foreign key — Phase 17 owns bookings and does not exist yet', async () => {
    const user = await newUser();
    const dispatch = await prisma.pushDispatch.create({
      data: {
        userId: user.id,
        kind: 'booking_accept_prompt',
        urgency: 'standard',
        subjectId: randomUUID(),
        context: { bookingType: 'Cleaning', customerFirstName: 'A', islandName: 'Malé' },
      },
    });
    expect(dispatch.subjectId).not.toBeNull();
  });
});
