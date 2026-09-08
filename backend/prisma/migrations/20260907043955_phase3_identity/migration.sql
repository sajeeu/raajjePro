-- CreateEnum
CREATE TYPE "user_status" AS ENUM ('active', 'frozen', 'anonymised');

-- CreateEnum
CREATE TYPE "verification_tier" AS ENUM ('none', 'bronze', 'silver', 'gold');

-- CreateEnum
CREATE TYPE "verification_status" AS ENUM ('unverified', 'pending', 'verified');

-- CreateEnum
CREATE TYPE "user_session_revoked_reason" AS ENUM ('logout', 'revoked_by_user', 'refresh_expired', 'refresh_reuse', 'password_change', 'email_change', 'anonymised');

-- CreateEnum
CREATE TYPE "otp_purpose" AS ENUM ('verify_email', 'change_email');

-- AlterEnum
ALTER TYPE "audit_actor_type" ADD VALUE 'user';

-- CreateTable
CREATE TABLE "app_user" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "email_verified_at" TIMESTAMPTZ(6),
    "password_hash" TEXT NOT NULL,
    "full_name" TEXT NOT NULL,
    "phone_e164" TEXT,
    "phone_dial_code" TEXT,
    "status" "user_status" NOT NULL DEFAULT 'active',
    "terms_accepted_at" TIMESTAMPTZ(6) NOT NULL,
    "deletion_requested_at" TIMESTAMPTZ(6),
    "deletion_deadline_at" TIMESTAMPTZ(6),
    "anonymised_at" TIMESTAMPTZ(6),
    "password_changed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "app_user_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_profile" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "business_name" TEXT,
    "verification_tier" "verification_tier" NOT NULL DEFAULT 'none',
    "verification_status" "verification_status" NOT NULL DEFAULT 'unverified',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_profile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_session" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_name" TEXT NOT NULL,
    "ip_address" TEXT NOT NULL,
    "user_agent" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "revoked_reason" "user_session_revoked_reason",

    CONSTRAINT "user_session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_token" (
    "id" UUID NOT NULL,
    "session_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "rotated_at" TIMESTAMPTZ(6),
    "replaced_by_id" UUID,

    CONSTRAINT "refresh_token_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "email_otp" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "purpose" "otp_purpose" NOT NULL,
    "target_email" TEXT NOT NULL,
    "code_hash" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "consumed_at" TIMESTAMPTZ(6),
    "invalidated_at" TIMESTAMPTZ(6),
    "email_message_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "email_otp_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "app_user_email_key" ON "app_user"("email");

-- CreateIndex
CREATE INDEX "app_user_phone_e164_idx" ON "app_user"("phone_e164");

-- CreateIndex
CREATE INDEX "app_user_status_deletion_deadline_at_idx" ON "app_user"("status", "deletion_deadline_at");

-- CreateIndex
CREATE UNIQUE INDEX "provider_profile_user_id_key" ON "provider_profile"("user_id");

-- CreateIndex
CREATE INDEX "user_session_user_id_revoked_at_idx" ON "user_session"("user_id", "revoked_at");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_token_token_hash_key" ON "refresh_token"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_token_session_id_rotated_at_idx" ON "refresh_token"("session_id", "rotated_at");

-- CreateIndex
CREATE INDEX "email_otp_user_id_purpose_created_at_idx" ON "email_otp"("user_id", "purpose", "created_at");

-- CreateIndex
CREATE INDEX "email_otp_target_email_created_at_idx" ON "email_otp"("target_email", "created_at");

-- AddForeignKey
ALTER TABLE "provider_profile" ADD CONSTRAINT "provider_profile_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_session" ADD CONSTRAINT "user_session_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_token" ADD CONSTRAINT "refresh_token_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "user_session"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "email_otp" ADD CONSTRAINT "email_otp_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "email_otp" ADD CONSTRAINT "email_otp_email_message_id_fkey" FOREIGN KEY ("email_message_id") REFERENCES "email_message"("id") ON DELETE SET NULL ON UPDATE CASCADE;
