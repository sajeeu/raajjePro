-- Phase 17.4 — recurring series, reschedule, the callback guarantee and saved
-- preferences. Additive only: two enum values, three booking columns, one
-- amendment column, five new tables. See
-- docs/decisions/31-phase-17-4-recurring-reschedule-callback.md.

-- CreateEnum
CREATE TYPE "recurring_series_status" AS ENUM ('active', 'paused', 'ended');

-- CreateEnum
CREATE TYPE "recurring_occurrence_state" AS ENUM ('asked', 'accepted', 'missed', 'skipped', 'withdrawn');

-- CreateEnum
CREATE TYPE "recurring_miss_reason" AS ENUM ('declined', 'timed_out', 'no_open_slot', 'could_not_ask');

-- AlterEnum
ALTER TYPE "amount_kind" ADD VALUE 'callback';

-- AlterEnum
ALTER TYPE "report_reason" ADD VALUE 'callback_declined';

-- AlterTable
ALTER TABLE "booking" ADD COLUMN     "callback_for_booking_id" UUID,
ADD COLUMN     "callback_guaranteed" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "rescheduled_at" TIMESTAMPTZ(6);

-- AlterTable
ALTER TABLE "booking_amendment" ADD COLUMN     "proposed_time_slot_id" UUID;

-- CreateTable
CREATE TABLE "recurring_series" (
    "id" UUID NOT NULL,
    "customer_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "origin_booking_id" UUID NOT NULL,
    "status" "recurring_series_status" NOT NULL DEFAULT 'active',
    "next_occurrence_at" TIMESTAMPTZ(6) NOT NULL,
    "next_ask_at" TIMESTAMPTZ(6),
    "consecutive_misses" INTEGER NOT NULL DEFAULT 0,
    "job_notes" VARCHAR(2000),
    "island_id" UUID,
    "address_detail" VARCHAR(300),
    "paused_at" TIMESTAMPTZ(6),
    "ended_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "recurring_series_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recurring_occurrence" (
    "id" UUID NOT NULL,
    "series_id" UUID NOT NULL,
    "occurs_at" TIMESTAMPTZ(6) NOT NULL,
    "booking_id" UUID,
    "state" "recurring_occurrence_state" NOT NULL,
    "miss_reason" "recurring_miss_reason",
    "resolved_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "recurring_occurrence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_address" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "label" VARCHAR(40) NOT NULL,
    "island_id" UUID NOT NULL,
    "address_line" VARCHAR(300) NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "saved_address_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_time_window" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "weekdays" INTEGER[],
    "start_minute" INTEGER NOT NULL,
    "end_minute" INTEGER NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "saved_time_window_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_preferences" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "standing_instructions" VARCHAR(500),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "saved_preferences_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "recurring_series_status_next_ask_at_idx" ON "recurring_series"("status", "next_ask_at");

-- CreateIndex
CREATE INDEX "recurring_series_customer_id_created_at_idx" ON "recurring_series"("customer_id", "created_at");

-- CreateIndex
CREATE INDEX "recurring_series_provider_profile_id_created_at_idx" ON "recurring_series"("provider_profile_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "recurring_occurrence_booking_id_key" ON "recurring_occurrence"("booking_id");

-- CreateIndex
CREATE INDEX "recurring_occurrence_state_idx" ON "recurring_occurrence"("state");

-- CreateIndex
CREATE UNIQUE INDEX "recurring_occurrence_series_id_occurs_at_key" ON "recurring_occurrence"("series_id", "occurs_at");

-- CreateIndex
CREATE INDEX "saved_address_user_id_deleted_at_created_at_idx" ON "saved_address"("user_id", "deleted_at", "created_at");

-- CreateIndex
CREATE INDEX "saved_time_window_user_id_deleted_at_created_at_idx" ON "saved_time_window"("user_id", "deleted_at", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "saved_preferences_user_id_key" ON "saved_preferences"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "booking_callback_for_booking_id_key" ON "booking"("callback_for_booking_id");

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_callback_for_booking_id_fkey" FOREIGN KEY ("callback_for_booking_id") REFERENCES "booking"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_series" ADD CONSTRAINT "recurring_series_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_series" ADD CONSTRAINT "recurring_series_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_series" ADD CONSTRAINT "recurring_series_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_series" ADD CONSTRAINT "recurring_series_origin_booking_id_fkey" FOREIGN KEY ("origin_booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_series" ADD CONSTRAINT "recurring_series_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_occurrence" ADD CONSTRAINT "recurring_occurrence_series_id_fkey" FOREIGN KEY ("series_id") REFERENCES "recurring_series"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recurring_occurrence" ADD CONSTRAINT "recurring_occurrence_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_address" ADD CONSTRAINT "saved_address_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_address" ADD CONSTRAINT "saved_address_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_time_window" ADD CONSTRAINT "saved_time_window_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_preferences" ADD CONSTRAINT "saved_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
