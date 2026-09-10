/**
 * `npm run db:seed`
 *
 * Bootstraps the reference data every later phase reads: the twelve categories
 * (§Phase 4, §1d) and the island register (§Phase 7, §0.0 item 12).
 *
 * 🔧 **This file was `seed-categories.ts` until Phase 7.** It was renamed
 * rather than joined by a second script because one command has to leave a
 * checkout with *all* its reference data — a `db:seed` that quietly did half
 * the job would show up as an empty island picker several phases later.
 *
 * Both seeds are create-if-absent and safe on every deploy. Neither reverts an
 * admin's edit; see each `seed*` function for what it does and does not
 * overwrite.
 */
import { createPrismaClient } from '../db/client.js';
import { loadConfig } from '../config/env.js';
import { seedCategories } from '../modules/categories/seed.js';
import { seedIslands } from '../modules/location/seed.js';

async function main(): Promise<void> {
  const config = loadConfig(process.env);
  const prisma = createPrismaClient(config.databaseUrl);
  try {
    const { created, adopted, skipped } = await seedCategories(prisma);
    if (created.length > 0) process.stdout.write(`Created: ${created.join(', ')}\n`);
    if (adopted.length > 0) process.stdout.write(`Adopted: ${adopted.join(', ')}\n`);
    if (skipped.length > 0) process.stdout.write(`Already present: ${skipped.join(', ')}\n`);
    process.stdout.write(
      `Categories: ${String(created.length)} created, ${String(adopted.length)} adopted, ` +
        `${String(skipped.length)} left alone.\n`,
    );

    const islands = await seedIslands(prisma);
    if (islands.ambiguityChanged.length > 0) {
      process.stdout.write(`Ambiguity changed on: ${islands.ambiguityChanged.join(', ')}\n`);
    }
    process.stdout.write(
      `Islands: ${String(islands.created)} created, ${String(islands.refreshed)} refreshed, ` +
        `${String(islands.ambiguousTotal)} rendered with an atoll code.\n`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
