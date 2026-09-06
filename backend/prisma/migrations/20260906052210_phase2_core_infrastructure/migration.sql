-- CreateEnum
CREATE TYPE "idempotency_status" AS ENUM ('in_progress', 'completed', 'abandoned');

-- CreateEnum
CREATE TYPE "admin_status" AS ENUM ('active', 'disabled');

-- CreateEnum
CREATE TYPE "session_revoked_reason" AS ENUM ('logout', 'force_logout', 'idle_timeout', 'absolute_expiry', 'mfa_failures', 'password_change');

-- CreateEnum
CREATE TYPE "audit_actor_type" AS ENUM ('admin', 'system');

-- CreateEnum
CREATE TYPE "email_channel" AS ENUM ('otp', 'notification', 'marketing');

-- CreateEnum
CREATE TYPE "email_message_status" AS ENUM ('queued', 'sent', 'failed', 'suppressed', 'delivered', 'bounced', 'complained', 'rejected', 'delivery_delayed');

-- CreateEnum
CREATE TYPE "suppression_reason" AS ENUM ('hard_bounce', 'complaint', 'manual');

-- CreateTable
CREATE TABLE "rate_limit_counter" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "window_started_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "rate_limit_counter_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "idempotency_record" (
    "id" UUID NOT NULL,
    "subject" TEXT NOT NULL,
    "operation" TEXT NOT NULL,
    "client_key" TEXT NOT NULL,
    "request_hash" TEXT NOT NULL,
    "status" "idempotency_status" NOT NULL,
    "response_status" INTEGER,
    "response_headers" JSONB,
    "response_body" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMPTZ(6),

    CONSTRAINT "idempotency_record_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_user" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'admin',
    "status" "admin_status" NOT NULL DEFAULT 'active',
    "totp_secret_encrypted" TEXT,
    "totp_enrolled_at" TIMESTAMPTZ(6),
    "password_changed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "admin_user_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_session" (
    "id" UUID NOT NULL,
    "admin_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "mfa_verified_at" TIMESTAMPTZ(6),
    "reauthenticated_at" TIMESTAMPTZ(6),
    "mfa_failures" INTEGER NOT NULL DEFAULT 0,
    "ip_address" TEXT NOT NULL,
    "user_agent" TEXT NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "revoked_reason" "session_revoked_reason",

    CONSTRAINT "admin_session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_recovery_code" (
    "id" UUID NOT NULL,
    "admin_id" UUID NOT NULL,
    "code_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "used_at" TIMESTAMPTZ(6),
    "revoked_at" TIMESTAMPTZ(6),

    CONSTRAINT "admin_recovery_code_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log_entry" (
    "id" UUID NOT NULL,
    "actor_type" "audit_actor_type" NOT NULL,
    "actor_id" UUID,
    "action" TEXT NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "metadata" JSONB,
    "request_id" TEXT,
    "ip_address" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_log_entry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "email_message" (
    "id" UUID NOT NULL,
    "channel" "email_channel" NOT NULL,
    "to_address" TEXT NOT NULL,
    "recipient_user_id" UUID,
    "subject" TEXT NOT NULL,
    "status" "email_message_status" NOT NULL,
    "configuration_set" TEXT,
    "provider_message_id" TEXT,
    "failure_reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sent_at" TIMESTAMPTZ(6),
    "last_event_at" TIMESTAMPTZ(6),

    CONSTRAINT "email_message_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "email_event" (
    "id" UUID NOT NULL,
    "sns_message_id" TEXT NOT NULL,
    "message_id" UUID,
    "provider_message_id" TEXT,
    "event_type" TEXT NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "payload" JSONB NOT NULL,
    "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "email_event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "email_suppression" (
    "id" UUID NOT NULL,
    "address" TEXT NOT NULL,
    "reason" "suppression_reason" NOT NULL,
    "source_event_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lifted_at" TIMESTAMPTZ(6),
    "lifted_by_admin_id" UUID,
    "lift_reason" TEXT,

    CONSTRAINT "email_suppression_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "idempotency_record_subject_operation_client_key_key" ON "idempotency_record"("subject", "operation", "client_key");

-- CreateIndex
CREATE UNIQUE INDEX "admin_user_email_key" ON "admin_user"("email");

-- CreateIndex
CREATE UNIQUE INDEX "admin_session_token_hash_key" ON "admin_session"("token_hash");

-- CreateIndex
CREATE INDEX "admin_session_admin_id_revoked_at_idx" ON "admin_session"("admin_id", "revoked_at");

-- CreateIndex
CREATE INDEX "admin_recovery_code_admin_id_code_hash_idx" ON "admin_recovery_code"("admin_id", "code_hash");

-- CreateIndex
CREATE INDEX "audit_log_entry_created_at_idx" ON "audit_log_entry"("created_at");

-- CreateIndex
CREATE INDEX "audit_log_entry_actor_id_created_at_idx" ON "audit_log_entry"("actor_id", "created_at");

-- CreateIndex
CREATE INDEX "audit_log_entry_action_created_at_idx" ON "audit_log_entry"("action", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "email_message_provider_message_id_key" ON "email_message"("provider_message_id");

-- CreateIndex
CREATE INDEX "email_message_to_address_created_at_idx" ON "email_message"("to_address", "created_at");

-- CreateIndex
CREATE INDEX "email_message_recipient_user_id_created_at_idx" ON "email_message"("recipient_user_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "email_event_sns_message_id_key" ON "email_event"("sns_message_id");

-- CreateIndex
CREATE INDEX "email_event_provider_message_id_idx" ON "email_event"("provider_message_id");

-- CreateIndex
CREATE INDEX "email_suppression_address_idx" ON "email_suppression"("address");

-- AddForeignKey
ALTER TABLE "admin_session" ADD CONSTRAINT "admin_session_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "admin_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "admin_recovery_code" ADD CONSTRAINT "admin_recovery_code_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "admin_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "email_event" ADD CONSTRAINT "email_event_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "email_message"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-edited additions. Prisma tracks neither of these, so a regenerated
-- migration would lose them; test/schema.test.ts asserts both.
-- ---------------------------------------------------------------------------

-- Ephemeral counters stay out of the WAL (and so out of PITR). An unclean
-- shutdown truncates the table: every limit fails open for one window.
ALTER TABLE "rate_limit_counter" SET UNLOGGED;

-- One ACTIVE suppression per address; lifted rows stay as history.
CREATE UNIQUE INDEX "email_suppression_active_address_key"
  ON "email_suppression" ("address") WHERE "lifted_at" IS NULL;
