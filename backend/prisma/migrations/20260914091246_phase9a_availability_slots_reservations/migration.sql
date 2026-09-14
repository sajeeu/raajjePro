-- CreateEnum
CREATE TYPE "time_slot_status" AS ENUM ('open', 'reserved', 'blocked');

-- CreateEnum
CREATE TYPE "reservation_kind" AS ENUM ('firm', 'provisional');

-- CreateEnum
CREATE TYPE "reservation_release_reason" AS ENUM ('cancelled', 'declined', 'expired', 'superseded');

-- CreateTable
CREATE TABLE "availability_rule" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "weekdays" INTEGER[],
    "start_time" VARCHAR(5) NOT NULL,
    "end_time" VARCHAR(5) NOT NULL,
    "slot_duration_minutes" INTEGER NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "availability_rule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "availability_exception" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "start_time" VARCHAR(5) NOT NULL,
    "end_time" VARCHAR(5) NOT NULL,
    "slot_duration_minutes" INTEGER,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "availability_exception_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_time_off" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_time_off_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "time_slot" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "starts_at" TIMESTAMPTZ(6) NOT NULL,
    "ends_at" TIMESTAMPTZ(6) NOT NULL,
    "status" "time_slot_status" NOT NULL DEFAULT 'open',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "time_slot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reservation" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "time_slot_id" UUID,
    "starts_at" TIMESTAMPTZ(6) NOT NULL,
    "ends_at" TIMESTAMPTZ(6) NOT NULL,
    "kind" "reservation_kind" NOT NULL,
    "expires_at" TIMESTAMPTZ(6),
    "released_at" TIMESTAMPTZ(6),
    "release_reason" "reservation_release_reason",
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "reservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_slot_state" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "next_generation_at" TIMESTAMPTZ(6),
    "generated_through" TIMESTAMPTZ(6),
    "last_generated_at" TIMESTAMPTZ(6),
    "last_run_ms" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_slot_state_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "availability_rule_listing_id_deleted_at_idx" ON "availability_rule"("listing_id", "deleted_at");

-- CreateIndex
CREATE INDEX "availability_exception_listing_id_deleted_at_start_date_idx" ON "availability_exception"("listing_id", "deleted_at", "start_date");

-- CreateIndex
CREATE INDEX "provider_time_off_provider_profile_id_deleted_at_start_date_idx" ON "provider_time_off"("provider_profile_id", "deleted_at", "start_date");

-- CreateIndex
CREATE INDEX "time_slot_listing_id_status_starts_at_idx" ON "time_slot"("listing_id", "status", "starts_at");

-- CreateIndex
CREATE INDEX "time_slot_provider_profile_id_starts_at_idx" ON "time_slot"("provider_profile_id", "starts_at");

-- CreateIndex
CREATE UNIQUE INDEX "time_slot_listing_id_starts_at_key" ON "time_slot"("listing_id", "starts_at");

-- CreateIndex
CREATE UNIQUE INDEX "reservation_time_slot_id_key" ON "reservation"("time_slot_id");

-- CreateIndex
CREATE INDEX "reservation_provider_profile_id_released_at_starts_at_idx" ON "reservation"("provider_profile_id", "released_at", "starts_at");

-- CreateIndex
CREATE INDEX "reservation_kind_released_at_expires_at_idx" ON "reservation"("kind", "released_at", "expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "listing_slot_state_listing_id_key" ON "listing_slot_state"("listing_id");

-- CreateIndex
CREATE INDEX "listing_slot_state_next_generation_at_idx" ON "listing_slot_state"("next_generation_at");

-- AddForeignKey
ALTER TABLE "availability_rule" ADD CONSTRAINT "availability_rule_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "availability_rule" ADD CONSTRAINT "availability_rule_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "availability_exception" ADD CONSTRAINT "availability_exception_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "availability_exception" ADD CONSTRAINT "availability_exception_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_time_off" ADD CONSTRAINT "provider_time_off_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "time_slot" ADD CONSTRAINT "time_slot_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "time_slot" ADD CONSTRAINT "time_slot_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reservation" ADD CONSTRAINT "reservation_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reservation" ADD CONSTRAINT "reservation_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reservation" ADD CONSTRAINT "reservation_time_slot_id_fkey" FOREIGN KEY ("time_slot_id") REFERENCES "time_slot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_slot_state" ADD CONSTRAINT "listing_slot_state_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_slot_state" ADD CONSTRAINT "listing_slot_state_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-written from here down. Prisma has no syntax for any of it.
-- ---------------------------------------------------------------------------

-- `btree_gist` is what lets a gist index hold the `=` operator on a uuid
-- alongside a range's `&&`. Without it the exclusion constraint below cannot
-- be created at all: gist knows ranges natively but not equality on a scalar.
-- Bundled with PostgreSQL's contrib modules, so this needs no package.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- An empty or inverted range never overlaps anything, so without these two a
-- row with ends_at <= starts_at would sail past the exclusion constraint and
-- silently disable the guarantee for that booking. Rejecting the row is the
-- only safe reading: there is no such thing as a zero-length appointment.
ALTER TABLE "time_slot"
  ADD CONSTRAINT "time_slot_ends_after_starts" CHECK ("ends_at" > "starts_at");

ALTER TABLE "reservation"
  ADD CONSTRAINT "reservation_ends_after_starts" CHECK ("ends_at" > "starts_at");

-- **The hard guarantee against double-booking** (plan §Phase 9a; root
-- CLAUDE.md invariant 1c).
--
-- Provider-scoped and range-based, deliberately replacing v2/v3's
-- `UNIQUE (providerId, listingId, startsAt)` — which allowed one provider to
-- be booked three times at 10:00 across three listings and detected nothing
-- at all about overlapping durations. This catches both, because it compares
-- the *interval* and ignores which listing it came from.
--
-- `tstzrange(starts_at, ends_at)` takes the default `[)` bounds, so 10:00–12:00
-- and 12:00–14:00 are adjacent rather than overlapping. That is what makes a
-- back-to-back grid generated from one availability rule bookable at all.
--
-- The `WHERE` is load-bearing. Invariant 8 keeps a released reservation row
-- forever; without the predicate a cancelled booking's time could never be
-- booked again by anyone, which is the exact opposite of §Phase 9a's "a
-- cancelled booking's slot reappears".
--
-- Application code cannot override this: it is enforced by the database on
-- every INSERT and UPDATE, inside whatever transaction the booking machine
-- (§Phase 17) opens, and a violation surfaces as SQLSTATE 23P01.
ALTER TABLE "reservation"
  ADD CONSTRAINT "reservation_provider_no_overlap"
  EXCLUDE USING gist (
    "provider_profile_id" WITH =,
    tstzrange("starts_at", "ends_at") WITH &&
  ) WHERE ("released_at" IS NULL);
