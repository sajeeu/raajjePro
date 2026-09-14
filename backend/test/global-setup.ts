// Runs once per `vitest` invocation, before any test file is loaded.
import 'dotenv/config';

import { Client } from 'pg';

/**
 * Empty the test database before a run.
 *
 * These tests still do not clean up *after* themselves, and that is still
 * deliberate: they isolate by unique key — a fresh email per admin,
 * `freshIp()` per rate-limit subject — rather than by truncating between
 * tests, which is what keeps the "counters survive an app restart" test
 * honest. That test writes counters, builds a second app and asserts the
 * limit still bites; a truncate between tests would erase the thing it is
 * asserting. Nothing here touches it, because this runs before the first
 * file is loaded.
 *
 * What changed on 2026-09-14 is the *cross-run* cost, which nobody had been
 * paying attention to. Rows accumulated for as long as the database existed,
 * and invariant 8 means none of them can ever be hard-deleted, so the table a
 * sweep-shaped test reads grew with every `npm test` anyone ran. A thousand
 * accumulated subscriptions is what pushed `phase8a-done-when.test.ts` past
 * the five-second timeout four days after it was written, with nothing
 * landing in between but test runs. A gate that decays on the calendar is
 * worse than one that fails, because "green" quietly stops meaning anything —
 * and both the session that wrote that test and the one that reviewed it saw
 * green in good faith.
 *
 * It also removes a second, quieter distortion: every test ran against
 * whatever the last few weeks happened to leave behind, so nobody could say
 * what state a failure had actually occurred in.
 *
 * `_prisma_migrations` survives, or the schema this just emptied would look
 * unmigrated to the next `db:deploy`.
 */

const REQUIRED_SUFFIX = '_test';
const PRESERVE = new Set(['_prisma_migrations']);

function databaseNameOf(url: string): string {
  try {
    return new URL(url).pathname.replace(/^\//, '');
  } catch {
    return '';
  }
}

export async function setup(): Promise<void> {
  const url = process.env.TEST_DATABASE_URL ?? process.env.DATABASE_URL;
  if (url === undefined) return;

  // The same rule `test/setup.ts` enforces, repeated rather than imported
  // because this file runs first and in its own context — and because of the
  // three places in this repository that name a database, this is the one
  // that issues TRUNCATE. A guard worth having twice.
  const name = databaseNameOf(url);
  if (!name.endsWith(REQUIRED_SUFFIX)) {
    throw new Error(
      `Refusing to truncate database "${name || url}": the name must end in "${REQUIRED_SUFFIX}".`,
    );
  }

  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    const { rows } = await client.query<{ tablename: string }>(
      `select tablename from pg_tables where schemaname = 'public'`,
    );
    const tables = rows.map((r) => r.tablename).filter((t) => !PRESERVE.has(t));
    if (tables.length === 0) return;
    // One statement: CASCADE resolves the foreign keys between them, and
    // RESTART IDENTITY resets the sequences the invoice numbering reads.
    await client.query(
      `truncate table ${tables.map((t) => `"${t}"`).join(', ')} restart identity cascade`,
    );
  } finally {
    await client.end();
  }
}
