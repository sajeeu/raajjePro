import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

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

    describe('suggested tags — §Phase 9’s step-1 chips', () => {
      it('seeds all twelve categories from the prototype’s map', async () => {
        await seedCategories(prisma);
        const rows = await prisma.category.findMany({ where: { seedKey: { not: null } } });
        const seeded = rows.filter((r) => CATEGORY_SEED.some((c) => c.name === r.seedKey));
        expect(seeded).toHaveLength(12);
        for (const row of seeded) {
          expect(row.suggestedTags.length).toBeGreaterThan(0);
        }
        // Transcribed, not invented — the values are the designer's.
        const electrical = seeded.find((r) => r.seedKey === 'Electrical');
        expect(electrical?.suggestedTags).toEqual([
          'Wiring',
          'Fault finding',
          'Rewiring',
          'Lighting',
          'Switchboards',
          'New sockets',
          'Safety check',
        ]);
      });

      it('recomputes them on an existing row, unlike every other column', async () => {
        // Create-if-absent would leave the twelve rows Phase 4 already made
        // with an empty chip list forever. Safe to overwrite because §Phase
        // 10b's editable Category fields are enumerated and this is not among
        // them, so there is no admin edit to revert.
        const before = await prisma.category.findUniqueOrThrow({ where: { seedKey: 'Cleaning' } });
        await prisma.category.update({
          where: { id: before.id },
          data: { suggestedTags: ['stale'] },
        });

        const result = await seedCategories(prisma);

        expect(result.tagsRefreshed).toContain('Cleaning');
        const after = await prisma.category.findUniqueOrThrow({ where: { seedKey: 'Cleaning' } });
        expect(after.suggestedTags).toEqual(before.suggestedTags);
        // …and it left everything else exactly as it was.
        expect(after.minimumLeadTimeMinutes).toBe(before.minimumLeadTimeMinutes);
        expect(after.name).toBe(before.name);
      });

      it('reports nothing refreshed on a second run', async () => {
        await seedCategories(prisma);
        const again = await seedCategories(prisma);
        expect(again.tagsRefreshed).toEqual([]);
      });
    });
  });
  /**
   * §Phase 8 (2026-09-10) added `suggestedTags` and made it the one column
   * this seed rewrites on an existing row.
   */

  /**
   * The schema comment on `Category.name` has promised this since §Phase 4 —
   * unique, "and unique case-insensitively as well (a functional index, added
   * in the migration)" — and no migration added it until 2026-09-15. It was
   * unreachable while the twelve were seeded and nothing else wrote a name;
   * §Phase 10b's admin rename is what makes names user-supplied, and this is
   * here so that endpoint meets a database that already refuses the collision
   * rather than one that has to be remembered about.
   */
  describe('a category name is unique whatever its case', () => {
    const prisma = createPrismaClient(testConfig().databaseUrl);

    // 🔧 These rows are deleted afterwards, which the rest of this suite
    // deliberately does not do. The convention — write real rows, isolate by
    // unique key, never clean up — holds while a test only cares about rows it
    // can name. It does not hold for `sortOrder`, which is a **shared global
    // ordering**: these clones sit at 9000+ and took the last position in the
    // category grid away from §Phase 4's Done-when, which asserts a thirteenth
    // category sorts after the seeded twelve. Parallel files made it a race —
    // green locally, red in CI.
    afterAll(async () => {
      await prisma.category.deleteMany({ where: { seedKey: { startsWith: 'case-' } } });
    });

    // Its own seed rather than the sibling describe's: a `-t` filter runs
    // this block without that one's `beforeAll`, and the failure then reads
    // as a broken constraint instead of an empty table. `seedCategories` is
    // idempotent, which the block above asserts.
    beforeAll(async () => {
      await seedCategories(prisma);
    });

    /// A copy of a real seeded row, so this test never has to be revisited
    /// when §Phase 4's table gains a column. Only the three fields under
    /// test are replaced.
    const clone = async (name: string, sortOrder: number) => {
      const {
        id: _id,
        createdAt: _c,
        updatedAt: _u,
        ...rest
      } = await prisma.category.findFirstOrThrow();
      return prisma.category.create({
        data: { ...rest, name, seedKey: `case-${randomUUID().slice(0, 8)}`, sortOrder },
      });
    };

    it('refuses a second row that differs only in case', async () => {
      const name = `Case ${randomUUID().slice(0, 8)}`;
      const created = await clone(name, 9000);
      expect(created.name).toBe(name);

      await expect(clone(name.toLowerCase(), 9001)).rejects.toThrow(
        /Unique constraint|category_name_lower_key/i,
      );
    });

    it('still allows two genuinely different names', async () => {
      const stem = randomUUID().slice(0, 8);
      await clone(`Case ${stem} One`, 9002);
      await clone(`Case ${stem} Two`, 9003);
    });
  });
});
