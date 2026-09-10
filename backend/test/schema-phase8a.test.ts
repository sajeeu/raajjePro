import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

/**
 * The Phase 8a schema, asserted where the guarantee is the column rather than
 * the code: integer money, the uniqueness the reference code and the invoice
 * number depend on, and the fact that a payer is a `User`.
 */
describe.skipIf(databaseUrl === undefined)('phase 8a schema', () => {
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

  const code = () =>
    `RP-${randomUUID().slice(0, 4).toUpperCase()}-${randomUUID().slice(0, 4).toUpperCase()}`;

  it('every money column is an integer — laari, never a float (invariant 7)', async () => {
    const columns = await prisma.$queryRaw<{ table_name: string; data_type: string }[]>`
      SELECT table_name, data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'amount_laari'
      ORDER BY table_name
    `;
    expect(columns).toEqual([
      { table_name: 'invoice', data_type: 'integer' },
      { table_name: 'payment_submission', data_type: 'integer' },
    ]);
  });

  it('a payer is a user, not a provider — the dispatch fee is paid by a customer', async () => {
    // §Phase 8a's entity is "generic": `purpose` has two values and §1c's MVR
    // 200 emergency dispatch fee is charged to a **customer**. A foreign key
    // to `provider_profile` here would make that unrepresentable, so the
    // subscription-specific check (that the payer *has* a provider profile)
    // lives in the confirming code instead.
    const [fk] = await prisma.$queryRaw<{ foreign_table: string }[]>`
      SELECT ccu.table_name AS foreign_table
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON kcu.constraint_name = tc.constraint_name
      JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
      WHERE tc.table_name = 'payment_submission'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'payer_id'
    `;
    expect(fk?.foreign_table).toBe('app_user');

    // And a customer with no provider profile can hold one, which is what
    // §Phase 17.3 will need.
    const customer = await freshUser();
    const row = await prisma.paymentSubmission.create({
      data: {
        payerId: customer.id,
        purpose: 'emergency_dispatch_fee',
        amountLaari: 20_000,
        referenceCode: code(),
      },
    });
    expect(row.status).toBe('pending');
    // §1b step 1–3: the row exists from the intent, and `submittedAt` is what
    // says a provider actually submitted proof.
    expect(row.submittedAt).toBeNull();
    expect(row.proofObjectKey).toBeNull();
  });

  it('refuses two submissions sharing a reference code', async () => {
    // The code is what an admin matches a bank-statement row against
    // (§Phase 10a's CSV importer treats it as an identifier), so two
    // submissions carrying one code would make a transfer unattributable.
    const user = await freshUser();
    const shared = code();
    await prisma.paymentSubmission.create({
      data: {
        payerId: user.id,
        purpose: 'subscription',
        amountLaari: 15_000,
        referenceCode: shared,
      },
    });
    await expect(
      prisma.paymentSubmission.create({
        data: {
          payerId: user.id,
          purpose: 'subscription',
          amountLaari: 15_000,
          referenceCode: shared,
        },
      }),
    ).rejects.toThrow();
  });

  it('refuses a second subscription row for one provider', async () => {
    const user = await freshUser();
    const profile = await prisma.providerProfile.create({ data: { userId: user.id } });
    await prisma.providerSubscription.create({ data: { providerProfileId: profile.id } });
    await expect(
      prisma.providerSubscription.create({ data: { providerProfileId: profile.id } }),
    ).rejects.toThrow();
  });

  it('defaults a new subscription row to the free tier with a full pause allowance', async () => {
    // An absent row and a fresh row are the same answer — §1b's free tier —
    // which is what lets the trial prompt create a row for a provider it has
    // merely nudged without changing anything about their entitlements.
    const user = await freshUser();
    const profile = await prisma.providerProfile.create({ data: { userId: user.id } });
    const row = await prisma.providerSubscription.create({
      data: { providerProfileId: profile.id },
    });
    expect(row.tier).toBe('free');
    expect(row.status).toBe('free');
    expect(row.cumulativePausedMinutes).toBe(0);
    expect(row.trialStartedAt).toBeNull();
    expect(row.billingAnchorAt).toBeNull();
  });

  it('issues invoice numbers from a sequence, so two at once cannot collide', async () => {
    // A count of existing rows races under concurrent confirmations and would
    // issue two invoices the same number. Gaps are acceptable; collisions are
    // not.
    const numbers = await Promise.all(
      Array.from({ length: 20 }, async () => {
        const [row] = await prisma.$queryRaw<
          { nextval: bigint }[]
        >`SELECT nextval('invoice_number_seq') AS nextval`;
        return String(row?.nextval);
      }),
    );
    expect(new Set(numbers).size).toBe(20);
  });

  it('keeps one invoice per confirmed submission', async () => {
    const user = await freshUser();
    const profile = await prisma.providerProfile.create({ data: { userId: user.id } });
    const submission = await prisma.paymentSubmission.create({
      data: {
        payerId: user.id,
        purpose: 'subscription',
        amountLaari: 15_000,
        referenceCode: code(),
      },
    });
    const base = {
      providerProfileId: profile.id,
      paymentSubmissionId: submission.id,
      amountLaari: 15_000,
      periodStart: new Date(),
      periodEnd: new Date(),
      issuedAt: new Date(),
    };
    await prisma.invoice.create({
      data: { ...base, invoiceNumber: `RP-${randomUUID().slice(0, 8)}`, objectKey: randomUUID() },
    });
    await expect(
      prisma.invoice.create({
        data: { ...base, invoiceNumber: `RP-${randomUUID().slice(0, 8)}`, objectKey: randomUUID() },
      }),
    ).rejects.toThrow();
  });
});
