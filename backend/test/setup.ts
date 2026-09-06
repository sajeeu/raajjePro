// Loads .env for tests run from a developer machine. In CI the runner injects
// the same variables, and dotenv leaves anything already set alone.
import 'dotenv/config';

/**
 * These tests write real rows and never clean up. That is deliberate — they
 * isolate by unique key (a fresh email per admin, `freshIp()` per rate-limit
 * subject) rather than by truncating, which keeps them parallel-safe and
 * keeps the "counters survive a restart" test honest. The cost is that every
 * run leaves admin accounts, sessions, audit entries and suppressed addresses
 * behind, and invariant 8 means none of them can ever be hard-deleted.
 *
 * So the database they run against must be one nobody minds. Nothing used to
 * enforce that: the suite read the same `DATABASE_URL` the application does,
 * so `npm test` with a staging URL exported would have written hundreds of
 * admin accounts and audit rows into staging — into the log that is supposed
 * to be the tamper-evident record of who did what.
 *
 * The rule is the database name. It must end in `_test`; anything else fails
 * here, before a single row is written. Set `TEST_DATABASE_URL` to point at
 * it, or name the database in `DATABASE_URL` accordingly.
 */
const REQUIRED_SUFFIX = '_test';

function databaseNameOf(url: string): string {
  try {
    return new URL(url).pathname.replace(/^\//, '');
  } catch {
    return '';
  }
}

const applicationUrl = process.env.DATABASE_URL;
const chosen = process.env.TEST_DATABASE_URL ?? applicationUrl;

if (chosen !== undefined) {
  const name = databaseNameOf(chosen);
  if (!name.endsWith(REQUIRED_SUFFIX)) {
    throw new Error(
      `Refusing to run tests against database "${name || chosen}": the name must end in ` +
        `"${REQUIRED_SUFFIX}". These tests write rows and never delete them.\n` +
        `  Create it once:  docker compose exec db createdb -U raajjepro raajjepro_test\n` +
        `  Migrate it:      DATABASE_URL=postgresql://raajjepro:raajjepro@localhost:5435/raajjepro_test?schema=public npm run db:deploy\n` +
        `  Then set TEST_DATABASE_URL to that URL in backend/.env (see .env.example).`,
    );
  }

  // The one database pg_cron writes to is the application's, named by the
  // server's cron.database_name — a second database gets the job_heartbeat
  // table from the migration but no scheduled job. The job-runner test is an
  // environment check rather than a unit test, so it reads this instead of
  // the test database. Where DATABASE_URL is itself the test database the two
  // are the same URL and nothing changes.
  if (applicationUrl !== undefined) process.env.CRON_DATABASE_URL = applicationUrl;
  process.env.DATABASE_URL = chosen;
}
