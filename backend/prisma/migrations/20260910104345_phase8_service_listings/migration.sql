-- CreateEnum
CREATE TYPE "pricing_model" AS ENUM ('fixed', 'hourly', 'daily', 'range', 'quote');

-- CreateEnum
CREATE TYPE "price_unit" AS ENUM ('job', 'hour', 'day', 'session', 'visit');

-- CreateEnum
CREATE TYPE "listing_status" AS ENUM ('draft', 'published');

-- CreateEnum
CREATE TYPE "listing_visibility" AS ENUM ('active', 'hidden_by_provider', 'hidden_over_cap', 'hidden_by_admin');

-- CreateEnum
CREATE TYPE "listing_media_status" AS ENUM ('pending', 'stored');

-- CreateEnum
CREATE TYPE "listing_event_kind" AS ENUM ('view', 'booking');

-- AlterTable
ALTER TABLE "category" ADD COLUMN     "suggested_tags" TEXT[];

-- CreateTable
CREATE TABLE "listing" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "category_id" UUID,
    "name" TEXT,
    "short_description" VARCHAR(200),
    "long_description" VARCHAR(2000),
    "tags" TEXT[],
    "pricing_model" "pricing_model",
    "price_laari" INTEGER,
    "price_min_laari" INTEGER,
    "price_max_laari" INTEGER,
    "price_unit" "price_unit",
    "booking_mode" "booking_mode",
    "working_days" INTEGER[],
    "working_hours_from" VARCHAR(5),
    "working_hours_to" VARCHAR(5),
    "is_emergency" BOOLEAN NOT NULL DEFAULT false,
    "whats_included" VARCHAR(1000),
    "whats_not_included" VARCHAR(1000),
    "faqs" JSONB NOT NULL DEFAULT '[]',
    "warranty_offered" BOOLEAN NOT NULL DEFAULT false,
    "warranty_terms_text" VARCHAR(500),
    "insurance_declared" BOOLEAN NOT NULL DEFAULT false,
    "insurance_detail_text" VARCHAR(500),
    "callback_guarantee_offered" BOOLEAN NOT NULL DEFAULT false,
    "cover_media_id" UUID,
    "status" "listing_status" NOT NULL DEFAULT 'draft',
    "visibility" "listing_visibility" NOT NULL DEFAULT 'active',
    "published_at" TIMESTAMPTZ(6),
    "first_published_at" TIMESTAMPTZ(6),
    "deleted_at" TIMESTAMPTZ(6),
    "view_count" INTEGER NOT NULL DEFAULT 0,
    "booking_count" INTEGER NOT NULL DEFAULT 0,
    "counts_rolled_up_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_service_area" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "island_id" UUID NOT NULL,
    "added_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "removed_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_service_area_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_media" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "object_key" TEXT NOT NULL,
    "content_type" TEXT NOT NULL,
    "byte_size" INTEGER,
    "status" "listing_media_status" NOT NULL DEFAULT 'pending',
    "sort_order" INTEGER,
    "stored_at" TIMESTAMPTZ(6),
    "removed_at" TIMESTAMPTZ(6),
    "hidden_by_admin_at" TIMESTAMPTZ(6),
    "hidden_by_admin_reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_media_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_event" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "kind" "listing_event_kind" NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "listing_event_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "listing_cover_media_id_key" ON "listing"("cover_media_id");

-- CreateIndex
CREATE INDEX "listing_provider_profile_id_status_visibility_deleted_at_idx" ON "listing"("provider_profile_id", "status", "visibility", "deleted_at");

-- CreateIndex
CREATE INDEX "listing_provider_profile_id_deleted_at_updated_at_idx" ON "listing"("provider_profile_id", "deleted_at", "updated_at");

-- CreateIndex
CREATE INDEX "listing_category_id_status_visibility_idx" ON "listing"("category_id", "status", "visibility");

-- CreateIndex
CREATE INDEX "listing_service_area_island_id_removed_at_idx" ON "listing_service_area"("island_id", "removed_at");

-- CreateIndex
CREATE UNIQUE INDEX "listing_service_area_listing_id_island_id_key" ON "listing_service_area"("listing_id", "island_id");

-- CreateIndex
CREATE UNIQUE INDEX "listing_media_object_key_key" ON "listing_media"("object_key");

-- CreateIndex
CREATE INDEX "listing_media_listing_id_removed_at_hidden_by_admin_at_sort_idx" ON "listing_media"("listing_id", "removed_at", "hidden_by_admin_at", "sort_order");

-- CreateIndex
CREATE INDEX "listing_event_listing_id_kind_occurred_at_idx" ON "listing_event"("listing_id", "kind", "occurred_at");

-- CreateIndex
CREATE INDEX "listing_event_occurred_at_idx" ON "listing_event"("occurred_at");

-- AddForeignKey
ALTER TABLE "listing" ADD CONSTRAINT "listing_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing" ADD CONSTRAINT "listing_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing" ADD CONSTRAINT "listing_cover_media_id_fkey" FOREIGN KEY ("cover_media_id") REFERENCES "listing_media"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_service_area" ADD CONSTRAINT "listing_service_area_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_service_area" ADD CONSTRAINT "listing_service_area_island_id_fkey" FOREIGN KEY ("island_id") REFERENCES "island"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_media" ADD CONSTRAINT "listing_media_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_event" ADD CONSTRAINT "listing_event_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
