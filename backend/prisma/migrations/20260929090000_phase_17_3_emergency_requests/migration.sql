-- §Phase 17.3, second migration: an emergency is raised by category and
-- island, not against a listing (owner's decision, 2026-09-28 — Round 23:
-- "dispatch never targets a provider"). The pre-selection half of the machine
-- moves from `booking` onto a new `emergency_request`; a booking is created
-- when the customer selects an offer, so `booking.listing_id` and
-- `provider_profile_id` stay NOT NULL and nothing in 17.1 or 17.2 changes.
--
-- `emergency_offer` gains a NOT NULL `emergency_request_id` without a
-- backfill. That is safe only because the table is one day old and has never
-- held a row outside a test run — asserted below rather than assumed.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "emergency_offer") THEN
    RAISE EXCEPTION 'emergency_offer has rows; this migration assumes it is empty';
  END IF;
END $$;

-- The partial index keyed on the booking goes; it is re-created on the request below.
DROP INDEX IF EXISTS "emergency_offer_one_open_per_provider";

-- CreateEnum
CREATE TYPE "emergency_request_status" AS ENUM ('requested', 'emergency_offered', 'matched', 'declined', 'cancelled');

-- DropForeignKey
ALTER TABLE "booking" DROP CONSTRAINT "booking_dispatch_fee_submission_id_fkey";

-- DropForeignKey
ALTER TABLE "emergency_offer" DROP CONSTRAINT "emergency_offer_booking_id_fkey";

-- DropIndex
DROP INDEX "booking_dispatch_fee_submission_id_key";

-- DropIndex
DROP INDEX "booking_status_emergency_window_ends_at_idx";

-- DropIndex
DROP INDEX "booking_status_offer_collection_closes_at_idx";

-- DropIndex
DROP INDEX "emergency_offer_booking_id_state_created_at_idx";

-- AlterTable
ALTER TABLE "booking" DROP COLUMN "dispatch_fee_submission_id",
DROP COLUMN "emergency_offer_count",
DROP COLUMN "emergency_window_ends_at",
DROP COLUMN "offer_collection_closes_at",
DROP COLUMN "rejected_provider_ids",
ADD COLUMN     "emergency_request_id" UUID;

-- AlterTable
ALTER TABLE "emergency_offer" ADD COLUMN     "emergency_request_id" UUID NOT NULL,
ALTER COLUMN "booking_id" DROP NOT NULL;

-- CreateTable
CREATE TABLE "emergency_request" (
    "id" UUID NOT NULL,
    "customer_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "island_id" UUID NOT NULL,
    "address_detail" VARCHAR(300),
    "job_notes" VARCHAR(2000) NOT NULL,
    "status" "emergency_request_status" NOT NULL DEFAULT 'requested',
    "window_ends_at" TIMESTAMPTZ(6) NOT NULL,
    "offer_collection_closes_at" TIMESTAMPTZ(6),
    "rejected_provider_ids" UUID[] DEFAULT ARRAY[]::UUID[],
    "dispatch_fee_submission_id" UUID,
    "closed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "emergency_request_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "emergency_pass" (
    "id" UUID NOT NULL,
    "emergency_request_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "emergency_pass_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "emergency_request_dispatch_fee_submission_id_key" ON "emergency_request"("dispatch_fee_submission_id");

-- CreateIndex
CREATE INDEX "emergency_request_customer_id_created_at_idx" ON "emergency_request"("customer_id", "created_at");

-- CreateIndex
CREATE INDEX "emergency_request_status_window_ends_at_idx" ON "emergency_request"("status", "window_ends_at");

-- CreateIndex
CREATE INDEX "emergency_request_status_offer_collection_closes_at_idx" ON "emergency_request"("status", "offer_collection_closes_at");

-- CreateIndex
CREATE INDEX "emergency_request_category_id_island_id_status_idx" ON "emergency_request"("category_id", "island_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "emergency_pass_emergency_request_id_provider_profile_id_key" ON "emergency_pass"("emergency_request_id", "provider_profile_id");

-- CreateIndex
CREATE INDEX "booking_emergency_request_id_idx" ON "booking"("emergency_request_id");

-- CreateIndex
CREATE UNIQUE INDEX "emergency_offer_booking_id_key" ON "emergency_offer"("booking_id");

-- CreateIndex
CREATE INDEX "emergency_offer_emergency_request_id_state_created_at_idx" ON "emergency_offer"("emergency_request_id", "state", "created_at");

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_emergency_request_id_fkey" FOREIGN KEY ("emergency_request_id") REFERENCES "emergency_request"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_offer" ADD CONSTRAINT "emergency_offer_emergency_request_id_fkey" FOREIGN KEY ("emergency_request_id") REFERENCES "emergency_request"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_offer" ADD CONSTRAINT "emergency_offer_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_request" ADD CONSTRAINT "emergency_request_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_request" ADD CONSTRAINT "emergency_request_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_request" ADD CONSTRAINT "emergency_request_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_request" ADD CONSTRAINT "emergency_request_dispatch_fee_submission_id_fkey" FOREIGN KEY ("dispatch_fee_submission_id") REFERENCES "payment_submission"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_pass" ADD CONSTRAINT "emergency_pass_emergency_request_id_fkey" FOREIGN KEY ("emergency_request_id") REFERENCES "emergency_request"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_pass" ADD CONSTRAINT "emergency_pass_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- One OPEN offer per provider per request. Partial, because a provider whose
-- offer expired (the customer said nothing for five minutes) is released
-- without exclusion and may answer the re-broadcast. Prisma cannot express it.
CREATE UNIQUE INDEX "emergency_offer_one_open_per_provider"
  ON "emergency_offer" ("emergency_request_id", "provider_profile_id")
  WHERE "state" = 'open';
