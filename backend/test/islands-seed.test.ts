import { beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import { loadIslandRegister, registerPath } from '../src/modules/location/seed-data.js';
import { seedIslands } from '../src/modules/location/seed.js';
import { databaseUrl, testConfig } from './helpers/app.js';

/**
 * §Phase 7's first bullet and §0.0 item 12 — the island register, and the one
 * rule that shapes everything downstream of it: **a name is not an
 * identifier.**
 *
 * The ambiguous set is asserted against the *data*, computed here a second
 * way, rather than against a list of sixteen names copied out of the seed —
 * a test that compared the seed's answer to the seed's own table would pass
 * whatever the grouping did.
 */
describe('Phase 7 — the island register', () => {
  const rows = loadIslandRegister();

  it('reads the real register, not a five-entry stand-in', () => {
    expect(registerPath()).toMatch(/docs\/data\/inhabited-islands\.json$/);
    expect(rows).toHaveLength(192);
    expect(new Set(rows.map((r) => r.atollAbbr)).size).toBe(20);
  });

  it('keys on the atoll and the name together, because a name is not unique', () => {
    expect(new Set(rows.map((r) => r.seedKey)).size).toBe(rows.length);
    // The name alone would collide — which is the whole point of item 12.
    expect(new Set(rows.map((r) => r.name)).size).toBeLessThan(rows.length);
  });

  it('finds Meedhoo in three atolls and flags every one of them', () => {
    const meedhoo = rows.filter((r) => r.name === 'Meedhoo');
    expect(meedhoo.map((r) => r.atollAbbr).sort()).toEqual(['Dh', 'R', 'S']);
    expect(meedhoo.every((r) => r.nameAmbiguous)).toBe(true);
  });

  it('computes ambiguity on the NORMALISED name, which finds 16 groups where the raw string finds 15', () => {
    const rawGroups = countGroups(rows.map((r) => r.name));
    const normalisedGroups = countGroups(rows.map((r) => r.searchName));
    expect(rawGroups).toBe(15);
    expect(normalisedGroups).toBe(16);

    // The pair that only the normalised grouping catches. Two different names
    // — one apostrophe apart — that search cannot tell apart, so both have to
    // carry their atoll code.
    const vilingili = rows.filter((r) => r.searchName === 'vilingili');
    expect(vilingili.map((r) => r.name).sort()).toEqual(["Vilin'gili", 'Vilingili']);
    expect(vilingili.every((r) => r.nameAmbiguous)).toBe(true);
  });

  it('flags exactly the islands whose normalised name is shared, and no others', () => {
    const shared = new Set(
      Object.entries(tally(rows.map((r) => r.searchName)))
        .filter(([, count]) => count > 1)
        .map(([name]) => name),
    );
    for (const row of rows) {
      expect(row.nameAmbiguous).toBe(shared.has(row.searchName));
    }
    expect(rows.filter((r) => r.nameAmbiguous)).toHaveLength(33);
  });

  it('preserves the register spelling, apostrophes and all', () => {
    const byName = new Map(rows.map((r) => [r.name, r]));
    // The apostrophe transliterates a Thaana glottal — stripping it stores a
    // different, wrong name. It comes out only for matching.
    expect(byName.has("An'golhitheemu")).toBe(true);
    expect(byName.get("An'golhitheemu")?.searchName).toBe('angolhitheemu');
    // A trailing apostrophe is part of the name too.
    expect(byName.has("Male'")).toBe(true);
    expect(byName.get("Male'")?.searchName).toBe('male');
  });

  it('carries none of the islands the register correctly does not list', () => {
    const names = new Set(rows.map((r) => r.name));
    // Depopulated, consolidated or destroyed — `docs/data/README.md` records
    // that each was checked. They are the ones an audit from memory reaches
    // for first.
    for (const absent of ['Faridhoo', 'Maavaidhoo', 'Firunbaidhoo', 'Kadholhudhoo', 'Gaadhoo']) {
      expect(names.has(absent)).toBe(false);
    }
    // And the islands people moved to are present.
    for (const present of ['Milandhoo', 'Dhuvaafaru']) {
      expect(names.has(present)).toBe(true);
    }
  });
});

describe.skipIf(databaseUrl === undefined)('Phase 7 — seeding the register', () => {
  const prisma = createPrismaClient(testConfig().databaseUrl);

  beforeAll(async () => {
    await seedIslands(prisma);
  });

  it('lands all 192 across 20 atolls', async () => {
    expect(await prisma.island.count()).toBeGreaterThanOrEqual(192);
    const atolls = await prisma.island.findMany({
      select: { atollAbbr: true },
      distinct: ['atollAbbr'],
    });
    expect(atolls.length).toBeGreaterThanOrEqual(20);
  });

  it('is idempotent — a second run creates nothing', async () => {
    const again = await seedIslands(prisma);
    expect(again.created).toBe(0);
    expect(again.refreshed).toBe(192);
    expect(again.ambiguityChanged).toEqual([]);
  });

  it('never reverts a deactivated island', async () => {
    const target = await prisma.island.findFirstOrThrow({ where: { seedKey: 'Dh:Meedhoo' } });
    await prisma.island.update({ where: { id: target.id }, data: { isActive: false } });
    await seedIslands(prisma);
    const after = await prisma.island.findUniqueOrThrow({ where: { id: target.id } });
    expect(after.isActive).toBe(false);
    await prisma.island.update({ where: { id: target.id }, data: { isActive: true } });
  });

  it('recomputes ambiguity rather than trusting the stored flag', async () => {
    // A stale flag on a row that IS ambiguous, and one on a row that is not:
    // the seed must move both back, because adding or losing an island changes
    // another island's answer and the flag cannot be decided row by row.
    const shared = await prisma.island.findFirstOrThrow({ where: { seedKey: 'R:Meedhoo' } });
    const unique = await prisma.island.findFirstOrThrow({
      where: { seedKey: 'HDh:Kulhudhuffushi' },
    });
    await prisma.island.update({ where: { id: shared.id }, data: { nameAmbiguous: false } });
    await prisma.island.update({ where: { id: unique.id }, data: { nameAmbiguous: true } });

    const result = await seedIslands(prisma);
    expect(result.ambiguityChanged).toEqual(['HDh:Kulhudhuffushi', 'R:Meedhoo']);
    expect(
      (await prisma.island.findUniqueOrThrow({ where: { id: shared.id } })).nameAmbiguous,
    ).toBe(true);
    expect(
      (await prisma.island.findUniqueOrThrow({ where: { id: unique.id } })).nameAmbiguous,
    ).toBe(false);
  });
});

function tally(values: string[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const value of values) counts[value] = (counts[value] ?? 0) + 1;
  return counts;
}

function countGroups(values: string[]): number {
  return Object.values(tally(values)).filter((count) => count > 1).length;
}
