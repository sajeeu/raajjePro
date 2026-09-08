import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 3 schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  const user = (email: string, phone: string | null) => ({
    email,
    passwordHash: 'x',
    fullName: 'Test',
    phoneE164: phone,
    phoneDialCode: phone === null ? null : '+960',
    termsAcceptedAt: new Date(),
  });

  it('email is unique at the database; phone is not (uniqueness begins at Bronze, §0.0 item 8a)', async () => {
    const email = `u-${randomUUID()}@example.test`;
    const phone = `+960${String(Math.floor(Math.random() * 9_000_000) + 1_000_000)}`;
    await prisma.user.create({ data: user(email, phone) });
    await expect(prisma.user.create({ data: user(email, null) })).rejects.toThrow();
    await expect(
      prisma.user.create({ data: user(`u-${randomUUID()}@example.test`, phone) }),
    ).resolves.toBeDefined();
  });

  it('a provider profile defaults to tier none and status unverified, one per user', async () => {
    const u = await prisma.user.create({ data: user(`u-${randomUUID()}@example.test`, null) });
    const profile = await prisma.providerProfile.create({ data: { userId: u.id } });
    expect(profile.verificationTier).toBe('none');
    expect(profile.verificationStatus).toBe('unverified');
    await expect(prisma.providerProfile.create({ data: { userId: u.id } })).rejects.toThrow();
  });

  it('the audit actor type accepts user', async () => {
    const row = await prisma.auditLogEntry.create({
      data: {
        actorType: 'user',
        actorId: randomUUID(),
        action: 'test.user_actor',
        targetType: 'test',
        targetId: randomUUID(),
        reason: 'schema test',
      },
    });
    expect(row.actorType).toBe('user');
  });
});
