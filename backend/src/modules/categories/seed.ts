import type { PrismaClient } from '../../generated/prisma/client.js';
import { CATEGORY_SEED } from './seed-data.js';

export interface SeedResult {
  created: string[];
  adopted: string[];
  skipped: string[];
  /** Categories whose `suggestedTags` were rewritten from the seed — see below. */
  tagsRefreshed: string[];
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
 * **Create-if-absent, never overwrite — with one deliberate exception.**
 * Every number on a category is admin-editable from Phase 10b, so a seed that
 * upserted would silently revert an admin's change on the next deploy. A
 * category already present is left exactly as it is, deactivated ones
 * included.
 *
 * 🔧 **`suggestedTags` is recomputed on every run** (§Phase 8, added
 * 2026-09-10), which is the island seed's pattern rather than this one's:
 * create-if-absent for the row, recompute-always for a column nobody else
 * owns. It is safe here for the reason the rest are not — §Phase 10b
 * enumerates the admin-editable Category fields (name, icon, active, lead
 * time, the accept window, the ETA presets, both quote windows,
 * `callbackEligible`) and this is not among them, so there is no admin edit
 * to revert. It is also **necessary**: the twelve rows already exist from
 * Phase 4, and create-if-absent would leave every one of them with an empty
 * chip list forever.
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
    select: { id: true, name: true, seedKey: true, suggestedTags: true },
  });
  const byKey = new Map(
    existing.filter((c) => c.seedKey !== null).map((c) => [c.seedKey, c] as const),
  );
  const unclaimedByName = new Map(
    existing.filter((c) => c.seedKey === null).map((c) => [c.name, c] as const),
  );

  const result: SeedResult = { created: [], adopted: [], skipped: [], tagsRefreshed: [] };

  for (const seed of CATEGORY_SEED) {
    const existing = byKey.get(seed.name);
    if (existing !== undefined) {
      result.skipped.push(seed.name);
      if (!sameTags(existing.suggestedTags, seed.suggestedTags)) {
        await prisma.category.update({
          where: { id: existing.id },
          data: { suggestedTags: seed.suggestedTags },
        });
        result.tagsRefreshed.push(seed.name);
      }
      continue;
    }
    const unclaimed = unclaimedByName.get(seed.name);
    if (unclaimed !== undefined) {
      await prisma.category.update({
        where: { id: unclaimed.id },
        data: { seedKey: seed.name, suggestedTags: seed.suggestedTags },
      });
      result.adopted.push(seed.name);
      continue;
    }
    await prisma.category.create({ data: { ...seed, seedKey: seed.name } });
    result.created.push(seed.name);
  }
  return result;
}

/** Order matters — the chips render in the order the prototype lists them. */
function sameTags(current: string[], seeded: string[]): boolean {
  return current.length === seeded.length && current.every((tag, i) => tag === seeded[i]);
}
