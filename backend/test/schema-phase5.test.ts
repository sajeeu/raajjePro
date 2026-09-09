import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

describe.skipIf(databaseUrl === undefined)('phase 5 schema', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  const freshUser = () =>
    prisma.user.create({
      data: {
        email: `u-${randomUUID()}@example.test`,
        passwordHash: 'x',
        fullName: 'Test',
        termsAcceptedAt: new Date(),
      },
    });

  it('a profile is creatable with nothing but a user — Phase 3 rows stay valid without a backfill', async () => {
    const user = await freshUser();
    const profile = await prisma.providerProfile.create({ data: { userId: user.id } });
    expect(profile.bio).toBeNull();
    expect(profile.bankAccountNumber).toBeNull();
    expect(profile.subscriptionPriceLaari).toBeNull();
    expect(profile.suspendedAt).toBeNull();
    // §1g: absent, not false.
    expect(profile.maldivianOwned).toBeNull();
    // §Phase 5: the toggle defaults on.
    expect(profile.acceptingNewCustomers).toBe(true);
  });

  it('the bio column is capped at 160 characters at the database as well as in Zod', async () => {
    const user = await freshUser();
    await expect(
      prisma.providerProfile.create({ data: { userId: user.id, bio: 'x'.repeat(161) } }),
    ).rejects.toThrow();
  });

  it('subscriptionPriceLaari is an integer column — money is laari, never a float (invariant 7)', async () => {
    const user = await freshUser();
    // MVR 150 = 15000 laari; MVR 75 = 7500. Stored as integers, so no
    // rounding exists to go wrong on renewal.
    const profile = await prisma.providerProfile.create({
      data: { userId: user.id, subscriptionPriceLaari: 7500 },
    });
    expect(profile.subscriptionPriceLaari).toBe(7500);
    expect(Number.isInteger(profile.subscriptionPriceLaari)).toBe(true);
    const [column] = await prisma.$queryRaw<{ data_type: string }[]>`
      SELECT data_type FROM information_schema.columns
      WHERE table_name = 'provider_profile' AND column_name = 'subscription_price_laari'
    `;
    expect(column?.data_type).toBe('integer');
  });

  it('has no phone column — §Phase 5 keeps exactly one copy, on the user row', async () => {
    const columns = await prisma.$queryRaw<{ column_name: string }[]>`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'provider_profile'
    `;
    const names = columns.map((c) => c.column_name);
    for (const forbidden of ['phone', 'phone_e164', 'whatsapp', 'viber', 'mobile']) {
      expect(names).not.toContain(forbidden);
    }
    // §0.2 item 2 and §1c: WhatsApp and Viber handles are not collected
    // anywhere in this system, at all, so nothing can reveal them.
    expect(names.some((n) => n.includes('whatsapp') || n.includes('viber'))).toBe(false);
  });
});
