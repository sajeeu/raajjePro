-- CreateEnum
CREATE TYPE "review_tag_sentiment" AS ENUM ('positive', 'negative');

-- AlterTable
ALTER TABLE "booking" ADD COLUMN     "conduct_excluded_at" TIMESTAMPTZ(6),
ADD COLUMN     "conduct_excluded_by_admin_id" UUID;

-- CreateTable
CREATE TABLE "review_tag" (
    "id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "key" VARCHAR(60) NOT NULL,
    "label" VARCHAR(60) NOT NULL,
    "sentiment" "review_tag_sentiment" NOT NULL,
    "sort_order" INTEGER NOT NULL,
    "retired_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "review_tag_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "review" (
    "id" UUID NOT NULL,
    "booking_id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "rating" SMALLINT NOT NULL,
    "body" VARCHAR(2000),
    "hidden_at" TIMESTAMPTZ(6),
    "hidden_by_admin_id" UUID,
    "hidden_reason" VARCHAR(500),
    "author_anonymised_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "review_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "review_tag_application" (
    "id" UUID NOT NULL,
    "review_id" UUID NOT NULL,
    "tag_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "review_tag_application_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_rating_aggregate" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "review_count" INTEGER NOT NULL DEFAULT 0,
    "rating_sum" INTEGER NOT NULL DEFAULT 0,
    "stars_1" INTEGER NOT NULL DEFAULT 0,
    "stars_2" INTEGER NOT NULL DEFAULT 0,
    "stars_3" INTEGER NOT NULL DEFAULT 0,
    "stars_4" INTEGER NOT NULL DEFAULT 0,
    "stars_5" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_rating_aggregate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_rating_aggregate" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "review_count" INTEGER NOT NULL DEFAULT 0,
    "rating_sum" INTEGER NOT NULL DEFAULT 0,
    "stars_1" INTEGER NOT NULL DEFAULT 0,
    "stars_2" INTEGER NOT NULL DEFAULT 0,
    "stars_3" INTEGER NOT NULL DEFAULT 0,
    "stars_4" INTEGER NOT NULL DEFAULT 0,
    "stars_5" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_rating_aggregate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_review_tag_count" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "tag_id" UUID NOT NULL,
    "application_count" INTEGER NOT NULL DEFAULT 0,
    "customer_count" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_review_tag_count_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "listing_review_tag_count" (
    "id" UUID NOT NULL,
    "listing_id" UUID NOT NULL,
    "tag_id" UUID NOT NULL,
    "application_count" INTEGER NOT NULL DEFAULT 0,
    "customer_count" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "listing_review_tag_count_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_conduct_snapshot" (
    "id" UUID NOT NULL,
    "provider_profile_id" UUID NOT NULL,
    "jobs_completed_count" INTEGER NOT NULL DEFAULT 0,
    "completed_in_window" INTEGER NOT NULL DEFAULT 0,
    "completion_rate_bp" INTEGER,
    "cancellation_rate_bp" INTEGER,
    "no_show_rate_bp" INTEGER,
    "on_time_rate_bp" INTEGER,
    "price_adherence_rate_bp" INTEGER,
    "acceptance_rate_bp" INTEGER,
    "median_response_seconds" INTEGER,
    "computed_at" TIMESTAMPTZ(6),
    "stale_since" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "provider_conduct_snapshot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "review_tag_category_id_sort_order_idx" ON "review_tag"("category_id", "sort_order");

-- CreateIndex
CREATE UNIQUE INDEX "review_tag_category_id_key_key" ON "review_tag"("category_id", "key");

-- CreateIndex
CREATE UNIQUE INDEX "review_booking_id_key" ON "review"("booking_id");

-- CreateIndex
CREATE INDEX "review_listing_id_hidden_at_created_at_idx" ON "review"("listing_id", "hidden_at", "created_at");

-- CreateIndex
CREATE INDEX "review_provider_profile_id_hidden_at_created_at_idx" ON "review"("provider_profile_id", "hidden_at", "created_at");

-- CreateIndex
CREATE INDEX "review_author_id_idx" ON "review"("author_id");

-- CreateIndex
CREATE INDEX "review_tag_application_tag_id_idx" ON "review_tag_application"("tag_id");

-- CreateIndex
CREATE UNIQUE INDEX "review_tag_application_review_id_tag_id_key" ON "review_tag_application"("review_id", "tag_id");

-- CreateIndex
CREATE UNIQUE INDEX "provider_rating_aggregate_provider_profile_id_key" ON "provider_rating_aggregate"("provider_profile_id");

-- CreateIndex
CREATE UNIQUE INDEX "listing_rating_aggregate_listing_id_key" ON "listing_rating_aggregate"("listing_id");

-- CreateIndex
CREATE UNIQUE INDEX "provider_review_tag_count_provider_profile_id_tag_id_key" ON "provider_review_tag_count"("provider_profile_id", "tag_id");

-- CreateIndex
CREATE UNIQUE INDEX "listing_review_tag_count_listing_id_tag_id_key" ON "listing_review_tag_count"("listing_id", "tag_id");

-- CreateIndex
CREATE UNIQUE INDEX "provider_conduct_snapshot_provider_profile_id_key" ON "provider_conduct_snapshot"("provider_profile_id");

-- CreateIndex
CREATE INDEX "provider_conduct_snapshot_stale_since_idx" ON "provider_conduct_snapshot"("stale_since");

-- AddForeignKey
ALTER TABLE "review_tag" ADD CONSTRAINT "review_tag_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review" ADD CONSTRAINT "review_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review" ADD CONSTRAINT "review_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review" ADD CONSTRAINT "review_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review" ADD CONSTRAINT "review_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "app_user"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review_tag_application" ADD CONSTRAINT "review_tag_application_review_id_fkey" FOREIGN KEY ("review_id") REFERENCES "review"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "review_tag_application" ADD CONSTRAINT "review_tag_application_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "review_tag"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_rating_aggregate" ADD CONSTRAINT "provider_rating_aggregate_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_rating_aggregate" ADD CONSTRAINT "listing_rating_aggregate_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_review_tag_count" ADD CONSTRAINT "provider_review_tag_count_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_review_tag_count" ADD CONSTRAINT "provider_review_tag_count_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "review_tag"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_review_tag_count" ADD CONSTRAINT "listing_review_tag_count_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "listing"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "listing_review_tag_count" ADD CONSTRAINT "listing_review_tag_count_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "review_tag"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "provider_conduct_snapshot" ADD CONSTRAINT "provider_conduct_snapshot_provider_profile_id_fkey" FOREIGN KEY ("provider_profile_id") REFERENCES "provider_profile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- §1f: a star rating is 1–5 and nothing else. Prisma cannot express a CHECK,
-- so it is written here; the Zod schema is the friendly message, this is the
-- guarantee.
ALTER TABLE "review" ADD CONSTRAINT "review_rating_range" CHECK ("rating" BETWEEN 1 AND 5);

-- Basis points, 0–10000, or null for "no denominator".
ALTER TABLE "provider_conduct_snapshot" ADD CONSTRAINT "provider_conduct_snapshot_rates_range" CHECK (
  ("completion_rate_bp" IS NULL OR "completion_rate_bp" BETWEEN 0 AND 10000) AND
  ("cancellation_rate_bp" IS NULL OR "cancellation_rate_bp" BETWEEN 0 AND 10000) AND
  ("no_show_rate_bp" IS NULL OR "no_show_rate_bp" BETWEEN 0 AND 10000) AND
  ("on_time_rate_bp" IS NULL OR "on_time_rate_bp" BETWEEN 0 AND 10000) AND
  ("price_adherence_rate_bp" IS NULL OR "price_adherence_rate_bp" BETWEEN 0 AND 10000) AND
  ("acceptance_rate_bp" IS NULL OR "acceptance_rate_bp" BETWEEN 0 AND 10000)
);
