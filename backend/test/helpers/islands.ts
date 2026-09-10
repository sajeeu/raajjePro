import type { PrismaClient } from '../../src/generated/prisma/client.js';
import { seedIslands } from '../../src/modules/location/seed.js';

/**
 * Seeds the island register once per process. The suite writes rows and never
 * deletes them (`test/setup.ts`), and the seed is create-if-absent, so this is
 * safe to call from every file that needs islands — the second call finds all
 * 192 present and only refreshes the derived columns.
 */
let seeded: Promise<unknown> | null = null;
export function ensureIslandsSeeded(prisma: PrismaClient): Promise<unknown> {
  seeded ??= seedIslands(prisma);
  return seeded;
}

/** The island the test wants, by register name and atoll code — never by name alone. */
export async function islandByName(prisma: PrismaClient, atollAbbr: string, name: string) {
  const island = await prisma.island.findUnique({
    where: { atollAbbr_name: { atollAbbr, name } },
  });
  if (island === null) throw new Error(`${atollAbbr}. ${name} is not seeded`);
  return island;
}
