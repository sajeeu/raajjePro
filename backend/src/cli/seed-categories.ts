/**
 * `npm run db:seed`
 *
 * Bootstraps the twelve seeded categories (§Phase 4, §1d). Create-if-absent —
 * see `seedCategories` for why it never overwrites an existing row.
 */
import { createPrismaClient } from '../db/client.js';
import { loadConfig } from '../config/env.js';
import { seedCategories } from '../modules/categories/seed.js';

async function main(): Promise<void> {
  const config = loadConfig(process.env);
  const prisma = createPrismaClient(config.databaseUrl);
  try {
    const { created, adopted, skipped } = await seedCategories(prisma);
    if (created.length > 0) process.stdout.write(`Created: ${created.join(', ')}\n`);
    if (adopted.length > 0) process.stdout.write(`Adopted: ${adopted.join(', ')}\n`);
    if (skipped.length > 0) process.stdout.write(`Already present: ${skipped.join(', ')}\n`);
    process.stdout.write(
      `${String(created.length)} created, ${String(adopted.length)} adopted, ` +
        `${String(skipped.length)} left alone.\n`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
