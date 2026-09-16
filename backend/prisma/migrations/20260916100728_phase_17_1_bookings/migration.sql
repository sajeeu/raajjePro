-- CreateEnum
CREATE TYPE "booking_status" AS ENUM ('requested', 'awaiting_quote', 'quote_offered', 'emergency_offered', 'accepted', 'awaiting_payment', 'payment_claimed', 'confirmed', 'completed', 'cancelled', 'declined', 'disputed', 'dispute_resolved', 'payment_unresolved');

-- CreateEnum
CREATE TYPE "amount_kind" AS ENUM ('fixed_price', 'hourly_total', 'daily_total', 'quoted', 'callout_fee');

-- CreateEnum
CREATE TYPE "booking_completed_via" AS ENUM ('confirmed', 'unconfirmed');

-- CreateEnum
CREATE TYPE "booking_actor_role" AS ENUM ('customer', 'provider', 'admin', 'system');

-- CreateEnum
CREATE TYPE "dispute_outcome" AS ENUM ('resolved_for_customer', 'resolved_for_provider', 'inconclusive', 'fraud_confirmed', 'withdrawn');

-- CreateEnum
CREATE TYPE "booking_amendment_status" AS ENUM ('proposed', 'accepted', 'rejected', 'withdrawn');

-- CreateEnum
CREATE TYPE "report_target_type" AS ENUM ('listing', 'review', 'user', 'booking', 'message', 'photo');

-- CreateEnum
CREATE TYPE "report_reason" AS ENUM ('misleading_description', 'wrong_category', 'contact_details_in_listing', 'prohibited_service', 'not_the_real_provider', 'fake_review', 'abusive_language', 'not_about_this_service', 'harassment', 'impersonation', 'fraud', 'repeated_no_show', 'work_not_done', 'price_changed_on_site', 'unsafe_work', 'payment_dispute', 'contact_solicitation', 'spam', 'abusive_content', 'not_own_work', 'inappropriate_content', 'contains_contact_details');

-- CreateEnum
CREATE TYPE "report_status" AS ENUM ('open', 'under_review', 'resolved', 'dismissed');

-- CreateEnum
CREATE TYPE "booking_kind" AS ENUM ('slot', 'request', 'emergency');

-- CreateTable
CREATE TABLE "booking" (
    "id" UUID NOT NULL,
    "reference" VARCHAR(12) NOT NULL,
    "listing_id" UUID NOT NULL,
    "customer_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "booking_mode" "booking_kind" NOT NULL,
    "status" "booking_status" NOT NULL DEFAULT 'requested',
    "time_slot_id" UUID,
    "reservation_id" UUID,
    "agreed_amount_laari" INTEGER,
    "amount_kind" "amount_kind",
    "quoted_amount_laari" INTEGER,
    "final_amount_laari" INTEGER,
    "amount_set_at" TIMESTAMPTZ(6),
    "scheduled_for" TIMESTAMPTZ(6),
    "preferred_window_text" VARCHAR(300),
    "preferred_window_from" TIMESTAMPTZ(6),
    "preferred_window_to" TIMESTAMPTZ(6),
    "occasion" VARCHAR(80),
    "job_notes" VARCHAR(2000),
    "island_id" UUID,
    "address_detail" VARCHAR(300),
    "payment_claimed_at" TIMESTAMPTZ(6),
    "payment_claim_withdrawn_at" TIMESTAMPTZ(6),
    "payment_attested_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "completed_via" "booking_completed_via",
    "completion_prompted_at" TIMESTAMPTZ(6),
    "cancelled_at" TIMESTAMPTZ(6),
    "cancelled_by_role" "booking_actor_role",
    "cancellation_reason" VARCHAR(500),
    "declined_at" TIMESTAMPTZ(6),
    "disputed_at" TIMESTAMPTZ(6),
    "dispute_outcome" "dispute_outcome",
    "dispute_resolved_at" TIMESTAMPTZ(6),
    "trial_hook_fired_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "booking_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "booking_status_event" (
    "id" UUID NOT NULL,
    "booking_id" UUID NOT NULL,
    "from_status" "booking_status",
    "to_status" "booking_status" NOT NULL,
    "actor_role" "booking_actor_role" NOT NULL,
    "actor_user_id" UUID,
    "transition" VARCHAR(60) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "booking_status_event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "booking_amendment" (
    "id" UUID NOT NULL,
    "booking_id" UUID NOT NULL,
    "proposed_by_role" "booking_actor_role" NOT NULL,
    "proposed_by_user_id" UUID NOT NULL,
    "previous_amount_laari" INTEGER,
    "previous_scheduled_for" TIMESTAMPTZ(6),
    "previous_scope_note" VARCHAR(2000),
    "proposed_amount_laari" INTEGER,
    "proposed_scheduled_for" TIMESTAMPTZ(6),
    "proposed_scope_note" VARCHAR(2000),
    "reason" VARCHAR(500),
    "status" "booking_amendment_status" NOT NULL DEFAULT 'proposed',
    "responded_by_user_id" UUID,
    "responded_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "booking_amendment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "report" (
    "id" UUID NOT NULL,
    "reporter_id" UUID,
    "target_type" "report_target_type" NOT NULL,
    "target_id" UUID NOT NULL,
    "booking_id" UUID,
    "reason" "report_reason" NOT NULL,
    "note" VARCHAR(1000),
    "status" "report_status" NOT NULL DEFAULT 'open',
    "reviewed_by_admin_id" UUID,
    "reviewed_at" TIMESTAMPTZ(6),
    "resolution_reason" VARCHAR(500),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "report_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "booking_reference_key" ON "booking"("reference");

-- CreateIndex
CREATE UNIQUE INDEX "booking_time_slot_id_key" ON "booking"("time_slot_id");

-- CreateIndex
CREATE UNIQUE INDEX "booking_reservation_id_key" ON "booking"("reservation_id");

-- CreateIndex
CREATE INDEX "booking_customer_id_status_created_at_idx" ON "booking"("customer_id", "status", "created_at");

-- CreateIndex
CREATE INDEX "booking_provider_profile_id_status_created_at_idx" ON "booking"("provider_profile_id", "status", "created_at");

-- CreateIndex
CREATE INDEX "booking_listing_id_status_scheduled_for_idx" ON "booking"("listing_id", "status", "scheduled_for");

-- CreateIndex
CREATE INDEX "booking_status_created_at_idx" ON "booking"("status", "created_at");

-- CreateIndex
CREATE INDEX "booking_status_event_booking_id_created_at_idx" ON "booking_status_event"("booking_id", "created_at");

-- CreateIndex
CREATE INDEX "booking_amendment_booking_id_status_created_at_idx" ON "booking_amendment"("booking_id", "status", "created_at");

-- CreateIndex
CREATE INDEX "report_status_created_at_idx" ON "report"("status", "created_at");

-- CreateIndex
CREATE INDEX "report_target_type_target_id_idx" ON "report"("target_type", "target_id");

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_time_slot_id_fkey" FOREIGN KEY ("time_slot_id") REFERENCES "time_slot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "reservation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking" ADD CONSTRAINT "booking_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking_status_event" ADD CONSTRAINT "booking_status_event_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "booking_amendment" ADD CONSTRAINT "booking_amendment_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "report" ADD CONSTRAINT "report_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "app_user"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "report" ADD CONSTRAINT "report_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE SET NULL ON UPDATE CASCADE;
