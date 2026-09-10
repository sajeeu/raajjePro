import type { PrismaClient } from '../../generated/prisma/client.js';
import { loadIslandRegister, type IslandSeedRow } from './seed-data.js';

export interface IslandSeedResult {
  /** Islands that did not exist and were inserted. */
  created: number;
  /** Islands already present, whose register-derived columns were refreshed. */
  refreshed: number;
  /** Rows whose `nameAmbiguous` flag changed as a result of this run. */
  ambiguityChanged: string[];
  /** How many islands carry a qualified display name after this run. */
  ambiguousTotal: number;
}

/**
 * Bootstraps the island register (§Phase 7, §0.0 item 12). `npm run db:seed`
 * runs it beside the category seed.
 *
 * **Create-if-absent for the row, recompute-always for the derived columns.**
 * That split is the difference between this and the category seed, and it is
 * deliberate:
 *
 *   - `isActive` is **never** touched on an existing row. Deactivating an
 *     island is Phase 10b's admin action (invariant 8's soft delete) and a
 *     seed that reverted it on the next deploy would make the action
 *     pointless — the same rule the category seed follows for every
 *     admin-editable number.
 *   - `nameAmbiguous`, `searchName` and `searchQualified` **are** rewritten,
 *     because they are not anybody's to edit: they are computed from the
 *     register, and §0.0 item 12 requires the ambiguous set to follow the data
 *     rather than a hardcoded list. Adding one island can make another
 *     island's name ambiguous, so the flag cannot be decided row by row.
 *
 * 🔧 **Ambiguity is recomputed across the whole table, not across the register
 * file.** Search answers from the database, so what makes two names
 * indistinguishable is two *rows* sharing a normalised name — including a row
 * an earlier register carried and this one does not. Computing from the file
 * alone would leave such a pair rendering one qualified name and one bare one.
 *
 * **A register spelling correction creates a second row, and does not merge.**
 * `seedKey` is `"<atollAbbr>:<name>"`, so a corrected name is a new key. That
 * is left as it is rather than guessed at: reconciling two spellings is an
 * identity decision a person makes, and the superseded row is deactivated
 * through Phase 10b. Nothing about it is silent — the counts below report a
 * creation.
 *
 * Idempotent: safe on every deploy.
 */
export async function seedIslands(
  prisma: PrismaClient,
  rows: IslandSeedRow[] = loadIslandRegister(),
): Promise<IslandSeedResult> {
  let created = 0;
  let refreshed = 0;

  for (const row of rows) {
    const existing = await prisma.island.findUnique({
      where: { seedKey: row.seedKey },
      select: { id: true },
    });
    if (existing === null) {
      await prisma.island.create({ data: row });
      created += 1;
      continue;
    }
    await prisma.island.update({
      where: { seedKey: row.seedKey },
      data: {
        atollName: row.atollName,
        atollAbbr: row.atollAbbr,
        searchName: row.searchName,
        searchQualified: row.searchQualified,
      },
    });
    refreshed += 1;
  }

  const ambiguityChanged = await recomputeAmbiguity(prisma);
  const ambiguousTotal = await prisma.island.count({ where: { nameAmbiguous: true } });
  return { created, refreshed, ambiguityChanged, ambiguousTotal };
}

/**
 * Groups every island by its normalised name and flags each one whose group
 * holds more than one row. Returns the seed keys whose flag moved, so the CLI
 * can say what changed rather than reporting a silent success.
 *
 * Deactivated rows count. A name is ambiguous because two islands carry it,
 * and an admin can reactivate one at any time; letting the flag depend on
 * activation would make a display name flicker on an unrelated admin action.
 */
async function recomputeAmbiguity(prisma: PrismaClient): Promise<string[]> {
  const all = await prisma.island.findMany({
    select: { id: true, seedKey: true, searchName: true, nameAmbiguous: true },
  });

  const sizes = new Map<string, number>();
  for (const island of all) sizes.set(island.searchName, (sizes.get(island.searchName) ?? 0) + 1);

  const changed: string[] = [];
  for (const island of all) {
    const shouldBeAmbiguous = (sizes.get(island.searchName) ?? 0) > 1;
    if (shouldBeAmbiguous === island.nameAmbiguous) continue;
    await prisma.island.update({
      where: { id: island.id },
      data: { nameAmbiguous: shouldBeAmbiguous },
    });
    changed.push(island.seedKey);
  }
  return changed.sort();
}
