-- CreateTable
CREATE TABLE "job_heartbeat" (
    "id" UUID NOT NULL,
    "job_name" TEXT NOT NULL,
    "fired_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "job_heartbeat_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "job_heartbeat_job_name_key" ON "job_heartbeat"("job_name");

-- ---------------------------------------------------------------------------
-- Job runner: pg_cron (plan §2 "pg_cron or equivalent", §Phase 0).
--
-- pg_cron can only be installed into the one database named by the server
-- setting cron.database_name, so this block runs only when it is applied to
-- that database. Anywhere else — Prisma's shadow database during
-- `migrate dev`, a scratch database — it is a no-op, and the table above still
-- exists so the schema stays consistent.
--
-- Requirements on the server (both true for infra/postgres via docker-compose):
--   shared_preload_libraries = 'pg_cron'
--   cron.database_name       = '<this database>'
-- On a managed host set the same two parameters in the parameter group and
-- make sure the migrating role may CREATE EXTENSION pg_cron.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF current_database() = current_setting('cron.database_name', true) THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;

    -- The no-op heartbeat. It proves the runner fires on schedule and nothing
    -- more: one row per job, its fired_at moved forward every minute. An upsert
    -- rather than insert-and-prune, so nothing is ever deleted (plan §2).
    -- cron.schedule(name, ...) is idempotent on the name: re-running this
    -- migration on a database that already has the job replaces it in place.
    PERFORM cron.schedule(
      'noop-heartbeat',
      '* * * * *',
      $job$
        INSERT INTO job_heartbeat (id, job_name, fired_at)
        VALUES (gen_random_uuid(), 'noop-heartbeat', now())
        ON CONFLICT (job_name) DO UPDATE SET fired_at = EXCLUDED.fired_at;
      $job$
    );
  ELSE
    RAISE NOTICE 'pg_cron skipped: % is not cron.database_name', current_database();
  END IF;
END
$$;
