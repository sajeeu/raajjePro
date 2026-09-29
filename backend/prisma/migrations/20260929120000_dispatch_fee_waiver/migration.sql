-- §0.0 item 24: the platform waives a dispatch fee for a booking it cancelled itself.
-- AlterTable
ALTER TABLE "payment_submission" ADD COLUMN     "waived_at" TIMESTAMPTZ(6),
ADD COLUMN     "waived_reason" VARCHAR(80);

