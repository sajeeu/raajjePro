-- CreateEnum
CREATE TYPE "push_platform" AS ENUM ('android', 'ios');

-- CreateEnum
CREATE TYPE "push_permission" AS ENUM ('unknown', 'granted', 'denied');

-- CreateEnum
CREATE TYPE "device_token_revoked_reason" AS ENUM ('signed_out', 'unregistered', 'claimed_by_another_account', 'account_anonymised');

-- CreateEnum
CREATE TYPE "notification_kind" AS ENUM ('booking_accept_prompt', 'emergency_dispatch');

-- CreateEnum
CREATE TYPE "notification_urgency" AS ENUM ('standard', 'emergency');

-- CreateEnum
CREATE TYPE "email_fallback_reason" AS ENUM ('permission_denied', 'no_registered_device', 'emergency_parallel', 'unconfirmed_after_window');

-- CreateEnum
CREATE TYPE "push_delivery_status" AS ENUM ('sent', 'failed', 'skipped', 'confirmed');

-- AlterTable
ALTER TABLE "app_user" ADD COLUMN     "push_permission" "push_permission" NOT NULL DEFAULT 'unknown',
ADD COLUMN     "push_permission_updated_at" TIMESTAMPTZ(6);

-- CreateTable
CREATE TABLE "device_token" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "installation_id" TEXT NOT NULL,
    "platform" "push_platform" NOT NULL,
    "token" TEXT NOT NULL,
    "device_name" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "revoked_reason" "device_token_revoked_reason",

    CONSTRAINT "device_token_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "push_dispatch" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "kind" "notification_kind" NOT NULL,
    "urgency" "notification_urgency" NOT NULL,
    "subject_id" UUID,
    "context" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmed_at" TIMESTAMPTZ(6),
    "fallback_due_at" TIMESTAMPTZ(6),
    "email_sent_at" TIMESTAMPTZ(6),
    "email_reason" "email_fallback_reason",
    "email_message_id" UUID,

    CONSTRAINT "push_dispatch_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "push_delivery" (
    "id" UUID NOT NULL,
    "dispatch_id" UUID NOT NULL,
    "device_token_id" UUID NOT NULL,
    "status" "push_delivery_status" NOT NULL,
    "provider_message_id" TEXT,
    "failure_reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmed_at" TIMESTAMPTZ(6),

    CONSTRAINT "push_delivery_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "device_token_user_id_revoked_at_idx" ON "device_token"("user_id", "revoked_at");

-- CreateIndex
CREATE UNIQUE INDEX "device_token_user_id_installation_id_key" ON "device_token"("user_id", "installation_id");

-- CreateIndex
CREATE INDEX "push_dispatch_fallback_due_at_idx" ON "push_dispatch"("fallback_due_at");

-- CreateIndex
CREATE INDEX "push_dispatch_user_id_created_at_idx" ON "push_dispatch"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "push_dispatch_kind_created_at_idx" ON "push_dispatch"("kind", "created_at");

-- CreateIndex
CREATE INDEX "push_delivery_dispatch_id_idx" ON "push_delivery"("dispatch_id");

-- AddForeignKey
ALTER TABLE "device_token" ADD CONSTRAINT "device_token_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_dispatch" ADD CONSTRAINT "push_dispatch_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_dispatch" ADD CONSTRAINT "push_dispatch_email_message_id_fkey" FOREIGN KEY ("email_message_id") REFERENCES "email_message"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_delivery" ADD CONSTRAINT "push_delivery_dispatch_id_fkey" FOREIGN KEY ("dispatch_id") REFERENCES "push_dispatch"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_delivery" ADD CONSTRAINT "push_delivery_device_token_id_fkey" FOREIGN KEY ("device_token_id") REFERENCES "device_token"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-edited additions. Prisma tracks neither of these, so a regenerated
-- migration would lose them; test/schema-phase3c.test.ts asserts both.
-- ---------------------------------------------------------------------------

-- One LIVE registration per raw device token, across every account. A device
-- handed from one person to another re-registers the same token under a new
-- user; without this the old owner's row stays live and keeps receiving the
-- new owner's booking notifications. Revoked rows stay as history, so the
-- index is partial rather than a plain UNIQUE on the column.
CREATE UNIQUE INDEX "device_token_live_token_key"
  ON "device_token" ("token") WHERE "revoked_at" IS NULL;

-- The fallback sweep asks one question every minute: which dispatches are due
-- and still have no email? A partial index keeps that scan proportional to the
-- work outstanding rather than to every dispatch ever made.
CREATE INDEX "push_dispatch_fallback_pending_idx"
  ON "push_dispatch" ("fallback_due_at")
  WHERE "fallback_due_at" IS NOT NULL AND "email_sent_at" IS NULL;
