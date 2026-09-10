import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { z } from 'zod';

import { islandSearchForms } from './normalise.js';

/**
 * The island register (§Phase 7's first bullet, §0.0 item 12).
 *
 * **The repository's data file is the seed.** `docs/data/inhabited-islands.json`
 * is the ministry-register extract — 192 inhabited islands across 20 atolls,
 * verified by two independent parses (`docs/data/README.md`). It is read here
 * rather than transcribed into a TypeScript literal so that there is exactly
 * one copy: a second one would drift, and §Phase 7's own instruction is not to
 * re-derive the list.
 *
 * The path is resolved from this module's own URL, which lands on the same
 * repository root from `src/` and from `dist/` alike. `ISLAND_REGISTER_PATH`
 * overrides it — the seed test uses that to seed a fixture rather than the
 * real register.
 */
const DEFAULT_REGISTER_PATH = fileURLToPath(
  new URL('../../../../docs/data/inhabited-islands.json', import.meta.url),
);

/**
 * Validated on read, because this is an external file rather than code: a
 * hand-edit that dropped an `abbr` would otherwise seed 192 islands whose
 * ambiguous names could never be qualified.
 */
const registerSchema = z.object({
  atolls: z
    .array(
      z.object({
        code: z.string().trim().min(1),
        abbr: z.string().trim().min(1),
        islands: z.array(z.string().trim().min(1)).min(1),
      }),
    )
    .min(1),
});

/** One island as the seed writes it — the register's own fields plus the derived ones. */
export interface IslandSeedRow {
  seedKey: string;
  name: string;
  atollName: string;
  atollAbbr: string;
  nameAmbiguous: boolean;
  searchName: string;
  searchQualified: string;
}

export function registerPath(): string {
  return process.env.ISLAND_REGISTER_PATH ?? DEFAULT_REGISTER_PATH;
}

/**
 * Reads the register and returns every island with its derived columns filled.
 *
 * 🔧 **The ambiguous set is computed here, not listed anywhere** (§0.0 item
 * 12). Islands are grouped by their **normalised** name — case-folded,
 * accent-folded, apostrophe-stripped — and every island in a group larger than
 * one is flagged. Grouping on the raw string is the trap the plan names: it
 * finds 15 collisions where the normalised form finds **16**, because
 * `K. Vilingili` and `GA. Vilin'gili` are different strings that a customer
 * typing "Vilingili" cannot tell apart. Computing it also means the rule
 * follows the register on its own if an island is ever added or lost.
 */
export function loadIslandRegister(path: string = registerPath()): IslandSeedRow[] {
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (cause) {
    throw new Error(
      `Cannot read the island register at ${path}. It ships in the repository at ` +
        `docs/data/inhabited-islands.json; set ISLAND_REGISTER_PATH to point elsewhere.`,
      { cause },
    );
  }

  const register = registerSchema.parse(JSON.parse(raw));

  const flat = register.atolls.flatMap((atoll) =>
    atoll.islands.map((name) => ({
      name,
      atollName: atoll.code,
      atollAbbr: atoll.abbr,
      ...islandSearchForms(name, atoll.abbr),
    })),
  );

  const groupSizes = new Map<string, number>();
  for (const island of flat) groupSizes.set(island.bare, (groupSizes.get(island.bare) ?? 0) + 1);

  return flat.map((island) => ({
    // Not the name: names repeat across atolls, and a row an admin renames
    // must not be re-created by the next seed run under its old name (the
    // same reasoning as `Category.seedKey`).
    seedKey: `${island.atollAbbr}:${island.name}`,
    name: island.name,
    atollName: island.atollName,
    atollAbbr: island.atollAbbr,
    nameAmbiguous: (groupSizes.get(island.bare) ?? 0) > 1,
    searchName: island.bare,
    searchQualified: island.qualified,
  }));
}
