-- CreateEnum
CREATE TYPE "payment_purpose" AS ENUM ('subscription', 'emergency_dispatch_fee');

-- CreateEnum
CREATE TYPE "payment_submission_status" AS ENUM ('pending', 'confirmed', 'rejected');

-- CreateEnum
CREATE TYPE "subscription_tier" AS ENUM ('free', 'premium');

-- CreateEnum
CREATE TYPE "subscription_status" AS ENUM ('trialing', 'active', 'paused', 'expired', 'free');

-- CreateTable
CREATE TABLE "provider_subscription" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "tier" "subscription_tier" NOT NULL DEFAULT 'free',
    "status" "subscription_status" NOT NULL DEFAULT 'free',
    "trial_started_at" TIMESTAMPTZ(6),
    "trial_ends_at" TIMESTAMPTZ(6),
    "billing_anchor_at" TIMESTAMPTZ(6),
    "current_period_end" TIMESTAMPTZ(6),
    "paused_at" TIMESTAMPTZ(6),
    "cumulative_paused_minutes" INTEGER NOT NULL DEFAULT 0,
    "trial_ending_notice_at" TIMESTAMPTZ(6),
    "period_ending_notice_at" TIMESTAMPTZ(6),
    "downgraded_at" TIMESTAMPTZ(6),
    "winback_day7_at" TIMESTAMPTZ(6),
    "winback_day30_at" TIMESTAMPTZ(6),
    "introductory_notice_at" TIMESTAMPTZ(6),
    "introductory_converted_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_submission" (
    "id" UUID NOT NULL,
    "payer_id" UUID NOT NULL,
    "purpose" "payment_purpose" NOT NULL,
    "amount_laari" INTEGER NOT NULL,
    "reference_code" TEXT NOT NULL,
    "status" "payment_submission_status" NOT NULL DEFAULT 'pending',
    "proof_object_key" TEXT,
    "proof_content_type" TEXT,
    "proof_byte_size" INTEGER,
    "submitted_at" TIMESTAMPTZ(6),
    "reviewed_by_admin_id" UUID,
    "reviewed_at" TIMESTAMPTZ(6),
    "rejection_reason" TEXT,
    "reversed_at" TIMESTAMPTZ(6),
    "reversed_by_admin_id" UUID,
    "reversal_reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "payment_submission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoice" (
    "id" UUID NOT NULL,
    "invoice_number" TEXT NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "payment_submission_id" UUID NOT NULL,
    "amount_laari" INTEGER NOT NULL,
    "period_start" TIMESTAMPTZ(6) NOT NULL,
    "period_end" TIMESTAMPTZ(6) NOT NULL,
    "issued_at" TIMESTAMPTZ(6) NOT NULL,
    "object_key" TEXT NOT NULL,
    "voided_at" TIMESTAMPTZ(6),
    "voided_reason" TEXT,

    CONSTRAINT "invoice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "provider_subscription_provider_profile_id_key" ON "provider_subscription"("provider_profile_id");

-- CreateIndex
CREATE INDEX "provider_subscription_status_trial_ends_at_idx" ON "provider_subscription"("status", "trial_ends_at");

-- CreateIndex
CREATE INDEX "provider_subscription_status_current_period_end_idx" ON "provider_subscription"("status", "current_period_end");

-- CreateIndex
CREATE INDEX "provider_subscription_status_downgraded_at_idx" ON "provider_subscription"("status", "downgraded_at");

-- CreateIndex
CREATE UNIQUE INDEX "payment_submission_reference_code_key" ON "payment_submission"("reference_code");

-- CreateIndex
CREATE UNIQUE INDEX "payment_submission_proof_object_key_key" ON "payment_submission"("proof_object_key");

-- CreateIndex
CREATE INDEX "payment_submission_purpose_status_submitted_at_idx" ON "payment_submission"("purpose", "status", "submitted_at");

-- CreateIndex
CREATE INDEX "payment_submission_payer_id_created_at_idx" ON "payment_submission"("payer_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_invoice_number_key" ON "invoice"("invoice_number");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_payment_submission_id_key" ON "invoice"("payment_submission_id");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_object_key_key" ON "invoice"("object_key");

-- CreateIndex
CREATE INDEX "invoice_provider_profile_id_issued_at_idx" ON "invoice"("provider_profile_id", "issued_at");

-- AddForeignKey
ALTER TABLE "provider_subscription" ADD CONSTRAINT "provider_subscription_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_submission" ADD CONSTRAINT "payment_submission_payer_id_fkey" FOREIGN KEY ("payer_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoice" ADD CONSTRAINT "invoice_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoice" ADD CONSTRAINT "invoice_payment_submission_id_fkey" FOREIGN KEY ("payment_submission_id") REFERENCES "payment_submission"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- The invoice number's source (§1b step 6). A sequence rather than a count of
-- existing rows: two admins confirming two payments at the same moment would
-- both read the same count and issue two invoices carrying the same number,
-- and an invoice number that is not unique is not an invoice number. Gaps are
-- acceptable (a rolled-back confirmation consumes one); collisions are not.
CREATE SEQUENCE "invoice_number_seq" AS BIGINT START WITH 1 OWNED BY "invoice"."invoice_number";
