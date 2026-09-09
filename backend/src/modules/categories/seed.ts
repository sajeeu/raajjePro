import type { PrismaClient } from '../../generated/prisma/client.js';
import { CATEGORY_SEED } from './seed-data.js';

export interface SeedResult {
  created: string[];
  adopted: string[];
  skipped: string[];
}

/**
 * Bootstraps the twelve categories (§Phase 4) into an empty catalogue.
 *
 * **Keyed on `seedKey`, not on `name`.** A category's name is admin-editable
 * — Round 25 renamed Computer to Appliance Repair, so a rename is a thing
 * that really happens — and a bootstrap that recognised its own rows by name
 * would re-create a renamed one under the old name on the next deploy,
 * leaving two active rows and two tiles in Explore.
 *
 * **Create-if-absent, never overwrite.** Every number on a category is
 * admin-editable from Phase 10b, so a seed that upserted would silently
 * revert an admin's change on the next deploy. A category already present is
 * left exactly as it is, deactivated ones included.
 *
 * **Adoption** covers the one-way step from before `seedKey` existed: a row
 * whose name matches a seed key and whose own key is still null is claimed
 * and stamped, rather than colliding with the name's unique constraint. It is
 * also what happens if an admin creates a category the seed was going to.
 *
 * Idempotent: safe to run on every deploy, reporting what it did.
 */
export async function seedCategories(prisma: PrismaClient): Promise<SeedResult> {
  const keys = CATEGORY_SEED.map((c) => c.name);
  const existing = await prisma.category.findMany({
    where: { OR: [{ seedKey: { in: keys } }, { name: { in: keys } }] },
    select: { id: true, name: true, seedKey: true },
  });
  const byKey = new Map(
    existing.filter((c) => c.seedKey !== null).map((c) => [c.seedKey, c] as const),
  );
  const unclaimedByName = new Map(
    existing.filter((c) => c.seedKey === null).map((c) => [c.name, c] as const),
  );

  const result: SeedResult = { created: [], adopted: [], skipped: [] };

  for (const seed of CATEGORY_SEED) {
    if (byKey.has(seed.name)) {
      result.skipped.push(seed.name);
      continue;
    }
    const unclaimed = unclaimedByName.get(seed.name);
    if (unclaimed !== undefined) {
      await prisma.category.update({
        where: { id: unclaimed.id },
        data: { seedKey: seed.name },
      });
      result.adopted.push(seed.name);
      continue;
    }
    await prisma.category.create({ data: { ...seed, seedKey: seed.name } });
    result.created.push(seed.name);
  }
  return result;
}
