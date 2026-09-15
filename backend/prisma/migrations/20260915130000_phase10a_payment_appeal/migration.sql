-- AlterTable
ALTER TABLE "payment_submission" ADD COLUMN     "appeal_note" TEXT,
ADD COLUMN     "appealed_at" TIMESTAMPTZ(6);
