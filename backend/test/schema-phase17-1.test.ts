import { beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

/**
 * What the migration has to guarantee about §Phase 17.1's tables, asserted
 * against `information_schema` rather than against the Prisma schema file —
 * the file is what we wrote, the catalogue is what the database has.
 *
 * The listings suite established this pattern for §1a's "no `lifecycle_status`
 * anywhere" rule. This is the same idea for the rule §1c states most sharply:
 * **no booking table holds a phone number**, so no future DTO can select one
 * by accident.
 */
describe.skipIf(databaseUrl === undefined)('Phase 17.1 — schema', () => {
  let prisma: PrismaClient;

  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });

  const BOOKING_TABLES = ['booking', 'booking_status_event', 'booking_amendment', 'report'];

  it('holds no contact-shaped column on any booking table', async () => {
    const rows = await prisma.$queryRaw<{ table_name: string; column_name: string }[]>`
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = ANY(${BOOKING_TABLES})
        AND (
          column_name ILIKE '%phone%'
          OR column_name ILIKE '%whatsapp%'
          OR column_name ILIKE '%viber%'
          OR column_name ILIKE '%msisdn%'
        )
    `;
    expect(rows).toEqual([]);
  });

  it('keys the booking location on an island id and never on a name', async () => {
    const rows = await prisma.$queryRaw<{ column_name: string }[]>`
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'booking'
        AND column_name ILIKE '%island%'
    `;
    // §0.0 item 12: fifteen names repeat across atolls and `Meedhoo` exists in
    // three, so a booking keyed on a name is a booking at one of three places.
    expect(rows.map((r) => r.column_name)).toEqual(['island_id']);
  });

  it('stores every amount as an integer, never a numeric or a float', async () => {
    const rows = await prisma.$queryRaw<{ column_name: string; data_type: string }[]>`
      SELECT column_name, data_type FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name IN ('booking', 'booking_amendment')
        AND column_name LIKE '%laari%'
    `;
    // Three on the booking — agreed, quoted, final — and two on the
    // amendment, which carries the previous amount beside the proposed one.
    expect(rows.map((r) => r.column_name).sort()).toEqual([
      'agreed_amount_laari',
      'final_amount_laari',
      'previous_amount_laari',
      'proposed_amount_laari',
      'quoted_amount_laari',
    ]);
    for (const row of rows) expect(row.data_type).toBe('integer');
  });

  it('carries every status §1c names, including the three later slices reach', async () => {
    const rows = await prisma.$queryRaw<{ label: string }[]>`
      SELECT e.enumlabel AS label
      FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE t.typname = 'booking_status'
      ORDER BY e.enumsortorder
    `;
    expect(rows.map((r) => r.label)).toEqual([
      'requested',
      'awaiting_quote',
      'quote_offered',
      'emergency_offered',
      'accepted',
      'awaiting_payment',
      'payment_claimed',
      'confirmed',
      'completed',
      'cancelled',
      'declined',
      'disputed',
      'dispute_resolved',
      'payment_unresolved',
    ]);
  });

  it('enumerates the dispute outcome rather than leaving it free text', async () => {
    const rows = await prisma.$queryRaw<{ label: string }[]>`
      SELECT e.enumlabel AS label
      FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE t.typname = 'dispute_outcome'
      ORDER BY e.enumsortorder
    `;
    // §1c: "v3 recorded 'an outcome' with no enumeration, which would have
    // produced an unstructured audit log you could not measure fairness
    // against."
    expect(rows.map((r) => r.label)).toEqual([
      'resolved_for_customer',
      'resolved_for_provider',
      'inconclusive',
      'fraud_confirmed',
      'withdrawn',
    ]);
  });

  it('gives a booking a unique reference and a unique hold on one slot', async () => {
    const rows = await prisma.$queryRaw<{ indexname: string }[]>`
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'booking'
    `;
    const names = rows.map((r) => r.indexname);
    expect(names).toContain('booking_reference_key');
    // One booking per slot, and one per reservation: the hard guarantee is
    // still §Phase 9a's exclusion constraint, and these stop a second booking
    // pointing at a hold that is already somebody's.
    expect(names).toContain('booking_time_slot_id_key');
    expect(names).toContain('booking_reservation_id_key');
  });

  it('still has §Phase 9a’s provider-scoped exclusion constraint, untouched', async () => {
    const rows = await prisma.$queryRaw<{ conname: string }[]>`
      SELECT conname FROM pg_constraint WHERE conname = 'reservation_provider_no_overlap'
    `;
    // §Phase 17.1 books through it; it must not have been replaced by a
    // UNIQUE on (providerId, listingId, startsAt), which root CLAUDE.md
    // rejects and which this phase would have been the one to break.
    expect(rows).toHaveLength(1);
  });
});
