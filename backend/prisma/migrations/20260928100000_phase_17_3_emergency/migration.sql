-- CreateEnum
CREATE TYPE "emergency_offer_state" AS ENUM ('open', 'selected', 'not_selected', 'rejected', 'expired', 'lapsed', 'no_show', 'cancelled');

-- CreateEnum
CREATE TYPE "kill_switch_key" AS ENUM ('emergency_contact_reveal');

-- AlterEnum
ALTER TYPE "report_reason" ADD VALUE 'provider_verification_revoked';

-- AlterTable
ALTER TABLE "booking" ADD COLUMN     "dispatch_fee_submission_id" UUID,
ADD COLUMN     "emergency_offer_count" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "emergency_window_ends_at" TIMESTAMPTZ(6),
ADD COLUMN     "offer_collection_closes_at" TIMESTAMPTZ(6),
ADD COLUMN     "rejected_provider_ids" UUID[] DEFAULT ARRAY[]::UUID[];

-- CreateTable
CREATE TABLE "emergency_offer" (
    "id" UUID NOT NULL,
    "booking_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "callout_fee_laari" INTEGER NOT NULL,
    "eta_minutes" INTEGER NOT NULL,
    "state" "emergency_offer_state" NOT NULL DEFAULT 'open',
    "closed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "emergency_offer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "contact_reveal_event" (
    "id" UUID NOT NULL,
    "booking_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "actor_role" "booking_actor_role" NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "contact_reveal_event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "kill_switch" (
    "id" UUID NOT NULL,
    "key" "kill_switch_key" NOT NULL,
    "engaged" BOOLEAN NOT NULL DEFAULT false,
    "changed_by_admin_id" UUID,
    "changed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "kill_switch_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "emergency_offer_booking_id_state_created_at_idx" ON "emergency_offer"("booking_id", "state", "created_at");

-- CreateIndex
CREATE INDEX "emergency_offer_provider_profile_id_state_created_at_idx" ON "emergency_offer"("provider_profile_id", "state", "created_at");

-- CreateIndex
CREATE INDEX "contact_reveal_event_booking_id_created_at_idx" ON "contact_reveal_event"("booking_id", "created_at");

-- CreateIndex
CREATE INDEX "contact_reveal_event_user_id_created_at_idx" ON "contact_reveal_event"("user_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "kill_switch_key_key" ON "kill_switch"("key");

-- CreateIndex
CREATE UNIQUE INDEX "booking_dispatch_fee_submission_id_key" ON "booking"("dispatch_fee_submission_id");

-- CreateIndex
CREATE INDEX "booking_status_emergency_window_ends_at_idx" ON "booking"("status", "emergency_window_ends_at");

-- CreateIndex
CREATE INDEX "booking_status_offer_collection_closes_at_idx" ON "booking"("status", "offer_collection_closes_at");

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_dispatch_fee_submission_id_fkey" FOREIGN KEY ("dispatch_fee_submission_id") REFERENCES "payment_submission"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_offer" ADD CONSTRAINT "emergency_offer_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_offer" ADD CONSTRAINT "emergency_offer_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "emergency_offer" ADD CONSTRAINT "emergency_offer_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contact_reveal_event" ADD CONSTRAINT "contact_reveal_event_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- §Phase 17.3, hand-written: one OPEN offer per provider per request.
--
-- Prisma cannot express a partial unique index. It has to be partial because a
-- provider whose offer expired (the customer said nothing for 5 minutes) is
-- released without exclusion and may answer the re-broadcast — so a plain
-- unique pair would refuse a legitimate second offer, while no index at all
-- would let a double tap put two bids from one provider side by side.
CREATE UNIQUE INDEX "emergency_offer_one_open_per_provider"
  ON "emergency_offer" ("booking_id", "provider_profile_id")
  WHERE "state" = 'open';
