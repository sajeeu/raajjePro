import { beforeAll, describe, expect, it } from 'vitest';

import { createPrismaClient } from '../src/db/client.js';
import { CATEGORY_SEED } from '../src/modules/categories/seed-data.js';
import { seedCategories } from '../src/modules/categories/seed.js';
import { databaseUrl, testConfig } from './helpers/app.js';

/**
 * The seed is the only place §Phase 4's numbers are written down, so this
 * asserts them against the plan one line at a time rather than against the
 * table itself — a test that read `CATEGORY_SEED` and compared it to
 * `CATEGORY_SEED` would pass no matter what the numbers said.
 */
describe.skipIf(databaseUrl === undefined)('Phase 4 — the seeded twelve', () => {
  const byName = new Map(CATEGORY_SEED.map((c) => [c.name, c]));
  const seed = (name: string) => {
    const found = byName.get(name);
    if (found === undefined) throw new Error(`${name} is not seeded`);
    return found;
  };

  it('seeds exactly the twelve the plan names, in the plan’s order', () => {
    expect(CATEGORY_SEED.map((c) => c.name)).toEqual([
      'Cleaning',
      'Plumbing',
      'Electrical',
      'AC Repair',
      'Beauty',
      'Photography',
      'Pest Control',
      'Appliance Repair',
      'Moving',
      'Fitness',
      'Home Repairs',
      'Boat Charter',
    ]);
    expect(CATEGORY_SEED.map((c) => c.sortOrder)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  it('carries none of the three stale category names', () => {
    for (const stale of ['Gardening', 'Computer', 'Events', 'Tuition']) {
      expect(byName.has(stale)).toBe(false);
    }
  });

  it('puts only Cleaning, Beauty and Fitness on slot mode (§1c)', () => {
    const slot = CATEGORY_SEED.filter((c) => c.bookingMode === 'slot').map((c) => c.name);
    expect(slot).toEqual(['Cleaning', 'Beauty', 'Fitness']);
  });

  it('makes exactly Plumbing, Electrical, AC Repair and Moving emergency-capable', () => {
    const capable = CATEGORY_SEED.filter((c) => c.emergencyCapable).map((c) => c.name);
    expect(capable).toEqual(['Plumbing', 'Electrical', 'AC Repair', 'Moving']);
  });

  it('sets the emergency tier bar per category — gold, never a flat silver (Round 15)', () => {
    expect(seed('Electrical').emergencyMinimumTier).toBe('gold');
    expect(seed('Plumbing').emergencyMinimumTier).toBe('gold');
    expect(seed('AC Repair').emergencyMinimumTier).toBe('silver');
    expect(seed('Moving').emergencyMinimumTier).toBe('silver');
    for (const c of CATEGORY_SEED.filter((x) => !x.emergencyCapable)) {
      expect(c.emergencyMinimumTier).toBeNull();
    }
  });

  it('gives every emergency category a 30-minute answer window, Moving included (Round 22)', () => {
    for (const c of CATEGORY_SEED.filter((x) => x.emergencyCapable)) {
      expect(c.emergencyAcceptWindowMinutes, c.name).toBe(30);
    }
    // The 120 that briefly sat on Moving described arrival, not response.
    expect(seed('Moving').emergencyAcceptWindowMinutes).not.toBe(120);
  });

  it('seeds the arrival presets Round 22 specifies, and nothing elsewhere', () => {
    expect(seed('Plumbing').emergencyEtaPresetsMinutes).toEqual([15, 30, 45, 60]);
    expect(seed('Electrical').emergencyEtaPresetsMinutes).toEqual([15, 30, 45, 60]);
    expect(seed('AC Repair').emergencyEtaPresetsMinutes).toEqual([15, 30, 45, 60]);
    expect(seed('Moving').emergencyEtaPresetsMinutes).toEqual([60, 90, 120, 180]);
    for (const c of CATEGORY_SEED.filter((x) => !x.emergencyCapable)) {
      expect(c.emergencyEtaPresetsMinutes, c.name).toEqual([]);
    }
  });

  it('sets the Round 14 lead times exactly as the plan gives them', () => {
    const expected: Record<string, number> = {
      Cleaning: 180,
      Beauty: 120,
      Fitness: 120,
      Plumbing: 60,
      Electrical: 60,
      'AC Repair': 60,
      'Appliance Repair': 120,
      'Pest Control': 180,
      Photography: 1440,
      Moving: 1440,
      'Boat Charter': 1440,
      'Home Repairs': 180,
    };
    for (const [name, minutes] of Object.entries(expected)) {
      expect(seed(name).minimumLeadTimeMinutes, name).toBe(minutes);
    }
  });

  it('puts the six household trades on 120/240 and the three planned categories on 1440/4320', () => {
    for (const name of [
      'Plumbing',
      'Electrical',
      'AC Repair',
      'Appliance Repair',
      'Pest Control',
      'Home Repairs',
    ]) {
      expect([seed(name).quoteExpiryMinutes, seed(name).quoteApprovalMinutes], name).toEqual([
        120, 240,
      ]);
    }
    for (const name of ['Photography', 'Moving', 'Boat Charter']) {
      expect([seed(name).quoteExpiryMinutes, seed(name).quoteApprovalMinutes], name).toEqual([
        1440, 4320,
      ]);
    }
    // The three slot categories do not quote.
    for (const name of ['Cleaning', 'Beauty', 'Fitness']) {
      expect([seed(name).quoteExpiryMinutes, seed(name).quoteApprovalMinutes], name).toEqual([
        null,
        null,
      ]);
    }
  });

  it('offers the callback guarantee only where something can un-fix (Round 28)', () => {
    const eligible = CATEGORY_SEED.filter((c) => c.callbackEligible).map((c) => c.name);
    expect(eligible).toEqual([
      'Plumbing',
      'Electrical',
      'AC Repair',
      'Pest Control',
      'Appliance Repair',
      'Home Repairs',
    ]);
  });

  it('seeds occasion chips for Photography and Boat Charter only, each ending in Other', () => {
    const withPresets = CATEGORY_SEED.filter((c) => c.occasionPresets.length > 0);
    expect(withPresets.map((c) => c.name)).toEqual(['Photography', 'Boat Charter']);
    for (const c of withPresets) {
      expect(c.occasionPresets.at(-1), c.name).toBe('Other');
    }
  });

  it('carries the broadened Appliance Repair scope in its description (Round 25)', () => {
    const description = seed('Appliance Repair').description.toLowerCase();
    for (const word of ['washing machine', 'refrigerator', 'tv', 'computer', 'phone']) {
      expect(description, word).toContain(word);
    }
  });

  it('gives every category a distinct colour token and icon identifier', () => {
    expect(new Set(CATEGORY_SEED.map((c) => c.colorToken)).size).toBe(12);
    expect(new Set(CATEGORY_SEED.map((c) => c.iconIdentifier)).size).toBe(12);
    // Tokens, not values: the client resolves both and falls back for one it
    // does not know, so a hex or an asset path here would defeat that.
    for (const c of CATEGORY_SEED) {
      expect(c.colorToken, c.name).toMatch(/^[A-Za-z][A-Za-z0-9]*$/);
      expect(c.iconIdentifier, c.name).toMatch(/^[A-Za-z][A-Za-z0-9]*$/);
    }
  });

  describe('running it', () => {
    const prisma = createPrismaClient(testConfig().databaseUrl);

    beforeAll(async () => {
      await seedCategories(prisma);
    });

    it('leaves all twelve in the database with the seeded values', async () => {
      const rows = await prisma.category.findMany({
        where: { name: { in: CATEGORY_SEED.map((c) => c.name) } },
      });
      expect(rows).toHaveLength(12);
      for (const row of rows) {
        const expected = seed(row.name);
        expect(row.bookingMode, row.name).toBe(expected.bookingMode);
        expect(row.minimumLeadTimeMinutes, row.name).toBe(expected.minimumLeadTimeMinutes);
        expect(row.emergencyMinimumTier, row.name).toBe(expected.emergencyMinimumTier);
        expect(row.quoteExpiryMinutes, row.name).toBe(expected.quoteExpiryMinutes);
        expect(row.callbackEligible, row.name).toBe(expected.callbackEligible);
      }
    });

    it('is idempotent — a second run creates nothing', async () => {
      const again = await seedCategories(prisma);
      expect(again.created).toEqual([]);
      expect(again.skipped).toHaveLength(12);
    });

    it('does not re-create a category an admin renamed', async () => {
      // Round 25 renamed Computer to Appliance Repair, so this is a real
      // sequence, not a hypothetical. A seed keyed on `name` would create a
      // second "Boat Charter" here and Explore would draw two tiles.
      const before = await prisma.category.findFirstOrThrow({
        where: { seedKey: 'Boat Charter' },
      });
      await prisma.category.update({
        where: { id: before.id },
        data: { name: 'Charters & Trips' },
      });

      const again = await seedCategories(prisma);
      expect(again.created).toEqual([]);
      expect(again.skipped).toContain('Boat Charter');

      const rows = await prisma.category.findMany({ where: { seedKey: 'Boat Charter' } });
      expect(rows).toHaveLength(1);
      expect(rows[0]?.name).toBe('Charters & Trips');
      expect(await prisma.category.findFirst({ where: { name: 'Boat Charter' } })).toBeNull();

      await prisma.category.update({ where: { id: before.id }, data: { name: before.name } });
    });

    it('adopts a matching row that predates the seed key rather than colliding', async () => {
      const before = await prisma.category.findFirstOrThrow({ where: { seedKey: 'Fitness' } });
      await prisma.category.update({ where: { id: before.id }, data: { seedKey: null } });

      const again = await seedCategories(prisma);
      expect(again.adopted).toContain('Fitness');
      expect(again.created).toEqual([]);

      const after = await prisma.category.findUniqueOrThrow({ where: { id: before.id } });
      expect(after.seedKey).toBe('Fitness');
      // Adoption stamps the key and touches nothing else.
      expect(after.minimumLeadTimeMinutes).toBe(before.minimumLeadTimeMinutes);
    });

    it('never overwrites an admin edit', async () => {
      const before = await prisma.category.findUniqueOrThrow({ where: { name: 'Cleaning' } });
      await prisma.category.update({
        where: { id: before.id },
        data: { minimumLeadTimeMinutes: 240 },
      });
      await seedCategories(prisma);
      const after = await prisma.category.findUniqueOrThrow({ where: { name: 'Cleaning' } });
      expect(after.minimumLeadTimeMinutes).toBe(240);
      // Put it back so the rest of the suite sees the seeded value.
      await prisma.category.update({
        where: { id: before.id },
        data: { minimumLeadTimeMinutes: before.minimumLeadTimeMinutes },
      });
    });
  });
});
