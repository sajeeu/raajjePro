import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import type { PrismaClient } from '../src/generated/prisma/client.js';
import { databaseUrl } from './helpers/app.js';

/**
 * The Phase 9a schema, asserted where the guarantee is **the database** rather
 * than the code.
 *
 * The exclusion constraint is the one thing in this phase that application
 * code cannot be trusted with: §Phase 9a calls it "the hard guarantee against
 * double-booking", and a guarantee that lives in a service method is one a
 * future caller can route around. So it is asserted here against
 * `pg_constraint` — which also means a later `prisma migrate dev` that
 * regenerated the migration without the hand-written section would fail a
 * test rather than quietly ship a marketplace that can double-book.
 */
describe.skipIf(databaseUrl === undefined)('phase 9a schema', () => {
  let prisma: PrismaClient;

  beforeAll(() => {
    prisma = createPrismaClient(databaseUrl ?? '');
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('has `btree_gist` installed — without it the constraint cannot exist at all', async () => {
    const rows = await prisma.$queryRaw<{ extname: string }[]>`
      SELECT extname FROM pg_extension WHERE extname = 'btree_gist'`;
    expect(rows).toHaveLength(1);
  });

  it('guards overlaps with a provider-scoped, range-based EXCLUDE, not a UNIQUE', async () => {
    const [row] = await prisma.$queryRaw<{ definition: string; contype: string }[]>`
      SELECT pg_get_constraintdef(oid) AS definition, contype::text AS contype
      FROM pg_constraint
      WHERE conrelid = 'reservation'::regclass AND conname = 'reservation_provider_no_overlap'`;

    expect(row).toBeDefined();
    // `x` is an exclusion constraint. A `u` here would mean somebody replaced
    // it with the UNIQUE that §Phase 9a and root CLAUDE.md both reject.
    expect(row?.contype).toBe('x');
    expect(row?.definition).toContain('EXCLUDE USING gist');
    // Scoped to the PROVIDER, so one person cannot be booked twice at 10:00
    // across two listings…
    expect(row?.definition).toContain('provider_profile_id WITH =');
    // …and compared as a RANGE, so overlapping durations are caught and not
    // only identical start times.
    expect(row?.definition).toContain('tstzrange(starts_at, ends_at) WITH &&');
    // And only while the reservation is held — without this predicate a
    // cancelled booking's time could never be booked again (invariant 8 keeps
    // the row forever).
    expect(row?.definition).toContain('released_at IS NULL');
    // It says nothing about the listing. A listing-scoped guard is the bug
    // this constraint exists to fix.
    expect(row?.definition).not.toContain('listing_id');
  });

  it('carries no `UNIQUE (provider, listing, startsAt)` anywhere — the constraint v2/v3 had', async () => {
    // Prisma expresses `@@unique` as a unique INDEX rather than a table
    // constraint, so this reads `pg_indexes` — checking `pg_constraint` alone
    // would report "no such uniqueness" while the index sat right there.
    const rows = await prisma.$queryRaw<{ indexname: string; indexdef: string }[]>`
      SELECT indexname, indexdef FROM pg_indexes
      WHERE schemaname = 'public'
        AND tablename IN ('reservation', 'time_slot')
        AND indexdef LIKE 'CREATE UNIQUE%'`;

    for (const row of rows) {
      expect(row.indexdef).not.toMatch(/\(provider_profile_id, listing_id, starts_at\)/);
    }
    // `time_slot` does carry a unique `(listing_id, starts_at)` —
    // deliberately. It is the **generation** key that makes re-running
    // idempotent, it is scoped to one listing, and it says nothing about the
    // provider. See the schema comment; it is not, and must not be mistaken
    // for, the guard.
    expect(rows.some((r) => r.indexdef.includes('(listing_id, starts_at)'))).toBe(true);
  });

  it('refuses a zero-length or inverted interval on both tables', async () => {
    // An empty range never overlaps anything, so without these checks a row
    // with ends_at <= starts_at would sail past the exclusion constraint and
    // silently disable the guarantee for that booking.
    const rows = await prisma.$queryRaw<{ conrelid: string; definition: string }[]>`
      SELECT conrelid::regclass::text AS conrelid, pg_get_constraintdef(oid) AS definition
      FROM pg_constraint
      WHERE contype = 'c' AND conname IN ('time_slot_ends_after_starts', 'reservation_ends_after_starts')`;
    expect(rows).toHaveLength(2);
    for (const row of rows) expect(row.definition).toContain('ends_at > starts_at');
  });

  it('stores every instant as timestamptz and every calendar day as a date', async () => {
    const columns = await prisma.$queryRaw<
      { table_name: string; column_name: string; data_type: string }[]
    >`
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name IN ('time_slot', 'reservation', 'availability_rule',
                           'availability_exception', 'provider_time_off', 'listing_slot_state')
        AND column_name IN ('starts_at', 'ends_at', 'expires_at', 'released_at',
                            'start_date', 'end_date', 'next_generation_at', 'generated_through')`;

    for (const column of columns) {
      // §Phase 9a: "all times stored UTC, presented in Maldives time". A
      // `timestamp without time zone` would make that presentation a guess.
      const expected = column.column_name.endsWith('_date') ? 'date' : 'timestamp with time zone';
      expect(`${column.table_name}.${column.column_name}: ${column.data_type}`).toBe(
        `${column.table_name}.${column.column_name}: ${expected}`,
      );
    }
    expect(columns.length).toBeGreaterThan(10);
  });

  it('has no `lifecycle_status` or other stored-visibility column on the new tables', async () => {
    // Root CLAUDE.md invariant 1a: visibility is derived, never stored, and a
    // `lifecycleStatus` anywhere is obsolete by definition.
    const rows = await prisma.$queryRaw<{ column_name: string }[]>`
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name IN ('time_slot', 'reservation', 'availability_rule',
                           'availability_exception', 'provider_time_off', 'listing_slot_state')
        AND column_name IN ('lifecycle_status', 'is_visible', 'provider_is_visible')`;
    expect(rows).toEqual([]);
  });
});
