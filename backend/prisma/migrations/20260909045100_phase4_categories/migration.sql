-- CreateEnum
CREATE TYPE "booking_mode" AS ENUM ('slot', 'request');

-- CreateTable
CREATE TABLE "category" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "icon_identifier" TEXT NOT NULL,
    "color_token" TEXT NOT NULL,
    "sort_order" INTEGER NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "booking_mode" "booking_mode" NOT NULL,
    "emergency_capable" BOOLEAN NOT NULL DEFAULT false,
    "minimum_lead_time_minutes" INTEGER NOT NULL,
    "emergency_accept_window_minutes" INTEGER,
    "emergency_minimum_tier" "verification_tier",
    "emergency_eta_presets_minutes" INTEGER[],
    "quote_expiry_minutes" INTEGER,
    "quote_approval_minutes" INTEGER,
    "callback_eligible" BOOLEAN NOT NULL DEFAULT false,
    "occasion_presets" TEXT[],
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "category_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "category_name_key" ON "category"("name");

-- CreateIndex
CREATE INDEX "category_is_active_sort_order_idx" ON "category"("is_active", "sort_order");
